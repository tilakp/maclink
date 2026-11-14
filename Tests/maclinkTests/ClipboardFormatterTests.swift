import XCTest
@testable import maclink

final class ClipboardFormatterTests: XCTestCase {
    private func urlRecord(_ url: String = "https://example.com/a", title: String = "Title") -> LinkRecord {
        LinkRecord(title: title, payload: .url(URLPayload(url: url)), captureMethod: .applescript)
    }

    private func fileRecord(_ path: String = "/tmp/a b.txt", isDirectory: Bool = false) -> LinkRecord {
        LinkRecord(
            title: (path as NSString).lastPathComponent,
            payload: .file(FilePayload(path: path, displayName: (path as NSString).lastPathComponent, isDirectory: isDirectory)),
            captureMethod: .applescript
        )
    }

    private func mailRecord(messageID: String) -> LinkRecord {
        LinkRecord(title: "Mail", payload: .mail(MailPayload(messageID: messageID, subject: "Mail")), captureMethod: .applescript)
    }

    private let genericRecord = LinkRecord(
        title: "Window",
        payload: .generic(GenericPayload(windowTitle: "Window")),
        captureMethod: .axGeneric
    )

    func testRawIsTheURL() {
        XCTAssertEqual(ClipboardFormatter.format(url: "u", title: "T", as: .raw), "u")
    }

    func testOrgSwapsBrackets() {
        XCTAssertEqual(ClipboardFormatter.format(url: "u", title: "Re: [list] foo]", as: .org), "[[u][Re: {list} foo}]]")
    }

    func testMarkdownEscapesBracketsAndBackslash() {
        XCTAssertEqual(ClipboardFormatter.format(url: "u", title: #"a [b] \ c"#, as: .markdown), #"[a \[b\] \\ c](u)"#)
    }

    func testMarkdownDestinationWrapsParens() {
        XCTAssertEqual(ClipboardFormatter.markdownDestination("https://en.wikipedia.org/wiki/Foo_(bar)"),
                       "<https://en.wikipedia.org/wiki/Foo_(bar)>")
        XCTAssertEqual(ClipboardFormatter.markdownDestination("https://a.com/x"), "https://a.com/x")
    }

    func testAddress() {
        XCTAssertEqual(ClipboardFormatter.address(for: urlRecord()), "https://example.com/a")
        XCTAssertEqual(ClipboardFormatter.address(for: fileRecord()), "/tmp/a b.txt")
        XCTAssertEqual(ClipboardFormatter.address(for: mailRecord(messageID: "abc@x.com")),
                       MailCapturer.messageURLString(for: "abc@x.com"))
        XCTAssertNil(ClipboardFormatter.address(for: mailRecord(messageID: "unknown-123")))
        XCTAssertNil(ClipboardFormatter.address(for: genericRecord))
    }

    func testFileURL() {
        XCTAssertEqual(ClipboardFormatter.fileURL(for: fileRecord()), "file:///tmp/a%20b.txt")
        XCTAssertEqual(ClipboardFormatter.fileURL(for: fileRecord("/tmp/folder", isDirectory: true))?.hasSuffix("/"), true)
        XCTAssertNil(ClipboardFormatter.fileURL(for: urlRecord()))
    }

    func testMarkdownAddressIsAlwaysMarkdown() {
        XCTAssertEqual(ClipboardFormatter.text(for: fileRecord(), kind: .markdownAddress, format: .org),
                       "[a b.txt](file:///tmp/a%20b.txt)")
        XCTAssertEqual(ClipboardFormatter.text(for: urlRecord(), kind: .markdownAddress, format: .org),
                       "[Title](https://example.com/a)")
        XCTAssertNil(ClipboardFormatter.text(for: genericRecord, kind: .markdownAddress, format: .org))
    }

    func testLinkUsesChosenFormat() {
        let record = urlRecord()
        XCTAssertEqual(ClipboardFormatter.text(for: record, kind: .link, format: .markdown),
                       "[Title](maclink://open/\(record.id.uuidString))")
    }
}
