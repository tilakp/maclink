import AppKit

/// Resolves `.mail` links via the `message:` URL scheme (spec §7.3, tier 1
/// only). Tier 2 — an AppleScript full-mailbox search fallback — is
/// explicitly Phase 2: it's O(all messages) and can hang Mail for minutes,
/// so the spec requires it be time-boxed, user-invoked, and cancellable,
/// none of which belongs in the plain resolve path.
struct MailResolver: Resolver {
    func resolve(_ record: LinkRecord, reveal: Bool) async throws -> LinkRecord? {
        guard case .mail(let payload) = record.payload else {
            throw ResolveError.notImplemented(record.resourceType)
        }
        guard !payload.messageID.hasPrefix("unknown-") else {
            // Captured from a message with no Message-ID (spec §7.3) — no
            // stable identifier to resolve against. The record is still a
            // useful breadcrumb (subject/sender/date), just not clickable.
            throw ResolveError.noStableIdentifier
        }
        let urlString = payload.messageURL ?? MailCapturer.messageURLString(for: payload.messageID)
        guard let url = URL(string: urlString) else {
            throw ResolveError.noStableIdentifier
        }
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}
