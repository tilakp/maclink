import AppKit

/// Routes the frontmost app to the right `Capturer` (spec §4.2). Falls back
/// to `CaptureError.unsupportedApp` until the generic AX capturer (build
/// order step 9) exists.
final class CaptureEngine {
    static let shared = CaptureEngine()

    private let capturers: [Capturer] = [
        FinderCapturer(),
        MailCapturer()
    ]

    private init() {}

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        guard let bundleID = frontApp.bundleIdentifier else {
            throw CaptureError.unsupportedApp("<no bundle id>")
        }
        guard let capturer = capturers.first(where: { $0.supportedBundleIDs.contains(bundleID) }) else {
            throw CaptureError.unsupportedApp(bundleID)
        }
        return try await capturer.capture(frontApp: frontApp)
    }
}
