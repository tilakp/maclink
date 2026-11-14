import AppKit
import XCTest
@testable import maclink

final class ChromiumCapturerTests: XCTestCase {
    func testScriptTargetsBundleIDAndUsesChromeDialect() {
        let script = ChromiumCapturer.script(for: "com.brave.Browser")
        XCTAssertTrue(script.contains(#"tell application id "com.brave.Browser""#))
        XCTAssertTrue(script.contains("active tab of front window"))
        XCTAssertTrue(script.contains("title of t"))
        XCTAssertTrue(script.contains("number 1002"))
    }

    func testScriptCompiles() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACLINK_LIVE_TESTS"] == "1",
                          "live test: set MACLINK_LIVE_TESTS=1 to run")
        try XCTSkipUnless(NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil,
                          "Chrome is not installed")
        var err: NSDictionary?
        let compiled = NSAppleScript(source: ChromiumCapturer.script(for: "com.google.Chrome"))!.compileAndReturnError(&err)
        XCTAssertTrue(compiled, "compile error: \(String(describing: err))")
    }

    func testSupportedBundleIDsIncludeMainBrowsers() {
        let ids = ChromiumCapturer.bundleIDs
        for id in ["com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi"] {
            XCTAssertTrue(ids.contains(id), "\(id) missing")
        }
        XCTAssertFalse(ids.contains("com.apple.Safari"))
    }

    func testEngineRoutesNoBrowserTwice() {
        XCTAssertTrue(SafariCapturer().supportedBundleIDs.isDisjoint(with: ChromiumCapturer.bundleIDs))
    }
}
