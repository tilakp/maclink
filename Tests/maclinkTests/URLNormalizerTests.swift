import XCTest
@testable import maclink

final class URLNormalizerTests: XCTestCase {
    private func assertNormalized(_ input: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(URLNormalizer.normalize(input), expected, file: file, line: line)
    }

    private func assertUnchanged(_ input: String, file: StaticString = #filePath, line: UInt = #line) {
        assertNormalized(input, input, file: file, line: line)
    }

    func testStripsUTMParams() {
        assertNormalized("https://example.com/page?utm_source=x&utm_campaign=y&id=42", "https://example.com/page?id=42")
    }

    func testRemovesQueryWhenAllParamsAreTracking() {
        assertNormalized("https://example.com/page?fbclid=abc", "https://example.com/page")
    }

    func testKeepsFragment() {
        assertNormalized("https://example.com/page?utm_source=x#section-2", "https://example.com/page#section-2")
    }

    func testNonTrackingQueryUnchanged() {
        assertUnchanged("https://example.com/page?id=42&sort=asc")
    }

    func testNoQueryUnchanged() {
        assertUnchanged("https://example.com/page")
    }

    func testRefIsKept() {
        assertUnchanged("https://github.com/a/b/tree/main?ref=main")
    }

    func testEncodingKeptWhenParamRemoved() {
        assertNormalized("https://example.com/s?q=a+b&x=%20y&utm_medium=z", "https://example.com/s?q=a+b&x=%20y")
    }

    func testEncodingKeptWhenNothingRemoved() {
        assertUnchanged("https://example.com/s?q=a+b&x=%20y")
    }

    func testLowercasesSchemeAndHostNotPath() {
        assertNormalized("HTTPS://Example.COM/Path", "https://example.com/Path")
    }

    func testDropsDefaultHTTPSPort() {
        assertNormalized("https://example.com:443/a", "https://example.com/a")
    }

    func testDropsDefaultHTTPPort() {
        assertNormalized("http://example.com:80/a", "http://example.com/a")
    }

    func testKeepsOtherPort() {
        assertUnchanged("https://example.com:8443/a")
    }

    func testEmptyPathBecomesSlash() {
        assertNormalized("https://example.com", "https://example.com/")
    }

    func testStripsSiOnYouTube() {
        assertNormalized("https://www.youtube.com/watch?v=abc&si=xyz&t=42", "https://www.youtube.com/watch?v=abc&t=42")
    }

    func testKeepsSiOnOtherHosts() {
        assertUnchanged("https://example.com/?si=keep")
    }

    func testParamNamesAreCaseInsensitive() {
        assertNormalized("https://example.com/?UTM_Source=x&a=1", "https://example.com/?a=1")
    }

    func testFileURLUnchanged() {
        assertUnchanged("file:///Users/x/a.txt")
    }

    func testAboutBlankUnchanged() {
        assertUnchanged("about:blank")
    }

    func testNotAURLUnchanged() {
        assertUnchanged("not a url")
    }

    // MARK: - CapturedResource.web

    func testWebBuildsNormalizedResource() throws {
        let input = "https://Example.com/?utm_source=x"
        let resource = try XCTUnwrap(CapturedResource.web(fields: [input, "Title"], bundleID: "com.apple.Safari", appName: "Safari"))
        guard case .url(let payload) = resource.payload else { return XCTFail("expected a url payload") }
        XCTAssertEqual(payload.url, "https://example.com/")
        XCTAssertEqual(payload.rawURL, input)
        XCTAssertEqual(payload.host, "example.com")
        XCTAssertEqual(resource.title, "Title")
        XCTAssertEqual(payload.browserBundleID, "com.apple.Safari")
    }

    func testWebEmptyURLIsNil() {
        XCTAssertNil(CapturedResource.web(fields: ["", "x"], bundleID: "com.apple.Safari", appName: "Safari"))
    }

    func testWebWrongFieldCountIsNil() {
        XCTAssertNil(CapturedResource.web(fields: ["https://a.com/"], bundleID: "com.apple.Safari", appName: "Safari"))
    }

    func testWebEmptyTitleUsesURL() throws {
        let resource = try XCTUnwrap(CapturedResource.web(fields: ["https://a.com/", ""], bundleID: "com.apple.Safari", appName: "Safari"))
        guard case .url(let payload) = resource.payload else { return XCTFail("expected a url payload") }
        XCTAssertEqual(resource.title, payload.url)
        XCTAssertNil(payload.pageTitle)
    }
}
