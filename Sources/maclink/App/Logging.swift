import OSLog

enum Log {
    private static let subsystem = "com.tilak.maclink"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let capture = Logger(subsystem: subsystem, category: "capture")
    static let resolve = Logger(subsystem: subsystem, category: "resolve")
    static let automation = Logger(subsystem: subsystem, category: "automation")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
