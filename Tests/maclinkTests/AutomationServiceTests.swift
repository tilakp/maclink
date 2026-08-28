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

    /// A hung target app must surface as `.timeout` *and* must not wedge the
    /// service: the orphaned thread keeps running the script it was given,
    /// so the next call has to get a fresh one rather than re-entering the
    /// same NSAppleScript instance from a second thread.
    func testTimeoutFailsFastAndLeavesTheServiceUsable() async throws {
        let started = Date()
        do {
            _ = try await AutomationService.shared.run("delay 1", timeout: 0.3)
            XCTFail("expected the call to time out")
        } catch let error as AutomationError {
            XCTAssertEqual(error, .timeout)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.9, "the caller must not wait out the whole script")

        // Still usable while the orphaned thread runs on: the serial queue
        // was released, and the timed-out script was dropped from the cache.
        let result = try await AutomationService.shared.run(#"return "still here""#, timeout: 5)
        XCTAssertEqual(result.stringValue, "still here")

        // Let the orphan retire before the next test starts. A live
        // AppleScript execution spanning a test boundary upsets XCTest's own
        // run-loop bookkeeping and fails whichever test comes next.
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    func testSyntaxErrorSurfacesAsScriptError() async throws {
        do {
            _ = try await AutomationService.shared.run("this is not applescript", timeout: 5)
            XCTFail("expected a compile failure")
        } catch let error as AutomationError {
            guard case .scriptError = error else {
                return XCTFail("expected .scriptError, got \(error)")
            }
        }
    }
}
