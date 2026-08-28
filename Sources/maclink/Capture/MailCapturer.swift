import AppKit
import Foundation

/// Captures the selected message(s) in Mail.app (spec §7.3) — the
/// highest-value and most fragile integration per the spec, so the
/// implementer notes there are followed closely:
///
/// - `selection` is a property of the *application*, not a window; if the
///   user is reading a message in its own separate window rather than the
///   list, `selection` can come back empty. MVP accepts that gap (the
///   generic AX fallback, once it exists, is the safety net) rather than
///   adding window-enumeration logic Mail's own scripting dictionary makes
///   awkward.
/// - `message id` is returned WITHOUT angle brackets on current macOS, but
///   this has varied historically — normalize defensively in both
///   directions rather than assume either shape.
/// - A tiny number of messages (drafts, some spam) have no Message-ID;
///   detect that and degrade rather than silently producing a broken link.
struct MailCapturer: Capturer {
    let supportedBundleIDs: Set<String> = ["com.apple.mail"]

    private static let script = #"""
        tell application "Mail"
            set sel to selection
            if sel is {} then error "no selection" number 1000
            set out to {}
            repeat with m in sel
                set theID to ""
                try
                    set theID to message id of m
                end try
                set theSubject to subject of m
                set theSender to ""
                try
                    set theSender to sender of m
                end try
                set theBox to ""
                try
                    set theBox to name of mailbox of m
                end try
                set theAcct to ""
                try
                    set theAcct to name of (account of mailbox of m)
                end try
                set theDate to ""
                try
                    set theDate to (date received of m) as string
                end try
                set end of out to {theID, theSubject, theSender, theBox, theAcct, theDate}
            end repeat
            return out
        end tell
        """#

    /// Mail is slower than Finder/Safari on large mailboxes; the spec
    /// budgets 5s here vs. the 3s default elsewhere (§4.3).
    private static let timeout: TimeInterval = 5

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        let result = try await AutomationService.shared.run(Self.script, timeout: Self.timeout)
        let messages = Self.parseMessages(from: result)
        guard !messages.isEmpty else {
            throw CaptureError.noSelection
        }
        return messages
    }

    /// AppleScript returns a flat list-of-lists as one big AEList; each
    /// message is 6 consecutive items (id, subject, sender, mailbox,
    /// account, date). Parsing is kept separate from the scripting so it's
    /// unit-testable against fixed AEDescs, per the spec's build-order note.
    static func parseMessages(from descriptor: NSAppleEventDescriptor) -> [CapturedResource] {
        guard descriptor.descriptorType == typeAEList, descriptor.numberOfItems > 0 else {
            return []
        }
        var resources: [CapturedResource] = []
        for i in 1...descriptor.numberOfItems {
            guard let row = descriptor.atIndex(i), row.descriptorType == typeAEList, row.numberOfItems == 6 else {
                continue
            }
            let fields = (1...6).map { row.atIndex($0)?.stringValue ?? "" }
            let (rawID, subject, sender, mailbox, account, dateString) = (fields[0], fields[1], fields[2], fields[3], fields[4], fields[5])

            let messageID = normalizeMessageID(rawID)
            let degraded = messageID.isEmpty
            let title = subject.isEmpty ? "(no subject)" : subject

            let payload = MailPayload(
                messageID: degraded ? "unknown-\(UUID().uuidString)" : messageID,
                subject: title,
                sender: sender.isEmpty ? nil : sender,
                senderAddress: extractEmailAddress(from: sender),
                dateSent: nil,
                dateReceived: nil,
                mailbox: mailbox.isEmpty ? nil : mailbox,
                account: account.isEmpty ? nil : account,
                messageURL: degraded ? nil : messageURLString(for: messageID)
            )

            resources.append(CapturedResource(
                payload: .mail(payload),
                title: title,
                subtitle: sender.isEmpty ? nil : sender,
                sourceBundleID: "com.apple.mail",
                sourceAppName: "Mail",
                captureMethod: .applescript
            ))
            _ = dateString // reserved for date_sent/date_received parsing (Phase 2: needs locale-safe parsing)
            _ = degraded
        }
        return resources
    }

    /// Message-IDs have historically been returned with or without angle
    /// brackets by Mail's AppleScript dictionary — always strip them so the
    /// stored form is consistent, and re-add them only when building a
    /// `message:` URL.
    static func normalizeMessageID(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "<> \n\t"))
    }

    static func messageURLString(for bareMessageID: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "?&=+%#/<>")
        let encoded = bareMessageID.addingPercentEncoding(withAllowedCharacters: allowed) ?? bareMessageID
        return "message://%3C\(encoded)%3E"
    }

    private static func extractEmailAddress(from sender: String) -> String? {
        // Mail's `sender` is usually "Display Name <addr@example.com>".
        guard let open = sender.lastIndex(of: "<"), let close = sender.lastIndex(of: ">"), open < close else {
            return sender.contains("@") ? sender : nil
        }
        return String(sender[sender.index(after: open)..<close])
    }
}
