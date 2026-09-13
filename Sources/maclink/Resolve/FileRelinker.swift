import AppKit

/// File repair ladder steps 3-5 (spec §7.6), reached once bookmark
/// resolution and the stored path have both failed. Every step here needs
/// user confirmation before touching the database: a Spotlight name match
/// can be wrong.
enum FileRelinker {
    enum Outcome {
        case relinked(URL)
        case deleted
        case cancelled
    }

    @MainActor
    static func repair(payload: FilePayload, linkID: UUID) async -> Outcome {
        NSApp.activate(ignoringOtherApps: true)

        // Step 3: name + size. A single hit here is a strong enough match to
        // lead with, ahead of the broader name-only search below.
        if let size = payload.byteSize {
            let hits = await spotlightSearch(name: payload.displayName, size: size)
            if hits.count == 1, confirmRelink(to: hits[0], originalPath: payload.path) {
                return .relinked(hits[0])
            }
        }

        // Step 4: name only. Multiple hits get a picker instead of guessing.
        let nameHits = await spotlightSearch(name: payload.displayName, size: nil)
        if nameHits.count == 1 {
            if confirmRelink(to: nameHits[0], originalPath: payload.path) {
                return .relinked(nameHits[0])
            }
        } else if nameHits.count > 1, let chosen = pickAmong(nameHits) {
            return .relinked(chosen)
        }

        // Step 5: give up, offer a manual picker or deletion.
        return giveUp(payload: payload, linkID: linkID)
    }

    // MARK: - Spotlight

    private static func spotlightSearch(name: String, size: Int64?, timeout: TimeInterval = 3) async -> [URL] {
        await withCheckedContinuation { continuation in
            // Only ever touched on the main queue below, despite not being
            // Sendable: the notification observer and the timeout fallback
            // both run on `.main`.
            nonisolated(unsafe) let query = NSMetadataQuery()
            // Spotlight's own query parser (unlike NSPredicate evaluated
            // in-process) doesn't understand the `[c]` case-insensitive
            // modifier on kMDItem comparisons -- it silently matches
            // nothing rather than erroring. Plain `==` is what spec §7.6
            // specifies and is the form that actually works.
            if let size {
                query.predicate = NSPredicate(
                    format: "kMDItemFSName == %@ AND kMDItemFSSize == %@", name, NSNumber(value: size)
                )
            } else {
                query.predicate = NSPredicate(format: "kMDItemFSName == %@", name)
            }
            query.searchScopes = [NSMetadataQueryLocalComputerScope]

            var finished = false
            var observer: NSObjectProtocol?
            func finish(_ urls: [URL]) {
                guard !finished else { return }
                finished = true
                if let observer { NotificationCenter.default.removeObserver(observer) }
                query.stop()
                continuation.resume(returning: urls)
            }

            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main
            ) { _ in
                let urls = (0..<query.resultCount).compactMap { index -> URL? in
                    guard let item = query.result(at: index) as? NSMetadataItem,
                          let path = item.value(forAttribute: NSMetadataItemPathKey) as? String
                    else { return nil }
                    return URL(fileURLWithPath: path)
                }
                finish(urls)
            }

            query.start()
            // A query that never finishes gathering (e.g. Spotlight indexing
            // disabled) must not hang the resolve path forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish([]) }
        }
    }

    // MARK: - Prompts

    private static func confirmRelink(to url: URL, originalPath: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Relink to this file?"
        alert.informativeText = "\"\(originalPath)\" couldn't be found. A file with the same name was found at:\n\n\(url.path)"
        alert.addButton(withTitle: "Relink")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func pickAmong(_ candidates: [URL]) -> URL? {
        let alert = NSAlert()
        alert.messageText = "Multiple matches found"
        alert.informativeText = "Choose which file this link should point to:"
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        popup.addItems(withTitles: candidates.map(\.path))
        alert.accessoryView = popup
        alert.addButton(withTitle: "Relink")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return candidates[popup.indexOfSelectedItem]
    }

    private static func giveUp(payload: FilePayload, linkID: UUID) -> Outcome {
        let alert = NSAlert()
        alert.messageText = "Can't find \"\(payload.displayName)\""
        alert.informativeText = "It was last seen at:\n\(payload.path)"
        alert.addButton(withTitle: "Choose File\u{2026}")
        alert.addButton(withTitle: "Delete Link")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let panel = NSOpenPanel()
            panel.canChooseDirectories = payload.isDirectory
            panel.canChooseFiles = !payload.isDirectory
            panel.allowsMultipleSelection = false
            panel.directoryURL = URL(fileURLWithPath: payload.path).deletingLastPathComponent()
            guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
            return .relinked(url)
        case .alertSecondButtonReturn:
            try? LinkStore.shared.delete(id: linkID)
            return .deleted
        default:
            return .cancelled
        }
    }
}
