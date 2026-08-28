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
/// just to render UI.
enum PermissionsService {
    static func automationStatus(forBundleIdentifier bundleID: String) -> AutomationPermissionStatus {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else {
            return .unknown
        }
        let status = AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, false)
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
