import XCTest
@testable import maclink

final class FileRepairTests: XCTestCase {
    func testRepairedPayloadRefreshesIdentity() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maclink-repair-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let old = FilePayload(path: "/nowhere/old.txt", displayName: "old.txt", isDirectory: false,
                              byteSize: 999, inode: 1)
        let repaired = FileResolver.repairedPayload(from: old, newURL: url)

        var statBuf = stat()
        XCTAssertEqual(stat(url.path, &statBuf), 0)
        XCTAssertEqual(repaired.path, url.path)
        XCTAssertEqual(repaired.displayName, url.lastPathComponent)
        XCTAssertEqual(repaired.byteSize, 5)
        XCTAssertEqual(repaired.inode, Int64(statBuf.st_ino))
    }

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
