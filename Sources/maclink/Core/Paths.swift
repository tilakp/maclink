import Foundation

enum Paths {
    /// `~/Library/Application Support/com.tilak.maclink/`, created on first access.
    static var appSupportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("com.tilak.maclink", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var databaseURL: URL {
        appSupportDirectory.appendingPathComponent("maclink.sqlite")
    }
}
