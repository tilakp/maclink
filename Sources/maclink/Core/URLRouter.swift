import Foundation

/// Parses `maclink://…` URLs per the spec's §6.1 grammar.
enum MaclinkRoute: Equatable {
    case open(id: UUID, reveal: Bool)
    case show(id: UUID)
    case search(query: String)
    case capture
    case unrecognized(raw: String)

    init(url: URL) {
        guard url.scheme?.lowercased() == "maclink" else {
            self = .unrecognized(raw: url.absoluteString)
            return
        }

        let host = url.host?.lowercased() ?? ""
        // A bare `maclink://<uuid>` (host holds the whole UUID, no path) is an
        // alias for `open/<uuid>` because that's what people type from memory.
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        case "open":
            guard let idString = pathComponents.first, let id = UUID(uuidString: idString) else {
                self = .unrecognized(raw: url.absoluteString)
                return
            }
            let reveal = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "reveal" })?.value == "1"
            self = .open(id: id, reveal: reveal)

        case "show":
            guard let idString = pathComponents.first, let id = UUID(uuidString: idString) else {
                self = .unrecognized(raw: url.absoluteString)
                return
            }
            self = .show(id: id)

        case "search":
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value ?? ""
            self = .search(query: query)

        case "capture":
            self = .capture

        default:
            // Bare `maclink://<uuid>` form: host itself is the UUID.
            if let id = UUID(uuidString: url.host ?? "") {
                self = .open(id: id, reveal: false)
            } else {
                self = .unrecognized(raw: url.absoluteString)
            }
        }
    }
}
