import AppKit
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {

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
        HotkeyService.shared.start()
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
