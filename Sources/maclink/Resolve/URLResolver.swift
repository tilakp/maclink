import AppKit

/// Resolves `.url` links, preferring the browser they were captured from
/// and falling back to the system default (spec §7.4).
struct URLResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .url(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }
        guard let url = URL(string: payload.url) else {
            throw ResolveError.malformedURL
        }
        await MainActor.run {
            if let bundleID = payload.browserBundleID,
               let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } else {
                NSWorkspace.shared.open(url) // system default browser
            }
        }
        return nil
    }
}
