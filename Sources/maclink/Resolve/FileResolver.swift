import AppKit

/// Resolves `.file` links via bookmark data, with the full repair ladder
/// (spec §7.2, §7.6): bookmark resolution, the stored path, then Spotlight
/// relink and a manual picker via `FileRelinker` (steps 3-5).
struct FileResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .file(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }

        var updatedRecord: LinkRecord?
        var resolvedURL: URL?

        if let bookmarkData = record.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [], // not .withSecurityScope: unsandboxed
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) {
                resolvedURL = url
                // Step 1: silently regenerate and persist the repair. The
                // bookmark being stale is one trigger; the other is the file
                // having simply moved, which resolves cleanly with
                // `stale == false` and used to leave a wrong `path` (and a
                // wrong subtitle, and a dedupe key that no longer matches)
                // in the database forever.
                let moved = url.path != payload.path
                if stale || moved {
                    Log.resolve.info("repairing file link \(record.id.uuidString, privacy: .public) (stale=\(stale, privacy: .public) moved=\(moved, privacy: .public))")
                    updatedRecord = Self.repairedRecord(from: record, payload: payload, newURL: url, regenerateBookmark: stale)
                }
            }
        }

        // Step 2: bookmark blob missing/corrupted but the stored path still works.
        if resolvedURL == nil, FileManager.default.fileExists(atPath: payload.path) {
            Log.resolve.info("bookmark unusable, falling back to stored path for \(record.id.uuidString, privacy: .public)")
            resolvedURL = URL(fileURLWithPath: payload.path)
        }

        // Steps 3-5: Spotlight relink, then a manual picker or deletion.
        // Each requires the user's confirmation before anything is written.
        if resolvedURL == nil {
            switch await FileRelinker.repair(payload: payload, linkID: record.id) {
            case .relinked(let url):
                Log.resolve.info("relinked file \(record.id.uuidString, privacy: .public) to \(url.path, privacy: .public)")
                resolvedURL = url
                updatedRecord = Self.repairedRecord(from: record, payload: payload, newURL: url, regenerateBookmark: true)
            case .deleted:
                throw ResolveError.linkDeleted
            case .cancelled:
                throw ResolveError.fileNotFound
            }
        }

        guard let url = resolvedURL else {
            throw ResolveError.fileNotFound
        }

        await MainActor.run {
            if reveal {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } else {
                NSWorkspace.shared.open(url)
            }
        }

        return updatedRecord
    }

    private static func repairedRecord(
        from record: LinkRecord, payload: FilePayload, newURL: URL, regenerateBookmark: Bool
    ) -> LinkRecord {
        var repaired = record
        if regenerateBookmark, let freshData = try? newURL.bookmarkData(
            options: [], includingResourceValuesForKeys: [.nameKey, .contentTypeKey], relativeTo: nil
        ) {
            repaired.bookmarkData = freshData
        }
        var repairedPayload = payload
        repairedPayload.path = newURL.path
        repairedPayload.displayName = newURL.lastPathComponent
        repaired.payload = .file(repairedPayload)
        repaired.subtitle = newURL.deletingLastPathComponent().path
        repaired.repairedAt = Date()
        return repaired
    }
}
