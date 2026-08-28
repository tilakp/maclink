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

/// A per-app capture strategy (spec §7). `supportedBundleIDs` is how
/// `CaptureEngine` routes the frontmost app to the right capturer; an empty
/// set marks the generic fallback.
protocol Capturer {
    var supportedBundleIDs: Set<String> { get }
    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource]
}
