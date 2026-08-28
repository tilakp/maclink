import AppKit
import Foundation

/// Facade over capture / resolve / search, per the architecture in spec §4.2.
final class LinkService {
    static let shared = LinkService()

    private let store = LinkStore.shared

    private init() {}

    func handle(_ url: URL) {
        let route = MaclinkRoute(url: url)
        Log.resolve.info("route: \(String(describing: route), privacy: .public)")

        switch route {
        case .open(let id, let reveal):
            open(id: id, reveal: reveal)
        case .show(let id):
            recordDiagnostic("show id=\(id.uuidString)")
        case .search(let query):
            let results = (try? store.search(query)) ?? []
            recordDiagnostic("search q=\(query) -> \(results.count) result(s)")
        case .capture:
            captureFromHotkey()
        case .unrecognized(let raw):
            recordDiagnostic("unrecognized: \(raw)")
        }
    }

    /// Resolves and opens a link by id — the shared path for the
    /// `maclink://open` URL route, the search dropdown, and the Recent menu.
    func open(id: UUID, reveal: Bool = false) {
        guard let record = try? store.fetch(id: id) else {
            recordDiagnostic("open: no such link \(id.uuidString)")
            NotificationService.notifyFailure(
                title: "Link not found",
                body: "This maclink doesn't exist — the database may have been reset or the link deleted."
            )
            return
        }
        Task {
            do {
                let repaired = try await ResolveEngine.shared.resolve(record, reveal: reveal)
                // Order matters: `update` overwrites the whole row from a
                // Swift value fetched before this resolve ran, so it must
                // land before the narrow open_count/last_opened_at bump
                // below — otherwise it clobbers that bump back to 0.
                if let repaired {
                    try? store.update(repaired)
                }
                try? store.recordOpened(id: id)
                recordDiagnostic("open: resolved \(record.resourceType.rawValue) \"\(record.title)\"")
            } catch {
                recordDiagnostic("open: failed to resolve \"\(record.title)\": \(error)")
                NotificationService.notifyFailure(
                    title: "Couldn't open \"\(record.title)\"",
                    body: Self.friendlyMessage(for: error, sourceAppName: record.sourceAppName)
                )
            }
        }
    }

    private static func friendlyMessage(for error: Error, sourceAppName: String?) -> String {
        let app = sourceAppName ?? "the source app"
        switch error {
        case AutomationError.permissionDenied:
            return "maclink needs permission to control \(app). Check System Settings > Privacy & Security > Automation."
        case AutomationError.appNotRunning:
            return "\(app) isn't running."
        case AutomationError.timeout:
            return "\(app) didn't respond in time."
        case ResolveError.fileNotFound:
            return "The file couldn't be found at its last known location."
        case ResolveError.noStableIdentifier:
            return "This item has no reliable identifier and can't be reopened."
        case ResolveError.appNotInstalled:
            return "\(app) doesn't appear to be installed."
        case ResolveError.malformedURL:
            return "The stored link is malformed."
        case CaptureError.accessibilityPermissionDenied:
            return "maclink needs Accessibility permission. Check System Settings > Privacy & Security > Accessibility."
        default:
            return "Something went wrong: \(String(describing: error))"
        }
    }

    func captureFromHotkey() {
        // Captured immediately, synchronously — the last moment it's
        // guaranteed to still be the app the user was actually looking at
        // (spec §4.4 step 1). maclink is LSUIElement and never activates
        // itself, so this stays correct even when triggered via the
        // maclink://capture URL route rather than a real hotkey yet.
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            recordDiagnostic("capture: no frontmost app")
            return
        }

        Task {
            do {
                let resources = try await CaptureEngine.shared.capture(frontApp: frontApp)
                var copiedURLs: [String] = []
                for resource in resources {
                    let maclinkURL = try storeAndDedupe(resource)
                    copiedURLs.append(maclinkURL)
                }
                if !copiedURLs.isEmpty {
                    writeToClipboard(copiedURLs.joined(separator: "\n"))
                }
                recordDiagnostic("capture: \(resources.count) link(s) from \(frontApp.bundleIdentifier ?? "?")")
            } catch CaptureError.unsupportedApp(let bundleID) {
                recordDiagnostic("capture: no capturer for \(bundleID) yet")
                NotificationService.notifyFailure(
                    title: "Can't capture from \(frontApp.localizedName ?? bundleID)",
                    body: "maclink doesn't support this app yet."
                )
            } catch CaptureError.noSelection {
                recordDiagnostic("capture: nothing selected in \(frontApp.bundleIdentifier ?? "?")")
                NotificationService.notifyFailure(
                    title: "Nothing to capture",
                    body: "Select something in \(frontApp.localizedName ?? "the frontmost app") first."
                )
            } catch {
                recordDiagnostic("capture failed: \(error)")
                NotificationService.notifyFailure(
                    title: "Capture failed",
                    body: Self.friendlyMessage(for: error, sourceAppName: frontApp.localizedName)
                )
            }
        }
    }

    /// Inserts a captured resource, or bumps the existing record if one
    /// already represents the same underlying resource (spec §8.5).
    private func storeAndDedupe(_ resource: CapturedResource) throws -> String {
        if let existing = try store.findExisting(for: resource.payload) {
            try store.update(existing) // bumps updated_at
            recordDiagnostic("capture: existing link reused (\(existing.tags.count) tags)")
            return "maclink://open/\(existing.id.uuidString)"
        }
        let record = LinkRecord(
            title: resource.title,
            subtitle: resource.subtitle,
            payload: resource.payload,
            bookmarkData: resource.bookmarkData,
            sourceBundleID: resource.sourceBundleID,
            sourceAppName: resource.sourceAppName,
            captureMethod: resource.captureMethod
        )
        let inserted = try store.insert(record)
        return "maclink://open/\(inserted.id.uuidString)"
    }

    func showSearchPanel() {
        StatusItemController.shared.showSearchDropdown()
    }

    func search(_ query: String, limit: Int = 30) -> [LinkRecord] {
        (try? store.search(query, limit: limit)) ?? []
    }

    func recent(limit: Int = 10) -> [LinkRecord] {
        (try? store.fetchAll(limit: limit)) ?? []
    }

    func copyLinkToClipboard(_ record: LinkRecord) {
        writeToClipboard("maclink://open/\(record.id.uuidString)")
    }

    private func writeToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Temporary: appends a line to a plain-text log so behavior can be
    /// verified from the terminal before there's a UI to look at. Remove
    /// once the capture toast (build order step 11) exists.
    private func recordDiagnostic(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = Paths.appSupportDirectory.appendingPathComponent("diagnostic.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
