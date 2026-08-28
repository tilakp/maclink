import Foundation

/// Per-type JSON payload shapes, matching spec §8.3. All payloads carry `v: 1`.
/// The wrapping `Payload` enum has no discriminator of its own — decoding is
/// driven by `LinkRecord.resourceType`, which already lives in its own column.
enum Payload: Equatable {
    case file(FilePayload)
    case mail(MailPayload)
    case url(URLPayload)
    case generic(GenericPayload)

    var resourceType: ResourceType {
        switch self {
        case .file: return .file
        case .mail: return .mail
        case .url: return .url
        case .generic: return .generic
        }
    }

    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        let data: Data
        switch self {
        case .file(let p): data = try encoder.encode(p)
        case .mail(let p): data = try encoder.encode(p)
        case .url(let p): data = try encoder.encode(p)
        case .generic(let p): data = try encoder.encode(p)
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(type: ResourceType, from json: String) throws -> Payload {
        let decoder = JSONDecoder()
        let data = Data(json.utf8)
        switch type {
        case .file: return .file(try decoder.decode(FilePayload.self, from: data))
        case .mail: return .mail(try decoder.decode(MailPayload.self, from: data))
        case .url: return .url(try decoder.decode(URLPayload.self, from: data))
        case .generic: return .generic(try decoder.decode(GenericPayload.self, from: data))
        }
    }
}

struct FilePayload: Codable, Equatable {
    var v: Int = 1
    var path: String
    var displayName: String
    var uti: String?
    var isDirectory: Bool
    var byteSize: Int64?
    var inode: Int64?
    var volumeUUID: String?
    var volumeName: String?
    var page: Int? = nil
    var selection: String? = nil

    enum CodingKeys: String, CodingKey {
        case v, path
        case displayName = "display_name"
        case uti
        case isDirectory = "is_directory"
        case byteSize = "byte_size"
        case inode
        case volumeUUID = "volume_uuid"
        case volumeName = "volume_name"
        case page, selection
    }
}

struct MailPayload: Codable, Equatable {
    var v: Int = 1
    var messageID: String
    var subject: String
    var sender: String?
    var senderAddress: String?
    var dateSent: TimeInterval?
    var dateReceived: TimeInterval?
    var mailbox: String?
    var account: String?
    var messageURL: String?

    enum CodingKeys: String, CodingKey {
        case v
        case messageID = "message_id"
        case subject, sender
        case senderAddress = "sender_address"
        case dateSent = "date_sent"
        case dateReceived = "date_received"
        case mailbox, account
        case messageURL = "message_url"
    }
}

struct URLPayload: Codable, Equatable {
    var v: Int = 1
    var url: String
    var rawURL: String?
    var host: String?
    var pageTitle: String?
    var browserBundleID: String?
    var selection: String? = nil

    enum CodingKeys: String, CodingKey {
        case v, url
        case rawURL = "raw_url"
        case host
        case pageTitle = "page_title"
        case browserBundleID = "browser_bundle_id"
        case selection
    }
}

struct GenericPayload: Codable, Equatable {
    var v: Int = 1
    var windowTitle: String
    var axDocumentURL: String?
    var hint: String?

    enum CodingKeys: String, CodingKey {
        case v
        case windowTitle = "window_title"
        case axDocumentURL = "ax_document_url"
        case hint
    }
}
