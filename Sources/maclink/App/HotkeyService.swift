import Carbon.HIToolbox
import Foundation

/// Global hotkeys via Carbon `RegisterEventHotKey` (spec §3.1, §4.2).
/// Deliberately not `NSEvent.addGlobalMonitorForEvents`, which requires
/// Accessibility permission just to observe keystrokes. This needs none.
/// Bindings are user-configurable (persisted in `HotkeySettings`, `nil`
/// meaning "no hotkey assigned") and can be changed at runtime from the
/// Settings window.
final class HotkeyService {
    static let shared = HotkeyService()

    private var hotKeyRefs: [String: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var idsByName: [String: UInt32] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerInstalled = false

    private init() {}

    func start() {
        installEventHandlerIfNeeded()
        _ = apply(name: "capture", binding: HotkeySettings.capture) {
            LinkService.shared.captureFromHotkey()
        }
        _ = apply(name: "search", binding: HotkeySettings.search) {
            LinkService.shared.showSearchPanel()
        }
        Log.app.info("global hotkeys registered")
    }

    /// Re-registers the capture hotkey to a new binding (or clears it, for
    /// `nil`) and persists the result. Returns false without changing
    /// anything if a non-nil binding couldn't be registered. Most
    /// commonly because another app already owns it.
    @discardableResult
    func updateCapture(_ binding: HotkeyBinding?) -> Bool {
        guard apply(name: "capture", binding: binding, handler: { LinkService.shared.captureFromHotkey() }) else {
            return false
        }
        HotkeySettings.capture = binding
        return true
    }

    @discardableResult
    func updateSearch(_ binding: HotkeyBinding?) -> Bool {
        guard apply(name: "search", binding: binding, handler: { LinkService.shared.showSearchPanel() }) else {
            return false
        }
        HotkeySettings.search = binding
        return true
    }

    private func installEventHandlerIfNeeded() {
        guard !eventHandlerInstalled else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
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
        // Flag was set before the call before this, so a failed install was
        // both unlogged and never retried: every hotkey would register with
        // Carbon and then quietly never fire.
        guard status == noErr else {
            Log.app.error("failed to install the hotkey event handler status=\(status, privacy: .public)")
            return
        }
        eventHandlerInstalled = true
    }

    /// Registers `binding` under `name`, unregistering whatever was there
    /// before. `binding == nil` clears the hotkey entirely and always
    /// succeeds. On failure to register a non-nil binding, the previous
    /// binding for `name` is left intact.
    @discardableResult
    private func apply(name: String, binding: HotkeyBinding?, handler: @escaping () -> Void) -> Bool {
        guard let binding else {
            if let oldRef = hotKeyRefs[name] {
                UnregisterEventHotKey(oldRef)
                hotKeyRefs.removeValue(forKey: name)
            }
            if let id = idsByName[name] {
                handlers.removeValue(forKey: id)
            }
            return true
        }

        let id = idsByName[name] ?? {
            let newID = nextID
            nextID += 1
            idsByName[name] = newID
            return newID
        }()

        var newRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode), UInt32(binding.modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &newRef
        )
        guard status == noErr, let newRef else {
            Log.app.error("failed to register hotkey '\(name, privacy: .public)' status=\(status, privacy: .public)")
            return false
        }

        // Only unregister the old one after the new one succeeds, so a
        // failed rebind doesn't leave the user with no hotkey at all.
        if let oldRef = hotKeyRefs[name] {
            UnregisterEventHotKey(oldRef)
        }
        hotKeyRefs[name] = newRef
        handlers[id] = handler
        return true
    }

    private static let signature: FourCharCode = {
        "mclk".utf8.reduce(FourCharCode(0)) { ($0 << 8) + FourCharCode($1) }
    }()
}
