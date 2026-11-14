import Foundation

/// Cleans a captured web URL before it is stored and used as the dedupe key
/// (spec §7.4, §8.5). Only http and https URLs change. Everything else
/// (file:, about:, chrome:, ...) comes back as given.
enum URLNormalizer {
    /// Any parameter whose lowercased name starts with this prefix is removed.
    static let trackingPrefix = "utm_"
    /// Removed on every host.
    static let trackingParams: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid",
        "mc_cid", "mc_eid", "igshid", "yclid", "twclid", "_hsenc", "_hsmi", "mkt_tok"
    ]
    /// Removed only on these hosts and their subdomains.
    static let hostTrackingParams: [String: Set<String>] = [
        "youtube.com": ["si"], "youtu.be": ["si"], "spotify.com": ["si"]
    ]

    static func normalize(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return urlString
        }
        components.scheme = scheme
        if let host = components.percentEncodedHost {
            components.percentEncodedHost = host.lowercased()
        }
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.percentEncodedPath.isEmpty {
            components.percentEncodedPath = "/"
        }
        if let items = components.percentEncodedQueryItems {
            let host = components.percentEncodedHost ?? ""
            let hostParams = hostTrackingParams
                .filter { host == $0.key || host.hasSuffix("." + $0.key) }
                .reduce(into: Set<String>()) { $0.formUnion($1.value) }
            let kept = items.filter { item in
                let name = item.name.lowercased()
                return !(name.hasPrefix(trackingPrefix) || trackingParams.contains(name) || hostParams.contains(name))
            }
            // Assign only when something was removed, so the query keeps its exact encoding otherwise.
            if kept.count != items.count {
                components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
            }
        }
        return components.string ?? urlString
    }
}
