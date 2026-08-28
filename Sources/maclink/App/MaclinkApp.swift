import SwiftUI

@main
struct MaclinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu-bar icon itself is a plain NSStatusItem (see
        // StatusItemController), not SwiftUI's MenuBarExtra: the search
        // dropdown needs to be shown programmatically from a global hotkey
        // callback via NSPopover, which MenuBarExtra has no API for.
        // Settings (build order step 12) will live in this scene.
        Settings {
            SettingsView()
        }
    }
}
