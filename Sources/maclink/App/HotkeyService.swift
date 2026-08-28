import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey` (spec §3.1, §4.2).
/// Deliberately not `NSEvent.addGlobalMonitorForEvents`, which requires
/// Accessibility permission just to observe keystrokes — this needs none.
final class HotkeyService {
    static let shared = HotkeyService()

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                service.handlers[hotKeyID.id]?()
                return noErr
            },
            1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )

        register(keyCode: kVK_ANSI_L, modifiers: [.control, .option, .command]) {
            LinkService.shared.captureFromHotkey()
        }
        register(keyCode: kVK_ANSI_K, modifiers: [.control, .option, .command]) {
            LinkService.shared.showSearchPanel()
        }
        Log.app.info("global hotkeys registered")
    }

    struct Modifiers: OptionSet {
        let rawValue: Int
        static let control = Modifiers(rawValue: controlKey)
        static let option = Modifiers(rawValue: optionKey)
        static let command = Modifiers(rawValue: cmdKey)
        static let shift = Modifiers(rawValue: shiftKey)
    }

    private func register(keyCode: Int, modifiers: Modifiers, handler: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers.rawValue), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        if status == noErr, let hotKeyRef {
            hotKeyRefs.append(hotKeyRef)
        } else {
            Log.app.error("failed to register hotkey id=\(id, privacy: .public) status=\(status, privacy: .public)")
        }
    }

    private static let signature: FourCharCode = {
        "mclk".utf8.reduce(FourCharCode(0)) { ($0 << 8) + FourCharCode($1) }
    }()
}
