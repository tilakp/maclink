import ServiceManagement
import SwiftUI

enum ClipboardFormat: String, CaseIterable, Identifiable {
    case raw, org, markdown
    var id: String { rawValue }
    var label: String {
        switch self {
        case .raw: return "Raw (maclink://open/…)"
        case .org: return "Org (\u{5B}[maclink://…][Title]])"
        case .markdown: return "Markdown ([Title](maclink://…))"
        }
    }
}

/// Settings window (spec §9.4). Per-app capturer enable/disable toggles are
/// a later enhancement, not required for the app to be usable.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeysSettingsView()
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            PermissionsSettingsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            DataSettingsView()
                .tabItem { Label("Data", systemImage: "cylinder.split.1x2") }
        }
        .frame(width: 460, height: 300)
        .scenePadding()
    }
}

private struct HotkeysSettingsView: View {
    @State private var captureBinding = HotkeySettings.capture
    @State private var searchBinding = HotkeySettings.search
    @State private var conflictMessage: String?

    var body: some View {
        Form {
            LabeledContent("Capture Link") {
                KeyRecorderView(
                    binding: captureBinding,
                    onCapture: { candidate in
                        guard HotkeyService.shared.updateCapture(candidate) else {
                            conflictMessage = "Couldn't register \(candidate.display) — it may already be in use by another app."
                            return false
                        }
                        captureBinding = candidate
                        conflictMessage = nil
                        return true
                    },
                    onClear: {
                        _ = HotkeyService.shared.updateCapture(nil)
                        captureBinding = nil
                        conflictMessage = nil
                    }
                )
            }
            LabeledContent("Search Links") {
                KeyRecorderView(
                    binding: searchBinding,
                    onCapture: { candidate in
                        guard HotkeyService.shared.updateSearch(candidate) else {
                            conflictMessage = "Couldn't register \(candidate.display) — it may already be in use by another app."
                            return false
                        }
                        searchBinding = candidate
                        conflictMessage = nil
                        return true
                    },
                    onClear: {
                        _ = HotkeyService.shared.updateSearch(nil)
                        searchBinding = nil
                        conflictMessage = nil
                    }
                )
            }

            Text("Click a shortcut, then press a new key combo. Delete clears it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button("Reset to Defaults") {
                if HotkeyService.shared.updateCapture(.defaultCapture) {
                    captureBinding = .defaultCapture
                }
                if HotkeyService.shared.updateSearch(.defaultSearch) {
                    searchBinding = .defaultSearch
                }
                conflictMessage = nil
            }
            .font(.caption)
        }
        .padding(.top, 8)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage("clipboardFormat") private var clipboardFormat: String = ClipboardFormat.raw.rawValue
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var applied = true
    // Read fresh in .onAppear (not just at init) so this reflects changes
    // made on the Hotkeys tab without needing a relaunch — a static literal
    // here was a real bug: it never updated after a rebind.
    @State private var captureDisplay = HotkeySettings.capture?.display ?? "None"
    @State private var searchDisplay = HotkeySettings.search?.display ?? "None"

    var body: some View {
        Form {
            Picker("Clipboard format", selection: $clipboardFormat) {
                ForEach(ClipboardFormat.allCases) { format in
                    Text(format.label).tag(format.rawValue)
                }
            }

            // Deliberately not wired reactively (no onChange/custom Binding):
            // both were observed to register a real login item on window
            // appearance with zero user interaction, for reasons that
            // didn't trace back to any code actually calling register().
            // An explicit Apply button makes the system call unambiguous —
            // it only ever runs from a real button-press event.
            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, _ in applied = false }
                if !applied {
                    Button("Apply") { applyLaunchAtLoginSetting() }
                        .font(.caption)
                }
            }
            LabeledContent("Capture") { Text(captureDisplay).foregroundStyle(.secondary) }
            LabeledContent("Search") { Text(searchDisplay).foregroundStyle(.secondary) }
        }
        .padding(.top, 8)
        .onAppear {
            captureDisplay = HotkeySettings.capture?.display ?? "None"
            searchDisplay = HotkeySettings.search?.display ?? "None"
        }
    }

    private func applyLaunchAtLoginSetting() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            applied = true
        } catch {
            Log.app.error("launch-at-login toggle failed: \(error.localizedDescription, privacy: .public)")
            launchAtLogin.toggle()
        }
    }
}

private struct PermissionsSettingsView: View {
    private struct Row: Identifiable {
        let id: String
        let name: String
        let status: () -> String
        let fix: () -> Void
    }

    @State private var refreshToken = UUID()

    private var rows: [Row] {
        [
            Row(id: "finder", name: "Finder", status: { PermissionsService.automationStatus(forBundleIdentifier: "com.apple.finder").rawValue }, fix: PermissionsService.openAutomationSettings),
            Row(id: "mail", name: "Mail", status: { PermissionsService.automationStatus(forBundleIdentifier: "com.apple.mail").rawValue }, fix: PermissionsService.openAutomationSettings),
            Row(id: "safari", name: "Safari", status: { PermissionsService.automationStatus(forBundleIdentifier: "com.apple.Safari").rawValue }, fix: PermissionsService.openAutomationSettings),
            Row(id: "ax", name: "Accessibility", status: { PermissionsService.accessibilityGranted ? "Granted" : "Denied" }, fix: PermissionsService.openAccessibilitySettings)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("maclink checks these lazily on first use — a permission won't show Granted here until you've captured from that app at least once.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Table(rows) {
                TableColumn("Integration") { Text($0.name) }
                TableColumn("Status") { row in
                    let value = row.status()
                    Text(value)
                        .foregroundStyle(value == "Granted" ? .green : (value == "Denied" ? .red : .secondary))
                }
                TableColumn("") { row in
                    Button("Open Settings…", action: row.fix)
                        .font(.caption)
                }
            }
            .id(refreshToken)

            Button("Refresh") { refreshToken = UUID() }
                .font(.caption)
        }
        .padding(.top, 8)
    }
}

private struct DataSettingsView: View {
    @State private var linkCount: Int = (try? LinkStore.shared.fetchAll(includeArchived: true, limit: 100_000))?.count ?? 0

    var body: some View {
        Form {
            LabeledContent("Database") {
                Text(Paths.databaseURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            LabeledContent("Links stored") {
                Text("\(linkCount)")
            }
            HStack {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Paths.databaseURL])
                }
                Button("Export as JSON…") {
                    exportJSON()
                }
            }
        }
        .padding(.top, 8)
    }

    private func exportJSON() {
        guard let records = try? LinkStore.shared.fetchAll(includeArchived: true, limit: 100_000) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "maclink-export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        struct ExportRecord: Encodable {
            let id: String
            let resourceType: String
            let title: String
            let subtitle: String?
            let tags: [String]
            let createdAt: Date
        }
        let export = records.map {
            ExportRecord(id: $0.id.uuidString, resourceType: $0.resourceType.rawValue, title: $0.title, subtitle: $0.subtitle, tags: $0.tags, createdAt: $0.createdAt)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(export) {
            try? data.write(to: url)
        }
    }
}
