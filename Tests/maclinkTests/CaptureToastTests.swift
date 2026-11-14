import XCTest
@testable import maclink

final class CaptureToastTests: XCTestCase {
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

    /// F3: tags typed in the toast for an existing link used to replace
    /// its old tags.
    func testTagsTypedForExistingLinkKeepOldTags() throws {
        let record = try store.insert(LinkRecord(
            title: "Page",
            payload: .url(URLPayload(url: "https://example.com/")),
            captureMethod: .applescript,
            tags: ["a"]
        ))
        CaptureToastController.addTags("b", to: [record], store: store)
        XCTAssertEqual(try store.fetch(id: record.id)?.tags, ["a", "b"])
    }

    func testMergedTagsAddsNewTag() {
        XCTAssertEqual(CaptureToastController.mergedTags(existing: ["a"], typed: "b"), ["a", "b"])
    }

    func testMergedTagsIgnoresCaseDuplicates() {
        XCTAssertEqual(CaptureToastController.mergedTags(existing: ["Work"], typed: "work, home"), ["Work", "home"])
    }

    func testMergedTagsDropsRepeatsAndEmptyParts() {
        XCTAssertEqual(CaptureToastController.mergedTags(existing: [], typed: "a a,  b"), ["a", "b"])
    }

    func testMergedTagsWithOnlySpacesKeepsExisting() {
        XCTAssertEqual(CaptureToastController.mergedTags(existing: ["a"], typed: "  "), ["a"])
    }
}
