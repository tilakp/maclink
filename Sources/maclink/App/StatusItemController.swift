import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the menu-bar icon: a classic `NSMenu` on click (spec §9.1) plus a
/// separate `NSPopover` "dropdown" for search, shown by the ⌃⌥⌘K hotkey
/// (OQ-3: dropdown chosen over a floating Spotlight-style panel).
final class StatusItemController: NSObject, ObservableObject, NSMenuDelegate {
    static let shared = StatusItemController()

    /// When pinned, opening or copying a link leaves the dropdown open so
    /// several links can be acted on in one sitting. Flipping this also
    /// switches the popover away from `.transient`, since that behavior
    /// auto-dismisses as soon as an opened link steals key window status
    /// (e.g. Mail or Safari activating), which would defeat pinning even
    /// with the explicit close calls below removed.
    var isPinned: Bool = false {
        willSet { objectWillChange.send() }
        didSet { popover?.behavior = isPinned ? .applicationDefined : .transient }
    }

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    /// Invisible 1x1 anchor window used only when the real status item frame
    /// is off-screen (see `showSearchDropdown`).
    private var anchorWindow: NSWindow?

    private override init() {
        super.init()
    }

    func setup() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "link.badge.plus", accessibilityDescription: "maclink")

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 400, height: 380)
        popover.contentViewController = NSHostingController(rootView: SearchPanelView(
            controller: self,
            onSelect: { [weak self] record in
                LinkService.shared.open(id: record.id)
                if self?.isPinned != true { self?.closeSearchDropdown() }
            },
            onCopy: { record in
                LinkService.shared.copyLinkToClipboard(record)
            },
            onReveal: { [weak self] record in
                LinkService.shared.open(id: record.id, reveal: true)
                if self?.isPinned != true { self?.closeSearchDropdown() }
            },
            onArchive: { record in
                LinkService.shared.archive(record)
            },
            onDelete: { record in
                LinkService.shared.delete(record)
            }
        ))
        self.popover = popover
    }

    func showSearchDropdown() {
        guard let button = statusItem?.button, let popover else {
            Log.ui.error("showSearchDropdown: no status item button yet")
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Activation must land before `show` computes the anchor rect, or
        // the popover can appear detached from the status item. Hence the
        // hop to the next run loop tick rather than showing inline.
        NSApp.activate(ignoringOtherApps: true)
        // Re-assert the behavior at show time. `didSet` on `isPinned` only
        // fires when the value actually changes, and AppKit reads this when
        // the popover is shown, so the two could disagree for a whole
        // showing otherwise.
        popover.behavior = isPinned ? .applicationDefined : .transient
        DispatchQueue.main.async {
            if let windowFrame = button.window?.frame, Self.isOnScreen(windowFrame.origin) {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            } else {
                // A sufficiently crowded menu bar can push a new status item
                // into an overflow state with a nonsensical off-screen frame
                // (observed: x=-4701 on this machine). Anchoring to it then
                // makes the dropdown appear to render nowhere useful, so
                // fall back to a small invisible anchor window placed at a
                // guaranteed-visible spot instead.
                Log.ui.info("status item frame is off-screen, using fallback anchor")
                popover.show(relativeTo: .zero, of: self.fallbackAnchorView(), preferredEdge: .minY)
            }
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private static func isOnScreen(_ point: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(point) }
    }

    private func fallbackAnchorView() -> NSView {
        let screen = NSScreen.main?.frame ?? .init(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: screen.midX - 1, y: screen.maxY - 8)
        let window: NSWindow
        if let existing = anchorWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(origin: origin, size: CGSize(width: 2, height: 2)),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .statusBar
            window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 2, height: 2))
            anchorWindow = window
        }
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        return window.contentView!
    }

    private func closeSearchDropdown() {
        popover?.performClose(nil)
    }

    /// Always closes, regardless of pin state. Used by the dropdown's own
    /// Esc handler, since `.applicationDefined` popovers (pinned) don't
    /// close on their own for anything.
    func forceCloseSearchDropdown() {
        popover?.performClose(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        // Built from the live bindings, not hardcoded: the menu used to keep
        // advertising ⌃⌥⌘L / ⌃⌥⌘K after the user rebound (or cleared) them.
        menu.addItem(Self.item("Capture Link", binding: HotkeySettings.capture, target: self, action: #selector(captureTapped)))
        menu.addItem(Self.item("Search Links…", binding: HotkeySettings.search, target: self, action: #selector(searchTapped)))

        let pinItem = NSMenuItem(title: "Pin Search Window", action: #selector(togglePinTapped), keyEquivalent: "")
        pinItem.target = self
        pinItem.state = isPinned ? .on : .off
        menu.addItem(pinItem)

        menu.addItem(.separator())

        let recent = LinkService.shared.recent(limit: 10)
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No links yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for record in recent {
                let item = NSMenuItem(title: record.title, action: #selector(recentItemTapped(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = record.id
                item.toolTip = record.subtitle
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(settingsTapped), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        // Plain ⌘Q. This shared the capture/search helper before, which
        // advertised it as ⌃⌥⌘Q.
        let quitItem = NSMenuItem(title: "Quit maclink", action: #selector(quitTapped), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    /// Menu item labelled with whatever global hotkey is currently bound to
    /// the same action, or with no shortcut at all when it's been cleared.
    private static func item(_ title: String, binding: HotkeyBinding?, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        if let binding, let key = binding.display.last {
            item.keyEquivalent = String(key).lowercased()
            item.keyEquivalentModifierMask = modifierFlags(carbon: binding.modifiers)
        }
        return item
    }

    private static func modifierFlags(carbon: Int) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & controlKey != 0 { flags.insert(.control) }
        if carbon & optionKey != 0 { flags.insert(.option) }
        if carbon & shiftKey != 0 { flags.insert(.shift) }
        if carbon & cmdKey != 0 { flags.insert(.command) }
        return flags
    }

    @objc private func captureTapped() {
        LinkService.shared.captureFromHotkey()
    }

    @objc private func searchTapped() {
        showSearchDropdown()
    }

    @objc private func togglePinTapped() {
        isPinned.toggle()
    }

    @objc private func recentItemTapped(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        // ⌥-click copies instead of opening (spec §9.1).
        if NSEvent.modifierFlags.contains(.option), let record = try? LinkStore.shared.fetch(id: id) {
            LinkService.shared.copyLinkToClipboard(record)
        } else {
            LinkService.shared.open(id: id)
        }
    }

    @objc private func settingsTapped() {
        openSettings()
    }

    /// Opens the Settings window. Only reachable through this status item's
    /// menu right now. A menu-bar-organizing tool like Ice or Bartender
    /// hiding the icon by default (as seen live on this machine) can make
    /// it genuinely unclickable; a global-hotkey fallback was considered
    /// and explicitly declined in favor of fixing the icon's visibility
    /// directly in the organizing tool.
    func openSettings() {
        // Activation must land before the action is sent, or the Settings
        // scene's command doesn't yet have a live window to target and the
        // call silently does nothing. Same race `showSearchDropdown`
        // works around by hopping a run loop tick before showing.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc private func quitTapped() {
        NSApplication.shared.terminate(nil)
    }
}
