import SwiftUI

/// The ⌃⌥⌘K search dropdown (spec §9.3, menu-bar-dropdown form factor per
/// OQ-3). Plain substring search over title/subtitle/notes/tags/payload via
/// `LinkStore`. The `type:`/`#tag`/`app:`/`since:` query mini-language is a
/// later enhancement, not required for the dropdown to be useful.
///
/// Pinning (via the pin button here or the "Pin Search Window" menu item)
/// keeps the window open after opening or copying a link, so multiple links
/// can be acted on in one sitting instead of reopening the dropdown each
/// time. `StatusItemController` owns `isPinned` since it also has to flip
/// the popover's dismiss-on-outside-click behavior, not just this view.
struct SearchPanelView: View {
    @ObservedObject var controller: StatusItemController
    var onSelect: (LinkRecord) -> Void
    var onCopy: (LinkRecord) -> Void
    var onReveal: (LinkRecord) -> Void

    @State private var query = ""
    @State private var results: [LinkRecord] = []
    @State private var selectedIndex = 0
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Search links…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($searchFieldFocused)
                    .onKeyPress { press in
                        switch press.key {
                        case .downArrow: move(1); return .handled
                        case .upArrow: move(-1); return .handled
                        case .return:
                            if press.modifiers.contains(.command) {
                                copySelected()
                            } else {
                                openSelected()
                            }
                            return .handled
                        case .escape:
                            controller.forceCloseSearchDropdown()
                            return .handled
                        default:
                            return .ignored
                        }
                    }

                Button {
                    controller.isPinned.toggle()
                } label: {
                    Image(systemName: controller.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(controller.isPinned ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(controller.isPinned
                      ? "Pinned: opening or copying a link won't close this window"
                      : "Pin so opening or copying a link doesn't close this window")
            }
            .padding(10)

            if controller.isPinned {
                Text("Pinned. Pick multiple links, then unpin or press Esc to close.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
            }

            Divider()

            if results.isEmpty {
                Text(query.isEmpty ? "No links yet" : "No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, record in
                                SearchResultRow(record: record, isSelected: index == selectedIndex, onCopy: onCopy)
                                    .id(index)
                                    .contentShape(Rectangle())
                                    .onTapGesture { onSelect(record) }
                                    .contextMenu {
                                        Button("Open") { onSelect(record) }
                                        Button("Copy Link") { onCopy(record) }
                                        if case .file = record.payload {
                                            Button("Reveal in Finder") { onReveal(record) }
                                        }
                                    }
                            }
                        }
                    }
                    .onChange(of: selectedIndex) { _, newValue in
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 400)
        .onAppear {
            searchFieldFocused = true
            refresh()
        }
        .onChange(of: query) { _, _ in
            selectedIndex = 0
            refresh()
        }
    }

    private func refresh() {
        results = LinkService.shared.search(query)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    private func openSelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onSelect(results[selectedIndex])
    }

    private func copySelected() {
        guard results.indices.contains(selectedIndex) else { return }
        onCopy(results[selectedIndex])
    }
}

private struct SearchResultRow: View {
    let record: LinkRecord
    let isSelected: Bool
    let onCopy: (LinkRecord) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundStyle(record.degraded ? .tertiary : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let subtitle = record.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if !record.tags.isEmpty {
                Text(record.tags.joined(separator: " "))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Button {
                onCopy(record)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy maclink:// URL")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private var icon: String {
        switch record.resourceType {
        case .file: return "doc"
        case .mail: return "envelope"
        case .url: return "globe"
        case .generic: return "app.dashed"
        }
    }
}
