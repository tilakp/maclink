import GRDB

/// Schema per spec §8.2. One migration for MVP; add more as `migrator.registerMigration`
/// calls when the schema needs to change post-ship.
enum Migrations {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "links") { t in
                t.column("id", .text).primaryKey()
                t.column("resource_type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("payload", .text).notNull()
                t.column("payload_blob", .blob)
                t.column("source_bundle_id", .text)
                t.column("source_app_name", .text)
                t.column("capture_method", .text).notNull()
                t.column("notes", .text).notNull().defaults(to: "")
                t.column("degraded", .boolean).notNull().defaults(to: false)
                t.column("created_at", .double).notNull()
                t.column("updated_at", .double).notNull()
                t.column("last_opened_at", .double)
                t.column("open_count", .integer).notNull().defaults(to: 0)
                t.column("repaired_at", .double)
                t.column("archived", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_links_created", on: "links", columns: ["created_at"])
            try db.create(index: "idx_links_type", on: "links", columns: ["resource_type"])
            try db.create(index: "idx_links_app", on: "links", columns: ["source_bundle_id"])
            try db.create(index: "idx_links_lastopen", on: "links", columns: ["last_opened_at"])

            try db.create(table: "tags") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("slug", .text).notNull().unique()
            }

            try db.create(table: "link_tags") { t in
                t.column("link_id", .text).notNull()
                    .references("links", onDelete: .cascade)
                t.column("tag_id", .integer).notNull()
                    .references("tags", onDelete: .cascade)
                t.primaryKey(["link_id", "tag_id"])
            }
            try db.create(index: "idx_link_tags_tag", on: "link_tags", columns: ["tag_id"])

            try db.create(virtualTable: "links_fts", using: FTS5()) { t in
                t.tokenizer = .unicode61(diacritics: .remove, tokenCharacters: Set("-_.@/"))
                t.content = "" // contentless: app writes rows explicitly (spec §8.2)
                t.column("title")
                t.column("subtitle")
                t.column("notes")
                t.column("tags_text")
                t.column("payload_text")
            }

            try db.create(table: "links_fts_map") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("link_id", .text).notNull().unique()
                    .references("links", onDelete: .cascade)
            }
        }

        return migrator
    }
}
