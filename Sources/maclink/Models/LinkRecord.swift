import Foundation
import GRDB

/// One row in `links` (spec §8.2). Payload JSON/blob encoding is handled
/// explicitly here rather than via GRDB's Codable synthesis, since the JSON
/// shape depends on `resourceType` (see Payload.swift) and dates are stored
/// as unix-epoch REALs, not ISO8601 strings.
struct LinkRecord: Identifiable, Equatable {
    var id: UUID
    var resourceType: ResourceType
    var title: String
    var subtitle: String?
    var payload: Payload
    var bookmarkData: Data?
    var sourceBundleID: String?
    var sourceAppName: String?
    var captureMethod: CaptureMethod
    var notes: String
    var degraded: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var openCount: Int
    var repairedAt: Date?
    var archived: Bool

    /// Hydrated separately via `link_tags`; not a column on `links`.
    var tags: [String] = []

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        payload: Payload,
        bookmarkData: Data? = nil,
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        captureMethod: CaptureMethod,
        notes: String = "",
        degraded: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        lastOpenedAt: Date? = nil,
        openCount: Int = 0,
        repairedAt: Date? = nil,
        archived: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.resourceType = payload.resourceType
        self.title = title
        self.subtitle = subtitle
        self.payload = payload
        self.bookmarkData = bookmarkData
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.captureMethod = captureMethod
        self.notes = notes
        self.degraded = degraded
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.lastOpenedAt = lastOpenedAt
        self.openCount = openCount
        self.repairedAt = repairedAt
        self.archived = archived
        self.tags = tags
    }
}

// MARK: - GRDB

extension LinkRecord: FetchableRecord, PersistableRecord {
    static let databaseTableName = "links"

    enum Columns {
        static let id = Column("id")
        static let resourceType = Column("resource_type")
        static let title = Column("title")
        static let subtitle = Column("subtitle")
        static let payload = Column("payload")
        static let payloadBlob = Column("payload_blob")
        static let sourceBundleID = Column("source_bundle_id")
        static let sourceAppName = Column("source_app_name")
        static let captureMethod = Column("capture_method")
        static let notes = Column("notes")
        static let degraded = Column("degraded")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
        static let lastOpenedAt = Column("last_opened_at")
        static let openCount = Column("open_count")
        static let repairedAt = Column("repaired_at")
        static let archived = Column("archived")
    }

    init(row: Row) throws {
        let idString: String = row[Columns.id]
        guard let uuid = UUID(uuidString: idString) else {
            throw DatabaseError(message: "links.id is not a valid UUID: \(idString)")
        }
        let resourceType = ResourceType(rawValue: row[Columns.resourceType])
            ?? .generic
        let payloadJSON: String = row[Columns.payload]

        id = uuid
        self.resourceType = resourceType
        title = row[Columns.title]
        subtitle = row[Columns.subtitle]
        payload = try Payload.decode(type: resourceType, from: payloadJSON)
        bookmarkData = row[Columns.payloadBlob]
        sourceBundleID = row[Columns.sourceBundleID]
        sourceAppName = row[Columns.sourceAppName]
        captureMethod = CaptureMethod(rawValue: row[Columns.captureMethod]) ?? .manual
        notes = row[Columns.notes]
        degraded = row[Columns.degraded]
        createdAt = Date(timeIntervalSince1970: row[Columns.createdAt])
        updatedAt = Date(timeIntervalSince1970: row[Columns.updatedAt])
        lastOpenedAt = (row[Columns.lastOpenedAt] as Double?).map(Date.init(timeIntervalSince1970:))
        openCount = row[Columns.openCount]
        repairedAt = (row[Columns.repairedAt] as Double?).map(Date.init(timeIntervalSince1970:))
        archived = row[Columns.archived]
        tags = [] // hydrated by LinkStore after fetch
    }

    func encode(to container: inout PersistenceContainer) {
        container[Columns.id] = id.uuidString.uppercased()
        container[Columns.resourceType] = resourceType.rawValue
        container[Columns.title] = title
        container[Columns.subtitle] = subtitle
        container[Columns.payload] = try? payload.encodedJSON()
        container[Columns.payloadBlob] = bookmarkData
        container[Columns.sourceBundleID] = sourceBundleID
        container[Columns.sourceAppName] = sourceAppName
        container[Columns.captureMethod] = captureMethod.rawValue
        container[Columns.notes] = notes
        container[Columns.degraded] = degraded
        container[Columns.createdAt] = createdAt.timeIntervalSince1970
        container[Columns.updatedAt] = updatedAt.timeIntervalSince1970
        container[Columns.lastOpenedAt] = lastOpenedAt?.timeIntervalSince1970
        container[Columns.openCount] = openCount
        container[Columns.repairedAt] = repairedAt?.timeIntervalSince1970
        container[Columns.archived] = archived
    }
}
