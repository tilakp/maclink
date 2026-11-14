import AppKit

/// Resolves `.file` links via bookmark data, with the full repair ladder
/// (spec §7.2, §7.6): bookmark resolution, the stored path, then Spotlight
/// relink and a manual picker via `FileRelinker` (steps 3-5).
struct FileResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .file(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }

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
                    Self.persistRepair(of: record, payload: payload, newURL: url, regenerateBookmark: stale)
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
                Self.persistRepair(of: record, payload: payload, newURL: url, regenerateBookmark: true)
            case .deleted:
                throw ResolveError.linkDeleted
            case .cancelled:
                throw ResolveError.fileNotFound
            case .failed(let error):
                throw error
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

        // Repairs are written above through `LinkStore.applyRepair`, so
        // there is no record for the caller to write back.
        return nil
    }

    /// Writes the repair with `LinkStore.applyRepair`. A failed write is
    /// logged only: the open must still happen.
    private static func persistRepair(
        of record: LinkRecord, payload: FilePayload, newURL: URL, regenerateBookmark: Bool
    ) {
        let newPayload = repairedPayload(from: payload, newURL: newURL)
        let bookmark = regenerateBookmark
            ? try? newURL.bookmarkData(options: [], includingResourceValuesForKeys: [.nameKey, .contentTypeKey], relativeTo: nil)
            : nil
        // Keep a title the user changed; follow the file name otherwise.
        let title = record.title == payload.displayName ? newURL.lastPathComponent : record.title
        let subtitle = newURL.deletingLastPathComponent().path
        do {
            try LinkStore.shared.applyRepair(
                id: record.id, payload: .file(newPayload), bookmarkData: bookmark, subtitle: subtitle, title: title
            )
        } catch {
            Log.db.error("applyRepair failed for \(record.id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// The file payload after a repair: path and name from `newURL`, and fresh
    /// identity fields (size, inode, volume, type) read from disk so dedupe by
    /// volume+inode keeps matching the file.
    static func repairedPayload(from payload: FilePayload, newURL: URL) -> FilePayload {
        var repaired = payload
        repaired.path = newURL.path
        repaired.displayName = newURL.lastPathComponent
        let values = try? newURL.resourceValues(forKeys: [
            .isDirectoryKey, .fileSizeKey, .contentTypeKey, .volumeNameKey, .volumeUUIDStringKey
        ])
        var statBuf = stat()
        let inode: Int64? = stat(newURL.path, &statBuf) == 0 ? Int64(statBuf.st_ino) : nil

        repaired.isDirectory = values?.isDirectory ?? payload.isDirectory
        repaired.byteSize = values?.fileSize.map(Int64.init) ?? payload.byteSize
        repaired.uti = values?.contentType?.identifier ?? payload.uti
        repaired.volumeName = values?.volumeName ?? payload.volumeName
        repaired.volumeUUID = values?.volumeUUIDString ?? payload.volumeUUID
        repaired.inode = inode ?? payload.inode
        return repaired
    }
}
