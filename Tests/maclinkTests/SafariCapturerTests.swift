import XCTest
@testable import maclink

final class SafariCapturerTests: XCTestCase {
    func testStripsTrackingParams() {
        let result = SafariCapturer.stripTrackingParams(
            from: "https://example.com/page?utm_source=x&utm_campaign=y&id=42"
        )
        XCTAssertEqual(result, "https://example.com/page?id=42")
    }

    func testRemovesQueryEntirelyWhenAllParamsAreTracking() {
        let result = SafariCapturer.stripTrackingParams(from: "https://example.com/page?fbclid=abc")
        XCTAssertEqual(result, "https://example.com/page")
    }

    func testLeavesFragmentIntact() {
        let result = SafariCapturer.stripTrackingParams(from: "https://example.com/page?utm_source=x#section-2")
        XCTAssertEqual(result, "https://example.com/page#section-2")
    }

    func testLeavesNonTrackingURLUnchanged() {
        let result = SafariCapturer.stripTrackingParams(from: "https://example.com/page?id=42&sort=asc")
        XCTAssertEqual(result, "https://example.com/page?id=42&sort=asc")
    }

    func testURLWithNoQueryIsUnchanged() {
        let result = SafariCapturer.stripTrackingParams(from: "https://example.com/page")
        XCTAssertEqual(result, "https://example.com/page")
    }
}
