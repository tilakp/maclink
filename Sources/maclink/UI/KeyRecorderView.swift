import Carbon.HIToolbox
import SwiftUI

/// A click-to-record shortcut control: click it, press a key combo, and it
/// captures the Carbon keyCode/modifiers needed to register a global hotkey
/// (spec §9.4 "a small key-recorder view"). Self-contained rather than
/// pulling in a third-party package, matching the spec's "small surface
/// area" principle for a personal tool. `binding == nil` displays "None"
/// and represents no hotkey assigned; press Delete/Backspace while
/// recording to clear an existing one.
struct KeyRecorderView: NSViewRepresentable {
    var binding: HotkeyBinding?
    /// Return true to accept the new binding, false to reject (e.g. the
    /// underlying `RegisterEventHotKey` call failed) and keep showing the
    /// old one.
    var onCapture: (HotkeyBinding) -> Bool
    var onClear: () -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onCapture = onCapture
        button.onClear = onClear
        button.displayText = binding?.display ?? "None"
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onCapture = onCapture
        nsView.onClear = onClear
        if !nsView.isRecording {
            nsView.displayText = binding?.display ?? "None"
        }
    }

    final class RecorderButton: NSButton {
        var onCapture: ((HotkeyBinding) -> Bool)?
        var onClear: (() -> Void)?
        private(set) var isRecording = false

        var displayText: String = "" {
            didSet { title = displayText }
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            bezelStyle = .rounded
            setButtonType(.momentaryPushIn)
            target = self
            action = #selector(startRecording)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

        override var acceptsFirstResponder: Bool { true }

        @objc private func startRecording() {
            isRecording = true
            title = "Press a key… (Delete to clear)"
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard isRecording else {
                super.keyDown(with: event)
                return
            }

            // Delete/Backspace with no modifier clears the binding entirely.
            if event.keyCode == kVK_Delete || event.keyCode == kVK_ForwardDelete {
                isRecording = false
                onClear?()
                return
            }

            var carbonModifiers = 0
            var display = ""
            let flags = event.modifierFlags
            if flags.contains(.control) { carbonModifiers |= controlKey; display += "⌃" }
            if flags.contains(.option) { carbonModifiers |= optionKey; display += "⌥" }
            if flags.contains(.shift) { carbonModifiers |= shiftKey; display += "⇧" }
            if flags.contains(.command) { carbonModifiers |= cmdKey; display += "⌘" }

            // Require at least one modifier. A bare-letter global hotkey
            // would otherwise swallow normal typing everywhere.
            guard carbonModifiers != 0 else {
                NSSound.beep()
                return
            }

            let keyChar = (event.charactersIgnoringModifiers ?? "?").uppercased()
            display += keyChar
            let candidate = HotkeyBinding(keyCode: Int(event.keyCode), modifiers: carbonModifiers, display: display)

            isRecording = false
            if onCapture?(candidate) == true {
                displayText = display
            } else {
                NSSound.beep()
                // displayText stays whatever the binding's updateNSView sets next
            }
        }

        override func resignFirstResponder() -> Bool {
            if isRecording {
                isRecording = false
                title = displayText
            }
            return super.resignFirstResponder()
        }
    }
}
