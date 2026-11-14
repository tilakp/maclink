import AppKit

enum CaptureError: Error {
    case unsupportedApp(String)
    case noSelection
    case malformedCapture(String)
    case accessibilityPermissionDenied
}

/// One resource pulled out of a `Capturer`, before it becomes a `LinkRecord`
/// (spec §4.2). `CaptureEngine` turns these into records; a capturer never
/// touches the database itself.
struct CapturedResource {
    var payload: Payload
    var title: String
    var subtitle: String? = nil
    var bookmarkData: Data? = nil
    var sourceBundleID: String
    var sourceAppName: String
    var captureMethod: CaptureMethod
    /// True when the capturer couldn't get the ideal identifier and the
    /// record is a breadcrumb rather than something reliably re-openable
    /// (spec §7.3, §8.2 `degraded`).
    var degraded: Bool = false
}

extension CapturedResource {
    /// Builds a `.url` resource from an AppleScript `{URL, title}` result.
    /// Returns nil when there is no usable URL (for example a new empty tab).
    static func web(fields: [String], bundleID: String, appName: String) -> CapturedResource? {
        guard fields.count == 2, !fields[0].isEmpty else { return nil }
        let rawURL = fields[0]
        let title = fields[1]
        let url = URLNormalizer.normalize(rawURL)
        let host = URL(string: url)?.host
        let payload = URLPayload(
            url: url,
            rawURL: url == rawURL ? nil : rawURL,
            host: host,
            pageTitle: title.isEmpty ? nil : title,
            browserBundleID: bundleID
        )
        return CapturedResource(
            payload: .url(payload),
            title: title.isEmpty ? url : title,
            subtitle: host,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            captureMethod: .applescript
        )
    }
}

/// A per-app capture strategy (spec §7). `supportedBundleIDs` is how
/// `CaptureEngine` routes the frontmost app to the right capturer; an empty
/// set marks the generic fallback.
protocol Capturer {
    var supportedBundleIDs: Set<String> { get }
    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource]
}
