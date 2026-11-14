/// The text-search condition shared by the app (`LinkStore.search`) and the
/// CLI (`maclink search`). `raycast-extension/src/db.ts` has a TypeScript
/// copy; keep it in step. Use inside `... FROM links WHERE ... AND <matchCondition>`
/// and bind `arguments(for:)` (five values) before any other argument
/// that comes after it.
public enum SearchSQL {
    public static let matchCondition = """
        (links.title LIKE ? ESCAPE '\\' OR links.subtitle LIKE ? ESCAPE '\\' OR
         links.notes LIKE ? ESCAPE '\\' OR links.search_text LIKE ? ESCAPE '\\' OR
         EXISTS (SELECT 1 FROM link_tags JOIN tags ON tags.id = link_tags.tag_id
                 WHERE link_tags.link_id = links.id AND tags.name LIKE ? ESCAPE '\\'))
        """

    /// Five copies of the `%query%` pattern, one per `?` in `matchCondition`.
    public static func arguments(for query: String) -> [String] {
        Array(repeating: "%\(escapedForLike(query))%", count: 5)
    }

    /// `%` and `_` are LIKE wildcards; escape them and the escape character
    /// itself, to pair with `ESCAPE '\'`.
    public static func escapedForLike(_ query: String) -> String {
        var out = ""
        out.reserveCapacity(query.count)
        for character in query {
            if character == "\\" || character == "%" || character == "_" {
                out.append("\\")
            }
            out.append(character)
        }
        return out
    }
}
