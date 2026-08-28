import AppKit
import Foundation
import UniformTypeIdentifiers

/// Captures the current Finder selection, or the front window's target
/// folder if nothing is selected (spec §7.2).
struct FinderCapturer: Capturer {
    let supportedBundleIDs: Set<String> = ["com.apple.finder"]

    private static let script = #"""
        tell application "Finder"
            set out to {}
            set sel to selection
            if sel is {} then
                if (count of windows) > 0 then
                    try
                        set end of out to (POSIX path of (target of front window as alias))
                    end try
                end if
            else
                repeat with i in sel
                    try
                        set end of out to (POSIX path of (i as alias))
                    end try
                end repeat
            end if
            return out
        end tell
        """#

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        let result = try await AutomationService.shared.run(Self.script)
        let paths = result.stringListValue
        guard !paths.isEmpty else {
            throw CaptureError.noSelection
        }
        return paths.compactMap { Self.resource(forPath: $0) }
    }

    private static func resource(forPath path: String) -> CapturedResource? {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey, .fileSizeKey, .contentTypeKey, .volumeNameKey, .volumeUUIDStringKey
        ])

        // Inode + volume UUID are the durable identity for dedupe/repair;
        // .fileResourceIdentifierKey is opaque NSCopying, so we go straight
        // to stat() as the spec's implementer note recommends (§7.2).
        var statBuf = stat()
        let inode: Int64? = stat(path, &statBuf) == 0 ? Int64(statBuf.st_ino) : nil

        let bookmarkData = try? url.bookmarkData(
            options: [], // not .withSecurityScope — we're unsandboxed
            includingResourceValuesForKeys: [.nameKey, .contentTypeKey],
            relativeTo: nil
        )

        let payload = FilePayload(
            path: path,
            displayName: url.lastPathComponent,
            uti: (values?.contentType)?.identifier,
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
            sourceBundleID: "com.apple.finder",
            sourceAppName: "Finder",
            captureMethod: .applescript
        )
    }
}
