import ApplicationServices
import AppKit

/// Best-effort resolution for `.generic` links (spec §7.5): activate the
/// source app by bundle ID, then try to raise the specific window by title
/// match. A `.generic` link is a breadcrumb, not a guarantee — failing to
/// raise the exact window is not treated as an error, only the app not
/// being installed at all is.
struct GenericResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .generic(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }
        guard let bundleID = record.sourceBundleID,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw ResolveError.appNotInstalled
        }

        await MainActor.run {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
        try? await Self.raiseWindow(bundleID: bundleID, title: payload.windowTitle)
        return nil
    }

    private static func raiseWindow(bundleID: String, title: String) async throws {
        // Give the app a moment to finish activating before querying its windows.
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return
        }
        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            if (titleRef as? String) == title {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }
}
