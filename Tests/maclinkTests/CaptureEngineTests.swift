import XCTest
@testable import maclink

final class CaptureEngineTests: XCTestCase {
    func testMalformedResultFallsBack() {
        XCTAssertNil(CaptureEngine.errorToSurface(for: AutomationError.malformedResult))
    }

    func testNoSelectionScriptErrorsBecomeNoSelection() {
        for number in [1000, 1002] {
            guard case CaptureError.noSelection? = CaptureEngine.errorToSurface(for: AutomationError.scriptError(number, "x")) else {
                return XCTFail("script error \(number) should become noSelection")
            }
        }
    }

    func testPermissionDeniedIsSurfaced() {
        let result = CaptureEngine.errorToSurface(for: AutomationError.permissionDenied)
        XCTAssertEqual(result as? AutomationError, .permissionDenied)
    }

    func testTimeoutIsSurfaced() {
        let result = CaptureEngine.errorToSurface(for: AutomationError.timeout)
        XCTAssertEqual(result as? AutomationError, .timeout)
    }

    func testOtherScriptErrorIsSurfaced() {
        let error = AutomationError.scriptError(-1728, "Can't get object.")
        XCTAssertEqual(CaptureEngine.errorToSurface(for: error) as? AutomationError, error)
    }

    func testCaptureErrorNoSelectionIsSurfaced() {
        guard case CaptureError.noSelection? = CaptureEngine.errorToSurface(for: CaptureError.noSelection) else {
            return XCTFail("CaptureError.noSelection should be surfaced")
        }
    }
}
