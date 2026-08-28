import AppKit

/// Resolves `.file` links via bookmark data, with repair ladder steps 1–2
/// (spec §7.2, §7.6). Steps 3–5 (Spotlight relink, manual picker) are
/// Phase 2.
struct FileResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .file(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }

        var updatedRecord: LinkRecord? = nil
        var resolvedURL: URL?

        if let bookmarkData = record.bookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [], // not .withSecurityScope — unsandboxed
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ), FileManager.default.fileExists(atPath: url.path) {
                resolvedURL = url
                if stale {
                    // Step 1: silently regenerate and persist the repaired bookmark.
                    Log.resolve.info("bookmark stale for \(record.id.uuidString, privacy: .public), regenerating")
                    var repaired = record
                    if let freshData = try? url.bookmarkData(
                        options: [], includingResourceValuesForKeys: [.nameKey, .contentTypeKey], relativeTo: nil
                    ) {
                        repaired.bookmarkData = freshData
                    }
                    var repairedPayload = payload
                    repairedPayload.path = url.path
                    repairedPayload.displayName = url.lastPathComponent
                    repaired.payload = .file(repairedPayload)
                    repaired.repairedAt = Date()
                    updatedRecord = repaired
                }
            }
        }

        // Step 2: bookmark blob missing/corrupted but the stored path still works.
        if resolvedURL == nil, FileManager.default.fileExists(atPath: payload.path) {
            Log.resolve.info("bookmark unusable, falling back to stored path for \(record.id.uuidString, privacy: .public)")
            resolvedURL = URL(fileURLWithPath: payload.path)
        }

        guard let url = resolvedURL else {
            // Steps 3–5 (Spotlight relink, manual picker) are Phase 2.
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
}
