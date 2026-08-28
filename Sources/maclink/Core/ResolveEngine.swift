/// Dispatches a `LinkRecord` to the resolver for its resource type (spec §4.2).
final class ResolveEngine {
    static let shared = ResolveEngine()

    private let fileResolver = FileResolver()
    private let mailResolver = MailResolver()
    private let urlResolver = URLResolver()
    private let genericResolver = GenericResolver()

    private init() {}

    /// Resolves the record and returns a repaired version to persist, if
    /// the resolver rewrote anything (e.g. a stale bookmark).
    @discardableResult
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        switch record.payload {
        case .file:
            return try await fileResolver.resolve(record, reveal: reveal)
        case .mail:
            return try await mailResolver.resolve(record, reveal: reveal)
        case .url:
            return try await urlResolver.resolve(record, reveal: reveal)
        case .generic:
            return try await genericResolver.resolve(record, reveal: reveal)
        }
    }
}
