import SwiftUI

@main
struct MaclinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("maclink", systemImage: "link.badge.plus") {
            MenuBarContentView()
        }
    }
}

struct MenuBarContentView: View {
    var body: some View {
        Button("Capture Link") {
            LinkService.shared.captureFromHotkey()
        }
        .keyboardShortcut("l", modifiers: [.control, .option, .command])

        Button("Search Links…") {
            LinkService.shared.showSearchPanel()
        }
        .keyboardShortcut("k", modifiers: [.control, .option, .command])

        Divider()

        Button("Quit maclink") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: [.command])
    }
}
