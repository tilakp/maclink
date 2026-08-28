import AppKit
import SwiftUI

/// Owns the menu-bar icon: a classic `NSMenu` on click (spec §9.1) plus a
/// separate `NSPopover` "dropdown" for search, shown by the ⌃⌥⌘K hotkey
/// (OQ-3: dropdown chosen over a floating Spotlight-style panel).
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

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
            onSelect: { [weak self] record in
                self?.closeSearchDropdown()
                LinkService.shared.open(id: record.id)
            },
            onCopy: { record in
                LinkService.shared.copyLinkToClipboard(record)
            },
            onReveal: { [weak self] record in
                self?.closeSearchDropdown()
                LinkService.shared.open(id: record.id, reveal: true)
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

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(Self.item("Capture Link", key: "l", target: self, action: #selector(captureTapped)))
        menu.addItem(Self.item("Search Links…", key: "k", target: self, action: #selector(searchTapped)))
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
        menu.addItem(Self.item("Quit maclink", key: "q", target: self, action: #selector(quitTapped)))
    }

    private static func item(_ title: String, key: String, target: AnyObject, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.control, .option, .command]
        item.target = target
        return item
    }

    @objc private func captureTapped() {
        LinkService.shared.captureFromHotkey()
    }

    @objc private func searchTapped() {
        showSearchDropdown()
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
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitTapped() {
        NSApplication.shared.terminate(nil)
    }
}
