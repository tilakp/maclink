import AppKit
import Foundation

/// Captures the current tab's URL + title from Safari (spec §7.4).
/// Chromium-family browsers use a different AppleScript dialect
/// (`active tab`/`title` vs. Safari's `current tab`/`name`) and use
/// `ChromiumCapturer`.
struct SafariCapturer: Capturer {
    let supportedBundleIDs: Set<String> = ["com.apple.Safari"]

    private static let script = #"""
        tell application "Safari"
            if (count of windows) = 0 then error "no window" number 1002
            set t to current tab of front window
            return {URL of t, name of t}
        end tell
        """#

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        let result = try await AutomationService.shared.run(Self.script)
        guard let resource = CapturedResource.web(fields: result.stringListValue, bundleID: "com.apple.Safari", appName: "Safari") else {
            throw CaptureError.noSelection
        }
        return [resource]
    }
}
