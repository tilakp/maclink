import XCTest
@testable import maclink

final class MailCapturerTests: XCTestCase {
    func testNormalizeMessageIDStripsAngleBrackets() {
        XCTAssertEqual(MailCapturer.normalizeMessageID("<abc123@example.com>"), "abc123@example.com")
        XCTAssertEqual(MailCapturer.normalizeMessageID("abc123@example.com"), "abc123@example.com")
        XCTAssertEqual(MailCapturer.normalizeMessageID("  <abc123@example.com>  "), "abc123@example.com")
    }

    func testMessageURLEncodesSpecialCharacters() {
        let url = MailCapturer.messageURLString(for: "abc?123&456@example.com")
        XCTAssertEqual(url, "message://%3Cabc%3F123%26456@example.com%3E")
    }

    func testMessageURLRoundTripsBareID() {
        let bare = MailCapturer.normalizeMessageID("<CAF=abc123$xyz@mail.example.com>")
        let url = MailCapturer.messageURLString(for: bare)
        XCTAssertTrue(url.hasPrefix("message://%3C"))
        XCTAssertTrue(url.hasSuffix("%3E"))
    }

    /// Builds the flat AEList-of-lists shape Mail's AppleScript dictionary
    /// returns, so parsing is testable without actually driving Mail.app
    /// (per the spec's build-order testing notes: keep AEDesc parsing
    /// separate from the scripting itself).
    private func makeDescriptor(rows: [[String]]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (i, row) in rows.enumerated() {
            let rowList = NSAppleEventDescriptor.list()
            for (j, field) in row.enumerated() {
                rowList.insert(NSAppleEventDescriptor(string: field), at: j + 1)
            }
            list.insert(rowList, at: i + 1)
        }
        return list
    }

    func testParseMessagesHappyPath() {
        let descriptor = makeDescriptor(rows: [
            ["abc123@example.com", "Q3 invoice", "Jane Doe <jane@example.com>", "INBOX", "Fastmail", "Monday, January 1, 2026"]
        ])
        let resources = MailCapturer.parseMessages(from: descriptor)
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources[0].title, "Q3 invoice")
        XCTAssertEqual(resources[0].subtitle, "Jane Doe <jane@example.com>")
        if case .mail(let payload) = resources[0].payload {
            XCTAssertEqual(payload.messageID, "abc123@example.com")
            XCTAssertEqual(payload.senderAddress, "jane@example.com")
            XCTAssertEqual(payload.mailbox, "INBOX")
            XCTAssertEqual(payload.account, "Fastmail")
            XCTAssertNotNil(payload.messageURL)
        } else {
            XCTFail("expected mail payload")
        }
    }

    func testParseMessagesWithMissingMessageIDDegradesGracefully() {
        let descriptor = makeDescriptor(rows: [
            ["", "Draft without an ID", "", "Drafts", "", ""]
        ])
        let resources = MailCapturer.parseMessages(from: descriptor)
        XCTAssertEqual(resources.count, 1)
        if case .mail(let payload) = resources[0].payload {
            XCTAssertTrue(payload.messageID.hasPrefix("unknown-"))
            XCTAssertNil(payload.messageURL)
        } else {
            XCTFail("expected mail payload")
        }
    }

    func testParseMessagesMultipleSelection() {
        let descriptor = makeDescriptor(rows: [
            ["id1@example.com", "First", "A <a@example.com>", "INBOX", "Acct", ""],
            ["id2@example.com", "Second", "B <b@example.com>", "INBOX", "Acct", ""]
        ])
        let resources = MailCapturer.parseMessages(from: descriptor)
        XCTAssertEqual(resources.count, 2)
        XCTAssertEqual(resources[1].title, "Second")
    }

    func testParseMessagesEmptyListReturnsEmpty() {
        let descriptor = NSAppleEventDescriptor.list()
        XCTAssertEqual(MailCapturer.parseMessages(from: descriptor).count, 0)
    }
}
