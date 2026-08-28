import Carbon.HIToolbox
import Foundation

/// A persisted, user-configurable hotkey: a Carbon virtual key code plus
/// modifier flags, along with a display string captured at recording time
/// (translating keyCode back to a character needs the keyboard layout APIs,
/// so it's simpler to just remember what the user actually typed).
struct HotkeyBinding: Equatable {
    var keyCode: Int
    var modifiers: Int // Carbon modifier mask (controlKey|optionKey|cmdKey|shiftKey)
    var display: String

    static let defaultCapture = HotkeyBinding(keyCode: kVK_ANSI_L, modifiers: controlKey | optionKey | cmdKey, display: "⌃⌥⌘L")
    static let defaultSearch = HotkeyBinding(keyCode: kVK_ANSI_K, modifiers: controlKey | optionKey | cmdKey, display: "⌃⌥⌘K")
}

enum HotkeySettings {
    private static let defaults = UserDefaults.standard

    /// `nil` means "no hotkey assigned" — explicitly cleared by the user,
    /// distinct from "never configured" (which falls back to the default).
    static var capture: HotkeyBinding? {
        get { load(prefix: "hotkey.capture", default: .defaultCapture) }
        set { save(newValue, prefix: "hotkey.capture") }
    }

    static var search: HotkeyBinding? {
        get { load(prefix: "hotkey.search", default: .defaultSearch) }
        set { save(newValue, prefix: "hotkey.search") }
    }

    private static func load(prefix: String, default defaultBinding: HotkeyBinding) -> HotkeyBinding? {
        guard defaults.object(forKey: "\(prefix).set") != nil else { return defaultBinding }
        guard defaults.bool(forKey: "\(prefix).enabled") else { return nil }
        let keyCode = defaults.integer(forKey: "\(prefix).keyCode")
        let modifiers = defaults.integer(forKey: "\(prefix).modifiers")
        let display = defaults.string(forKey: "\(prefix).display") ?? "?"
        return HotkeyBinding(keyCode: keyCode, modifiers: modifiers, display: display)
    }

    private static func save(_ binding: HotkeyBinding?, prefix: String) {
        defaults.set(true, forKey: "\(prefix).set")
        defaults.set(binding != nil, forKey: "\(prefix).enabled")
        if let binding {
            defaults.set(binding.keyCode, forKey: "\(prefix).keyCode")
            defaults.set(binding.modifiers, forKey: "\(prefix).modifiers")
            defaults.set(binding.display, forKey: "\(prefix).display")
        }
    }
}
