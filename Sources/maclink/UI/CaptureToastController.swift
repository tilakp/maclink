import AppKit
import SwiftUI

/// Owns the capture confirmation toast lifecycle (spec §9.2): a
/// non-activating floating panel, top-center of the screen under the
/// mouse, auto-dismissing after 4s unless the tag field has focus.
final class CaptureToastController {
    static let shared = CaptureToastController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var trackedRecordIDs: [UUID] = []
    private var newRecordIDs: Set<UUID> = []
    private var previousClipboard: String?

    private init() {}

    func show(records: [(record: LinkRecord, isNew: Bool)], previousClipboard: String?) {
        guard !records.isEmpty else { return }
        dismiss()

        trackedRecordIDs = records.map { $0.record.id }
        newRecordIDs = Set(records.filter(\.isNew).map { $0.record.id })
        self.previousClipboard = previousClipboard

        let view = CaptureToastView(
            records: records.map(\.record),
            onTagsCommitted: { [weak self] text in self?.commitTags(text) },
            onDismiss: { [weak self] in self?.dismiss() },
            onUndo: { [weak self] in self?.undo() },
            onFieldFocusChanged: { [weak self] focused in
                focused ? self?.cancelAutoDismiss() : self?.scheduleAutoDismiss()
            }
        )

        let hosting = NSHostingController(rootView: view)
        // NSPanel(contentViewController:) sizes the window from the hosting
        // view's frame *at construction time*, which SwiftUI hasn't laid
        // out yet. That produces a zero-size, invisible panel. Giving an
        // explicit content rect up front avoids that trap.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        positionTopCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleAutoDismiss()
    }

    private func positionTopCenter(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 40)
        panel.setFrameOrigin(origin)
    }

    private func scheduleAutoDismiss() {
        cancelAutoDismiss()
        let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    private func cancelAutoDismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
    }

    private func commitTags(_ text: String) {
        let tags = text
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tags.isEmpty else { return }
        for id in trackedRecordIDs {
            do {
                try LinkStore.shared.setTags(tags, for: id)
            } catch {
                Log.db.error("failed to tag \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                NotificationService.notifyFailure(
                    title: "Couldn't save tags",
                    body: "The link was captured, but its tags weren't saved."
                )
            }
        }
    }

    /// Deletes only the records this capture actually created. A reused
    /// (deduped) record predates this capture and undo must not touch it.
    private func undo() {
        for id in newRecordIDs {
            do {
                try LinkStore.shared.delete(id: id)
            } catch {
                Log.db.error("undo failed to delete \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                NotificationService.notifyFailure(
                    title: "Couldn't undo the capture",
                    body: "The link is still in your database. Delete it from the search dropdown instead."
                )
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let previousClipboard {
            pasteboard.setString(previousClipboard, forType: .string)
        }
        dismiss()
    }

    private func dismiss() {
        cancelAutoDismiss()
        panel?.close()
        panel = nil
    }
}
