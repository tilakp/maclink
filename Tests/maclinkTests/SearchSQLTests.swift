import XCTest
import MaclinkShared

final class SearchSQLTests: XCTestCase {
    func testEscapesUnderscore() {
        XCTAssertEqual(SearchSQL.escapedForLike("report_final"), "report\\_final")
    }

    func testEscapesPercent() {
        XCTAssertEqual(SearchSQL.escapedForLike("100%"), "100\\%")
    }

    func testEscapesBackslash() {
        XCTAssertEqual(SearchSQL.escapedForLike("a\\b"), "a\\\\b")
    }

    func testArgumentsAreFiveCopiesOfThePattern() {
        XCTAssertEqual(SearchSQL.arguments(for: "x"), Array(repeating: "%x%", count: 5))
    }

    func testMatchConditionHasFivePlaceholders() {
        XCTAssertEqual(SearchSQL.matchCondition.filter { $0 == "?" }.count, 5)
    }
}
