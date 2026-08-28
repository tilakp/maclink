import XCTest
@testable import maclink

final class AutomationServiceTests: XCTestCase {
    /// Deliberately doesn't touch `front window`. That fails whenever
    /// Finder has no window open, which made this test flaky depending on
    /// what else was going on on the machine. `name of application` needs
    /// no window and still exercises the real AppleScript round trip
    /// (compile, dispatch to the automation queue, execute, decode).
    func testTrivialFinderScript() async throws {
        let result = try await AutomationService.shared.run(
            #"tell application "Finder" to return name of application "Finder""#,
            timeout: 5
        )
        XCTAssertEqual(result.stringValue, "Finder")
    }
}
