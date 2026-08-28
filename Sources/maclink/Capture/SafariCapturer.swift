import AppKit
import Foundation

/// Captures the current tab's URL + title from Safari (spec §7.4).
/// Chromium-family browsers use a different AppleScript dialect
/// (`active tab`/`title` vs. Safari's `current tab`/`name`) and are Phase 2.
struct SafariCapturer: Capturer {
    let supportedBundleIDs: Set<String> = ["com.apple.Safari"]

    private static let script = #"""
        tell application "Safari"
            if (count of windows) = 0 then error "no window" number 1002
            set t to current tab of front window
            return {URL of t, name of t}
        end tell
        """#

    /// Hosts where known tracking params get stripped at capture time
    /// (spec §7.4 "cheap wins"). Kept intentionally small for MVP.
    private static let trackingParams: Set<String> = ["utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content", "fbclid", "gclid", "mc_eid", "ref"]

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        let result = try await AutomationService.shared.run(Self.script)
        let fields = result.stringListValue
        guard fields.count == 2, let rawURL = fields.first, !rawURL.isEmpty else {
            throw CaptureError.noSelection
        }
        let title = fields[1]
        let cleanedURL = Self.stripTrackingParams(from: rawURL)

        let payload = URLPayload(
            url: cleanedURL,
            rawURL: cleanedURL == rawURL ? nil : rawURL,
            host: URL(string: cleanedURL)?.host,
            pageTitle: title.isEmpty ? nil : title,
            browserBundleID: "com.apple.Safari"
        )

        return [CapturedResource(
            payload: .url(payload),
            title: title.isEmpty ? cleanedURL : title,
            subtitle: URL(string: cleanedURL)?.host,
            sourceBundleID: "com.apple.Safari",
            sourceAppName: "Safari",
            captureMethod: .applescript
        )]
    }

    /// Strips a small allowlist of tracking params but never touches the
    /// fragment. The spec explicitly calls those out as often meaningful
    /// anchors, not cruft.
    static func stripTrackingParams(from urlString: String) -> String {
        guard var components = URLComponents(string: urlString), let items = components.queryItems, !items.isEmpty else {
            return urlString
        }
        let kept = items.filter { !trackingParams.contains($0.name.lowercased()) }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.string ?? urlString
    }
}
