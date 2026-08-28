import Foundation

enum ResourceType: String, Codable, CaseIterable {
    case file
    case mail
    case url
    case generic
}

enum CaptureMethod: String, Codable {
    case applescript
    case axDocument = "ax-document"
    case axGeneric = "ax-generic"
    case manual
    case urlImport = "url-import"
}
