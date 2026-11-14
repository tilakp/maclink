import XCTest
import GRDB
@testable import maclink

final class LinkStoreTests: XCTestCase {
    var store: LinkStore!
    var dbURL: URL!

    override func setUpWithError() throws {
        dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclink-test-\(UUID().uuidString).sqlite")
        store = try LinkStore(url: dbURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dbURL)
    }

    private func mailRecord(
        subject: String = "Q3 invoice",
        messageID: String = "abc123@example.com",
        tags: [String] = ["finance", "q3"]
    ) -> LinkRecord {
        LinkRecord(
            title: subject,
            subtitle: "Jane Doe",
            payload: .mail(MailPayload(messageID: messageID, subject: subject, sender: "Jane Doe")),
            sourceBundleID: "com.apple.mail",
            sourceAppName: "Mail",
            captureMethod: .applescript,
            tags: tags
        )
    }

    func testInsertAndFetch() throws {
        let record = try store.insert(mailRecord())
        let fetched = try store.fetch(id: record.id)
        XCTAssertEqual(fetched?.title, "Q3 invoice")
        XCTAssertEqual(fetched?.resourceType, .mail)
        XCTAssertEqual(Set(fetched?.tags ?? []), ["finance", "q3"])
        if case .mail(let payload) = fetched?.payload {
            XCTAssertEqual(payload.messageID, "abc123@example.com")
        } else {
            XCTFail("expected mail payload")
        }
    }

    func testFetchAllOrdersByMostRecentCapture() throws {
        let first = try store.insert(mailRecord(subject: "First", messageID: "1@example.com"))
        Thread.sleep(forTimeInterval: 0.01)
        let second = try store.insert(mailRecord(subject: "Second", messageID: "2@example.com"))

        let all = try store.fetchAll()
        XCTAssertEqual(all.map(\.id), [second.id, first.id])

        // A recapture (dedupe hit) calls `update`, which moves the link to the top.
        Thread.sleep(forTimeInterval: 0.01)
        try store.update(first)
        XCTAssertEqual(try store.fetchAll().map(\.id), [first.id, second.id])
        XCTAssertEqual(try store.search("").map(\.id), [first.id, second.id])
    }

    func testSearchMatchesTitleSubtitleAndTags() throws {
        try store.insert(mailRecord(subject: "Q3 invoice", messageID: "1@example.com"))
        try store.insert(mailRecord(subject: "Unrelated", messageID: "2@example.com", tags: ["misc"]))

        XCTAssertEqual(try store.search("invoice").count, 1)
        XCTAssertEqual(try store.search("finance").count, 1) // tag match
        XCTAssertEqual(try store.search("Jane Doe").count, 2) // subtitle match on both
        XCTAssertEqual(try store.search("nonexistent").count, 0)
        XCTAssertEqual(try store.search("").count, 2) // empty query = recent
    }

    func testDegradedFlagRoundTrips() throws {
        let record = LinkRecord(
            title: "Draft without an ID",
            payload: .mail(MailPayload(messageID: "unknown-x", subject: "Draft without an ID")),
            captureMethod: .applescript,
            degraded: true
        )
        let inserted = try store.insert(record)
        XCTAssertEqual(try store.fetch(id: inserted.id)?.degraded, true)
    }

    func testSearchTreatsLikeWildcardsAsLiteralText() throws {
        try store.insert(mailRecord(subject: "report_final", messageID: "1@example.com", tags: []))
        try store.insert(mailRecord(subject: "reportXfinal", messageID: "2@example.com", tags: []))
        try store.insert(mailRecord(subject: "100% done", messageID: "3@example.com", tags: []))
        try store.insert(mailRecord(subject: "nothing to do with it", messageID: "4@example.com", tags: []))

        // `_` must match a literal underscore, not "any character".
        let underscore = try store.search("report_final")
        XCTAssertEqual(underscore.map(\.title), ["report_final"])

        // A bare `%` must match only rows that literally contain one,
        // not every row in the database.
        XCTAssertEqual(try store.search("%").map(\.title), ["100% done"])

        // And a backslash must not smuggle in an escape of its own.
        XCTAssertEqual(try store.search("\\").count, 0)
    }

    func testSearchHydratesTagsForEveryResult() throws {
        try store.insert(mailRecord(subject: "First", messageID: "1@example.com", tags: ["alpha"]))
        try store.insert(mailRecord(subject: "Second", messageID: "2@example.com", tags: ["beta", "gamma"]))
        try store.insert(mailRecord(subject: "Third", messageID: "3@example.com", tags: []))

        let results = try store.search("Jane Doe")
        XCTAssertEqual(results.count, 3)
        let tagsByTitle = Dictionary(uniqueKeysWithValues: results.map { ($0.title, Set($0.tags)) })
        XCTAssertEqual(tagsByTitle["First"], ["alpha"])
        XCTAssertEqual(tagsByTitle["Second"], ["beta", "gamma"])
        XCTAssertEqual(tagsByTitle["Third"], [])
    }

    func testCountMatchesFetchAll() throws {
        try store.insert(mailRecord(subject: "One", messageID: "1@example.com"))
        let archived = try store.insert(mailRecord(subject: "Two", messageID: "2@example.com"))
        try store.setArchived(true, id: archived.id)

        XCTAssertEqual(try store.count(), 1)
        XCTAssertEqual(try store.count(includeArchived: true), 2)
    }

    func testDedupeByMessageID() throws {
        let original = try store.insert(mailRecord(messageID: "dupe@example.com"))
        let payload = MailPayload(messageID: "dupe@example.com", subject: "Different subject now")
        let existing = try store.findExisting(for: .mail(payload))
        XCTAssertEqual(existing?.id, original.id)

        let noMatch = try store.findExisting(for: .mail(MailPayload(messageID: "other@example.com", subject: "x")))
        XCTAssertNil(noMatch)
    }

    func testDedupeByFileVolumeAndInode() throws {
        let filePayload = FilePayload(
            path: "/Users/tilak/Documents/spec.pdf",
            displayName: "spec.pdf",
            isDirectory: false,
            inode: 42,
            volumeUUID: "VOL-1"
        )
        let record = LinkRecord(title: "spec.pdf", payload: .file(filePayload), captureMethod: .applescript)
        let inserted = try store.insert(record)

        // same volume+inode, different (renamed/moved) path -> still a match
        let movedPayload = FilePayload(
            path: "/Users/tilak/Documents/renamed.pdf",
            displayName: "renamed.pdf",
            isDirectory: false,
            inode: 42,
            volumeUUID: "VOL-1"
        )
        let existing = try store.findExisting(for: .file(movedPayload))
        XCTAssertEqual(existing?.id, inserted.id)
    }

    func testGenericPayloadNeverDedupes() throws {
        let payload = GenericPayload(windowTitle: "notes.txt — ~/scratch")
        let record = LinkRecord(title: "notes.txt", payload: .generic(payload), captureMethod: .axGeneric)
        try store.insert(record)
        let existing = try store.findExisting(for: .generic(payload))
        XCTAssertNil(existing)
    }

    func testDeleteRemovesLink() throws {
        let record = try store.insert(mailRecord())
        try store.delete(id: record.id)
        XCTAssertNil(try store.fetch(id: record.id))
    }

    func testSetArchivedHidesFromDefaultFetchAndSearchButNotFromFetch() throws {
        let record = try store.insert(mailRecord())
        try store.setArchived(true, id: record.id)

        XCTAssertNotNil(try store.fetch(id: record.id), "archiving must not delete the row")
        XCTAssertFalse(try store.fetchAll().contains { $0.id == record.id })
        XCTAssertTrue(try store.fetchAll(includeArchived: true).contains { $0.id == record.id })
        XCTAssertFalse(try store.search("invoice").contains { $0.id == record.id })

        try store.setArchived(false, id: record.id)
        XCTAssertTrue(try store.fetchAll().contains { $0.id == record.id }, "un-archiving must restore visibility")
    }

    func testRecordOpenedBumpsOpenCountAndLastOpenedAt() throws {
        let record = try store.insert(mailRecord())
        XCTAssertEqual(record.openCount, 0)
        try store.recordOpened(id: record.id)
        let fetched = try store.fetch(id: record.id)
        XCTAssertEqual(fetched?.openCount, 1)
        XCTAssertNotNil(fetched?.lastOpenedAt)
    }

    // MARK: - File repair (C2)

    private func fileRecord(path: String, tags: [String] = []) -> LinkRecord {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return LinkRecord(
            title: name,
            payload: .file(FilePayload(path: path, displayName: name, isDirectory: false)),
            bookmarkData: Data([1, 2, 3]),
            captureMethod: .applescript,
            tags: tags
        )
    }

    func testApplyRepairKeepsTagsArchiveAndUpdatedAt() throws {
        let record = try store.insert(fileRecord(path: "/tmp/old/a.txt", tags: ["a"]))
        try store.setArchived(true, id: record.id)
        let before = try XCTUnwrap(store.fetch(id: record.id))

        let newPayload = FilePayload(path: "/tmp/new/b.txt", displayName: "b.txt", isDirectory: false)
        try store.applyRepair(id: record.id, payload: .file(newPayload), bookmarkData: nil,
                              subtitle: "/tmp/new", title: "b.txt")

        let after = try XCTUnwrap(store.fetch(id: record.id))
        XCTAssertEqual(after.tags, ["a"])
        XCTAssertTrue(after.archived)
        XCTAssertEqual(after.updatedAt, before.updatedAt)
        XCTAssertEqual(after.title, "b.txt")
        guard case .file(let payload) = after.payload else { return XCTFail("expected file payload") }
        XCTAssertEqual(payload.path, "/tmp/new/b.txt")
        XCTAssertNotNil(after.repairedAt)
        XCTAssertEqual(after.bookmarkData, Data([1, 2, 3]))
    }

    func testApplyRepairOnDeletedRowDoesNotThrow() throws {
        let record = try store.insert(fileRecord(path: "/tmp/old/a.txt"))
        try store.delete(id: record.id)
        let payload = FilePayload(path: "/tmp/new/a.txt", displayName: "a.txt", isDirectory: false)
        XCTAssertNoThrow(try store.applyRepair(id: record.id, payload: .file(payload), bookmarkData: nil,
                                               subtitle: "/tmp/new", title: "a.txt"))
    }

    // MARK: - Search on payload values (C3)

    private func urlRecord(title: String, url: String, host: String?) -> LinkRecord {
        LinkRecord(
            title: title,
            payload: .url(URLPayload(url: url, host: host, browserBundleID: "com.apple.Safari")),
            captureMethod: .applescript
        )
    }

    func testSearchIgnoresJSONKeyNames() throws {
        try store.insert(urlRecord(title: "Example", url: "https://example.org/a", host: "example.org"))
        XCTAssertEqual(try store.search("host").count, 0)
        XCTAssertEqual(try store.search("browser_bundle_id").count, 0)
        XCTAssertEqual(try store.search("page_title").count, 0)
    }

    func testSearchMatchesURLsWithSlashes() throws {
        let record = try store.insert(urlRecord(title: "Swift", url: "https://github.com/apple/swift", host: "github.com"))
        XCTAssertEqual(try store.search("github.com/apple").map(\.id), [record.id])
    }

    func testSearchMatchesFilePathWithSlashes() throws {
        let payload = FilePayload(path: "/Users/x/Documents/report.pdf", displayName: "report.pdf", isDirectory: false)
        let record = try store.insert(LinkRecord(title: "report.pdf", subtitle: nil, payload: .file(payload), captureMethod: .applescript))
        XCTAssertEqual(try store.search("Documents/report").map(\.id), [record.id])
    }

    func testSearchReturnsEachLinkOnceWhenSeveralTagsMatch() throws {
        try store.insert(mailRecord(subject: "Tagged", messageID: "1@example.com", tags: ["alpha", "alphabet"]))
        let results = try store.search("alpha")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(Set(results.first?.tags ?? []), ["alpha", "alphabet"])
    }

    func testMigrationV2BackfillsSearchText() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclink-migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: path) }

        let goodID = UUID().uuidString.uppercased()
        do {
            let dbQueue = try DatabaseQueue(path: path.path)
            try Migrations.migrator().migrate(dbQueue, upTo: "v1")
            try dbQueue.write { db in
                let insert = """
                    INSERT INTO links (id, resource_type, title, payload, capture_method, created_at, updated_at)
                    VALUES (?, ?, ?, ?, 'applescript', ?, ?)
                    """
                let now = Date().timeIntervalSince1970
                try db.execute(sql: insert, arguments: [
                    goodID, "url", "Repo",
                    #"{"v":1,"url":"https:\/\/github.com\/a\/b","host":"github.com"}"#, now, now
                ])
                try db.execute(sql: insert, arguments: [
                    UUID().uuidString.uppercased(), "url", "Broken", "not json", now, now
                ])
            }
        }

        let migrated = try LinkStore(url: path)
        XCTAssertEqual(try migrated.search("github.com/a").map { $0.id.uuidString.uppercased() }, [goodID])
    }

    func testSetTagsReplacesExistingTags() throws {
        let record = try store.insert(mailRecord())
        try store.setTags(["work", "urgent"], for: record.id)
        let fetched = try store.fetch(id: record.id)
        XCTAssertEqual(Set(fetched?.tags ?? []), ["work", "urgent"])
    }
}
