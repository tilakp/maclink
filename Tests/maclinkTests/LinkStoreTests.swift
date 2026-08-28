import XCTest
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

    func testFetchAllOrdersByCreatedAtDescending() throws {
        let first = try store.insert(mailRecord(subject: "First", messageID: "1@example.com"))
        Thread.sleep(forTimeInterval: 0.01)
        let second = try store.insert(mailRecord(subject: "Second", messageID: "2@example.com"))

        let all = try store.fetchAll()
        XCTAssertEqual(all.map(\.id), [second.id, first.id])
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

    func testSetTagsReplacesExistingTags() throws {
        let record = try store.insert(mailRecord())
        try store.setTags(["work", "urgent"], for: record.id)
        let fetched = try store.fetch(id: record.id)
        XCTAssertEqual(Set(fetched?.tags ?? []), ["work", "urgent"])
    }
}
