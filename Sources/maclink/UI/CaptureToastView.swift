import SwiftUI

/// Content of the capture confirmation toast (spec §9.2).
struct CaptureToastView: View {
    let records: [LinkRecord]
    var onTagsCommitted: (String) -> Void
    var onDismiss: () -> Void
    var onUndo: () -> Void
    var onFieldFocusChanged: (Bool) -> Void

    @State private var tagText = ""
    @FocusState private var tagFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(subheadline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Button("Undo", action: onUndo)
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            TextField("Add tags…", text: $tagText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                .focused($tagFieldFocused)
                .onSubmit {
                    onTagsCommitted(tagText)
                    onDismiss()
                }
        }
        .padding(12)
        .frame(width: 320)
        .onKeyPress(.escape) { onDismiss(); return .handled }
        .onKeyPress(.deleteForward, phases: .down) { _ in .ignored } // no-op, keeps ⌫ local to the field
        .onChange(of: tagFieldFocused) { _, focused in onFieldFocusChanged(focused) }
        .background(KeyEquivalentCatcher(onCommandDelete: onUndo))
    }

    private var icon: String {
        switch records.first?.resourceType {
        case .file: return "doc"
        case .mail: return "envelope"
        case .url: return "globe"
        case .generic, .none: return "app.dashed"
        }
    }

    private var headline: String {
        records.first?.title ?? "Captured"
    }

    private var subheadline: String {
        if records.count > 1 {
            return "\(records.count) links copied"
        }
        let source = records.first?.sourceAppName ?? ""
        return source.isEmpty ? "Copied to clipboard" : "\(source) · copied to clipboard"
    }
}

/// SwiftUI's `.onKeyPress` doesn't cleanly expose ⌘⌫ as a single case, so a
/// thin NSViewRepresentable catches it directly. This is the toast's undo
/// shortcut (spec §9.2: "mis-fires are common").
private struct KeyEquivalentCatcher: NSViewRepresentable {
    let onCommandDelete: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onCommandDelete = onCommandDelete
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onCommandDelete = onCommandDelete
    }

    final class CatcherView: NSView {
        var onCommandDelete: (() -> Void)?

        override var acceptsFirstResponder: Bool { false }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == String(UnicodeScalar(127)) {
                onCommandDelete?()
                return true
            }
            return false
        }
    }
}
