# maclink — Product & Technical Specification

**Status:** Draft v1 (spec only — no implementation yet)
**Platform:** macOS 14+ (Sonoma and later)
**Audience:** the implementing agent/developer, plus the single end user (the author)

---

## 1. Overview & Goals

### 1.1 What it is

**maclink** is a personal, local-first macOS menu-bar utility that turns "whatever I'm looking at right now" into a **durable, pasteable deep link**.

Press a global hotkey → maclink inspects the frontmost application, figures out what resource is currently active (a file selected in Finder, a message selected in Mail, the current browser tab, an open document in an editor), records it in a local database with metadata, and puts a `maclink://…` URL on the clipboard. Paste that URL anywhere. Clicking/opening it later brings you back to that exact resource.

A second global hotkey opens a Spotlight-style search panel over everything you've ever captured, searchable by title, tag, source app, resource type, and date.

It is conceptually a stripped-down, self-hosted Hookmark, tuned for one user whose primary "inbox" for links is Emacs org-mode.

### 1.2 Core user stories

1. **Capture.** "I'm reading an email that I need to act on next Tuesday. I hit ⌃⌥⌘L, switch to Emacs, and paste a link into my org agenda file. On Tuesday I hit `C-c C-o` on that link and Mail.app opens that exact message."
2. **Capture a file.** "I select a spec PDF in Finder, hit the hotkey, paste into org. Three weeks later the file has been renamed and moved into a subfolder — the link still opens it."
3. **Capture a web page.** "Safari is on a page I want to reference. Hotkey, paste. Clicking reopens the page." (Here the `maclink://` layer buys metadata + tags + search on top of the raw URL.)
4. **Recall.** "I know I bookmarked something about 'invoice' from Mail last month. ⌃⌥⌘K, type `invoice mail`, Enter → the message opens. Or ⌘C on the result → the `maclink://` URL is on my clipboard."
5. **Organize.** "Right after capture I can type a tag or two into a small inline field without leaving my flow."

### 1.3 Design principles

- **Local-first, zero network.** Everything in one SQLite file under `~/Library/Application Support/`. The app should function fully with networking disabled.
- **Links are durable.** A `maclink://` URL is a stable UUID that never changes. What it points at may be re-resolved/repaired over time.
- **Keyboard-first.** Every primary action reachable without the mouse. No modal dialogs in the capture path.
- **Degrade gracefully.** If a per-app integration fails, fall back to a generic capture (frontmost app + window title + best-effort document URL) rather than doing nothing.
- **Small surface area.** This is a personal tool. Prefer 300 lines of obvious code over a plugin architecture.

### 1.4 Explicit non-goals

| Non-goal | Notes |
|---|---|
| Cloud sync / multi-device | Single Mac. The DB is backed up by Time Machine/iCloud Drive if the user points it there. Revisit only if a second Mac appears. |
| Team sharing / collaboration | Links are personal; a `maclink://` URL is meaningless on another machine (see §6.5 for the portable-link escape hatch). |
| iOS / iPadOS / Windows / Linux | macOS-only by construction — the whole value is in Apple Events + Accessibility. |
| Mac App Store distribution | See §3.4 and Open Question OQ-6. App Sandbox would gut the automation story. |
| A general bookmark manager / read-later service | No Instapaper/Pinboard/DEVONthink integrations. No content archiving. |
| Bidirectional "hook to new note" (MVP) | Deferred to Phase 2 (§12). |
| Full-text indexing of linked *content* | We index metadata only, not the body of the PDF/email. |
| Multi-user / accounts / auth | Single user, no login. |

---

## 2. Glossary

| Term | Meaning |
|---|---|
| **Link record** | A row in the `links` table: a UUID + resource type + payload + metadata. |
| **maclink URL** | `maclink://open/<uuid>` — the pasteable artifact. |
| **Capture** | Inspecting the frontmost app and producing a link record. |
| **Resolution** | Taking a link record and bringing the user back to the resource. |
| **Capturer** | A per-app strategy object that knows how to capture from one app (or family of apps). |
| **Resolver** | A per-resource-type strategy object that knows how to reopen a resource. |

---

## 3. Tech Stack

### 3.1 Recommendation

**Native Swift 5.9+ / SwiftUI + AppKit, built in Xcode, shipped as a `LSUIElement` (menu-bar-only) app.**

| Layer | Choice | Notes |
|---|---|---|
| Language | Swift 5.9+ | |
| UI | SwiftUI for views, AppKit for the shell | `MenuBarExtra` for the menu bar; a hand-rolled `NSPanel` for the search panel (SwiftUI alone can't make a non-activating floating panel). |
| Persistence | SQLite via **GRDB.swift** | Mature, synchronous, gives FTS5, migrations, and value-type record mapping. Alternative: raw `sqlite3` C API (no dependency, more boilerplate). **Do not use Core Data or SwiftData** — we want a plain file we can `sqlite3` from a shell/Emacs. |
| Global hotkeys | Carbon `RegisterEventHotKey` (via the small **HotKey** package, or ~80 lines inline) | Deliberately *not* `NSEvent.addGlobalMonitorForEvents`, which requires Accessibility permission just to see keystrokes. `RegisterEventHotKey` needs no permission at all. |
| Automation | `NSAppleScript` / `OSAScript` for compiled AppleScripts; `ScriptingBridge` optional | See §3.3. |
| Accessibility | `AXUIElement` C API (via a thin Swift wrapper) | For the generic fallback capturer. |
| Build | Xcode project (not SwiftPM executable) — we need an `.app` bundle with an `Info.plist` for `CFBundleURLTypes` and `LSUIElement`. | |
| Distribution | Developer ID signed + notarized, **not sandboxed**, hardened runtime **on** with the Apple Events entitlement. | See §3.4. |

Minimum deployment target: **macOS 14.0**. (Gets us `MenuBarExtra`, `@Observable`, modern `ScrollView` APIs. Nothing here needs 15+.)

### 3.2 Rationale vs. alternatives

| Alternative | Why not |
|---|---|
| **Electron / Tauri** | Every single interesting capability here — global hotkeys, Apple Events with per-target TCC prompts, `AXUIElement`, `NSURL` security-scoped bookmarks, `CFBundleURLTypes` handling, a non-activating floating panel — requires a native bridge anyway. You'd write the same Swift/ObjC and then pay 150 MB of RAM and a Chromium process to render a list of 400 rows. For a resident background utility this is the wrong trade. |
| **Python + `py-applescript` + rumps** | Fastest path to a prototype, and genuinely viable for a v0 spike. But: no good story for a signed/notarized bundle that registers a URL scheme, fragile packaging (`py2app`), and TCC prompts attach to the interpreter binary in confusing ways. Not recommended for the real thing. |
| **A pile of shell scripts + Hammerspoon** | Hammerspoon gives you global hotkeys, AppleScript, and Lua for free, and could do 70% of this in an afternoon. Rejected because (a) the URL-scheme handler and search panel would still be awkward, (b) the user wants a real artifact. **However:** Hammerspoon is a reasonable way to prototype the capture AppleScripts before writing Swift. |
| **Objective-C** | No reason in 2026. |

### 3.3 A note on AppleScript from Swift

Three ways to talk to another app; the spec assumes **(1)** for MVP:

1. **`NSAppleScript` with source strings** — simplest, most flexible, easiest to iterate on. Compile once at launch and cache the `NSAppleScript` instances (compilation is the slow part, ~10–50 ms; execution is ~5–200 ms depending on target app). **Must be executed off the main thread** — but note `NSAppleScript` is not thread-safe; use a single dedicated serial `DispatchQueue` (or an actor) that owns all script execution, and never call it from the main thread, or the UI will beachball while Mail thinks.
2. **`ScriptingBridge`** — type-ish-safe, but requires generating headers per app (`sdef`/`sdp`), and silently returns `nil` in ways that are hard to debug. Fine if a particular script becomes a hot spot.
3. **Raw Apple Events (`AEDesc`)** — only if something can't be expressed otherwise.

Wrap all of it behind one internal API:

```swift
protocol AppleScriptRunner {
    /// Runs `source`, returns the result descriptor coerced to a Swift value.
    /// Throws AutomationError.permissionDenied (-1743), .appNotRunning (-600),
    /// .timeout, .scriptError(code, message).
    func run(_ source: String, timeout: TimeInterval) async throws -> AEValue
}
```

Error code `-1743` (`errAEEventNotPermitted`) is the "user denied Automation permission" case and **must** be handled explicitly with a helpful message pointing at System Settings → Privacy & Security → Automation.

### 3.4 Sandboxing decision (important)

**Recommendation: do not sandbox. Ship as a Developer ID–signed, notarized, direct-distribution app with the hardened runtime enabled.**

Reasoning:

- A sandboxed app can only send Apple Events to apps explicitly listed in `com.apple.security.temporary-exception.apple-events` (an entitlement Apple discourages and reviews), which kills the generic/extensible capture story.
- A sandboxed app can only use the Accessibility API in limited ways and gets no `AXUIElement` access to other processes' windows without being outside the sandbox.
- File access outside the sandbox container requires security-scoped bookmarks *and* user-initiated selection; we want to record links to files the user merely *selected in Finder*, which is not the same as an `NSOpenPanel` grant.

Consequence: no Mac App Store. Given "single-user personal tool," that's free. This is flagged as **OQ-6** in case the user disagrees.

Required signing configuration:

- Hardened runtime **enabled**.
- Entitlement `com.apple.security.automation.apple-events` = `true` (required for a hardened-runtime app to send *any* Apple Event, even unsandboxed).
- `Info.plist` key `NSAppleEventsUsageDescription` with a human-readable string — without it, the TCC prompt is suppressed and automation silently fails.

---

## 4. Architecture

### 4.1 Component map

```
┌────────────────────────────────────────────────────────────────────┐
│ maclink.app  (LSUIElement, always resident)                        │
│                                                                    │
│  ┌──────────────┐   ┌─────────────────┐   ┌────────────────────┐   │
│  │ HotkeyService│   │ URLSchemeHandler│   │  MenuBarExtra UI   │   │
│  │ (Carbon)     │   │ (kAEGetURL)     │   │  + Settings window │   │
│  └──────┬───────┘   └────────┬────────┘   └─────────┬──────────┘   │
│         │                    │                      │              │
│         ▼                    ▼                      ▼              │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    LinkService (façade)                    │    │
│  │  capture() · resolve(id) · search(query) · tag() · delete() │   │
│  └───┬──────────────────────┬─────────────────────┬───────────┘    │
│      │                      │                     │                │
│      ▼                      ▼                     ▼                │
│ ┌──────────────┐     ┌─────────────┐      ┌───────────────┐        │
│ │ CaptureEngine│     │ ResolveEngine│      │ LinkStore     │        │
│ │              │     │              │      │ (GRDB/SQLite) │        │
│ │ Capturer[]   │     │ Resolver[]   │      │ + FTS5 index  │        │
│ │  Finder      │     │  file        │      └───────────────┘        │
│ │  Mail        │     │  mail        │                               │
│ │  Safari      │     │  url                                         │
│ │  Chrome (P2) │     │  generic                                     │
│ │  Generic(AX) │     └─────────────┘                                │
│ └──────┬───────┘                                                    │
│        │                                                            │
│        ▼                                                            │
│ ┌──────────────────────────────┐  ┌──────────────────────────────┐  │
│ │ AutomationService            │  │ QuickPanel (NSPanel+SwiftUI) │  │
│ │  (serial queue, NSAppleScript│  │  search / capture-confirm    │  │
│ │   + AXUIElement + NSWorkspace)│  └──────────────────────────────┘  │
│ └──────────────────────────────┘                                    │
└────────────────────────────────────────────────────────────────────┘
        │                                              ▲
        ▼ (optional)                                   │
   ~/.local/bin/maclink  (thin CLI, reads the same DB) │
                                                        │
   Emacs / org-mode ──── open "maclink://open/<uuid>" ──┘
```

### 4.2 Component responsibilities

**HotkeyService**
Registers two (configurable) global hotkeys via `RegisterEventHotKey`:
- `⌃⌥⌘L` — **Capture link** (default)
- `⌃⌥⌘K` — **Search links** (default)

Stretch: `⌃⌥⌘⇧L` — capture *and* immediately insert into the frontmost app via synthetic ⌘V (needs Accessibility). Phase 2.

Hotkey handling must return within microseconds — dispatch the real work asynchronously.

**CaptureEngine**
Determines the frontmost application (`NSWorkspace.shared.frontmostApplication` → `bundleIdentifier`, captured *before* maclink does anything that could steal focus), selects a `Capturer` from a registry keyed by bundle ID, runs it, and falls back to `GenericCapturer` on failure or if unregistered.

```swift
protocol Capturer {
    /// Bundle IDs this capturer claims. Empty = generic fallback.
    var supportedBundleIDs: Set<String> { get }
    /// Returns 0..n candidate resources (Finder may have a multi-selection).
    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource]
}

struct CapturedResource {
    var type: ResourceType          // .file | .mail | .url | .generic
    var title: String               // human label, required, never empty
    var payload: Payload            // type-specific, see §8
    var sourceBundleID: String
    var sourceAppName: String
}
```

**ResolveEngine**
Given a `LinkRecord`, dispatches on `resource_type` to a `Resolver`. Resolvers are responsible for repair (§7.6) and for activating the target app.

**LinkStore**
All persistence. Owns migrations, the FTS5 index, and tag management. Exposes synchronous methods run on a database queue.

**URLSchemeHandler**
Receives `maclink://` activations (§6.3) and forwards to `LinkService.resolve`.

**QuickPanel**
A single reusable `NSPanel` subclass used for two modes: the post-capture confirm/tag toast, and the search panel. See §9.

**MenuBarExtra UI**
Menu with: Capture Link, Search Links…, Recent (last 10, click to resolve, ⌥-click to copy), Open Settings, Permissions Health Check, Quit.

**Settings**
Hotkey bindings, clipboard format (raw / org / markdown), default browser behavior, DB location display + "Reveal in Finder", permission status + re-request buttons, launch at login (`SMAppService.mainApp.register()`).

### 4.3 Concurrency model

- One serial `DispatchQueue` (label `com.maclink.automation`) owns **all** `NSAppleScript` and `AXUIElement` calls. `AXUIElement` calls against an unresponsive app can block for the full `kAXTimeout`; never on main.
- One `DatabaseQueue` (GRDB) owns all DB access.
- UI on main, `@MainActor`.
- Every automation call gets a hard timeout (default **3 s**; Mail can be slow on huge mailboxes — allow 5 s for Mail). On timeout, fall back to generic capture and tell the user.

### 4.4 The capture flow, end to end

1. Hotkey fires. Record `NSWorkspace.shared.frontmostApplication` **immediately** and synchronously (this is the last moment it's guaranteed correct).
2. Dispatch to automation queue; run the matching `Capturer`.
3. On success with exactly 1 resource → create link record, write to DB, write to pasteboard, show the confirm toast.
4. On success with >1 resource (Finder multi-select) → create N records; pasteboard gets N lines (newline-joined); toast says "3 links copied."
5. On failure → generic capture; if *that* fails, show an error toast naming the app and the reason (esp. permission denial, with a "Open System Settings" button).
6. Toast (§9.2) appears near the top-center of the active screen for ~4 s, focusable for tagging, dismissible with Esc.

Target end-to-end latency: **< 400 ms** for Finder/Safari, **< 1 s** for Mail. If Mail routinely exceeds this, consider the `mdfind`-free path in §7.3.

---

## 5. Permissions

macOS will gate nearly everything. The app must (a) request lazily at first need, (b) never crash on denial, (c) provide a **Permissions Health Check** panel in Settings that shows live status and deep-links to the right System Settings pane.

| Permission | Needed for | How requested | Notes |
|---|---|---|---|
| **Automation (Apple Events) — per target app** | Finder, Mail, Safari, Chrome capture & resolution | First Apple Event to each app triggers a per-app TCC prompt | Requires `NSAppleEventsUsageDescription` in Info.plist. Denial → `errAEEventNotPermitted` (-1743). Cannot be re-prompted programmatically; user must fix in System Settings → Privacy & Security → Automation. Use `AEDeterminePermissionToAutomateTarget()` to *check* status without triggering a prompt when rendering the health check. |
| **Accessibility** | `GenericCapturer` (AX inspection of other apps' windows); synthetic paste (Phase 2) | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` | One global toggle. Poll `AXIsProcessTrusted()` to detect the grant; the app does **not** need to restart on modern macOS, but restarting is the reliable path — offer a "Restart maclink" button. |
| **Full Disk Access** | Reading `~/Library/Mail/…` directly, *if* we ever need Mail's on-disk index | **Not required for MVP** — AppleScript to Mail.app avoids it. Avoid needing FDA; it's the most annoying prompt. Only consider for the Phase-2 fast Mail search path. |
| **Files & Folders / Desktop / Documents / Downloads** | Resolving `NSURL` bookmarks to files in protected locations | Prompted automatically on first access | Non-sandboxed apps still hit TCC for `~/Desktop`, `~/Documents`, `~/Downloads`, iCloud Drive. Handle denial by falling back to `open -R` (which asks Finder to reveal, and Finder has its own access). |
| **AppleScript-in-browser (`do JavaScript`)** | Safari/Chrome page selection & rich metadata (Phase 2) | User must enable Safari: Develop → *Allow JavaScript from Apple Events*; Chrome: View → Developer → *Allow JavaScript from Apple Events* | Not enabled by default and **not** programmatically enablable. MVP must not depend on it. |
| **Launch at login** | Convenience | `SMAppService.mainApp.register()` | User can revoke in Login Items. |

Health-check display: a table of `Permission | Status | Fix` where Status ∈ {Granted, Denied, Not yet requested, N/A} and Fix opens e.g. `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`.

---

## 6. The `maclink://` URL Scheme

### 6.1 URL shape

Canonical form:

```
maclink://open/<uuid>
```

Example: `maclink://open/3F2A9C1E-7B44-4D0A-9E31-5C8A1B2D3E4F`

Grammar:

```
maclink://open/<uuid>                 resolve and go to the resource
maclink://open/<uuid>?reveal=1        for files: reveal in Finder instead of opening
maclink://show/<uuid>                 open maclink's own detail/edit view for this link
maclink://search?q=<urlencoded>       open the search panel pre-filled
maclink://capture                     trigger a capture (lets Emacs/Keyboard Maestro drive it)
```

Rules:
- UUIDs are canonical uppercase RFC 4122 with hyphens. Parsing is case-insensitive.
- Unknown paths → open the menu-bar app and show an error toast; never crash.
- A **bare** `maclink://<uuid>` (no `open/`) must also be accepted as an alias for `open/<uuid>`, because it's what people will type from memory.

### 6.2 Why UUID-only rather than an encoded payload

- Keeps links short and stable when the underlying resource metadata is edited (retitled, retagged, path repaired).
- Lets the DB be the single source of truth for repair.
- Trade-off: the link is meaningless on another machine or after a DB loss. Mitigations: (a) the DB is a single small SQLite file that's trivially backed up; (b) the Phase-2 *portable link* form (§6.5).

### 6.3 Registration & handling

`Info.plist`:

```xml
<key>LSUIElement</key>
<true/>

<key>NSAppleEventsUsageDescription</key>
<string>maclink uses automation to read what you have selected in Finder, Mail, and your browser, and to reopen those items later.</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>com.tilak.maclink.url</string>
    <key>CFBundleTypeRole</key>
    <string>Viewer</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>maclink</string>
    </array>
  </dict>
</array>
```

Registration happens automatically when Launch Services first sees the bundle — i.e. after the app is built into `/Applications` (or run once from Xcode's DerivedData, which is a common source of "it opens the *old* copy" confusion). **Implementation note for the build/test loop:** if the scheme resolves to a stale bundle, run
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user`
and verify with `mdls` / `swift`-side `LSCopyDefaultHandlerForURLScheme("maclink")`.

Handling in the app — with SwiftUI's `MenuBarExtra` scene there is no window to attach `.onOpenURL` to reliably, so register an `NSApplicationDelegate` and use the Apple Event manager:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ n: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor,
                              withReply reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: s) else { return }
        LinkService.shared.handle(url)
    }
}
```

Registering in `applicationWillFinishLaunching` (not `didFinishLaunching`) matters: if the app is *launched by* the URL open, the event arrives very early and is otherwise dropped.

`maclink` must **not** steal focus when handling `open/<uuid>` — it activates the *target* app, not itself.

### 6.4 What this buys us

`open maclink://open/<uuid>` works from: Terminal, Emacs (`browse-url` / `org-open-at-point`), Slack, Apple Notes, Obsidian, Things, Reminders, a `.webloc`, a Shortcut, Alfred — anywhere macOS URL handling is available. That universality is the entire point of choosing a URL scheme over a bespoke file format or an Emacs package.

### 6.5 Portable links (Phase 2, design note)

For links that must survive a DB loss or move to another Mac, define a self-describing form:

```
maclink://v1/<base64url(json-payload)>
```

where the payload is `{t, title, ...type-specific fields}` — e.g. for mail, the Message-ID; for web, the URL; for files, the path + a volume-relative hint (bookmark data is machine-specific and is deliberately *omitted*). On open, maclink resolves it directly and optionally imports it into the local DB. Not MVP; note it in the schema versioning so `v1/` doesn't collide with `open/`.

---

## 7. Per-App Capture & Resolution Strategies

### 7.1 Strategy matrix

| Source | Bundle ID | Capture mechanism | Stable identifier | Resolution mechanism | MVP? |
|---|---|---|---|---|---|
| Finder | `com.apple.finder` | AppleScript `selection`; fallback: `target of front window` | `NSURL` bookmark data + path + inode + volume UUID | `NSWorkspace.open` / `activateFileViewerSelecting` | ✅ |
| Mail | `com.apple.mail` | AppleScript `selection` of the message viewer | RFC 5322 `Message-ID` (+ account/mailbox as a hint) | `message://%3C…%3E` URL, with AppleScript search as fallback | ✅ |
| Safari | `com.apple.Safari` | AppleScript `URL`/`name of current tab of front window` | The URL itself | `NSWorkspace.open(url, withApplicationAt: Safari)` | ✅ |
| Chrome | `com.google.Chrome` | AppleScript `URL`/`title of active tab of front window` | The URL itself | Same, targeting Chrome | ⬜ P2 |
| Arc / Brave / Edge / Orion | various | Chromium-family AppleScript dialect is identical to Chrome's | URL | same | ⬜ P2 |
| Preview (PDF page) | `com.apple.Preview` | AX: focused window `AXDocument` → file URL; page # is not exposed reliably | file bookmark + page number | `open file://…#page=N` (Preview honors `#page=`) | ⬜ P2 |
| Emacs | `org.gnu.Emacs` | Generic AX; or a `maclink-emacs.el` companion exposing buffer/file/line via `emacsclient --eval` | file + line | `emacsclient -n +LINE FILE` | ⬜ P2 |
| Terminal / iTerm2 | | AppleScript for cwd | directory path | Finder reveal / new terminal at path | ⬜ P2 |
| **Anything else** | * | `GenericCapturer` (§7.5) | file URL if the window has one, else app+title | open file, else just activate the app | ✅ |

### 7.2 Finder

**Capture.** Preferred: the current selection. If the selection is empty, fall back to the front window's target folder. If there is no window, fail over to generic.

```applescript
tell application "Finder"
    set out to {}
    set sel to selection
    if sel is {} then
        if (count of windows) > 0 then
            set end of out to (POSIX path of (target of front window as alias))
        end if
    else
        repeat with i in sel
            set end of out to (POSIX path of (i as alias))
        end repeat
    end if
    return out
end tell
```

Return a list of POSIX paths; Swift converts each to a `URL`.

Notes:
- `as alias` fails for items that aren't real files (e.g. a network share not mounted, some smart-folder results). Wrap each iteration in `try … end try` and skip failures.
- Title = `URL.lastPathComponent` (keep the extension; the user is an engineer).
- Also capture, for the payload: `path`, bookmark data, inode (`NSFileSystemFileNumber` via `URLResourceValues.fileResourceIdentifier` — note this is opaque `NSCopying`; store the *inode* from `stat()` plus the volume UUID from `.volumeUUIDStringKey` for a human-debuggable fallback), UTI (`.contentTypeKey`), file size, and `isDirectory`.

**The robust-path trick.** Create bookmark data at capture time:

```swift
let data = try url.bookmarkData(
    options: [],                     // NOT .withSecurityScope — we're unsandboxed
    includingResourceValuesForKeys: [.nameKey, .contentTypeKey],
    relativeTo: nil)
```

macOS bookmarks record volume + inode + path + a name hint, so they survive **rename and move within the same volume** — this is exactly the "robust file links" property Hookmark advertises, and it comes free from the OS. Store the `Data` blob (typically 700 B–1.5 KB) as a BLOB column, base64 in the JSON payload only if convenient — prefer a real BLOB column (`payload_blob`) to keep the JSON small.

**Resolution.**

```swift
var stale = false
if let url = try? URL(resolvingBookmarkData: data,
                      options: [],           // no .withSecurityScope
                      relativeTo: nil,
                      bookmarkDataIsStale: &stale) {
    if stale { /* regenerate + write back to DB */ }
    if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    else      { NSWorkspace.shared.open(url) }
}
```

Default action for files: **open** with the default app. `?reveal=1` (and ⌥ in the search panel) reveals in Finder instead. Make the *default* configurable in Settings (OQ-4).

Repair ladder if the bookmark fails (see §7.6).

### 7.3 Mail.app

This is the highest-value and most fragile integration. Get it right.

**Capture.**

```applescript
tell application "Mail"
    set sel to selection
    if sel is {} then error "no selection" number 1000
    set m to item 1 of sel
    set theID to message id of m
    set theSubject to subject of m
    set theSender to sender of m
    set theDate to (date received of m) as string
    set theBox to name of mailbox of m
    try
        set theAcct to name of (account of mailbox of m)
    on error
        set theAcct to "On My Mac"
    end try
    return {theID, theSubject, theSender, theDate, theBox, theAcct}
end tell
```

Key facts the implementer must know:

- `selection` is a property of the **application** in Mail's dictionary (not of a window). It returns a list of `message` objects for the messages highlighted in the message list. If the user is reading a message in a *separate window* rather than the viewer, `selection` may be empty — in that case fall back to iterating `message viewers` / open windows, or to reading the front window's title as a last resort.
- `message id` returns the RFC 5322 Message-ID. **Empirically it is returned WITHOUT the surrounding angle brackets** on current macOS, but this has varied. **The implementation must normalize defensively**: strip any leading `<` and trailing `>`, store the bare form, and re-add brackets at resolution time. Add a unit test for both shapes.
- A tiny number of messages (mostly spam, or drafts) have no Message-ID. Detect empty/nil and fall back to a `.generic` capture holding subject+sender+date so the user still gets *something*; mark the record `degraded = 1`.
- Multi-select: capture only `item 1` in MVP, but the payload/schema should not preclude N. (Or capture all N — cheap. Recommended: capture all, same as Finder.)
- Performance: on a mailbox with 100k messages this script is still fast because it touches only the selection. Do **not** write scripts that enumerate mailboxes at capture time.

**Title** = subject, or `"(no subject)"`. Store sender and date separately for the search UI.

**Resolution.** Two-tier.

*Tier 1 — the `message:` URL scheme.* Mail.app registers the `message:` scheme and will open a message by Message-ID:

```
message://%3C<url-encoded-message-id>%3E
```

`%3C`/`%3E` are the encoded `<` and `>`. The bare Message-ID must additionally be percent-encoded (it can legally contain `?`, `&`, `%`, `+`, and non-ASCII). Implementation:

```swift
let bare = messageID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
var cs = CharacterSet.urlQueryAllowed
cs.remove(charactersIn: "?&=+%#/")
let enc = bare.addingPercentEncoding(withAllowedCharacters: cs)!
let url = URL(string: "message://%3C\(enc)%3E")!
NSWorkspace.shared.open(url)
```

This opens the message in a Mail window and activates Mail. It works only if the message is still in a mailbox Mail knows about (deleted/archived-off-device messages will fail). It also historically works in the shorter `message:%3C…%3E` form — support constructing both and try the second if the first no-ops.

*Tier 2 — AppleScript search fallback.* If Tier 1 doesn't visibly work (we can't easily detect this; make it a user-invokable "Try harder" action, plus the automatic path when the stored account/mailbox is known):

```applescript
on findAndOpen(mid, acctName, boxName)
    tell application "Mail"
        set candidates to {}
        try
            set mb to mailbox boxName of account acctName
            set candidates to (every message of mb whose message id is mid)
        end try
        if candidates is {} then
            repeat with a in accounts
                repeat with mb in mailboxes of a
                    try
                        set candidates to (every message of mb whose message id is mid)
                        if candidates is not {} then exit repeat
                    end try
                end repeat
                if candidates is not {} then exit repeat
            end repeat
        end if
        if candidates is {} then error "not found" number 1001
        open (item 1 of candidates)
        activate
    end tell
end findAndOpen
```

**Warning:** the full-scan branch is O(all messages) and can hang Mail for minutes on a large account. It must be (a) time-boxed, (b) run only on explicit user request, (c) show a cancellable progress indicator. Never run it inside the normal resolve path without asking.

**Do not** parse `~/Library/Mail/` directly in MVP — the on-disk format (`.emlx` + a SQLite `Envelope Index`) is undocumented, changes between releases, and requires Full Disk Access.

### 7.4 Safari (and Chrome, Phase 2)

**Safari capture.**

```applescript
tell application "Safari"
    if (count of windows) = 0 then error "no window" number 1002
    set t to current tab of front window
    return {URL of t, name of t}
end tell
```

**Chrome capture** (Phase 2; same shape for all Chromium forks — Brave, Edge, Arc, Vivaldi, Orion):

```applescript
tell application "Google Chrome"
    if (count of windows) = 0 then error "no window" number 1002
    set t to active tab of front window
    return {URL of t, title of t}
end tell
```

Note the dialect difference: Safari uses `current tab` / `name`; Chrome uses `active tab` / `title`. Don't share a script string between them.

Both require Automation permission for that browser. Neither requires *Allow JavaScript from Apple Events* for URL+title — only for the Phase-2 extras (selected text, scroll position, canonical URL, `og:` metadata, favicon).

**Normalization at capture time (MVP, cheap wins):**
- Strip known tracking params: `utm_*`, `fbclid`, `gclid`, `mc_eid`, `ref` on a small allowlist of hosts. Keep the raw URL too, in the payload as `raw_url`.
- Do **not** strip fragments — they're often meaningful anchors.

**Resolution.** Prefer reopening in the browser it came from:

```swift
if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: payload.sourceBundleID) {
    NSWorkspace.shared.open([url], withApplicationAt: app,
                            configuration: NSWorkspace.OpenConfiguration())
} else {
    NSWorkspace.shared.open(url)   // system default browser
}
```

Setting: "Reopen web links in: the capturing browser / the default browser" (default: capturing browser, fall back to default if it's not installed).

Phase 2 nicety: before opening a new tab, ask the browser whether the URL is already open in some tab and just focus it (`repeat with w in windows / repeat with t in tabs of w`).

### 7.5 Generic fallback (Accessibility)

For any app without a registered capturer, or when a capturer throws.

```swift
// 1. Frontmost app (captured at hotkey time)
let pid = frontApp.processIdentifier
let axApp = AXUIElementCreateApplication(pid)

// 2. Focused window
var winRef: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef)

// 3. Try to get a real document URL — many document-based apps expose this
var docRef: CFTypeRef?
AXUIElementCopyAttributeValue(win, kAXDocumentAttribute as CFString, &docRef)
// kAXDocumentAttribute is a String containing a file:// URL when present.

// 4. Title
AXUIElementCopyAttributeValue(win, kAXTitleAttribute as CFString, &titleRef)
```

Decision:
- If `kAXDocumentAttribute` yields a `file://` URL → treat as a **`.file`** capture (create bookmark data etc.) and note `capture_method = "ax-document"`. This single trick covers TextEdit, Pages, Numbers, Preview, Xcode, BBEdit, Word, and many others for free.
- Else → **`.generic`** capture: `{bundle_id, app_name, window_title}`. Title = window title.

Also set `AXUIElementSetMessagingTimeout(axApp, 2.0)` so a hung app can't hang maclink.

**Generic resolution.** Best effort, and be honest about it: activate the app by bundle ID (`NSWorkspace.shared.openApplication(at:configuration:)`). If a window title was recorded, additionally try to raise a window whose `AXTitle` matches (via `kAXRaiseAction`). If the app isn't installed, show the record's metadata in maclink's detail view with a "Copy title" affordance. A `.generic` link is a *breadcrumb*, not a guarantee — the UI should visually mark these (a dimmed icon / "best effort" badge) so the user's expectations are calibrated.

### 7.6 The repair ladder (files)

On resolve failure, in order, stopping at the first success. Steps 3+ require user confirmation (they can be wrong).

1. Resolve bookmark data. If `stale == true` but resolution succeeded → **regenerate bookmark + update `path`** in the DB silently.
2. Try the stored `path` directly (`FileManager.fileExists`) — covers "bookmark blob got corrupted."
3. Spotlight query by name + size: `kMDItemFSName == "<name>" && kMDItemFSSize == <n>` via `NSMetadataQuery`. Single hit → offer "Relink to `<newpath>`?"
4. Spotlight query by name only. Multiple hits → present a small picker.
5. Give up: show the last known path, offer "Choose file…" (`NSOpenPanel`) to relink manually, or "Delete link."

Every successful repair writes back `path`, bookmark data, and bumps `repaired_at`. Log repairs (a small `link_events` table, Phase 2) so the user can see what moved.

---

## 8. Data Model

### 8.1 Location & format

- File: `~/Library/Application Support/com.tilak.maclink/maclink.sqlite` (plus `-wal`, `-shm`).
- WAL mode on (`PRAGMA journal_mode=WAL`), `foreign_keys=ON`, `synchronous=NORMAL`.
- Schema version tracked via GRDB `DatabaseMigrator` (which uses its own `grdb_migrations` table). Also stamp `PRAGMA user_version`.
- The file is deliberately plain SQLite so the user can query it from `sqlite3`, Emacs (`sql-sqlite`, `emacsql`), or scripts. **Treat that as a supported interface** — don't put anything essential only in memory.

### 8.2 Schema

```sql
-- ---------------------------------------------------------------
-- links: one row per captured resource
-- ---------------------------------------------------------------
CREATE TABLE links (
    id              TEXT PRIMARY KEY NOT NULL,   -- UUID, uppercase, hyphenated
    resource_type   TEXT NOT NULL,               -- 'file'|'mail'|'url'|'generic'
    title           TEXT NOT NULL,               -- display label; never empty
    subtitle        TEXT,                        -- sender / host / parent folder
    payload         TEXT NOT NULL,               -- JSON, shape depends on resource_type (§8.3)
    payload_blob    BLOB,                        -- NSURL bookmark data for files; NULL otherwise
    source_bundle_id TEXT,                       -- e.g. 'com.apple.mail'
    source_app_name  TEXT,                       -- e.g. 'Mail'
    capture_method  TEXT NOT NULL,               -- 'applescript'|'ax-document'|'ax-generic'|'manual'|'url-import'
    notes           TEXT NOT NULL DEFAULT '',    -- freeform user notes
    degraded        INTEGER NOT NULL DEFAULT 0,  -- 1 = we couldn't get the ideal identifier
    created_at      REAL NOT NULL,               -- unix epoch seconds (REAL, UTC)
    updated_at      REAL NOT NULL,
    last_opened_at  REAL,                        -- for recency ranking
    open_count      INTEGER NOT NULL DEFAULT 0,  -- for frecency ranking
    repaired_at     REAL,
    archived        INTEGER NOT NULL DEFAULT 0   -- soft delete / hide from default search
);

CREATE INDEX idx_links_created   ON links(created_at DESC);
CREATE INDEX idx_links_type      ON links(resource_type);
CREATE INDEX idx_links_app       ON links(source_bundle_id);
CREATE INDEX idx_links_lastopen  ON links(last_opened_at DESC);

-- ---------------------------------------------------------------
-- tags: freeform, normalized, case-insensitively unique
-- ---------------------------------------------------------------
CREATE TABLE tags (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    name    TEXT NOT NULL,                       -- as typed, for display
    slug    TEXT NOT NULL UNIQUE                 -- lowercased, spaces->'-', for matching
);

CREATE TABLE link_tags (
    link_id TEXT NOT NULL REFERENCES links(id) ON DELETE CASCADE,
    tag_id  INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (link_id, tag_id)
);
CREATE INDEX idx_link_tags_tag ON link_tags(tag_id);

-- ---------------------------------------------------------------
-- Full-text search (external-content FTS5 over a denormalized doc)
-- ---------------------------------------------------------------
CREATE VIRTUAL TABLE links_fts USING fts5(
    title,
    subtitle,
    notes,
    tags_text,        -- space-joined tag names, maintained by the app
    payload_text,     -- searchable bits: URL, path, sender, mailbox — NOT the raw JSON
    content='',       -- contentless: app writes rows explicitly
    tokenize = "unicode61 remove_diacritics 2 tokenchars '-_.@/'"
);
-- Map fts rowid <-> links.id
CREATE TABLE links_fts_map (
    rowid   INTEGER PRIMARY KEY AUTOINCREMENT,
    link_id TEXT NOT NULL UNIQUE REFERENCES links(id) ON DELETE CASCADE
);
```

Notes for the implementer:
- The custom `tokenchars` keeps `foo-bar`, `user@host`, `some/path`, and `file.pdf` searchable as units *and* their parts.
- Contentless FTS5 (`content=''`) means updates are delete+insert. That's fine at this scale (thousands of rows). Rebuild the whole index on migration.
- Keep `tags_text` denormalized in FTS so `"invoice acme"` matches title+tag combinations in one query.
- Alternative simpler design if FTS5 proves annoying: a single `search_text` column on `links` plus `LIKE '%…%'`. At <20k rows this is genuinely fast enough (single-digit ms). **Ship FTS5 if easy, but don't let it block the MVP.**

### 8.3 Payload shapes (JSON in `links.payload`)

All payloads carry `"v": 1`.

**`file`**
```json
{
  "v": 1,
  "path": "/Users/tilak/Documents/specs/maclink.pdf",
  "display_name": "maclink.pdf",
  "uti": "com.adobe.pdf",
  "is_directory": false,
  "byte_size": 184320,
  "inode": 12905817,
  "volume_uuid": "6A1F0C2B-....",
  "volume_name": "Macintosh HD",
  "page": null,
  "selection": null
}
```
Bookmark data lives in `payload_blob`, not here. `page`/`selection` reserved for Phase-2 PDF deep links.

**`mail`**
```json
{
  "v": 1,
  "message_id": "CAF=abc123$xyz@mail.example.com",
  "subject": "Q3 invoice",
  "sender": "Jane Doe <jane@example.com>",
  "sender_address": "jane@example.com",
  "date_sent": 1756300000.0,
  "date_received": 1756300012.0,
  "mailbox": "INBOX",
  "account": "Fastmail",
  "message_url": "message://%3CCAF%3Dabc123%24xyz%40mail.example.com%3E"
}
```
Store `message_id` **without** angle brackets. `message_url` is precomputed for debuggability and for the Phase-2 portable-link form; the resolver may recompute it.

**`url`**
```json
{
  "v": 1,
  "url": "https://developer.apple.com/documentation/appkit/nsworkspace",
  "raw_url": "https://developer.apple.com/documentation/appkit/nsworkspace?utm_source=x",
  "host": "developer.apple.com",
  "page_title": "NSWorkspace | Apple Developer Documentation",
  "browser_bundle_id": "com.apple.Safari",
  "selection": null
}
```

**`generic`**
```json
{
  "v": 1,
  "window_title": "notes.txt — ~/scratch",
  "ax_document_url": null,
  "hint": "best-effort: activates the app only"
}
```

### 8.4 Swift types

```swift
enum ResourceType: String, Codable, CaseIterable {
    case file, mail, url, generic
}

struct LinkRecord: Identifiable, Codable {
    var id: UUID
    var resourceType: ResourceType
    var title: String
    var subtitle: String?
    var payload: Payload          // enum with associated values, encoded to JSON
    var bookmarkData: Data?
    var sourceBundleID: String?
    var sourceAppName: String?
    var captureMethod: CaptureMethod
    var notes: String
    var degraded: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastOpenedAt: Date?
    var openCount: Int
    var repairedAt: Date?
    var archived: Bool
    // hydrated separately
    var tags: [String] = []
}
```

Encode `Payload` as an enum with associated values and a hand-written `Codable` keyed on `resource_type`, so adding a type is one case + one capturer + one resolver.

### 8.5 Deduplication

At capture, before inserting, check for an existing non-archived link with the same *identity key*:

| Type | Identity key |
|---|---|
| file | `volume_uuid` + `inode`, else normalized `path` |
| mail | `message_id` |
| url | normalized URL (scheme+host lowercased, tracking params stripped, trailing slash normalized) |
| generic | never dedupe |

If a match exists: **do not create a new row.** Bump `updated_at`, put the *existing* UUID on the clipboard, and have the toast say "Existing link (3 tags)" so the user knows. This keeps tags/notes attached to one canonical record instead of fragmenting. Add a Settings toggle "Always create a new link" for the user who disagrees.

---

## 9. UI

### 9.1 Menu bar

`MenuBarExtra` with a monochrome template SF Symbol (suggest `link.badge.plus` or a custom glyph). Menu:

```
Capture Link                 ⌃⌥⌘L
Search Links…                ⌃⌥⌘K
──────────────────────────────────
Recent
  ▸ Q3 invoice — Mail            (click: open · ⌥click: copy maclink URL)
  ▸ maclink.pdf — Finder
  ▸ NSWorkspace | Apple Developer…
──────────────────────────────────
Settings…                       ⌘,
Permissions…
──────────────────────────────────
Quit maclink                    ⌘Q
```

Recent shows 10, each with a small type icon (doc / envelope / globe / app icon).

### 9.2 Capture confirmation toast

A small non-activating `NSPanel`, `.floating` level, appearing top-center of the screen containing the mouse (or the active screen), auto-dismissing after 4 s.

```
┌──────────────────────────────────────────────┐
│  ✉  Q3 invoice                               │
│     Jane Doe · Mail · copied to clipboard    │
│  ┌────────────────────────────────────────┐  │
│  │ tags…                                  │  │  ← focused only if user presses ⇥ or ⌘T
│  └────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

Behavior:
- **Does not steal focus by default** (`NSPanel` with `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded = true`). The user should be able to keep typing in the app they were in.
- Pressing the capture hotkey *again* within the toast's lifetime focuses the tag field (a cheap way to opt into tagging without a second binding). Alternatively ⌘T while the toast is visible.
- Tag field: comma- or space-separated, with inline completion from existing tags (⇥ accepts). Return commits and dismisses.
- Esc dismisses without tagging (the link is already saved).
- ⌘⌫ within the toast **undoes** the capture (deletes the row, restores previous pasteboard contents). Worth doing: mis-fires are common.

### 9.3 Search panel

A Spotlight/Alfred-style floating window, invoked by `⌃⌥⌘K`.

Implementation: `NSPanel` subclass with `styleMask = [.nonactivatingPanel, .titled, .fullSizeContentView]`, `isFloatingPanel = true`, `level = .floating`, `hidesOnDeactivate = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, and an override of `canBecomeKey` returning `true` (an `NSPanel` won't accept keyboard input otherwise). Content is SwiftUI via `NSHostingView`. Width ~680 pt, positioned at 25% from the top of the active screen.

**Before showing it, record `NSWorkspace.shared.frontmostApplication`** so actions can return focus / paste back into the right place.

```
┌───────────────────────────────────────────────────────────┐
│ 🔍  invoice type:mail                                     │
├───────────────────────────────────────────────────────────┤
│ ✉  Q3 invoice                       Jane Doe · 2d ago     │  ← selected
│    #finance #q3                                           │
│ ✉  Re: Q3 invoice                   Jane Doe · 2d ago     │
│ 📄 acme-invoice-2026.pdf            ~/Documents · 1w ago   │
│ 🌐 Invoicing best practices         stripe.com · 1mo ago   │
├───────────────────────────────────────────────────────────┤
│ ↩ Open   ⌘↩ Copy link   ⌥↩ Reveal   ⌘T Tag   ⌘⌫ Delete    │
└───────────────────────────────────────────────────────────┘
```

**Query language.** Plain text is fuzzy-matched across title/subtitle/tags/notes/payload_text. Prefixed tokens filter:

| Token | Meaning |
|---|---|
| `type:mail` / `type:file` / `type:url` / `type:generic` | resource type (accept `m`, `f`, `u`, `g` prefixes) |
| `#tag` or `tag:foo` | has tag |
| `app:mail`, `app:safari` | source app (match against `source_app_name` and bundle ID) |
| `since:7d`, `since:2026-01-01`, `before:30d` | `created_at` range |
| `is:archived`, `is:degraded` | flags |
| `host:github.com` | url payload host |

Unrecognized `word:` tokens are treated as literal text (don't be clever).

**Ranking.** Score = fuzzy-match score (title weighted 3×, tags 2×, subtitle 1.5×, notes/payload 1×) × recency-decay boost, plus a frecency bump from `open_count` and `last_opened_at`. With an empty query, show the 30 most recent. Keep it simple; a plain `bm25()` from FTS5 combined with a recency multiplier is enough.

**Actions on the selected row.**

| Key | Action |
|---|---|
| `↩` | Resolve — go to the resource (activates the target app; panel closes) |
| `⌘↩` | Copy `maclink://open/<uuid>` to the clipboard (in the configured format), close |
| `⌥↩` | Reveal in Finder (files) / open in maclink detail view (others) |
| `⇧↩` | Copy the *native* link instead (`file://…`, the raw `https://…`, `message://…`) — useful for pasting where `maclink://` is unwanted |
| `⌘T` | Inline tag editor for this row |
| `⌘⌫` | Archive (soft delete). ⇧⌘⌫ hard-deletes with confirmation. |
| `⌘C` | Copy title |
| `Esc` | Close panel, restore focus to the previously frontmost app |

Type-ahead must feel instant: debounce ~60 ms, query on the DB queue, cap at 100 results.

### 9.4 Settings window

Tabs: **General** (launch at login, clipboard format, default file action, dedupe behavior), **Hotkeys** (two recorders; use a small key-recorder view — `KeyboardShortcuts` by Sindre Sorhus is the obvious dependency if a dependency is acceptable), **Apps** (per-app capturer enable/disable, browser reopen preference), **Permissions** (the health check from §5), **Data** (DB path + Reveal, link count, Export JSON, Vacuum, Rebuild search index).

### 9.5 Clipboard format

On capture, write **multiple representations** to `NSPasteboard.general`:

- `public.utf8-plain-text` — per the Settings preference:
  - `raw` (default): `maclink://open/<uuid>`
  - `org`: `[[maclink://open/<uuid>][Q3 invoice]]`
  - `markdown`: `[Q3 invoice](maclink://open/<uuid>)`
- `public.url` — the `maclink://` URL
- `public.html` — `<a href="maclink://open/…">Q3 invoice</a>` so rich-text targets (Notes, Mail compose) get a titled hyperlink for free.

Also expose a modifier at capture time: holding **⇧** while pressing the capture hotkey forces `org` format regardless of the preference. (Cheap, and matches the user's actual workflow.)

---

## 10. Emacs / org-mode Integration

### 10.1 The baseline: nothing is required

This is the important claim and it should be verified early in implementation, because it determines whether any elisp is needed at all.

org-mode's link opener (`org-open-at-point` → `org-link-open`) handles a link whose type has no registered handler by falling through to `browse-url`. On macOS, `browse-url-browser-function` defaults to `browse-url-default-browser`, which on Darwin ends up calling `browse-url-default-macosx-browser`, i.e. shelling out to `/usr/bin/open`. `open maclink://open/<uuid>` hands the URL to Launch Services, which routes it to maclink.

So: **paste `maclink://open/<uuid>` into an org buffer, put point on it, press `C-c C-o` → Mail opens the message.** No package, no config.

Two caveats to check and document in the README:
1. Some Emacs configurations set `browse-url-browser-function` to `eww` or a specific browser function, which would break non-http schemes. The fix is a one-liner the user can add:
   ```elisp
   (setq browse-url-handlers
         (append '(("\\`maclink://" . browse-url-default-macosx-browser))
                 browse-url-handlers))
   ```
2. Bracketed org links (`[[maclink://…][Title]]`) work the same way; org may warn about an unknown link type when *exporting*, not when opening.

### 10.2 Optional sugar #1 — insert the latest capture

A ~15-line function bound to e.g. `C-c m`. Simplest version reads the clipboard, since capture already puts the link there:

```elisp
(defun maclink-insert-from-clipboard ()
  "Insert the maclink:// URL currently on the macOS pasteboard as an org link."
  (interactive)
  (let ((s (string-trim (shell-command-to-string "pbpaste"))))
    (cond
     ((string-match "\\`\\[\\[maclink://" s) (insert s))          ; already org-formatted
     ((string-match "\\`maclink://" s)
      (insert (format "[[%s][%s]]" s (read-string "Description: "))))
     (t (user-error "Clipboard does not contain a maclink URL")))))
```

### 10.3 Optional sugar #2 — a `maclink` CLI, and title lookup

A tiny CLI (a shell script or a second target in the Xcode project, installed to `~/.local/bin/maclink`) that reads the same SQLite file:

```
maclink latest [--org|--json|--url]   # most recent link
maclink get <uuid> [--json]
maclink search <query> [--json --limit N]
maclink capture                        # -> open "maclink://capture"
```

`latest --org` prints `[[maclink://open/<uuid>][Q3 invoice]]`. Then:

```elisp
(defun maclink-insert-latest ()
  "Insert the most recently captured maclink as an org link at point."
  (interactive)
  (insert (string-trim (shell-command-to-string "maclink latest --org"))))
(define-key org-mode-map (kbd "C-c m") #'maclink-insert-latest)
```

Implementation note: the CLI must open the DB **read-only** (`file:…?mode=ro`, or GRDB's `DatabaseQueue` with `readonly: true`) so it can never contend with or corrupt the app's writes. WAL mode makes concurrent readers safe.

### 10.4 Optional sugar #3 — a real org link type

Purely for display, completion, and export — **not** needed for opening:

```elisp
(require 'org)

(defun maclink-org-follow (path _arg)
  (start-process "maclink" nil "open" (concat "maclink://" path)))

(defun maclink-org-export (path desc backend)
  (or desc (concat "maclink://" path)))

(defun maclink-org-complete ()
  "Completing-read over saved links via the CLI."
  (let* ((lines (process-lines "maclink" "search" "" "--limit" "500"))
         (choice (completing-read "maclink: " lines)))
    (concat "maclink:" (car (split-string choice "\t")))))

(org-link-set-parameters "maclink"
  :follow   #'maclink-org-follow
  :export   #'maclink-org-export
  :complete #'maclink-org-complete
  :face     '(:foreground "DarkOrange" :underline t))
```

Note the type registered is `maclink`, so `org-link-set-parameters` will match `maclink:open/<uuid>` (single colon). Since our canonical URL is `maclink://open/<uuid>`, org sees type `maclink` and path `//open/<uuid>` — the follow function must handle the leading `//`. Keep this in mind and normalize with `(string-remove-prefix "//" path)`.

Ship §10.4 as a `contrib/maclink.el` file in the repo, clearly labeled optional.

### 10.5 Round trip (Phase 2)

Capture *from* Emacs: an `emacsclient --eval` call that returns `(buffer-file-name)`, `(line-number-at-pos)`, and the org heading ID at point; resolve via `emacsclient -n +LINE FILE` or `org-id-goto`. This makes maclink bidirectional with the user's notes and is the natural Phase-2 payoff.

---

## 11. Non-functional Requirements

| Aspect | Target |
|---|---|
| Idle memory | < 60 MB resident |
| Idle CPU | ~0% (no polling loops; hotkeys are event-driven) |
| Capture latency (Finder/Safari) | p95 < 400 ms hotkey → clipboard |
| Capture latency (Mail) | p95 < 1 s |
| Search latency | < 50 ms for 20k links |
| Launch | < 500 ms to menu-bar-ready |
| Failure mode | Never block the UI; never lose a capture silently; always tell the user *why* something failed |
| Logging | `OSLog` with subsystem `com.tilak.maclink`, categories: `capture`, `resolve`, `automation`, `db`, `ui`. A "Copy diagnostics" button in Settings. |
| Backup | The DB is one file; Settings offers "Export all links as JSON" (nightly automatic export to `~/Library/Application Support/com.tilak.maclink/exports/` is a nice Phase-2 safety net). |

---

## 12. Scope: MVP vs. Phase 2

### 12.1 MVP (ship this first)

**Must have:**
- [ ] Menu-bar-only Swift app (`LSUIElement`), signed, notarized, non-sandboxed, hardened runtime + Apple Events entitlement.
- [ ] Global capture hotkey (`⌃⌥⌘L`, configurable) via `RegisterEventHotKey`.
- [ ] Capturers: **Finder**, **Mail.app**, **Safari**, **generic AX fallback** (including the `kAXDocumentAttribute` → file trick).
- [ ] SQLite store (GRDB) with the §8.2 schema and migrations.
- [ ] `maclink://open/<uuid>` scheme: `CFBundleURLTypes` registration + `NSAppleEventManager` handler.
- [ ] Resolvers: file (bookmark + repair steps 1–2), mail (`message://` tier 1), url, generic (activate app).
- [ ] Clipboard write with raw/org/markdown preference + `public.html` representation.
- [ ] Capture toast with inline tagging and ⌘⌫ undo.
- [ ] Search panel (`⌃⌥⌘K`) with text search + `type:`/`#tag`/`app:`/`since:` filters and the §9.3 action keys.
- [ ] Menu bar menu with Recent.
- [ ] Settings: hotkeys, clipboard format, permissions health check, launch at login.
- [ ] Deduplication per §8.5.
- [ ] `contrib/maclink.el` (optional elisp) + a README documenting the zero-config org path.

**Explicitly deferred out of MVP** even though tempting: Chrome, `do JavaScript` extras, the Mail full-scan fallback UI, PDF page links, the CLI.

### 12.2 Phase 2

Roughly in value order:

1. **`maclink` CLI** (read-only DB access) — unlocks the nicer Emacs integration. *(Small, high value — could arguably be MVP.)*
2. **Chrome + Chromium forks** (Arc, Brave, Edge). Near-zero marginal cost once Safari works.
3. **Repair ladder steps 3–5** (Spotlight relink, manual relink UI) and the Mail tier-2 search fallback with a cancellable progress UI.
4. **Emacs as a capture source** via `emacsclient` (§10.5).
5. **PDF/Preview deep links** — page number via `#page=N`; text-selection anchors need PDFKit and a quoting scheme (store the selected text + page + a character range, re-find the text on open since ranges drift).
6. **Browser text-selection capture** via `do JavaScript` (requires the user to enable Allow JavaScript from Apple Events) — store `window.getSelection()` text plus a scroll anchor; resolve by re-finding and highlighting.
7. **"Link to New"** — create a new note in a chosen app (Obsidian/org file/Apple Notes) pre-seeded with the `maclink://` backlink, and store the note's own link on the source record, giving Hookmark-style bidirectional linking. Needs a `link_relations(from_id, to_id, kind)` table.
8. **Synthetic paste** (`⌃⌥⌘⇧L` = capture and paste in place) — needs Accessibility + `CGEvent` key synthesis.
9. **Portable links** (`maclink://v1/<base64url>`) per §6.5.
10. **Browser extension** for capturing per-scroll-position / SPA-route links Safari's AppleScript can't see.
11. **Other apps**: Things/OmniFocus tasks, Obsidian notes (`obsidian://`), DEVONthink (`x-devonthink-item://`), Zotero, Terminal cwd, Xcode file+line.
12. **Smart lists / saved searches** in the panel.
13. **Cloud sync** — only if a second Mac exists. The obvious cheap version is putting the SQLite file in iCloud Drive, which is a **bad idea** (WAL + cloud sync = corruption). The right version is an append-only event log synced as separate files, or CloudKit. Do not start this without a real need.

---

## 13. Suggested Build Order

A dependency-ordered path for the implementing agent; each step should be independently verifiable.

1. **Skeleton**: Xcode app target, `LSUIElement`, `MenuBarExtra` with a Quit item. Verify it runs with no Dock icon.
2. **URL scheme first** (it's the riskiest infrastructure piece): register `maclink://`, handle it, show an alert with the received URL. Verify `open maclink://open/TEST` from Terminal hits the handler. Sort out `lsregister` issues now, not later.
3. **DB layer**: GRDB, migrations, `LinkRecord` CRUD, unit tests. Seed a few fake rows.
4. **Automation service**: serial queue + `NSAppleScript` wrapper with timeout and error mapping. Test with a trivial `tell application "Finder" to return name of front window`.
5. **Finder capturer + file resolver** (bookmark data round trip; test move/rename survival explicitly).
6. **Global hotkey** + clipboard write + a plain notification. Now the loop is closed: hotkey → clipboard → `open` → file opens.
7. **Mail capturer + resolver.** Budget real time here. Test with: normal selection, message in its own window, no selection, message without a Message-ID, Message-ID containing `?`/`&`/non-ASCII, multi-select.
8. **Safari capturer + url resolver.**
9. **Generic AX capturer.**
10. **Search panel.** `NSPanel` focus behavior is fiddly — expect a session on `canBecomeKey`, `hidesOnDeactivate`, and restoring focus on Esc.
11. **Capture toast + tagging.**
12. **Settings + permissions health check.**
13. **Signing, notarization, `contrib/maclink.el`, README.**

### Testing notes

- Unit-testable without a UI: Message-ID normalization/encoding, URL normalization/dedupe keys, query-language parsing, payload JSON round trips, search ranking.
- The AppleScript layer should be testable by pointing the runner at fixed scripts and asserting on parsed output — keep the parsing (AEDesc → Swift struct) separate from the scripting.
- Manual test matrix worth writing down: for each capturer × {happy path, app not running, no window, no selection, permission denied}.

---

## 14. Risks

| Risk | Mitigation |
|---|---|
| Mail's `message id` format or `selection` semantics change in a macOS update | Defensive normalization; a diagnostics view showing the raw captured value; `degraded` flag so failures are visible not silent. |
| `message://` scheme stops working | Tier-2 AppleScript fallback already specified. |
| TCC prompts confuse or get denied and the app looks broken | The Permissions health check is not optional polish — build it in MVP. |
| The generic AX capturer produces useless links | Mark `.generic` visually as best-effort; don't oversell. |
| The user grants Automation to Mail but Mail is slow on a large archive | Hard timeouts + never full-scan without asking. |
| Scope creep into "a bookmark manager" | The non-goals table in §1.4 is the contract. |

---

## 15. Open Questions for the User

These are decisions with real consequences that shouldn't be made unilaterally:

- **OQ-1 — Chrome in MVP?** The spec puts Safari in MVP and Chrome in Phase 2. If Chrome is the daily driver, that's backwards — it's a ~30-line addition, so just say which browser(s) you actually use and they can swap or both ship in MVP.
- **OQ-2 — Mail clients.** Mail.app only, or do you also use Outlook, Spark, Missive, or a terminal MUA (mu4e/notmuch in Emacs)? mu4e in particular would change the design significantly — if your mail already lives in Emacs, the mail capturer might be better implemented as an Emacs-side capture returning a `mu4e:msgid:` link rather than as AppleScript to Mail.app.
- **OQ-3 — Search panel form factor.** Floating Spotlight-style panel (spec's assumption, better for keyboard flow) vs. a dropdown attached to the menu bar item (simpler, less window management)? Or both?
- **OQ-4 — Default action for file links.** Open in the default app, or reveal in Finder? The spec defaults to *open*, with reveal on ⌥. Confirm.
- **OQ-5 — Tags: freeform or a fixed taxonomy?** The spec assumes freeform with autocomplete. A fixed vocabulary (with validation) is easy to add if you know your categories; a hierarchical scheme (`work/acme`, `read/later`) is a middle ground worth considering, since it plays nicely with org tags.
- **OQ-6 — Sandbox / distribution.** The spec strongly recommends **non-sandboxed, Developer ID, direct distribution**, because App Sandbox would cripple Apple Events and the Accessibility API. This forecloses the Mac App Store. Confirm you're fine with that. (Related: do you have a paid Apple Developer account for signing/notarization, or will you run this ad-hoc-signed locally? Ad-hoc works for personal use but you'll re-approve TCC prompts on every rebuild, which is genuinely annoying during development — consider a stable signing identity even for local builds.)
- **OQ-7 — Should the maclink URL be UUID-only or self-describing?** Spec chooses UUID-only (§6.2). If you want links pasted into org files to survive a DB loss without repair, the portable form should be MVP rather than Phase 2.
- **OQ-8 — Capture-time friction.** Should the toast ever *require* interaction (e.g. always focus the tag field), or always be fire-and-forget with optional tagging? Spec assumes fire-and-forget.
- **OQ-9 — Default clipboard format.** Raw `maclink://…`, or org-bracket format, given that org is the primary destination? Spec defaults to raw with a ⇧-modifier for org; the opposite default may suit you better.
- **OQ-10 — Multi-select in Finder/Mail.** Create N separate links (spec's assumption), or one link to the set? N is simpler and probably right.
- **OQ-11 — Swift comfort level.** The spec assumes Swift is acceptable. If you'd rather stay in a language you use daily, say so before implementation starts — a Hammerspoon or Python prototype is a legitimate first step, and the AppleScript snippets here transfer verbatim.
