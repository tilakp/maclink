import Foundation

enum ResolveError: Error {
    case notImplemented(ResourceType)
    case fileNotFound
    case bookmarkResolutionFailed
    case noStableIdentifier
    case malformedURL
    case appNotInstalled
    /// The user chose "Delete Link" from the file repair ladder (spec
    /// §7.6 step 5) after the file couldn't be found or relinked.
    case linkDeleted
}

/// A per-resource-type strategy that brings the user back to a captured
/// resource (spec §4.2). Resolvers own repair (§7.6) and activate the
/// target app themselves; `ResolveEngine` just dispatches to one.
protocol Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord?
}

extension Resolver {
    /// Default: most resolvers don't need to rewrite the record.
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? { nil }
}
