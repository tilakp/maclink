import XCTest
@testable import maclink

final class FileRepairTests: XCTestCase {
    func testSpotlightFindsThisTestFile() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MACLINK_LIVE_TESTS"] == "1",
                          "live test: set MACLINK_LIVE_TESTS=1 to run")
        let url = URL(fileURLWithPath: #filePath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-name", "FileRepairTests.swift"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard output.split(separator: "\n").contains(where: { $0 == url.path }) else {
            throw XCTSkip("Spotlight has not indexed \(url.path) yet")
        }

        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        let hits = await FileRelinker.spotlightSearch(name: url.lastPathComponent, size: size)
        XCTAssertTrue(hits.map(\.path).contains(url.path))
    }
}
