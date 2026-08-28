import ApplicationServices
import AppKit
import UniformTypeIdentifiers

/// Fallback for any app without a registered capturer, or when a specific
/// capturer throws (spec §7.5). `supportedBundleIDs` is empty. `CaptureEngine`
/// treats that as "always eligible, tried last."
///
/// The one trick worth knowing: `kAXDocumentAttribute` on the focused window
/// is a `file://` URL for most document-based apps (TextEdit, Pages, Preview,
/// Xcode, BBEdit, Word, ...) even though none of them have a dedicated
/// capturer. That single AX read covers all of them for free.
struct GenericCapturer: Capturer {
    let supportedBundleIDs: Set<String> = []

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        guard AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) else {
            throw CaptureError.accessibilityPermissionDenied
        }

        let pid = frontApp.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, 2.0)

        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else {
            throw CaptureError.noSelection
        }
        let window = winRef as! AXUIElement // swiftlint:disable:this force_cast

        var docRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &docRef)

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

        let bundleID = frontApp.bundleIdentifier ?? "unknown"
        let appName = frontApp.localizedName ?? bundleID
        let windowTitle = (titleRef as? String) ?? appName

        if let docString = docRef as? String,
           let url = URL(string: docString), url.isFileURL {
            return [Self.fileResource(url: url, bundleID: bundleID, appName: appName)]
        }

        let payload = GenericPayload(
            windowTitle: windowTitle,
            axDocumentURL: docRef as? String,
            hint: "best-effort: activates the app only"
        )
        return [CapturedResource(
            payload: .generic(payload),
            title: windowTitle,
            subtitle: appName,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            captureMethod: .axGeneric
        )]
    }

    private static func fileResource(url: URL, bundleID: String, appName: String) -> CapturedResource {
        let path = url.path
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .fileSizeKey, .contentTypeKey, .volumeNameKey, .volumeUUIDStringKey
        ])
        var statBuf = stat()
        let inode: Int64? = stat(path, &statBuf) == 0 ? Int64(statBuf.st_ino) : nil
        let bookmarkData = try? url.bookmarkData(
            options: [], includingResourceValuesForKeys: [.nameKey, .contentTypeKey], relativeTo: nil
        )
        let payload = FilePayload(
            path: path,
            displayName: url.lastPathComponent,
            uti: values?.contentType?.identifier,
            isDirectory: values?.isDirectory ?? false,
            byteSize: values?.fileSize.map(Int64.init),
            inode: inode,
            volumeUUID: values?.volumeUUIDString,
            volumeName: values?.volumeName
        )
        return CapturedResource(
            payload: .file(payload),
            title: url.lastPathComponent,
            subtitle: url.deletingLastPathComponent().path,
            bookmarkData: bookmarkData,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            captureMethod: .axDocument
        )
    }
}
