import AppKit

/// Routes the frontmost app to the right `Capturer` (spec §4.2). Apps with
/// no specific capturer use the generic AX capturer. Errors from a specific
/// capturer are shown to the user, see `errorToSurface(for:)`.
final class CaptureEngine {
    static let shared = CaptureEngine()

    private let capturers: [Capturer] = [
        FinderCapturer(),
        MailCapturer(),
        SafariCapturer(),
        ChromiumCapturer()
    ]
    private let genericCapturer = GenericCapturer()

    private init() {}

    /// Routes to the bundle-ID-matched capturer. Unregistered apps, and a
    /// specific capturer that returns a malformed result, use the generic
    /// AX capturer (spec §4.2). Other errors are thrown to the caller.
    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        if let bundleID = frontApp.bundleIdentifier,
           let capturer = capturers.first(where: { $0.supportedBundleIDs.contains(bundleID) }) {
            do {
                return try await capturer.capture(frontApp: frontApp)
            } catch {
                if let surfaced = Self.errorToSurface(for: error) { throw surfaced }
                Log.capture.info("specific capturer returned a malformed result, falling back to generic")
            }
        }
        return try await genericCapturer.capture(frontApp: frontApp)
    }

    /// What to do when an app-specific capturer throws. `nil` means "try the
    /// generic AX capturer"; anything else is the error to show the user.
    static func errorToSurface(for error: Error) -> Error? {
        switch error {
        case AutomationError.malformedResult:
            return nil
        case AutomationError.scriptError(let number, _) where number == 1000 || number == 1002:
            return CaptureError.noSelection   // our scripts' "no selection" / "no window"
        default:
            return error
        }
    }
}
