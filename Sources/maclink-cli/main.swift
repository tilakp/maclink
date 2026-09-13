import Foundation
import GRDB

// A thin, read-only CLI over maclink's SQLite database (spec §10.3). It is a
// separate executable from the app on purpose: it opens the database
// read-only so it can never contend with or corrupt the app's writes, and it
// only needs a handful of columns, not the app's full LinkRecord/Payload
// model.

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case notFound(String)

    var description: String {
        switch self {
        case .usage(let message), .notFound(let message):
            return message
        }
    }
}

let usage = """
    Usage:
      maclink latest [--org|--json|--url]
      maclink get <uuid> [--json]
      maclink search <query> [--json] [--limit N]
      maclink capture

    Reads maclink's database read-only. "capture" opens maclink://capture,
    which triggers a normal capture in the running app.
    """

// MARK: - Database

let databaseURL: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base
        .appendingPathComponent("com.tilak.maclink", isDirectory: true)
        .appendingPathComponent("maclink.sqlite")
}()

func openDatabase() throws -> DatabaseQueue {
    var config = Configuration()
    config.readonly = true
    return try DatabaseQueue(path: databaseURL.path, configuration: config)
}

struct Link {
    let id: String
    let title: String
    let subtitle: String?
    let resourceType: String
    let createdAt: Date
    var tags: [String] = []

    var url: String { "maclink://open/\(id)" }
}

/// Same escaping `LinkStore.search` uses: `%`/`_` are LIKE wildcards, so a
/// literal query containing either must not be treated as a pattern.
func escapedForLike(_ query: String) -> String {
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

/// Fetches links matching `whereClause` (ANDed onto `archived = 0`), then
/// hydrates tags in one follow-up query rather than via GROUP_CONCAT, so a
/// tag-matching search still returns each link's full tag list, not just the
/// tag that matched.
func fetchLinks(
    db: Database,
    whereClause: String,
    arguments: StatementArguments,
    limit: Int
) throws -> [Link] {
    let rows = try Row.fetchAll(db, sql: """
        SELECT DISTINCT links.id AS id, links.title AS title, links.subtitle AS subtitle,
               links.resource_type AS resource_type, links.created_at AS created_at
        FROM links
        LEFT JOIN link_tags ON link_tags.link_id = links.id
        LEFT JOIN tags ON tags.id = link_tags.tag_id
        WHERE links.archived = 0 \(whereClause)
        ORDER BY links.created_at DESC
        LIMIT ?
        """, arguments: arguments + [limit])

    var links = rows.map {
        Link(
            id: $0["id"],
            title: $0["title"],
            subtitle: $0["subtitle"],
            resourceType: $0["resource_type"],
            createdAt: Date(timeIntervalSince1970: $0["created_at"] as Double)
        )
    }

    guard !links.isEmpty else { return links }
    let ids = links.map { $0.id }
    let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
    let tagRows = try Row.fetchAll(db, sql: """
        SELECT link_tags.link_id AS link_id, tags.name AS name FROM tags
        JOIN link_tags ON link_tags.tag_id = tags.id
        WHERE link_tags.link_id IN (\(placeholders))
        ORDER BY tags.name
        """, arguments: StatementArguments(ids))
    var tagsByID: [String: [String]] = [:]
    for row in tagRows {
        tagsByID[row["link_id"], default: []].append(row["name"])
    }
    for i in links.indices {
        links[i].tags = tagsByID[links[i].id] ?? []
    }
    return links
}

// MARK: - JSON output

struct JSONLink: Encodable {
    let id: String
    let url: String
    let title: String
    let subtitle: String?
    let resourceType: String
    let tags: [String]
    let createdAt: Date
}

func toJSONLink(_ link: Link) -> JSONLink {
    JSONLink(
        id: link.id, url: link.url, title: link.title, subtitle: link.subtitle,
        resourceType: link.resourceType, tags: link.tags, createdAt: link.createdAt
    )
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: try encoder.encode(value), encoding: .utf8)!)
}

// MARK: - Commands

func runLatest(_ args: [String]) throws {
    var format = "url"
    for arg in args {
        switch arg {
        case "--org", "--json", "--url": format = String(arg.dropFirst(2))
        default: throw CLIError.usage("unknown option: \(arg)\n\n\(usage)")
        }
    }
    let db = try openDatabase()
    let link = try db.read { db in
        try fetchLinks(db: db, whereClause: "", arguments: [], limit: 1)
    }.first
    guard let link else { throw CLIError.notFound("no links captured yet") }
    switch format {
    case "org": print("[[\(link.url)][\(link.title)]]")
    case "json": try printJSON(toJSONLink(link))
    default: print(link.url)
    }
}

func runGet(_ args: [String]) throws {
    guard let idArg = args.first else { throw CLIError.usage("usage: maclink get <uuid> [--json]") }
    guard UUID(uuidString: idArg) != nil else { throw CLIError.usage("not a valid uuid: \(idArg)") }
    let asJSON = args.dropFirst().contains("--json")

    let db = try openDatabase()
    let link = try db.read { db in
        try fetchLinks(db: db, whereClause: "AND links.id = ?", arguments: [idArg.uppercased()], limit: 1)
    }.first
    guard let link else { throw CLIError.notFound("no link with id \(idArg)") }

    if asJSON {
        try printJSON(toJSONLink(link))
    } else {
        print("\(link.title)\t\(link.url)")
    }
}

func runSearch(_ args: [String]) throws {
    var asJSON = false
    var limit = 100
    var terms: [String] = []
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--json":
            asJSON = true
        case "--limit":
            i += 1
            guard i < args.count, let n = Int(args[i]) else {
                throw CLIError.usage("--limit requires a number")
            }
            limit = n
        default:
            terms.append(args[i])
        }
        i += 1
    }
    let query = terms.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

    let db = try openDatabase()
    let links = try db.read { db -> [Link] in
        if query.isEmpty {
            return try fetchLinks(db: db, whereClause: "", arguments: [], limit: limit)
        }
        let like = "%\(escapedForLike(query))%"
        return try fetchLinks(
            db: db,
            whereClause: """
                AND (links.title LIKE ? ESCAPE '\\' OR links.subtitle LIKE ? ESCAPE '\\' OR
                     links.notes LIKE ? ESCAPE '\\' OR links.payload LIKE ? ESCAPE '\\' OR
                     tags.name LIKE ? ESCAPE '\\')
                """,
            arguments: [like, like, like, like, like],
            limit: limit
        )
    }

    if asJSON {
        try printJSON(links.map(toJSONLink))
    } else {
        // First tab field is `open/<uuid>`, not the full maclink:// URL, so
        // `maclink-org-complete` in contrib/maclink.el can prefix it with the
        // `maclink:` org link type directly (see spec §10.4).
        for link in links {
            let label = link.subtitle.map { "\(link.title) · \($0)" } ?? link.title
            print("open/\(link.id)\t\(label)")
        }
    }
}

func runCapture() throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["maclink://capture"]
    try process.run()
    process.waitUntilExit()
}

// MARK: - Entry point

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    guard let command = arguments.first else { throw CLIError.usage(usage) }
    let rest = Array(arguments.dropFirst())
    switch command {
    case "latest": try runLatest(rest)
    case "get": try runGet(rest)
    case "search": try runSearch(rest)
    case "capture": try runCapture()
    default: throw CLIError.usage("unknown command: \(command)\n\n\(usage)")
    }
} catch let error as CLIError {
    FileHandle.standardError.write((error.description + "\n").data(using: .utf8)!)
    exit(1)
} catch {
    FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
    exit(1)
}
