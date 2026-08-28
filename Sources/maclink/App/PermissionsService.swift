import ApplicationServices
import AppKit

enum AutomationPermissionStatus: String {
    case authorized = "Granted"
    case denied = "Denied"
    case notDetermined = "Not yet requested"
    case unknown = "Unknown"
}

/// Read-only permission checks for the Settings health check (spec §5):
/// these never trigger a system prompt themselves, so they're safe to call
/// just to render UI. `automationStatus` is *not* safe to call on the main
/// thread, though. See its note.
enum PermissionsService {
    /// Callers must keep this off the main thread. `AE.framework` documents
    /// that this call "may take arbitrarily long to return", and it talks to
    /// the target app to decide.
    static func automationStatus(forBundleIdentifier bundleID: String) -> AutomationPermissionStatus {
        // The descriptor has to outlive the AEDesc pointer it vends: `aeDesc`
        // returns interior storage owned by the descriptor, and binding only
        // the pointer let ARC release the temporary before the call below
        // dereferenced it.
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let target = descriptor.aeDesc else {
            return .unknown
        }
        let status = withExtendedLifetime(descriptor) {
            AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false)
        }
        switch Int(status) {
        case 0: return .authorized
        case -1743: return .denied // errAEEventNotPermitted
        case -1744: return .notDetermined // errAEEventWouldRequireUserConsent
        default: return .unknown
        }
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    static func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
