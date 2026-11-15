import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let servicesProvider = ServicesProvider()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Must register here (not didFinishLaunching): if maclink is *launched by*
        // a URL open, the GetURL Apple Event arrives very early and is dropped
        // if the handler isn't installed yet.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        Log.app.info("maclink launching, URL event handler installed")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Open the database now so its migrations run at launch. The CLI and
        // the Raycast extension read the `search_text` column that `v2` adds,
        // and `LinkStore.shared` is otherwise only created on first use.
        _ = LinkStore.shared
        StatusItemController.shared.setup()
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
        HotkeyService.shared.start()
        NotificationService.requestAuthorizationIfNeeded()
        Log.app.info("maclink ready")
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            Log.app.error("received malformed GetURL event")
            return
        }
        Log.app.info("handling URL: \(url.absoluteString, privacy: .public)")
        LinkService.shared.handle(url)
    }
}
