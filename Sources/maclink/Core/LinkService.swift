import Foundation

/// Facade over capture / resolve / search, per the architecture in spec §4.2.
/// Wired up incrementally: this milestone only proves the `maclink://` URL
/// round trip end to end. Capture/search/DB land in later build-order steps.
final class LinkService {
    static let shared = LinkService()

    private init() {}

    func handle(_ url: URL) {
        let route = MaclinkRoute(url: url)
        Log.resolve.info("route: \(String(describing: route), privacy: .public)")

        switch route {
        case .open(let id, let reveal):
            recordDiagnostic("open id=\(id.uuidString) reveal=\(reveal)")
            // TODO(build-order step 5+): ResolveEngine.shared.resolve(id, reveal: reveal)
        case .show(let id):
            recordDiagnostic("show id=\(id.uuidString)")
        case .search(let query):
            recordDiagnostic("search q=\(query)")
        case .capture:
            recordDiagnostic("capture (external trigger)")
            captureFromHotkey()
        case .unrecognized(let raw):
            recordDiagnostic("unrecognized: \(raw)")
        }
    }

    func captureFromHotkey() {
        Log.capture.info("capture requested (not yet implemented)")
        recordDiagnostic("capture requested (stub)")
    }

    func showSearchPanel() {
        Log.ui.info("search panel requested (not yet implemented)")
        recordDiagnostic("search panel requested (stub)")
    }

    /// Temporary: appends a line to a plain-text log so URL-scheme handling
    /// can be verified from the terminal before there's any UI to look at.
    /// Remove once the real resolve/capture paths exist.
    private func recordDiagnostic(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = Paths.appSupportDirectory.appendingPathComponent("diagnostic.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
