import Foundation

/// What a copy action puts on the clipboard (spec §9.3, §9.5).
enum CopyKind {
    /// The maclink URL, in the user's clipboard format setting.
    case link
    /// The original address: web URL, file path, or `message:` URL.
    case address
    /// `file://` URL (files only).
    case fileURL
    /// Markdown link to the original address (file URL for files).
    case markdownAddress
}

/// Pure text building for every clipboard write. No AppKit here, so tests
/// can call it directly.
enum ClipboardFormatter {
    static func format(url: String, title: String, as format: ClipboardFormat) -> String {
        switch format {
        case .raw: return url
        case .org: return "[[\(url)][\(orgDescription(title))]]"
        case .markdown: return "[\(markdownText(title))](\(markdownDestination(url)))"
        }
    }

    /// Org has no escape for brackets inside a description; swap them.
    static func orgDescription(_ title: String) -> String {
        title.replacingOccurrences(of: "[", with: "{").replacingOccurrences(of: "]", with: "}")
    }

    /// Escapes `\`, `[` and `]` (backslash first).
    static func markdownText(_ title: String) -> String {
        title.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    /// Wraps the URL in `<...>` when it contains a space, `(` or `)`.
    static func markdownDestination(_ url: String) -> String {
        url.contains(where: { $0 == " " || $0 == "(" || $0 == ")" }) ? "<\(url)>" : url
    }

    static func maclinkURL(for record: LinkRecord) -> String {
        "maclink://open/\(record.id.uuidString)"
    }

    /// The original address, or nil when there is none (generic links,
    /// mail without a Message-ID).
    static func address(for record: LinkRecord) -> String? {
        switch record.payload {
        case .url(let p): return p.url
        case .file(let p): return p.path
        case .mail(let p):
            guard !p.messageID.hasPrefix("unknown-") else { return nil }
            return p.messageURL ?? MailCapturer.messageURLString(for: p.messageID)
        case .generic: return nil
        }
    }

    static func fileURL(for record: LinkRecord) -> String? {
        guard case .file(let p) = record.payload else { return nil }
        return URL(fileURLWithPath: p.path, isDirectory: p.isDirectory).absoluteString
    }

    /// The full clipboard text for one record, or nil if `kind` doesn't apply.
    static func text(for record: LinkRecord, kind: CopyKind, format: ClipboardFormat) -> String? {
        switch kind {
        case .link: return self.format(url: maclinkURL(for: record), title: record.title, as: format)
        case .address: return address(for: record)
        case .fileURL: return fileURL(for: record)
        case .markdownAddress:
            guard let target = fileURL(for: record) ?? address(for: record) else { return nil }
            return self.format(url: target, title: record.title, as: .markdown)
        }
    }
}
