import Foundation

/// Facade over capture / resolve / search, per the architecture in spec §4.2.
/// Wired up incrementally: this milestone only proves the `maclink://` URL
/// round trip end to end. Capture/search/DB land in later build-order steps.
final class LinkService {
    static let shared = LinkService()

    private let store = LinkStore.shared

    private init() {}

    func handle(_ url: URL) {
        let route = MaclinkRoute(url: url)
        Log.resolve.info("route: \(String(describing: route), privacy: .public)")

        switch route {
        case .open(let id, let reveal):
            recordDiagnostic("open id=\(id.uuidString) reveal=\(reveal)")
            guard let record = try? store.fetch(id: id) else {
                recordDiagnostic("open: no such link \(id.uuidString)")
                return
            }
            try? store.recordOpened(id: id)
            // TODO(build-order step 5+): ResolveEngine.shared.resolve(record, reveal: reveal)
            recordDiagnostic("open: found \(record.resourceType.rawValue) \"\(record.title)\"")
        case .show(let id):
            recordDiagnostic("show id=\(id.uuidString)")
        case .search(let query):
            let results = (try? store.search(query)) ?? []
            recordDiagnostic("search q=\(query) -> \(results.count) result(s)")
        case .capture:
            recordDiagnostic("capture (external trigger)")
            captureFromHotkey()
        case .unrecognized(let raw):
            recordDiagnostic("unrecognized: \(raw)")
        }
    }

    func captureFromHotkey() {
        Log.capture.info("capture requested (not yet implemented)")
        recordDiagnostic("capture requested (stub)")

        // TODO(build-order step 5+): remove once CaptureEngine exists.
        // Temporary smoke test for AutomationService / the Automation TCC
        // permission flow (spec §3.3, §5) — proves the AppleScript path
        // works (or reports exactly why not) before Finder/Mail capturers
        // are built on top of it.
        Task {
            do {
                let result = try await AutomationService.shared.run(
                    #"tell application "Finder" to return name of front window"#
                )
                recordDiagnostic("automation smoke test ok: \(result.stringValue ?? "<no window>")")
            } catch {
                recordDiagnostic("automation smoke test failed: \(error)")
            }
        }
    }

    func showSearchPanel() {
        Log.ui.info("search panel requested (not yet implemented)")
        recordDiagnostic("search panel requested (stub)")
    }

    /// Temporary: appends a line to a plain-text log so URL-scheme handling
    /// can be verified from the terminal before there's any UI to look at.
    /// Remove once the real resolve/capture paths exist.
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
