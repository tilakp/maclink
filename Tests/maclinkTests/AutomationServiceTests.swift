import XCTest
@testable import maclink

final class AutomationServiceTests: XCTestCase {
    func testTrivialFinderScript() async throws {
        let result = try await AutomationService.shared.run(
            #"tell application "Finder" to return name of front window"#,
            timeout: 5
        )
        print("RESULT: \(result.stringValue ?? "<nil>")")
    }
}
