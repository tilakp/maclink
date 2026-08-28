import Foundation
import GRDB

/// All persistence (spec §4.2 "LinkStore"). Owns migrations and tag
/// management. `links_fts`/`links_fts_map` exist per the §8.2 schema so the
/// database is ready for the FTS5-backed search described in §9.3, but this
/// milestone searches via `LIKE`. Contentless FTS5 delete/update needs
/// SQLite's `contentless_delete` option (3.43+) handled carefully, and the
/// spec explicitly sanctions LIKE as "genuinely fast enough" at MVP scale
/// (§8.2). Swap the query in `search(_:limit:)` for FTS5 without touching
/// callers once that's worth doing.
final class LinkStore {
    static let shared = try! LinkStore(url: Paths.databaseURL)

    let dbQueue: DatabaseQueue

    init(url: URL) throws {
        var config = Configuration()
        config.prepareDatabase { db in
            // Must run outside any transaction, or SQLite rejects the
            // journal_mode change ("cannot change into wal mode from
            // within a transaction"). PrepareDatabase runs right after
            // the connection opens, before GRDB wraps anything.
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        dbQueue = try DatabaseQueue(path: url.path, configuration: config)
        try Migrations.migrator().migrate(dbQueue)
        Log.db.info("database ready at \(url.path, privacy: .public)")
    }

    // MARK: - CRUD

    @discardableResult
    func insert(_ record: LinkRecord) throws -> LinkRecord {
        let record = record
        try dbQueue.write { db in
            try record.insert(db)
            try self.setTags(record.tags, for: record.id, db: db)
        }
        Log.db.info("inserted link \(record.id.uuidString, privacy: .public) (\(record.resourceType.rawValue, privacy: .public))")
        return record
    }

    func update(_ record: LinkRecord) throws {
        var record = record
        record.updatedAt = Date()
        try dbQueue.write { db in
            try record.update(db)
            try self.setTags(record.tags, for: record.id, db: db)
        }
    }

    func fetch(id: UUID) throws -> LinkRecord? {
        try dbQueue.read { db in
            guard var record = try LinkRecord.fetchOne(db, key: id.uuidString.uppercased()) else {
                return nil
            }
            record.tags = try self.tags(for: id, db: db)
            return record
        }
    }

    func fetchAll(includeArchived: Bool = false, limit: Int = 100) throws -> [LinkRecord] {
        try dbQueue.read { db in
            var request = LinkRecord.order(LinkRecord.Columns.createdAt.desc).limit(limit)
            if !includeArchived {
                request = request.filter(LinkRecord.Columns.archived == false)
            }
            var records = try request.fetchAll(db)
            for i in records.indices {
                records[i].tags = try self.tags(for: records[i].id, db: db)
            }
            return records
        }
    }

    func delete(id: UUID) throws {
        _ = try dbQueue.write { db in
            try LinkRecord.deleteOne(db, key: id.uuidString.uppercased())
        }
    }

    /// Soft delete: hides the link from `fetchAll`/`search` without losing
    /// it, so it can be restored later. `delete(id:)` above is permanent.
    func setArchived(_ archived: Bool, id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE links SET archived = ?, updated_at = ? WHERE id = ?",
                arguments: [archived, Date().timeIntervalSince1970, id.uuidString.uppercased()]
            )
        }
    }

    func recordOpened(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE links
                    SET last_opened_at = ?, open_count = open_count + 1
                    WHERE id = ?
                    """,
                arguments: [Date().timeIntervalSince1970, id.uuidString.uppercased()]
            )
        }
    }

    // MARK: - Tags

    private func slug(_ name: String) -> String {
        name.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
    }

    private func tags(for linkID: UUID, db: Database) throws -> [String] {
        try String.fetchAll(db, sql: """
            SELECT tags.name FROM tags
            JOIN link_tags ON link_tags.tag_id = tags.id
            WHERE link_tags.link_id = ?
            ORDER BY tags.name
            """, arguments: [linkID.uuidString.uppercased()])
    }

    func setTags(_ names: [String], for linkID: UUID, db: Database) throws {
        try db.execute(sql: "DELETE FROM link_tags WHERE link_id = ?", arguments: [linkID.uuidString.uppercased()])
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let tagSlug = slug(trimmed)
            try db.execute(
                sql: "INSERT INTO tags (name, slug) VALUES (?, ?) ON CONFLICT(slug) DO NOTHING",
                arguments: [trimmed, tagSlug]
            )
            try db.execute(sql: """
                INSERT INTO link_tags (link_id, tag_id)
                SELECT ?, id FROM tags WHERE slug = ?
                """, arguments: [linkID.uuidString.uppercased(), tagSlug])
        }
    }

    func setTags(_ names: [String], for linkID: UUID) throws {
        try dbQueue.write { db in
            try self.setTags(names, for: linkID, db: db)
        }
    }

    // MARK: - Search

    func search(_ query: String, limit: Int = 100) throws -> [LinkRecord] {
        try dbQueue.read { db in
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            var records: [LinkRecord]
            if trimmed.isEmpty {
                records = try LinkRecord.fetchAll(db, sql: """
                    SELECT * FROM links WHERE archived = 0
                    ORDER BY created_at DESC LIMIT ?
                    """, arguments: [limit])
            } else {
                let like = "%\(trimmed)%"
                records = try LinkRecord.fetchAll(db, sql: """
                    SELECT DISTINCT links.* FROM links
                    LEFT JOIN link_tags ON link_tags.link_id = links.id
                    LEFT JOIN tags ON tags.id = link_tags.tag_id
                    WHERE links.archived = 0 AND (
                        links.title LIKE ? OR links.subtitle LIKE ? OR
                        links.notes LIKE ? OR links.payload LIKE ? OR
                        tags.name LIKE ?
                    )
                    ORDER BY links.created_at DESC
                    LIMIT ?
                    """, arguments: [like, like, like, like, like, limit])
            }
            for i in records.indices {
                records[i].tags = try self.tags(for: records[i].id, db: db)
            }
            return records
        }
    }

    // MARK: - Dedupe (spec §8.5)

    /// Returns an existing non-archived link with the same identity key as
    /// `payload`, if any. `.generic` never dedupes.
    func findExisting(for payload: Payload) throws -> LinkRecord? {
        try dbQueue.read { db in
            let row: Row?
            switch payload {
            case .file(let p):
                if let vol = p.volumeUUID, let inode = p.inode {
                    row = try Row.fetchOne(db, sql: """
                        SELECT id FROM links
                        WHERE resource_type = 'file' AND archived = 0
                          AND json_extract(payload, '$.volume_uuid') = ?
                          AND json_extract(payload, '$.inode') = ?
                        LIMIT 1
                        """, arguments: [vol, inode])
                } else {
                    row = try Row.fetchOne(db, sql: """
                        SELECT id FROM links
                        WHERE resource_type = 'file' AND archived = 0
                          AND json_extract(payload, '$.path') = ?
                        LIMIT 1
                        """, arguments: [p.path])
                }
            case .mail(let p):
                row = try Row.fetchOne(db, sql: """
                    SELECT id FROM links
                    WHERE resource_type = 'mail' AND archived = 0
                      AND json_extract(payload, '$.message_id') = ?
                    LIMIT 1
                    """, arguments: [p.messageID])
            case .url(let p):
                row = try Row.fetchOne(db, sql: """
                    SELECT id FROM links
                    WHERE resource_type = 'url' AND archived = 0
                      AND json_extract(payload, '$.url') = ?
                    LIMIT 1
                    """, arguments: [p.url])
            case .generic:
                row = nil
            }
            guard let row, let idString: String = row["id"], let id = UUID(uuidString: idString) else {
                return nil
            }
            var record = try LinkRecord.fetchOne(db, key: idString)
            record?.tags = try self.tags(for: id, db: db)
            return record
        }
    }
}
