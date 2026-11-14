import AppKit

/// Receives the "Copy maclink" service (Info.plist `NSServices`). The
/// selector must match `NSMessage`: `copyMaclink:userData:error:`.
final class ServicesProvider: NSObject {
    @objc func copyMaclink(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "Select one or more files first." as NSString
            return
        }
        LinkService.shared.captureFiles(urls)
    }
}
