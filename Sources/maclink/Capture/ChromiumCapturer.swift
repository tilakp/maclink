import AppKit

/// Captures the active tab's URL and title from Chromium-family browsers
/// (spec §7.4). They share Chrome's AppleScript dialect: `active tab` and
/// `title`, where Safari uses `current tab` and `name`. One capturer covers
/// all of them; the script targets the frontmost browser by bundle ID.
struct ChromiumCapturer: Capturer {
    static let bundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",            // Arc
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi"
    ]

    var supportedBundleIDs: Set<String> { Self.bundleIDs }

    static func script(for bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            if (count of windows) = 0 then error "no window" number 1002
            set t to active tab of front window
            return {URL of t, title of t}
        end tell
        """
    }

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        guard let bundleID = frontApp.bundleIdentifier, Self.bundleIDs.contains(bundleID) else {
            throw CaptureError.noSelection
        }
        let result = try await AutomationService.shared.run(Self.script(for: bundleID))
        guard let resource = CapturedResource.web(
            fields: result.stringListValue,
            bundleID: bundleID,
            appName: frontApp.localizedName ?? bundleID
        ) else {
            throw CaptureError.noSelection
        }
        return [resource]
    }
}
