import AppKit

/// Routes the frontmost app to the right `Capturer` (spec §4.2). Falls back
/// to `CaptureError.unsupportedApp` until the generic AX capturer (build
/// order step 9) exists.
final class CaptureEngine {
    static let shared = CaptureEngine()

    private let capturers: [Capturer] = [
        FinderCapturer(),
        MailCapturer(),
        SafariCapturer()
    ]
    private let genericCapturer = GenericCapturer()

    private init() {}

    /// Routes to the bundle-ID-matched capturer; falls back to the generic
    /// AX capturer on any failure or if the app is unregistered (spec §4.2).
    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        if let bundleID = frontApp.bundleIdentifier,
           let capturer = capturers.first(where: { $0.supportedBundleIDs.contains(bundleID) }) {
            do {
                return try await capturer.capture(frontApp: frontApp)
            } catch {
                Log.capture.info("specific capturer failed (\(String(describing: error), privacy: .public)), falling back to generic")
            }
        }
        return try await genericCapturer.capture(frontApp: frontApp)
    }
}
