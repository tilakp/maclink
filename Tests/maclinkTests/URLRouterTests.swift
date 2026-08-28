import XCTest
@testable import maclink

final class URLRouterTests: XCTestCase {
    func testOpenRoute() {
        let id = UUID()
        let route = MaclinkRoute(url: URL(string: "maclink://open/\(id.uuidString)")!)
        XCTAssertEqual(route, .open(id: id, reveal: false))
    }

    func testOpenRouteWithReveal() {
        let id = UUID()
        let route = MaclinkRoute(url: URL(string: "maclink://open/\(id.uuidString)?reveal=1")!)
        XCTAssertEqual(route, .open(id: id, reveal: true))
    }

    func testBareUUIDIsAliasForOpen() {
        let id = UUID()
        let route = MaclinkRoute(url: URL(string: "maclink://\(id.uuidString)")!)
        XCTAssertEqual(route, .open(id: id, reveal: false))
    }

    func testSearchRouteDecodesQuery() {
        let route = MaclinkRoute(url: URL(string: "maclink://search?q=invoice%20mail")!)
        XCTAssertEqual(route, .search(query: "invoice mail"))
    }

    func testCaptureRoute() {
        let route = MaclinkRoute(url: URL(string: "maclink://capture")!)
        XCTAssertEqual(route, .capture)
    }

    func testUnrecognizedSchemeDoesNotCrash() {
        let route = MaclinkRoute(url: URL(string: "https://example.com")!)
        XCTAssertEqual(route, .unrecognized(raw: "https://example.com"))
    }

    func testMalformedUUIDIsUnrecognized() {
        let route = MaclinkRoute(url: URL(string: "maclink://open/not-a-uuid")!)
        if case .unrecognized = route {
            // ok
        } else {
            XCTFail("expected unrecognized route, got \(route)")
        }
    }
}
