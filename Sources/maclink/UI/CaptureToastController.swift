import AppKit
import SwiftUI

/// Owns the capture confirmation toast lifecycle (spec §9.2): a
/// non-activating floating panel, centered on the screen under the
/// mouse, auto-dismissing after 4s unless the tag field has focus.
final class CaptureToastController {
    static let shared = CaptureToastController()

    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?
    private var trackedRecords: [LinkRecord] = []
    private var newRecordIDs: Set<UUID> = []
    private var previousClipboard: String?
    private var localEscMonitor: Any?
    private var globalEscMonitor: Any?

    private init() {}

    func show(records: [(record: LinkRecord, isNew: Bool)], previousClipboard: String?) {
        guard !records.isEmpty else { return }
        dismiss()

        trackedRecords = records.map(\.record)
        newRecordIDs = Set(records.filter(\.isNew).map { $0.record.id })
        self.previousClipboard = previousClipboard

        let view = CaptureToastView(
            records: records.map(\.record),
            existingTagCount: records.count == 1 && !records[0].isNew ? records[0].record.tags.count : nil,
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

        positionCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleAutoDismiss()
        installEscMonitors()
    }

    private func positionCenter(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }

    /// The panel is non-activating and usually isn't the key window, so a
    /// plain SwiftUI `.onKeyPress(.escape)` only fires once the tag field
    /// has been clicked into. These monitors catch Esc regardless of focus.
    private func installEscMonitors() {
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            self?.dismiss()
        }
    }

    private func removeEscMonitors() {
        if let localEscMonitor { NSEvent.removeMonitor(localEscMonitor) }
        if let globalEscMonitor { NSEvent.removeMonitor(globalEscMonitor) }
        localEscMonitor = nil
        globalEscMonitor = nil
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
        Self.addTags(text, to: trackedRecords, store: .shared)
    }

    /// Adds the typed tags to each record's existing tags. A capture can
    /// reuse an existing link, so the typed tags must not replace its old
    /// ones. `store` is a parameter so tests can use a temporary database.
    static func addTags(_ text: String, to records: [LinkRecord], store: LinkStore) {
        for record in records {
            let merged = mergedTags(existing: record.tags, typed: text)
            if merged == record.tags { continue }
            do {
                try store.setTags(merged, for: record.id)
            } catch {
                Log.db.error("failed to tag \(record.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                NotificationService.notifyFailure(
                    title: "Couldn't save tags",
                    body: "The link was captured, but its tags weren't saved."
                )
            }
        }
    }

    /// Existing tags plus the newly typed ones (split on commas and spaces),
    /// in order, with no case-insensitive duplicates. Tag slugs are lowercased
    /// names, so a case-insensitive match is a slug match.
    static func mergedTags(existing: [String], typed: String) -> [String] {
        var result = existing
        var seen = Set(existing.map { $0.lowercased() })
        for tag in typed.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) where !tag.isEmpty {
            if seen.insert(tag.lowercased()).inserted { result.append(tag) }
        }
        return result
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
        removeEscMonitors()
        panel?.close()
        panel = nil
    }
}
