# maclink 0.3 implementation spec

Status: ready for implementation. Base commit: `91dda90` on `main`.

This spec is for engineers who work in parallel, each in a separate git worktree, with no other context. Read sections 0 to 3 first. Then read only your track.

Inputs: the codebase audit and the competitor research of 2026-11-14, plus `README.md`, `SPEC.md` and the source at `91dda90`. Line numbers in this file refer to `91dda90`. Finding IDs such as "F1" refer to the audit. You do not need the audit to do your work. This file has all the detail.

---

## 0. Rules for every worker

### 0.1 Toolchain (read this first)

The default toolchain on the development machine is the Command Line Tools (`xcode-select -p` prints `/Library/Developer/CommandLineTools`). With it, `swift build` and `swift test` fail with 18 errors like `plugin for module 'SwiftUIMacros' not found`. This is not a code bug. Full Xcode is necessary.

Until item A1 lands, set `DEVELOPER_DIR` in every shell before you build or test:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
swift test
```

With this setting, `swift build` passes and `swift test` passes 37 tests at the base commit. The one project warning is `MailResolver.swift:23:25: result of call to 'run(resultType:body:)' is unused` (item B4 removes it).

### 0.2 Definition of done for a track

1. `swift build` passes with no new warnings in project code.
2. `swift test` passes. All existing tests pass, or you changed them on purpose and the spec says so.
3. Each work item is one commit (or more) on your worktree branch, with a clear message that starts with the item ID, for example `B2: Normalize web URLs before storage and dedupe`.
4. You did not edit a file that belongs to a different track (see section 2 and the table in section 9).

### 0.3 Things you must not do

- Do not run `Scripts/install.sh`.
- Do not run `Scripts/build-app.sh`. It registers the bundle `com.tilak.maclink` with Launch Services. A second copy in your worktree can take over the `maclink://` scheme from the installed app. CI runs it on a clean machine instead (item A2).
- Do not push. Do not open a pull request. Commit on your worktree branch only.
- Do not edit files outside your track's file list. If you think you must, stop and write the reason in your final report.
- Do not refactor code that this spec does not ask you to change. Do not delete pre-existing dead code. If your change makes a function, import or variable unused, delete it.
- Do not change `CFBundleShortVersionString` or `CFBundleVersion`. The owner sets the version at release time.

### 0.4 Style

- Match the existing code style: doc comments with `///`, `Log.<category>` for logs, `NotificationService.notifyFailure` for errors the user must see.
- Swift 5 language mode (tools version 5.10). No strict concurrency changes.
- Tests are XCTest in `Tests/maclinkTests`, with `@testable import maclink`. Put parsing and normalization logic in pure `static func`s so tests can call them without the UI or AppleScript.
- Tests that need real apps, real Spotlight, or Automation permission must skip unless the environment variable `MACLINK_LIVE_TESTS` is `1`. Use this exact guard at the top of the test:

```swift
try XCTSkipUnless(ProcessInfo.processInfo.environment["MACLINK_LIVE_TESTS"] == "1",
                  "live test: set MACLINK_LIVE_TESTS=1 to run")
```

---

## 1. Scope summary

In scope for 0.3:

- Code fixes from the audit: Spotlight relink (F1), toolchain guard (F2), toast tags wipe (F3), silent capture fallback (F4), search on raw JSON (F5), recent order after recapture (F6), repair write-back (F7), lenient row decoding (part of F8), failed opens and the MailResolver warning (F9 part), `ref` parameter stripping (F10), clipboard escaping and copy format (F11), diagnostic log (F13), CI (F15), relink picker (F18), two small CLI bugs (part of F19), hotkey registration failure (F9 part).
- Features: Chromium-family browser capture with reopen in the same browser; URL cleaning and normalization; more copy formats and a title edit in the toast; Finder "Copy maclink" through the Services menu.

Out of scope: see section 8. The file table for all tracks is in section 9.

---

## 2. Tracks at a glance

| Track | Name | Items |
|---|---|---|
| A | Build, CI, hotkey warning, docs | A1, A2, A3, A4 |
| B | Capture and reopen | B1, B2, B3, B4 |
| C | Store, search, file repair, CLI | C1, C2, C3, C4, C5, C6 |
| D | Clipboard, toast, Finder service | D1, D2, D3, D4, D5, D6, D7 |

No file is in two tracks. Shared files have one owner:

- `README.md`, `SPEC.md`: track A only (item A4 documents the work of all tracks).
- `Resources/Info.plist`, `App/AppDelegate.swift`, `Core/LinkService.swift`: track D only.
- `Package.swift`, `Store/LinkStore.swift`: track C only.
- `Core/CaptureEngine.swift`: track B only.

### 2.1 Cross-track contracts

The tracks build and test alone. These points only matter after all four tracks merge. Do them exactly as written so the merged result works.

1. **Error text for failed opens.** Track B adds `ResolveError.openFailed` and makes `ResolveError` conform to `LocalizedError` (item B4). Track D changes the `default:` branch of `LinkService.friendlyMessage` to use `(error as? LocalizedError)?.errorDescription` when it is not nil (item D6). Neither track references the other's new code.
2. **File repairs are written by `FileResolver`.** Track C makes `FileResolver` write repairs itself through a new `LinkStore.applyRepair` and return `nil` (item C2). The `if let repaired { try? store.update(repaired) }` lines in `LinkService.open` (lines 49-51) then never run for files. Track D must not remove them. They stay for the `Resolver` protocol contract.
3. **Live test switch.** Tracks A and C both use the `MACLINK_LIVE_TESTS` guard from section 0.4. CI (item A2) does not set it.
4. **New database column.** Track C adds the column `links.search_text` in migration `v2` (item C4). `LinkRecord.encode` fills it on every insert and update. Track D's title edit (item D4) uses the existing `LinkStore.update`, so it fills the column too after the merge. The CLI and the Raycast extension need the 0.3 app to run once (so the migration runs) before they work. Item A4 documents this.
5. **Services capture uses `FinderCapturer`.** Track D owns `Capture/FinderCapturer.swift` and `Models/ResourceType.swift`. Track B does not touch them.

### 2.2 Merge order

Any order works because no file is shared. Recommended: A, B, C, D. After the last merge, run `swift build` and `swift test` on `main` with `DEVELOPER_DIR` set (or without it, after A1), then the owner runs `Scripts/install.sh` and does the manual checks marked "Manual" in each item.

---

## 3. Background that more than one track needs

- Capture flow today: `HotkeyService` calls `LinkService.captureFromHotkey()` (`Core/LinkService.swift:94-145`). It reads the frontmost app, then in a `Task` calls `CaptureEngine.shared.capture(frontApp:)` (`Core/CaptureEngine.swift:20-30`), stores each `CapturedResource` with dedupe (`storeAndDedupe`, lines 157-175), writes the clipboard (lines 117-119), and shows the toast on the main actor (lines 122-124).
- `CaptureEngine` picks a capturer by bundle ID (Finder, Mail, Safari). Today it catches every error from that capturer and runs `GenericCapturer`.
- `URLResolver` (`Resolve/URLResolver.swift`) already opens a web link in the app named by `URLPayload.browserBundleID` when that app is installed, else in the default browser. So "reopen in the browser that made it" works for any capturer that sets `browserBundleID` correctly.
- Dedupe for web links (`LinkStore.findExisting`, `Store/LinkStore.swift:287-293`) compares `json_extract(payload, '$.url')` with the new payload's `url` as exact strings. If capturers store a normalized URL, dedupe uses it with no change to `LinkStore`.
- `ClipboardFormat` (`raw`, `org`, `markdown`) is defined in `UI/SettingsView.swift:4-13` and stored in `UserDefaults` key `clipboardFormat`.

---

## 4. Track A: Build, CI, hotkey warning, docs

Files (complete list):
- `Scripts/require-xcode.sh` (new)
- `Scripts/build-app.sh`
- `Scripts/install-cli.sh`
- `.github/workflows/ci.yml` (new)
- `Tests/maclinkTests/AutomationServiceTests.swift`
- `Sources/maclink/App/HotkeyService.swift`
- `README.md`
- `SPEC.md`

Order: A1, A2, A3, then A4 last.

### A1. Find Xcode or fail with a clear message (F2)

**Problem.** When `xcode-select` points at the Command Line Tools, `Scripts/build-app.sh` (line 29), `Scripts/install-cli.sh` (line 11) and so `Scripts/install.sh` (it calls `build-app.sh` at line 12) fail with 18 `SwiftUIMacros` errors. The errors do not say that full Xcode is necessary.

**Files.** New `Scripts/require-xcode.sh`. Edit `Scripts/build-app.sh`, `Scripts/install-cli.sh`. Do not edit `Scripts/install.sh`: it calls `build-app.sh` before it quits the running app, so it gets the same check and stops before it changes anything.

**Approach.**

1. Create `Scripts/require-xcode.sh`. It is sourced, not run, so it has no shebang requirement, but add `# shellcheck shell=bash` and a header comment. Content:

```bash
# shellcheck shell=bash
# Sourced by build-app.sh and install-cli.sh. The Command Line Tools do not
# ship the SwiftUI macro plugins, so `swift build` fails with
# "plugin for module 'SwiftUIMacros' not found". Use full Xcode instead.
if [ -z "${DEVELOPER_DIR:-}" ]; then
    MACLINK_SELECTED_DIR="$(xcode-select -p 2>/dev/null || true)"
    case "$MACLINK_SELECTED_DIR" in
        *.app/Contents/Developer)
            ;; # full Xcode is selected, nothing to do
        *)
            if [ -d /Applications/Xcode.app/Contents/Developer ]; then
                export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
                echo "==> using Xcode at $DEVELOPER_DIR (xcode-select points at ${MACLINK_SELECTED_DIR:-nothing})"
            else
                echo "error: maclink needs full Xcode, not the Command Line Tools." >&2
                echo "       xcode-select points at: ${MACLINK_SELECTED_DIR:-nothing}" >&2
                echo "       Install Xcode, then run one of:" >&2
                echo "         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
                echo "         export DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer" >&2
                exit 1
            fi
            ;;
    esac
fi
```

2. In `Scripts/build-app.sh`, add `source "$ROOT/Scripts/require-xcode.sh"` on a new line directly after line 26 (`CONTENTS=...`) and before the `echo "==> swift build -c $CONFIG"` line.
3. In `Scripts/install-cli.sh`, add the same `source` line directly after line 8 (`DEST=...`).
4. If the caller already set `DEVELOPER_DIR`, the script does nothing. This keeps CI and custom setups working.

**Acceptance criteria.**
- `for f in Scripts/require-xcode.sh Scripts/build-app.sh Scripts/install-cli.sh; do bash -n "$f"; done` prints nothing. (`bash -n` checks only its first file argument, so loop.)
- `env -u DEVELOPER_DIR bash -c 'source Scripts/require-xcode.sh; echo "DEVELOPER_DIR=$DEVELOPER_DIR"'` on the development machine (CLT selected, Xcode installed) prints the `==> using Xcode` line and `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- `DEVELOPER_DIR=/x bash -c 'source Scripts/require-xcode.sh; echo "$DEVELOPER_DIR"'` prints `/x` and no other line.
- Manual (owner, after merge): `Scripts/install.sh` with no `DEVELOPER_DIR` set builds and installs.

**Tests.** No XCTest. The shell checks above are the tests.

### A2. GitHub Actions CI (F15)

**Problem.** There is no CI. The toolchain break in A1 was found by hand. `AutomationServiceTests.testTrivialFinderScript` drives the real Finder and needs Automation permission, which a CI runner does not have.

**Files.** New `.github/workflows/ci.yml`. Edit `Tests/maclinkTests/AutomationServiceTests.swift`.

**Approach.**

1. In `AutomationServiceTests.swift`, add the `MACLINK_LIVE_TESTS` guard from section 0.4 as the first line of `testTrivialFinderScript` only. The other two tests (`testTimeoutFailsFastAndLeavesTheServiceUsable` uses `delay 1`, `testSyntaxErrorSurfacesAsScriptError` fails at compile) do not send Apple Events to another app. Leave them as they are.
2. Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Show toolchain
        run: |
          xcode-select -p
          swift --version
      - name: Build
        run: swift build
      - name: Test
        run: swift test
      - name: Build CLI (release)
        run: swift build -c release --product maclink-cli
      - name: Check Info.plist
        run: plutil -lint Resources/Info.plist
      - name: Check shell scripts
        run: for f in Scripts/*.sh; do bash -n "$f"; done
      - name: Assemble app bundle
        run: Scripts/build-app.sh debug adhoc
```

3. No caching, no release job, no matrix. Keep it to this.

**Acceptance criteria.**
- `MACLINK_LIVE_TESTS` unset: `swift test` reports `testTrivialFinderScript` as skipped, and all other tests pass.
- `MACLINK_LIVE_TESTS=1 swift test --filter AutomationServiceTests` runs all three tests (on a machine with Automation permission for the test runner).
- The YAML parses: `ruby -ryaml -e 'YAML.load_file(".github/workflows/ci.yml")'` (or any YAML linter) prints no error.
- Manual (owner, after push): the workflow runs green on GitHub.

**Tests.** The gate itself, checked as above.

### A3. Tell the user when a global hotkey cannot be registered (F9 part)

**Problem.** `HotkeyService.start()` (`App/HotkeyService.swift:21-30`) ignores the `Bool` that `apply` returns and always logs "global hotkeys registered". If another app owns Ctrl-Opt-Cmd-L, the hotkey does nothing and the user gets no message.

**Files.** `Sources/maclink/App/HotkeyService.swift`.

**Approach.** In `start()`, keep the two `apply` calls but check each result. If `apply` returns `false` for a non-nil binding, call:

```swift
NotificationService.notifyFailure(
    title: "Capture hotkey \(binding.display) is not available",
    body: "Another app may already use it. Choose a different shortcut in maclink Settings > Hotkeys."
)
```

Use "Search hotkey" in the title for the search binding. Read the binding from `HotkeySettings.capture` / `HotkeySettings.search` into a local first so you can use `display`. Change the final log line to report which hotkeys registered, for example `Log.app.info("global hotkeys: capture=\(captureOK) search=\(searchOK)")`. A `nil` binding (hotkey turned off) is not a failure. `apply` already returns `true` for `nil`; do not notify in that case.

**Acceptance criteria.**
- Build passes.
- Manual (owner): bind another app to Ctrl-Opt-Cmd-L, launch maclink, see one notification for the capture hotkey.

**Tests.** None (Carbon registration needs a live session). Do not add a test.

### A4. Update README and SPEC for 0.3 (F1 docs, F2 docs, features)

Do this item last, after you read sections 5 to 8 of this file. Describe what the other tracks build. Do not describe anything that is not in this spec.

**Files.** `README.md`, `SPEC.md`.

**Approach. README.md.**

1. Line 15. Replace the sentence that begins "The manual picker and delete-link steps are verified live end-to-end; the Spotlight-relink steps haven't yet shown..." to the end of the paragraph with: "In 0.2 the Spotlight-relink steps never found a file. The cause was a code bug: the Spotlight query started on a background thread with no run loop, so it never ran. 0.3 fixes this (see `SPEC.md` §12.2 item 3). Files in protected folders such as Documents may still need a Files and Folders grant; this is not yet verified."
2. "What works today" (line 17 on). Change the **Capture** bullet to add Chromium-family browsers by name: Chrome, Chromium, Arc, Brave, Edge, Vivaldi. Add these bullets:
   - **Clean web links**: tracking parameters (`utm_*`, `fbclid`, `gclid` and similar) are removed before a web link is stored, so the stored URL is clean and recaptures dedupe.
   - **Copy formats**: from the search dropdown, copy the maclink in your chosen format, the original address or path (Shift-Return), the file URL, or a Markdown link to the original address. Org and Markdown titles are escaped.
   - **Finder Services**: select one or more files in Finder, then right-click > Quick Actions (or Services) > Copy maclink. If the item is missing, turn it on in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders.
   - In the **Capture toast** bullet, add: edit the title before you paste, and tags you add to an existing link are added to its old tags.
   - In the **Dedupe** bullet, add: a recaptured link moves to the top of Recent and of `maclink latest`.
3. "Building and running" (line 39). Replace "Requires Xcode (for the Swift toolchain) on macOS 14 or later." with: "Requires full Xcode on macOS 14 or later. The Command Line Tools alone cannot build maclink (the SwiftUI macro plugins are missing). The scripts in `Scripts/` find `/Applications/Xcode.app` by themselves. For a plain `swift build` or `swift test`, either select Xcode with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` or set `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`." After "Run the test suite with `swift test`." (line 49), add: "Tests that drive real apps or Spotlight are skipped unless `MACLINK_LIVE_TESTS=1` is set."
4. CLI section (line 94). Change the comment on `maclink latest` to `# most recently captured or recaptured link (default: bare URL)`. After the code block, add: "After you update to 0.3, open the app once before you use the CLI or the Raycast extension. The app adds a search column to the database on first launch."

**Approach. SPEC.md.**

1. Line 530: change the heading to `### 7.4 Safari and Chromium browsers`. Line 542: remove "(Phase 2; " and the matching ")" so it reads "**Chrome capture** (same shape for all Chromium forks: Brave, Edge, Arc, Vivaldi):". Remove "Orion" from that list (it is WebKit, not Chromium, and is not supported).
2. Line 557: replace the bullet with: "Normalize every captured http/https URL: lowercase scheme and host, drop the default port, use `/` for an empty path, and remove tracking parameters (any `utm_*`, plus `fbclid`, `gclid`, `gclsrc`, `dclid`, `gbraid`, `wbraid`, `msclkid`, `mc_cid`, `mc_eid`, `igshid`, `yclid`, `twclid`, `_hsenc`, `_hsmi`, `mkt_tok`, and `si` on YouTube and Spotify hosts). `ref` is kept: it is a real parameter on many sites. Keep the raw URL in the payload as `raw_url` when it differs. See `Core/URLNormalizer.swift`."
3. Line 802 (the `url` row of the dedupe table): replace the key text with "the normalized URL (§7.4). `http` vs `https`, `www.`, and trailing slashes on non-root paths are not merged."
4. Line 1060 (Phase 2 item 2): append " **Built** in 0.3: `Capture/ChromiumCapturer.swift`."
5. Line 1061 (Phase 2 item 3): replace the text from "Most likely cause:" up to (not including) "The Mail tier-2 search fallback" with: "The cause was a code bug, not a permission: `spotlightSearch` was a non-isolated async function, so `NSMetadataQuery` started on a background thread with no run loop and never gathered results. 0.3 runs it on the main actor (`FileRelinker.swift`). Files in protected folders such as Documents may still need a Files and Folders grant; not yet verified."

**Acceptance criteria.**
- `grep -n "Documents-folder access" README.md SPEC.md` finds nothing.
- `grep -n "DEVELOPER_DIR" README.md` finds the new text.
- No em-dash characters are added (`git diff | grep -n $'^+.*\u2014'` finds nothing; old lines may keep theirs).

**Tests.** None.

---

## 5. Track B: Capture and reopen

Files (complete list):
- `Sources/maclink/Core/CaptureEngine.swift`
- `Sources/maclink/Core/URLNormalizer.swift` (new)
- `Sources/maclink/Capture/Capturer.swift`
- `Sources/maclink/Capture/SafariCapturer.swift`
- `Sources/maclink/Capture/ChromiumCapturer.swift` (new)
- `Sources/maclink/Capture/MailCapturer.swift` (doc comment only)
- `Sources/maclink/Resolve/Resolver.swift`
- `Sources/maclink/Resolve/MailResolver.swift`
- `Sources/maclink/Resolve/URLResolver.swift`
- `Sources/maclink/Resolve/GenericResolver.swift`
- `Tests/maclinkTests/SafariCapturerTests.swift` (delete)
- `Tests/maclinkTests/URLNormalizerTests.swift` (new)
- `Tests/maclinkTests/ChromiumCapturerTests.swift` (new)
- `Tests/maclinkTests/CaptureEngineTests.swift` (new)

Order: B1, B2, B3, B4.

### B1. Show capture errors instead of a silent generic fallback (F4)

**Problem.** `CaptureEngine.capture` (`Core/CaptureEngine.swift:20-30`) catches every error from the Finder, Mail or Safari capturer and runs `GenericCapturer`. Results: with no Mail selection, the user gets a "success" toast for a useless window-title link to Mail; with Automation denied, the user never sees "allow maclink to control Mail". This hides permission errors, which are the most common problem.

**Files.** `Core/CaptureEngine.swift`, `Capture/MailCapturer.swift` (doc comment only), new `Tests/maclinkTests/CaptureEngineTests.swift`.

**Approach.**

1. Add a pure function to `CaptureEngine`:

```swift
/// What to do when an app-specific capturer throws. `nil` means "try the
/// generic AX capturer"; anything else is the error to show the user.
static func errorToSurface(for error: Error) -> Error? {
    switch error {
    case AutomationError.malformedResult:
        return nil
    case AutomationError.scriptError(let number, _) where number == 1000 || number == 1002:
        return CaptureError.noSelection   // our scripts' "no selection" / "no window"
    default:
        return error
    }
}
```

2. In `capture(frontApp:)`, change the `catch` block to:

```swift
} catch {
    if let surfaced = Self.errorToSurface(for: error) { throw surfaced }
    Log.capture.info("specific capturer returned a malformed result, falling back to generic")
}
```

3. Timeouts are surfaced, not used as a reason to fall back. Reason: a fallback after a Mail timeout makes exactly the misleading window-title link this item removes. `LinkService.friendlyMessage` already has text for `.timeout`, `.permissionDenied` and `.appNotRunning`, and `LinkService` already shows "Nothing to capture" for `CaptureError.noSelection`. No change in `LinkService` is necessary.
4. Apps with no specific capturer still go to `GenericCapturer` as before.
5. Fix the stale doc comment at lines 3-5 to: "Routes the frontmost app to the right `Capturer` (spec §4.2). Apps with no specific capturer use the generic AX capturer. Errors from a specific capturer are shown to the user, see `errorToSurface(for:)`." Fix the comment at lines 18-19 to match.
6. In `Capture/MailCapturer.swift` lines 8-13, replace the sentence about the generic fallback being the safety net with: "MVP accepts that gap: the capture then fails with \"Nothing to capture\" instead of making a window-title link to Mail."

**Acceptance criteria.**
- Manual (owner): in Mail with no message selected, the capture hotkey shows the "Nothing to capture" notification and the clipboard does not change.
- Manual (owner): with Automation for Mail turned off in System Settings, capture shows "maclink needs permission to control Mail...".
- Manual (owner): TextEdit with a saved document still gives a file link (generic path).

**Tests** (`CaptureEngineTests.swift`):
- `testMalformedResultFallsBack`: `errorToSurface(for: AutomationError.malformedResult)` is `nil`.
- `testNoSelectionScriptErrorsBecomeNoSelection`: for numbers 1000 and 1002, the result is `CaptureError.noSelection` (use `guard case CaptureError.noSelection? = ...`).
- `testPermissionDeniedIsSurfaced`, `testTimeoutIsSurfaced`, `testOtherScriptErrorIsSurfaced` (number -1728): the result is the same error (compare with `as? AutomationError` and `==`; `AutomationError` is `Equatable`).
- `testCaptureErrorNoSelectionIsSurfaced`.

### B2. Normalize web URLs before storage and dedupe (feature 2, F10)

**Problem.** Only Safari strips tracking parameters, and its list removes `ref` from every URL (`Capture/SafariCapturer.swift:18-20`). `ref` is a real parameter on many sites, for example GitHub `?ref=main`. The function also rebuilds the URL through `URLComponents` even when nothing was removed, which can change percent-encoding. Hosts are not lowercased, so dedupe misses `Example.com` vs `example.com`.

**Files.** New `Core/URLNormalizer.swift`. Edit `Capture/SafariCapturer.swift`, `Capture/Capturer.swift`. Delete `Tests/maclinkTests/SafariCapturerTests.swift`. New `Tests/maclinkTests/URLNormalizerTests.swift`.

**Approach.**

1. Create `Core/URLNormalizer.swift`:

```swift
import Foundation

/// Cleans a captured web URL before it is stored and used as the dedupe key
/// (spec §7.4, §8.5). Only http and https URLs change. Everything else
/// (file:, about:, chrome:, ...) comes back as given.
enum URLNormalizer {
    /// Any parameter whose lowercased name starts with this prefix is removed.
    static let trackingPrefix = "utm_"
    /// Removed on every host.
    static let trackingParams: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid",
        "mc_cid", "mc_eid", "igshid", "yclid", "twclid", "_hsenc", "_hsmi", "mkt_tok"
    ]
    /// Removed only on these hosts and their subdomains.
    static let hostTrackingParams: [String: Set<String>] = [
        "youtube.com": ["si"], "youtu.be": ["si"], "spotify.com": ["si"]
    ]

    static func normalize(_ urlString: String) -> String { ... }
}
```

2. `normalize` does these steps, in this order:
   1. `guard var components = URLComponents(string: urlString), let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return urlString }`.
   2. `components.scheme = scheme`.
   3. If `components.percentEncodedHost` is not nil, set it to its `lowercased()` value.
   4. If `(scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443)`, set `components.port = nil`.
   5. If `components.percentEncodedPath.isEmpty`, set it to `"/"`.
   6. If `components.percentEncodedQueryItems` is not nil, filter out each item whose lowercased name has the prefix `trackingPrefix`, is in `trackingParams`, or is in the set for a host key `h` where the lowercased host equals `h` or ends with `"." + h`. Only if at least one item was removed: set `percentEncodedQueryItems` to the kept items, or to `nil` when none are kept (this removes the `?`). If nothing was removed, do not assign the query at all, so its encoding stays exactly as it was.
   7. Do not change the fragment. Do not remove trailing slashes from non-empty paths. Do not remove `www.`. Do not change `http` to `https`. Do not sort parameters.
   8. `return components.string ?? urlString`.
3. In `Capture/Capturer.swift`, add one shared builder for web captures, used by Safari now and by Chromium in B3:

```swift
extension CapturedResource {
    /// Builds a `.url` resource from an AppleScript `{URL, title}` result.
    /// Returns nil when there is no usable URL (for example a new empty tab).
    static func web(fields: [String], bundleID: String, appName: String) -> CapturedResource? {
        guard fields.count == 2, !fields[0].isEmpty else { return nil }
        let rawURL = fields[0]
        let title = fields[1]
        let url = URLNormalizer.normalize(rawURL)
        let host = URL(string: url)?.host
        let payload = URLPayload(
            url: url,
            rawURL: url == rawURL ? nil : rawURL,
            host: host,
            pageTitle: title.isEmpty ? nil : title,
            browserBundleID: bundleID
        )
        return CapturedResource(
            payload: .url(payload),
            title: title.isEmpty ? url : title,
            subtitle: host,
            sourceBundleID: bundleID,
            sourceAppName: appName,
            captureMethod: .applescript
        )
    }
}
```

4. In `SafariCapturer.capture`, replace lines 24-46 with:

```swift
guard let resource = CapturedResource.web(fields: result.stringListValue, bundleID: "com.apple.Safari", appName: "Safari") else {
    throw CaptureError.noSelection
}
return [resource]
```

   Delete `trackingParams` (lines 18-20) and `stripTrackingParams` (lines 49-59); they are now unused. Update the type's doc comment (lines 4-6) to say Chromium browsers use `ChromiumCapturer`.
5. Delete `Tests/maclinkTests/SafariCapturerTests.swift`. Its cases move to `URLNormalizerTests.swift` (below).
6. Existing rows keep their old stored URL. A recapture of an old link whose host had capitals makes one new row. This is accepted; no data migration.

**Acceptance criteria.**
- All tests below pass.
- Manual (owner): capture `https://github.com/apple/swift/tree/main?ref=main&utm_source=x` in Safari. The clipboard link opens; `maclink search github.com/apple` (after C4) or the search dropdown shows the row; the stored URL (`sqlite3 ~/Library/Application\ Support/com.tilak.maclink/maclink.sqlite "select json_extract(payload,'$.url') from links order by created_at desc limit 1"`) is `https://github.com/apple/swift/tree/main?ref=main`.

**Tests** (`URLNormalizerTests.swift`, each one assertion of input to expected output):
- `https://example.com/page?utm_source=x&utm_campaign=y&id=42` to `https://example.com/page?id=42`
- `https://example.com/page?fbclid=abc` to `https://example.com/page`
- `https://example.com/page?utm_source=x#section-2` to `https://example.com/page#section-2`
- `https://example.com/page?id=42&sort=asc` unchanged
- `https://example.com/page` unchanged
- `https://github.com/a/b/tree/main?ref=main` unchanged (F10)
- `https://example.com/s?q=a+b&x=%20y&utm_medium=z` to `https://example.com/s?q=a+b&x=%20y` (encoding kept)
- `https://example.com/s?q=a+b&x=%20y` unchanged (nothing removed, query not reassigned)
- `HTTPS://Example.COM/Path` to `https://example.com/Path` (path case kept)
- `https://example.com:443/a` to `https://example.com/a`; `http://example.com:80/a` to `http://example.com/a`; `https://example.com:8443/a` unchanged
- `https://example.com` to `https://example.com/`
- `https://www.youtube.com/watch?v=abc&si=xyz&t=42` to `https://www.youtube.com/watch?v=abc&t=42` (`t` kept)
- `https://example.com/?si=keep` unchanged (`si` only on listed hosts)
- `https://example.com/?UTM_Source=x&a=1` to `https://example.com/?a=1` (case-insensitive names)
- `file:///Users/x/a.txt` unchanged; `about:blank` unchanged; `not a url` unchanged
- `CapturedResource.web(fields: ["https://Example.com/?utm_source=x", "Title"], bundleID: "com.apple.Safari", appName: "Safari")`: payload `url` is `https://example.com/`, `rawURL` is the input, `host` is `example.com`, `title` is `Title`, `browserBundleID` is `com.apple.Safari`.
- `CapturedResource.web(fields: ["", "x"], ...)` is nil; `CapturedResource.web(fields: ["https://a.com/"], ...)` is nil; title `""` gives `title == url` and `pageTitle == nil`.

### B3. Capture from Chromium-family browsers and reopen in the same browser (feature 1)

**Problem.** Chrome, Arc, Brave, Edge and Vivaldi fall to the generic capturer and give a window-title link that only reactivates the app.

**Files.** New `Capture/ChromiumCapturer.swift`. Edit `Core/CaptureEngine.swift`. New `Tests/maclinkTests/ChromiumCapturerTests.swift`.

**Approach.**

1. Create `Capture/ChromiumCapturer.swift`:

```swift
import AppKit

/// Captures the active tab's URL and title from Chromium-family browsers
/// (spec §7.4). They share Chrome's AppleScript dialect: `active tab` and
/// `title`, where Safari uses `current tab` and `name`. One capturer covers
/// all of them; the script targets the frontmost browser by bundle ID.
struct ChromiumCapturer: Capturer {
    static let bundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "company.thebrowser.Browser",            // Arc
        "com.brave.Browser", "com.brave.Browser.beta", "com.brave.Browser.nightly",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev", "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi"
    ]

    var supportedBundleIDs: Set<String> { Self.bundleIDs }

    static func script(for bundleID: String) -> String {
        """
        tell application id "\(bundleID)"
            if (count of windows) = 0 then error "no window" number 1002
            set t to active tab of front window
            return {URL of t, title of t}
        end tell
        """
    }

    func capture(frontApp: NSRunningApplication) async throws -> [CapturedResource] {
        guard let bundleID = frontApp.bundleIdentifier, Self.bundleIDs.contains(bundleID) else {
            throw CaptureError.noSelection
        }
        let result = try await AutomationService.shared.run(Self.script(for: bundleID))
        guard let resource = CapturedResource.web(
            fields: result.stringListValue,
            bundleID: bundleID,
            appName: frontApp.localizedName ?? bundleID
        ) else {
            throw CaptureError.noSelection
        }
        return [resource]
    }
}
```

   The script text must use a literal bundle ID (interpolated into the source) so AppleScript compiles the terms against that browser's dictionary. `AutomationService` caches one compiled script per source string, so each browser gets its own cache entry.
2. In `CaptureEngine`, add `ChromiumCapturer()` to the `capturers` array after `SafariCapturer()`.
3. Reopen: no resolver change. `CapturedResource.web` sets `browserBundleID` to the capturing browser's bundle ID, and `URLResolver` already opens the link in that app if it is installed, else in the default browser.
4. Not included on purpose: Opera, Orion, Dia, Helium, Firefox. Their AppleScript support is not verified (Orion is WebKit). They keep using the generic capturer. Add a bundle ID to the list only after a person checks it by hand.
5. `Resources/Info.plist` `NSAppleEventsUsageDescription` already says "your browser". No change.
6. The Settings Permissions tab is not changed in this release. macOS asks for Automation permission for each browser on first capture.

**Acceptance criteria.**
- Manual (owner): in Chrome (and Arc, Brave, Edge, Vivaldi where installed), the capture hotkey asks for Automation permission once, then copies a `maclink://open/...` link. The toast shows the page title and the browser name.
- Manual (owner): capture a page in Chrome, then open the link while Safari is the default browser. The page opens in Chrome.
- Manual (owner): in Chrome with no window open, capture shows "Nothing to capture".

**Tests** (`ChromiumCapturerTests.swift`):
- `testScriptTargetsBundleIDAndUsesChromeDialect`: `script(for: "com.brave.Browser")` contains `tell application id "com.brave.Browser"`, `active tab of front window`, `title of t`, and `number 1002`.
- `testScriptCompiles` (live, gated with `MACLINK_LIVE_TESTS`, and also `XCTSkipUnless` `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil`): `NSAppleScript(source: script(for: "com.google.Chrome"))!.compileAndReturnError(&err)` is true.
- `testSupportedBundleIDsIncludeMainBrowsers`: the set contains Chrome, Arc, Brave, Edge and Vivaldi IDs and does not contain `com.apple.Safari`.
- `testEngineRoutesNoBrowserTwice`: the bundle ID sets of `SafariCapturer().supportedBundleIDs` and `ChromiumCapturer.bundleIDs` do not intersect.

### B4. Report failed opens, and remove the MailResolver warning (F9 part)

**Problem.** `MailResolver.swift:23-25` discards the `Bool` from `NSWorkspace.open` (the only compiler warning). `URLResolver.swift:16` and `GenericResolver.swift:20` call the completion-handler APIs without a handler. A failed open shows nothing, and `LinkService.open` still counts it in `open_count`.

**Files.** `Resolve/Resolver.swift`, `Resolve/MailResolver.swift`, `Resolve/URLResolver.swift`, `Resolve/GenericResolver.swift`.

**Approach.**

1. In `Resolver.swift`, add `case openFailed` to `ResolveError`, with the doc comment "macOS refused to open the item (no app for the URL scheme, or a launch failure)." Add:

```swift
extension ResolveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .openFailed:
            return "macOS couldn't open it. The app that handles this kind of link may be missing."
        default:
            return nil
        }
    }
}
```

   Returning `nil` for the other cases keeps today's messages, which `LinkService.friendlyMessage` matches by case.
2. `MailResolver`: replace lines 23-25 with:

```swift
let opened = await MainActor.run { NSWorkspace.shared.open(url) }
guard opened else { throw ResolveError.openFailed }
```

3. `URLResolver`: replace the `MainActor.run` block (lines 13-20) with:

```swift
if let bundleID = payload.browserBundleID,
   let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
    do {
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    } catch {
        Log.resolve.error("open in \(bundleID, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        throw ResolveError.openFailed
    }
} else {
    let opened = await MainActor.run { NSWorkspace.shared.open(url) } // system default browser
    guard opened else { throw ResolveError.openFailed }
}
```

4. `GenericResolver`: replace the `MainActor.run` block (lines 19-21) with a `do { _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) } catch { Log.resolve.error(...); throw ResolveError.openFailed }`. Keep the window raise after it.
5. Do not change `FileResolver` (track C owns it).

**Acceptance criteria.**
- `swift build` shows no warning in `MailResolver.swift`.
- Manual (owner): open a web link, a mail link and a generic link; each still opens as before.

**Tests.** Add `testOpenFailedHasMessageAndOthersDoNot` to `CaptureEngineTests.swift`, under a `// MARK: - ResolveError` comment: `(ResolveError.openFailed as LocalizedError).errorDescription` is not nil, and `(ResolveError.fileNotFound as LocalizedError).errorDescription` is nil. The resolvers themselves need live apps; do not add tests for them.

---

## 6. Track C: Store, search, file repair, CLI

Files (complete list):
- `Package.swift`
- `Sources/MaclinkShared/SearchSQL.swift` (new)
- `Sources/maclink/Store/LinkStore.swift`
- `Sources/maclink/Store/Migrations.swift`
- `Sources/maclink/Models/Payload.swift`
- `Sources/maclink/Models/LinkRecord.swift`
- `Sources/maclink/Resolve/FileRelinker.swift`
- `Sources/maclink/Resolve/FileResolver.swift`
- `Sources/maclink-cli/main.swift`
- `raycast-extension/src/db.ts`
- `Tests/maclinkTests/LinkStoreTests.swift`
- `Tests/maclinkTests/SearchSQLTests.swift` (new)
- `Tests/maclinkTests/FileRepairTests.swift` (new)

Order: C1, C3, C2, C4, C5, C6. Do C3 before C2: C3 adds the `search_text` column and `Payload.searchText`, which C2's `applyRepair` writes. C3 also adds the `v2` index that C4 uses.

### C1. Run the Spotlight relink query on the main actor (F1)

**Problem.** Repair ladder steps 3 and 4 never find a file. `FileRelinker.repair` is `@MainActor`, but `spotlightSearch` (`Resolve/FileRelinker.swift:43-90`) is a non-isolated `async` function. In Swift 5 mode it runs on the global executor, so `NSMetadataQuery` is created and started on a background thread with no run loop. The query never gathers, the 3 s timeout fires, and the result is `[]`. The audit proved this with a probe: non-isolated gave `hits=-1` (timeout); the same code with `@MainActor` gave `hits=1`. The comment at lines 45-47 is wrong.

**Files.** `Resolve/FileRelinker.swift`, new `Tests/maclinkTests/FileRepairTests.swift`.

**Approach.**

1. Change the declaration to `@MainActor static func spotlightSearch(name: String, size: Int64?, timeout: TimeInterval = 10) async -> [URL]`. Remove `private` so tests can call it. Raise the default timeout from 3 to 10 seconds (name-only queries over the local computer can take longer on first gather).
2. Replace `nonisolated(unsafe) let query = NSMetadataQuery()` with `let query = NSMetadataQuery()`.
3. Replace the comment at lines 45-47 with: "`NSMetadataQuery` must start on a thread with a run loop. This function is `@MainActor`, so the continuation body, the observer (queue `.main`) and the timeout all run on the main thread."
4. No other change to the query.

**Acceptance criteria.**
- Manual (owner): capture a file in `~/workspace` (not a protected folder), move it with `mv` to another folder so the bookmark cannot follow (or delete the bookmark by editing a copy of the DB), open the link: the "Relink to this file?" alert shows the new path.

**Tests** (`FileRepairTests.swift`):
- `testSpotlightFindsThisTestFile` (live, gated with `MACLINK_LIVE_TESTS`): let `url = URL(fileURLWithPath: #filePath)`; skip with `XCTSkip` if `mdfind -name FileRepairTests.swift` (run with `Process`, read stdout) does not list `url.path` (the worktree may not be indexed yet). Then `let hits = await FileRelinker.spotlightSearch(name: url.lastPathComponent, size: <file size from resourceValues>)` and assert `hits.map(\.path)` contains `url.path`.

### C2. Narrow repair write-back, fresh identity fields, honest delete, capped picker (F7, F18)

**Problem.**
- `LinkService.open` writes the repaired record with `store.update` (full row rewrite) from a value fetched before the resolve. The relink alerts are modal and can stay up for minutes. Archive state, notes or tags changed in that time are overwritten. If the row was deleted, the error is swallowed.
- `FileResolver.repairedRecord` (lines 74-90) updates `path`, `displayName`, `subtitle`, but not `title`, `byteSize`, `inode`, `volumeUUID`. After a relink to a renamed file, the title is old and dedupe by inode no longer matches, so the next capture makes a duplicate.
- `FileRelinker.giveUp` (line 133) uses `try?` on delete and returns `.deleted` even when the delete failed.
- The name-only picker (`pickAmong`, lines 103-114) has no limit. A common name such as `README.md` can fill the popup with thousands of rows. If the user cancels the step-3 confirm, step 4 usually asks the same question again.

**Files.** `Store/LinkStore.swift`, `Resolve/FileResolver.swift`, `Resolve/FileRelinker.swift`, `Tests/maclinkTests/LinkStoreTests.swift`, `Tests/maclinkTests/FileRepairTests.swift`.

**Approach.**

1. In `LinkStore`, add (in the CRUD section, after `recordOpened`):

```swift
/// Writes a file-link repair (spec §7.6) without touching tags, notes,
/// archive state or `updated_at`. A relink can sit behind a modal alert for
/// minutes; a full-row `update` from a value fetched before that would
/// overwrite anything the user changed meanwhile. `bookmarkData == nil`
/// keeps the stored bookmark.
func applyRepair(id: UUID, payload: Payload, bookmarkData: Data?, subtitle: String?, title: String) throws {
    let changed = try dbQueue.write { db -> Int in
        try db.execute(
            sql: """
                UPDATE links
                SET payload = ?, search_text = ?, payload_blob = COALESCE(?, payload_blob),
                    subtitle = ?, title = ?, repaired_at = ?
                WHERE id = ?
                """,
            arguments: [try payload.encodedJSON(), payload.searchText, bookmarkData, subtitle, title,
                        Date().timeIntervalSince1970, id.uuidString.uppercased()]
        )
        return db.changesCount
    }
    if changed == 0 {
        Log.db.info("applyRepair: link \(id.uuidString, privacy: .public) no longer exists")
    }
    notifyChanged()
}
```

   `search_text` and `payload.searchText` come from C3, which you do first.
2. In `FileResolver`, add a pure, testable function that replaces the payload part of `repairedRecord`:

```swift
/// The file payload after a repair: path and name from `newURL`, and fresh
/// identity fields (size, inode, volume, type) read from disk so dedupe by
/// volume+inode keeps matching the file.
static func repairedPayload(from payload: FilePayload, newURL: URL) -> FilePayload
```

   It sets `path = newURL.path`, `displayName = newURL.lastPathComponent`, then reads `newURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .volumeNameKey, .volumeUUIDStringKey])` and `stat(newURL.path, &buf)`. For each of `isDirectory`, `byteSize`, `uti`, `volumeName`, `volumeUUID`, `inode`: if the new value is not nil, use it, else keep the old value. Copy the stat code style from `FinderCapturer.swift:49-50`.
3. Replace `repairedRecord(...)` with a function that persists, and stop returning a record:
   - Compute `newPayload = repairedPayload(from: payload, newURL: url)`.
   - Bookmark: when `regenerateBookmark` is true, `try? newURL.bookmarkData(options: [], includingResourceValuesForKeys: [.nameKey, .contentTypeKey], relativeTo: nil)`, else `nil` (keep the stored one).
   - Title: if `record.title == payload.displayName`, use `newURL.lastPathComponent`; else keep `record.title` (the user may have renamed the link, see D4).
   - Subtitle: `newURL.deletingLastPathComponent().path`.
   - Call `try LinkStore.shared.applyRepair(id: record.id, payload: .file(newPayload), bookmarkData: bookmark, subtitle: subtitle, title: title)` inside `do/catch`. On error, log with `Log.db.error` and continue: the open must still happen.
   - `resolve` returns `nil` in every path. Remove the `updatedRecord` variable. Keep the `-> LinkRecord?` signature (protocol contract).
4. In `FileRelinker`:
   - Add `case failed(Error)` to `Outcome`.
   - In `giveUp`, replace `try? LinkStore.shared.delete(id: linkID); return .deleted` with `do { try LinkStore.shared.delete(id: linkID); return .deleted } catch { return .failed(error) }`.
   - In `FileResolver`, map `.failed(let error)` to `throw error`.
   - In `repair`, keep the URL that the user rejected in step 3 (`var rejected: URL?`, set it when `confirmRelink` returns false). In step 4, filter it out: `let nameHits = await spotlightSearch(...).filter { $0 != rejected }`.
   - In `pickAmong`, if there are more than 50 candidates, sort by `path` and keep the first 50, and set `informativeText` to "Showing 50 of \(candidates.count) files with this name. Choose which file this link should point to:". Return the URL from the kept list.

**Acceptance criteria.**
- Manual (owner): relink a moved file whose link has tags; after the relink the tags are still there and the title shows the new file name.
- Manual (owner): choose "Delete Link" in the give-up alert; the link is gone from search.

**Tests.**
- `LinkStoreTests.testApplyRepairKeepsTagsArchiveAndUpdatedAt`: insert a file record with tags `["a"]`, then `setArchived(true, id:)`, read back `updatedAt`; call `applyRepair` with a new path, `bookmarkData: nil`, a new title; fetch: tags are `["a"]`, `archived` is true, `updatedAt` is unchanged, `title` and payload `path` are the new values, `repairedAt` is not nil, `bookmarkData` is the old one.
- `LinkStoreTests.testApplyRepairOnDeletedRowDoesNotThrow`: delete the row, then `applyRepair` does not throw.
- `FileRepairTests.testRepairedPayloadRefreshesIdentity`: write a 5-byte temp file, build an old `FilePayload` with wrong `byteSize`, `inode` and `displayName`; `repairedPayload(from:newURL:)` gives the temp file's path, name, `byteSize == 5`, and the inode from `stat`.

### C3. Search payload values, not raw JSON, and share the search SQL (F5)

**Problem.** Search runs `LIKE` on the raw payload JSON (`Store/LinkStore.swift:243`). JSON key names match: `path`, `url`, `host`, `subject`, `true`, `inode` and others match every link of a type. `JSONEncoder` writes `/` as `\/`, so `github.com/foo` or `Documents/report` never match the payload. The same SQL clause is copied in `Sources/maclink-cli/main.swift:219-223` and `raycast-extension/src/db.ts:58-64`.

**Files.** `Package.swift`, new `Sources/MaclinkShared/SearchSQL.swift`, `Store/Migrations.swift`, `Models/Payload.swift`, `Models/LinkRecord.swift`, `Store/LinkStore.swift`, `Sources/maclink-cli/main.swift`, `raycast-extension/src/db.ts`, `Tests/maclinkTests/LinkStoreTests.swift`, new `Tests/maclinkTests/SearchSQLTests.swift`.

**Approach.**

1. **Shared SQL.** Add a library target with only the search condition and the `LIKE` escaping. The app and the CLI use it. (Raycast is TypeScript and keeps a copy, with a comment that points to this file.) In `Package.swift`:
   - Add `.target(name: "MaclinkShared", path: "Sources/MaclinkShared")` to `targets`.
   - Add `"MaclinkShared"` to the `dependencies` of `maclink`, `maclink-cli` and `maclinkTests`.
2. Create `Sources/MaclinkShared/SearchSQL.swift`:

```swift
/// The text-search condition shared by the app (`LinkStore.search`) and the
/// CLI (`maclink search`). `raycast-extension/src/db.ts` has a TypeScript
/// copy; keep it in step. Use inside `... FROM links WHERE ... AND <matchCondition>`
/// and bind `arguments(for:)` (five values) before any other argument
/// that comes after it.
public enum SearchSQL {
    public static let matchCondition = """
        (links.title LIKE ? ESCAPE '\\' OR links.subtitle LIKE ? ESCAPE '\\' OR
         links.notes LIKE ? ESCAPE '\\' OR links.search_text LIKE ? ESCAPE '\\' OR
         EXISTS (SELECT 1 FROM link_tags JOIN tags ON tags.id = link_tags.tag_id
                 WHERE link_tags.link_id = links.id AND tags.name LIKE ? ESCAPE '\\'))
        """

    /// Five copies of the `%query%` pattern, one per `?` in `matchCondition`.
    public static func arguments(for query: String) -> [String] {
        Array(repeating: "%\(escapedForLike(query))%", count: 5)
    }

    /// `%` and `_` are LIKE wildcards; escape them and the escape character
    /// itself, to pair with `ESCAPE '\'`.
    public static func escapedForLike(_ query: String) -> String { /* body of LinkStore.escapedForLike, lines 214-224 */ }
}
```

   The `EXISTS` subquery replaces today's `LEFT JOIN ... DISTINCT`. Each link appears once, and tag hydration still returns all of its tags.
3. **Payload text.** In `Models/Payload.swift`, add to `Payload`:

```swift
/// The payload values that search matches (spec §9.3 `payload_text`):
/// values only, never JSON key names, and with `/` unescaped.
var searchText: String {
    let values: [String?]
    switch self {
    case .file(let p): values = [p.path]
    case .mail(let p): values = [p.messageID.hasPrefix("unknown-") ? nil : p.messageID, p.subject, p.sender, p.mailbox, p.account]
    case .url(let p): values = [p.url, p.host, p.pageTitle]
    case .generic(let p): values = [p.windowTitle]
    }
    return values.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
}
```

4. **Column.** In `Store/Migrations.swift`, register a second migration after `v1`:

```swift
migrator.registerMigration("v2") { db in
    try db.alter(table: "links") { t in
        t.add(column: "search_text", .text).notNull().defaults(to: "")
    }
    // Backfill from the stored JSON. json_extract returns unescaped values;
    // json_valid guards against a hand-edited bad row, which would otherwise
    // fail the migration and so the app launch.
    try db.execute(sql: """
        UPDATE links SET search_text = CASE WHEN json_valid(payload) THEN TRIM(
            COALESCE(json_extract(payload, '$.path'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.url'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.host'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.page_title'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.message_id'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.subject'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.sender'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.mailbox'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.account'), '') || ' ' ||
            COALESCE(json_extract(payload, '$.window_title'), '')
        ) ELSE '' END
        """)
    try db.create(index: "idx_links_updated", on: "links", columns: ["updated_at"])
}
```

   The `idx_links_updated` index is for C4.
5. In `Models/LinkRecord.swift`, add `static let searchText = Column("search_text")` to `Columns`, and in `encode(to:)` add `container[Columns.searchText] = payload.searchText`. Do not read it in `init(row:)`. This fills the column on every `insert` and `update`.
6. In `LinkStore.search`, the non-empty branch becomes:

```swift
records = try LinkRecord.fetchAll(db, sql: """
    SELECT links.* FROM links
    WHERE links.archived = 0 AND \(SearchSQL.matchCondition)
    ORDER BY links.created_at DESC
    LIMIT ?
    """, arguments: StatementArguments(SearchSQL.arguments(for: trimmed)) + [limit])
```

   (C4 changes the `ORDER BY`; C5 changes the decode.) Add `import MaclinkShared` at the top of `LinkStore.swift`. Delete `LinkStore.escapedForLike` (lines 210-224); it is now unused.
7. In `Sources/maclink-cli/main.swift`: `import MaclinkShared`; delete the local `escapedForLike` (lines 59-71); in `fetchLinks`, remove `DISTINCT` and both `LEFT JOIN` lines from the SQL (they were only there for the tag match); in `runSearch`, use `whereClause: "AND \(SearchSQL.matchCondition)"` and `arguments: StatementArguments(SearchSQL.arguments(for: query))`.
8. In `raycast-extension/src/db.ts`:
   - Change `SELECT` to select tags with a subquery, not a join:

```ts
const SELECT = `
  SELECT links.id, links.resource_type, links.title, links.subtitle,
         links.payload, links.degraded, links.created_at,
         (SELECT GROUP_CONCAT(tags.name, ' ') FROM link_tags
            JOIN tags ON tags.id = link_tags.tag_id
            WHERE link_tags.link_id = links.id) AS tags
  FROM links
`;
```

   - In the search branch, replace the `WHERE ... GROUP BY links.id` text with the same condition as `SearchSQL.matchCondition`, with `'${pattern}'` in place of each `?` and `links.search_text` in place of `links.payload`. Remove both `GROUP BY links.id` (no longer needed). Add a comment above the query: `// Keep in step with Sources/MaclinkShared/SearchSQL.swift.`
   - This also fixes the audit's F19 Raycast bug: a tag search showed only the matching tag, now it shows all tags of the link.

**Acceptance criteria.**
- All tests below pass.
- `swift build -c release --product maclink-cli` passes.
- Manual (owner, after install): `maclink search github.com/` lists web links with that host; `maclink search path` does not list every file link.
- Raycast: if `node` is available, `cd raycast-extension && npm run build` passes. If not, the worker says so in the final report.

**Tests.**
- `SearchSQLTests` (`import MaclinkShared`): `escapedForLike("report_final")` is `report\_final`; `escapedForLike("100%")` is `100\%`; `escapedForLike("a\\b")` is `a\\\\b` (one backslash becomes two); `arguments(for: "x")` is five copies of `%x%`; `matchCondition` contains exactly five `?` characters.
- `LinkStoreTests.testSearchIgnoresJSONKeyNames`: insert a url record titled "Example" (`url: "https://example.org/a"`, `host: "example.org"`); `search("host")`, `search("browser_bundle_id")` and `search("page_title")` return 0 rows.
- `LinkStoreTests.testSearchMatchesURLsWithSlashes`: url record with `url: "https://github.com/apple/swift"` and title "Swift"; `search("github.com/apple")` returns it.
- `LinkStoreTests.testSearchMatchesFilePathWithSlashes`: file record, path `/Users/x/Documents/report.pdf`, title `report.pdf`, subtitle `nil`; `search("Documents/report")` returns it.
- `LinkStoreTests.testSearchReturnsEachLinkOnceWhenSeveralTagsMatch`: record with tags `["alpha", "alphabet"]`; `search("alpha")` returns 1 row with both tags.
- `LinkStoreTests.testMigrationV2BackfillsSearchText`: create a `DatabaseQueue` at a temp path, run `Migrations.migrator().migrate(dbQueue, upTo: "v1")`, insert one url row with raw SQL whose payload JSON has `"url":"https:\/\/github.com\/a\/b"` (escaped slashes, as `JSONEncoder` writes), plus one row whose payload is `not json`. Raw inserts must give every NOT NULL column: `id` (uppercase UUID), `resource_type`, `title`, `payload`, `capture_method` (`applescript`), `created_at`, `updated_at`. Release the queue. Open `LinkStore(url:)` on the same path (this runs `v2`). `search("github.com/a")` returns the first row, and the migration did not throw. (`import GRDB` in the test file for `DatabaseQueue`; the test target gets GRDB through the `maclink` dependency. If it does not resolve, add `.product(name: "GRDB", package: "GRDB.swift")` to the test target in `Package.swift`.)
- Keep `testSearchTreatsLikeWildcardsAsLiteralText` and `testSearchHydratesTagsForEveryResult` unchanged; they must still pass.

### C4. Order "recent" by last capture, so a recapture comes back to the top (F6)

**Problem.** Recent menu, empty search and `maclink latest` order by `created_at`. A dedupe hit only bumps `updated_at` (`LinkService.swift:158-161` calls `store.update`, which sets `updatedAt = Date()`). So after you recapture a file from last week, the clipboard has its old link, but `maclink latest --org` (used by `maclink-insert-latest` in `contrib/maclink.el`) returns a different link.

**Files.** `Store/LinkStore.swift`, `Sources/maclink-cli/main.swift`, `raycast-extension/src/db.ts`, `Tests/maclinkTests/LinkStoreTests.swift`.

**Approach.**

1. `LinkStore.fetchAll`: order by `LinkRecord.Columns.updatedAt.desc` (C5 rewrites this function to SQL; then use `ORDER BY updated_at DESC`).
2. `LinkStore.search`: both branches `ORDER BY updated_at DESC` (`links.updated_at` in the non-empty branch).
3. CLI `fetchLinks`: `ORDER BY links.updated_at DESC`. The JSON output keeps `createdAt`.
4. Raycast `db.ts`: both queries `ORDER BY links.updated_at DESC`.
5. `updated_at` is also bumped by `setArchived` (archived rows are hidden, so no effect) and by `update` (capture dedupe and the D4 title edit). `applyRepair` (C2) does not bump it, on purpose: opening a repaired file is not a capture.

**Acceptance criteria.**
- Manual (owner): capture file A, then file B, then A again. The Recent menu shows A first, and `maclink latest` prints A's link.

**Tests.**
- Rename `testFetchAllOrdersByCreatedAtDescending` to `testFetchAllOrdersByMostRecentCapture` and extend it: insert first, sleep 10 ms, insert second, assert `[second, first]`; sleep 10 ms, `store.update(first)`, assert `fetchAll()` is `[first, second]` and `search("")` has the same order.

### C5. One bad row must not hide every link (F8 part)

**Problem.** `LinkRecord.init(row:)` throws when a payload does not decode (a hand-edited row, or a future payload version). `fetchAll` and `search` then throw, and the dropdown and Recent menu show "No links yet" for everything.

**Files.** `Store/LinkStore.swift`, `Tests/maclinkTests/LinkStoreTests.swift`.

**Approach.**

1. Add to `LinkStore`:

```swift
/// Decodes rows one by one and skips (and logs) any that fail, so one bad
/// payload can't empty every list.
private static func decodeSkippingBadRows(_ rows: [Row]) -> [LinkRecord] {
    rows.compactMap { row in
        do {
            return try LinkRecord(row: row)
        } catch {
            Log.db.error("skipping undecodable link row \(String(describing: row["id"] as String?), privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
```

2. `fetchAll`: replace the query-interface request with SQL: `SELECT * FROM links \(includeArchived ? "" : "WHERE archived = 0") ORDER BY updated_at DESC LIMIT ?`, fetch `Row.fetchAll`, then `decodeSkippingBadRows`. Hydrate tags as before.
3. `search`: both branches fetch `Row.fetchAll` with the same SQL and arguments as now, then `decodeSkippingBadRows`.
4. `fetch(id:)` and `findExisting` stay as they are (a single bad row there is a real error for that one link).
5. The launch crash on a broken database file (`static let shared = try! ...`) is not in this item. See section 8.2.

**Acceptance criteria.** Tests below.

**Tests.**
- `LinkStoreTests.testUndecodableRowIsSkippedNotFatal`: insert two good records; insert one row with raw SQL with `resource_type = 'file'` and `payload = '{"v":1}'` (missing required keys), and the other NOT NULL columns as in the C3 migration test; `fetchAll()` and `search("")` each return the 2 good rows and do not throw.

### C6. Two small CLI fixes (F19 part)

**Problem.** `maclink get <uuid>` filters `archived = 0`, so an archived link reports "no link with id". `--limit` accepts zero and negative numbers (SQLite treats `LIMIT -1` as no limit).

**Files.** `Sources/maclink-cli/main.swift`.

**Approach.**

1. Add a parameter `includeArchived: Bool = false` to `fetchLinks`. Build the first `WHERE` term as `includeArchived ? "1 = 1" : "links.archived = 0"`. `runGet` passes `includeArchived: true`. Other callers do not change.
2. In `runSearch`, change the `--limit` guard to `guard i < args.count, let n = Int(args[i]), n > 0 else { throw CLIError.usage("--limit requires a positive number") }`.

**Acceptance criteria.**
- `swift build --product maclink-cli` passes.
- Manual (owner): archive a link in the dropdown, then `maclink get <its uuid>` prints it. `maclink search x --limit 0` prints the usage error and exits 1.

**Tests.** None (the CLI has no test target; adding one is out of scope).

---

## 7. Track D: Clipboard, toast, Finder service

Files (complete list):
- `Sources/maclink/Core/ClipboardFormatter.swift` (new)
- `Sources/maclink/Core/LinkService.swift`
- `Sources/maclink/UI/SearchPanelView.swift`
- `Sources/maclink/App/StatusItemController.swift`
- `Sources/maclink/UI/CaptureToastController.swift`
- `Sources/maclink/UI/CaptureToastView.swift`
- `Sources/maclink/App/ServicesProvider.swift` (new)
- `Sources/maclink/App/AppDelegate.swift`
- `Sources/maclink/Capture/FinderCapturer.swift`
- `Sources/maclink/Models/ResourceType.swift`
- `Resources/Info.plist`
- `Tests/maclinkTests/ClipboardFormatterTests.swift` (new)
- `Tests/maclinkTests/CaptureToastTests.swift` (new)

Order: D1, D2, D3, D4, D5, D6, D7.

### D1. One clipboard formatter with escaping, used by every copy path (F11)

**Problem.** `LinkService.formatClipboardEntry` (lines 147-153) does not escape titles. A title with `]` (for example `Re: [list] foo]`) makes a broken org link `[[url][Re: [list] foo]]]` and a broken Markdown link. The per-row copy button, Cmd-Return and Option-click in Recent always write the raw URL, even when the user chose org or Markdown (`copyLinkToClipboard`, lines 201-203).

**Files.** New `Core/ClipboardFormatter.swift`, `Core/LinkService.swift`, `App/StatusItemController.swift`, new `Tests/maclinkTests/ClipboardFormatterTests.swift`.

**Approach.**

1. Create `Core/ClipboardFormatter.swift`:

```swift
import Foundation

/// What a copy action puts on the clipboard (spec §9.3, §9.5).
enum CopyKind {
    /// The maclink URL, in the user's clipboard format setting.
    case link
    /// The original address: web URL, file path, or `message:` URL.
    case address
    /// `file://` URL (files only).
    case fileURL
    /// Markdown link to the original address (file URL for files).
    case markdownAddress
}

/// Pure text building for every clipboard write. No AppKit here, so tests
/// can call it directly.
enum ClipboardFormatter {
    static func format(url: String, title: String, as format: ClipboardFormat) -> String {
        switch format {
        case .raw: return url
        case .org: return "[[\(url)][\(orgDescription(title))]]"
        case .markdown: return "[\(markdownText(title))](\(markdownDestination(url)))"
        }
    }

    /// Org has no escape for brackets inside a description; swap them.
    static func orgDescription(_ title: String) -> String {
        title.replacingOccurrences(of: "[", with: "{").replacingOccurrences(of: "]", with: "}")
    }

    /// Escapes `\`, `[` and `]` (backslash first).
    static func markdownText(_ title: String) -> String { ... }

    /// Wraps the URL in `<...>` when it contains a space, `(` or `)`.
    static func markdownDestination(_ url: String) -> String { ... }

    static func maclinkURL(for record: LinkRecord) -> String {
        "maclink://open/\(record.id.uuidString)"
    }

    /// The original address, or nil when there is none (generic links,
    /// mail without a Message-ID).
    static func address(for record: LinkRecord) -> String? {
        switch record.payload {
        case .url(let p): return p.url
        case .file(let p): return p.path
        case .mail(let p):
            guard !p.messageID.hasPrefix("unknown-") else { return nil }
            return p.messageURL ?? MailCapturer.messageURLString(for: p.messageID)
        case .generic: return nil
        }
    }

    static func fileURL(for record: LinkRecord) -> String? {
        guard case .file(let p) = record.payload else { return nil }
        return URL(fileURLWithPath: p.path, isDirectory: p.isDirectory).absoluteString
    }

    /// The full clipboard text for one record, or nil if `kind` doesn't apply.
    static func text(for record: LinkRecord, kind: CopyKind, format: ClipboardFormat) -> String? {
        switch kind {
        case .link: return self.format(url: maclinkURL(for: record), title: record.title, as: format)
        case .address: return address(for: record)
        case .fileURL: return fileURL(for: record)
        case .markdownAddress:
            guard let target = fileURL(for: record) ?? address(for: record) else { return nil }
            return self.format(url: target, title: record.title, as: .markdown)
        }
    }
}
```

2. In `LinkService`:
   - Add `private static var currentFormat: ClipboardFormat { UserDefaults.standard.string(forKey: "clipboardFormat").flatMap(ClipboardFormat.init) ?? .raw }`.
   - `formatClipboardEntry(url:title:)` returns `ClipboardFormatter.format(url: url, title: title, as: Self.currentFormat)`.
   - Replace `copyLinkToClipboard(_:)` with:

```swift
/// Copies one record. Returns false (and writes nothing) when `kind`
/// doesn't apply to this record, for example a file URL for an email.
@discardableResult
func copy(_ record: LinkRecord, as kind: CopyKind) -> Bool {
    guard let text = ClipboardFormatter.text(for: record, kind: kind, format: Self.currentFormat) else { return false }
    writeToClipboard(text)
    return true
}
```

3. In `StatusItemController`: the popover's `onCopy` closure (lines 56-58) becomes `onCopy: { record, kind in LinkService.shared.copy(record, as: kind) }` (D2 changes the closure type). In `recentItemTapped` (line 237), use `LinkService.shared.copy(record, as: .link)`.

**Acceptance criteria.**
- With "Org" chosen in Settings, the per-row copy button and Option-click in Recent put `[[maclink://open/...][Title]]` on the clipboard.

**Tests** (`ClipboardFormatterTests.swift`):
- `format(url: "u", title: "T", as: .raw)` is `u`.
- org: title `Re: [list] foo]` gives `[[u][Re: {list} foo}]]`.
- markdown: title `a [b] \ c` gives `[a \[b\] \\ c](u)`.
- markdown destination: `https://en.wikipedia.org/wiki/Foo_(bar)` gives `<https://en.wikipedia.org/wiki/Foo_(bar)>`; `https://a.com/x` unchanged.
- `address(for:)`: url record gives its URL; file record gives its path; mail record with `messageID: "abc@x.com"` and `messageURL: nil` gives `MailCapturer.messageURLString(for: "abc@x.com")`; mail with `unknown-...` gives nil; generic gives nil.
- `fileURL(for:)`: path `/tmp/a b.txt` gives `file:///tmp/a%20b.txt`; directory path gives a URL that ends in `/`; url record gives nil.
- `text(for:kind: .markdownAddress, format: .org)` on a file record gives `[a b.txt](file:///tmp/a%20b.txt)` (always Markdown, file URL); on a url record gives `[Title](https://...)`; on a generic record gives nil.
- `text(for:kind: .link, format: .markdown)` gives `[Title](maclink://open/<UUID>)`.

### D2. More copy actions in the search dropdown (feature 3)

**Problem.** The dropdown can copy only the `maclink://` URL. Users need the real address or path where a `maclink://` link is wrong (chat with other people, a terminal).

**Files.** `UI/SearchPanelView.swift`, `App/StatusItemController.swift`.

**Approach.**

1. In `SearchPanelView`, change `var onCopy: (LinkRecord) -> Void` to `var onCopy: (LinkRecord, CopyKind) -> Void`. In `SearchResultRow`, change its `onCopy` the same way; the row button calls `onCopy(record, .link)`. Change its `.help` to `"Copy link (in your clipboard format)"`.
2. Keyboard, in the `.return` case of `onKeyPress` (lines 38-44):
   - Command held: `copySelected(.link)`.
   - Else Shift held: `copySelected(.address)`.
   - Else: `openSelected()`.
   `copySelected(_ kind: CopyKind)` calls `onCopy(results[selectedIndex], kind)`. If `ClipboardFormatter.text(for: record, kind: kind, format: .raw) == nil` (the kind does not apply to this record), call `NSSound.beep()` instead and do not call `onCopy`. Add `import AppKit` if needed for `NSSound`.
3. Context menu (lines 99-113): after "Copy Link", add, in this order:
   - If `ClipboardFormatter.address(for: record) != nil`: a button titled "Copy Path" for file records, "Copy Address" for others, calling `onCopy(record, .address)`.
   - If the record is a file: "Copy File URL", calling `onCopy(record, .fileURL)`.
   - If `ClipboardFormatter.address(for: record) != nil`: "Copy Markdown Link to Original", calling `onCopy(record, .markdownAddress)`.
4. Copy does not close the dropdown (same as today's copy).
5. Fix the stale doc comment at line 8: remove "or the \"Pin Search Window\" menu item" (that menu item no longer exists).
6. In `StatusItemController`, the closure from D1 step 3 already has the new type.

**Acceptance criteria.**
- Manual (owner): in the dropdown, Shift-Return on a web link copies `https://...`; on a file copies the path; on an email copies `message://%3C...%3E`; on a generic link it beeps.
- Manual (owner): the context menu on a file shows Copy Link, Copy Path, Copy File URL, Copy Markdown Link to Original. On a generic link it shows only Copy Link.

**Tests.** Covered by D1's formatter tests. No UI tests.

### D3. Toast tags add to existing tags, and the toast says "Existing link" (F3)

**Problem.** When a capture reuses an existing record, the toast still offers "Add tags…". `commitTags` (`UI/CaptureToastController.swift:111-128`) calls `LinkStore.setTags`, which starts with `DELETE FROM link_tags WHERE link_id = ?`. Typing `foo` replaces all earlier tags with just `foo`. This is silent data loss on a normal path. Also, typing the same tag twice (`a a`) makes `setTags` fail on the `link_tags` primary key. The toast does not say that the link already existed (SPEC §8.5 wants "Existing link (3 tags)").

**Files.** `UI/CaptureToastController.swift`, `UI/CaptureToastView.swift`, new `Tests/maclinkTests/CaptureToastTests.swift`.

**Approach.**

1. In `CaptureToastController`, store the records, not only their IDs: replace `trackedRecordIDs: [UUID]` with `trackedRecords: [LinkRecord]` (set in `show`). `undo()` keeps using `newRecordIDs`.
2. Add a pure function:

```swift
/// Existing tags plus the newly typed ones (split on commas and spaces),
/// in order, with no case-insensitive duplicates. Tag slugs are lowercased
/// names, so a case-insensitive match is a slug match.
static func mergedTags(existing: [String], typed: String) -> [String] {
    var result = existing
    var seen = Set(existing.map { $0.lowercased() })
    for tag in typed.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init) where !tag.isEmpty {
        if seen.insert(tag.lowercased()).inserted { result.append(tag) }
    }
    return result
}
```

3. In the tag commit, for each record in `trackedRecords`: `let merged = Self.mergedTags(existing: record.tags, typed: text)`; if `merged == record.tags`, skip; else `try LinkStore.shared.setTags(merged, for: record.id)` with the same error handling as today. Use the existing `LinkStore.setTags`; do not add a store method (track C owns `LinkStore.swift`).
4. In `CaptureToastView`, add `let existingTagCount: Int?` (nil when the capture made a new link or captured more than one item). The controller sets it to `records[0].record.tags.count` when `records.count == 1 && !records[0].isNew`, else nil. `subheadline` then returns, for a single existing link: `"Existing link (\(n) tag\(n == 1 ? "" : "s")) · copied to clipboard"`. Other cases stay as today.

**Acceptance criteria.**
- Manual (owner): capture a file, tag it `a`. Capture the same file again. The toast says "Existing link (1 tag)". Type `b` and press Return. The search dropdown shows tags `a b`.

**Tests** (`CaptureToastTests.swift`):
- `mergedTags(existing: ["a"], typed: "b")` is `["a", "b"]`.
- `mergedTags(existing: ["Work"], typed: "work, home")` is `["Work", "home"]`.
- `mergedTags(existing: [], typed: "a a,  b")` is `["a", "b"]`.
- `mergedTags(existing: ["a"], typed: "  ")` is `["a"]`.

### D4. Edit the title in the toast before you paste (feature 3)

**Problem.** The captured title is often noisy (page titles with site names, file names). With org or Markdown format, the noisy title goes into the pasted link.

**Files.** `UI/CaptureToastView.swift`, `UI/CaptureToastController.swift`, `Core/LinkService.swift`.

**Approach.**

1. `LinkService`, add:

```swift
/// Renames a link. If the clipboard still holds exactly what the capture
/// wrote (same `changeCount`), it is rewritten with the new title, so a
/// pasted org or Markdown link carries it.
func rename(id: UUID, to newTitle: String, clipboardChangeCount: Int) {
    do {
        guard var record = try store.fetch(id: id) else { return }
        record.title = newTitle
        try store.update(record)
        if NSPasteboard.general.changeCount == clipboardChangeCount {
            writeToClipboard(formatClipboardEntry(url: ClipboardFormatter.maclinkURL(for: record), title: newTitle))
        }
    } catch {
        Log.db.error("rename failed for \(id.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
        NotificationService.notifyFailure(title: "Couldn't rename the link", body: Self.friendlyMessage(for: error, sourceAppName: nil))
    }
}
```

   `rename` is only for a capture of one record (the clipboard then has one line).
2. `CaptureToastController.show`: record `clipboardChangeCount = NSPasteboard.general.changeCount` (the capture wrote the clipboard just before `show` runs).
3. `CaptureToastView`:
   - Replace `onTagsCommitted: (String) -> Void` with `onCommit: (_ title: String, _ tags: String) -> Void`.
   - Add `@State private var titleText: String` (initialize from `records.first?.title ?? ""` in an `init`, or in `.onAppear`).
   - Replace `@FocusState private var tagFieldFocused: Bool` with `private enum Field { case title, tags }` and `@FocusState private var focusedField: Field?`. `.onChange(of: focusedField) { _, field in onFieldFocusChanged(field != nil) }`.
   - When `records.count == 1`, show the headline as `TextField("Title", text: $titleText)` with `.textFieldStyle(.plain)`, the same font as the current headline (`.system(size: 13, weight: .medium)`), `.lineLimit(1)`, `.focused($focusedField, equals: .title)`. When there are several records, keep the current `Text(headline)`.
   - Both fields use `.onSubmit { onCommit(titleText, tagText); onDismiss() }`. The tag field uses `.focused($focusedField, equals: .tags)`.
   - Panel size stays `320 x 110`; the text field replaces the text in the same row.
4. `CaptureToastController`: the commit handler does, in order: if `trackedRecords.count == 1`, trim the title; if it is not empty and differs from `trackedRecords[0].title`, call `LinkService.shared.rename(id:to:clipboardChangeCount:)`. Then the tag merge from D3.
5. Undo is not changed: it deletes only new records and restores the old clipboard text.

**Acceptance criteria.**
- Manual (owner): with org format, capture a Safari page, click the title in the toast, change it, press Return. Paste: the org link has the new title. The search dropdown shows the new title.
- Manual (owner): click the title, change nothing, press Return. Nothing is written (no `updated_at` change, clipboard unchanged).
- Manual (owner): with the title field focused, the toast does not auto-dismiss.

**Tests.** None beyond D1 and D3 (UI and pasteboard). Do not add UI tests.

### D5. Finder "Copy maclink" through the Services menu (feature 4)

**Problem.** Capture needs the hotkey. Linker and Hookmark both offer a Finder right-click action, also for many files at once.

**Files.** `Resources/Info.plist`, new `App/ServicesProvider.swift`, `App/AppDelegate.swift`, `Core/LinkService.swift`, `Capture/FinderCapturer.swift`, `Models/ResourceType.swift`.

**Approach.**

1. `Models/ResourceType.swift`: add `case service` to `CaptureMethod` (raw value `"service"`). Older builds map unknown raw values to `.manual` (`LinkRecord.swift:112`), so this is safe.
2. `Capture/FinderCapturer.swift`: change `private static func resource(forPath path: String) -> CapturedResource?` to `static func resource(forPath path: String, method: CaptureMethod = .applescript) -> CapturedResource?` and pass `method` to `captureMethod:` (line 76). The existing caller (line 37) does not change.
3. `Resources/Info.plist`: add this key before the closing `</dict>`:

```xml
    <!-- Finder right-click > Quick Actions / Services > "Copy maclink"
         (one or many files). Handled by ServicesProvider.copyMaclink. -->
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Copy maclink</string>
            </dict>
            <key>NSMessage</key>
            <string>copyMaclink</string>
            <key>NSPortName</key>
            <string>maclink</string>
            <key>NSRequiredContext</key>
            <dict/>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
        </dict>
    </array>
```

4. Create `App/ServicesProvider.swift`:

```swift
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
```

5. `App/AppDelegate.swift`: add `private let servicesProvider = ServicesProvider()`. In `applicationDidFinishLaunching`, after `StatusItemController.shared.setup()`, add `NSApp.servicesProvider = servicesProvider` and `NSUpdateDynamicServices()`.
6. `Core/LinkService.swift`:
   - Move lines 110-124 of `captureFromHotkey` (store, clipboard, diagnostic, toast) into `private func finishCapture(_ resources: [CapturedResource], previousClipboard: String?, source: String) async throws`. Start it with `guard !resources.isEmpty else { throw CaptureError.noSelection }`. `captureFromHotkey`'s `Task` then calls `let resources = try await CaptureEngine.shared.capture(frontApp: frontApp)` and `try await finishCapture(resources, previousClipboard: previousClipboard, source: frontApp.bundleIdentifier ?? "?")`. Keep its `catch` blocks as they are.
   - Add:

```swift
/// Captures files handed over by the Finder service (spec §7.2 resource
/// building, same dedupe, clipboard and toast as a hotkey capture).
func captureFiles(_ urls: [URL]) {
    let previousClipboard = NSPasteboard.general.string(forType: .string)
    let resources = urls.compactMap { FinderCapturer.resource(forPath: $0.path, method: .service) }
    Task {
        do {
            try await finishCapture(resources, previousClipboard: previousClipboard, source: "service")
        } catch {
            NotificationService.notifyFailure(
                title: "Capture failed",
                body: Self.friendlyMessage(for: error, sourceAppName: "Finder")
            )
        }
    }
}
```

7. Several files give several links, one per line on the clipboard, and one toast ("3 links copied"), the same as a multi-select hotkey capture.
8. After install, macOS may cache the Services menu. If "Copy maclink" does not show, run `/System/Library/CoreServices/pbs -update`, or turn it on in System Settings > Keyboard > Keyboard Shortcuts > Services > Files and Folders. Item A4 documents this for users.

**Acceptance criteria.**
- `plutil -lint Resources/Info.plist` passes.
- `swift build` passes.
- Manual (owner, after `Scripts/install.sh`): in Finder, select one file, right-click > Quick Actions (or Services) > Copy maclink. The toast shows, and the clipboard has one link in the chosen format. Select three files: three lines on the clipboard, toast says "3 links copied". Do it again on the same file: the toast says "Existing link".

**Tests.** None (Services need a live session). D1 tests cover formatting.

### D6. Clearer error text for script errors and failed opens

**Problem.** After B1, AppleScript errors that are not "no selection" reach the user. Today they show as "Something went wrong: scriptError(-1728, ...)". After B4, a failed open has its own text through `LocalizedError`, but `friendlyMessage` does not read it.

**Files.** `Core/LinkService.swift`.

**Approach.** In `friendlyMessage(for:sourceAppName:)`:
1. Add before `default:`: `case AutomationError.scriptError(_, let message): return "\(app) reported an error: \(message)"`.
2. Change `default:` to `return (error as? LocalizedError)?.errorDescription ?? "Something went wrong: \(String(describing: error))"`.

**Acceptance criteria.** Build passes. After the merge with track B, a failed `message:` open shows "macOS couldn't open it...".

**Tests.** None (`friendlyMessage` is private; do not change its visibility only for a test).

### D7. Replace the temporary diagnostic file log with OSLog (F13)

**Problem.** `recordDiagnostic` (`LinkService.swift:239-256`) is marked "Temporary: remove once the capture toast exists". The toast exists. It appends to `~/Library/Application Support/com.tilak.maclink/diagnostic.log` forever with no size limit, records every search query and every title opened, makes a new `ISO8601DateFormatter` per line, and is called from concurrent tasks with an unsynchronized seek-then-write.

**Files.** `Core/LinkService.swift`.

**Approach.** Replace each `recordDiagnostic("...")` call with a `Log` call with the same text: `Log.resolve.info` in `handle` and `open` (use `.error` in the two failure `catch` blocks of `open`), `Log.capture.info` in the capture paths (`.error` for "capture failed"), `Log.db.error` in `archive` and `delete` failures. Mark user content (`query`, `title`) with `privacy: .private` and IDs and bundle IDs with `privacy: .public`. Then delete `recordDiagnostic`. Do not delete an existing `diagnostic.log` file on disk.

**Acceptance criteria.**
- `grep -n recordDiagnostic Sources` finds nothing.
- Manual (owner): `log stream --predicate 'subsystem == "com.tilak.maclink"'` shows capture and open lines.

**Tests.** None.

---

## 8. Not in 0.3

### 8.1 Deferred features

| Feature | Reason |
|---|---|
| Capture from Things, OmniFocus, DEVONthink, Apple Notes, Obsidian | Cannot be verified without those apps installed; their scripting differs per app. |
| Two-way links between items | Needs a product decision by the owner (it touches SPEC non-goals and the data model). |
| "Link to New" (create a note that links back) | Depends on two-way links and on a choice of target app. |
| PDF page deep links and selected-text links | Preview has no reliable page API; needs PDFKit work and a quoting scheme. |
| App Intents (Shortcuts actions) | SwiftPM executables do not produce the App Intents metadata; needs an Xcode project. |
| Share, Finder Sync and other app extensions | SwiftPM cannot build `.appex` targets; extensions also need the sandbox. |
| Sync across Macs | SPEC non-goal; SQLite in a synced folder corrupts. |
| https wrapper links for web apps | Needs a hosted redirect page; goes against local-first. |
| Opera, Orion, Dia, Helium, Firefox capture | AppleScript support not verified; add bundle IDs to `ChromiumCapturer` only after a manual check. |

### 8.2 Audit findings not included

| Finding | Reason |
|---|---|
| F8 launch crash when the database cannot open (`try!` in `LinkStore.shared`) | Medium change that touches every caller of `LinkStore.shared` across all tracks. Do after 0.3. (Lenient row decoding is in C5.) |
| F12 full JSON export and import | Not a bug in normal use; the SQLite file is the real backup. |
| F14 `MaclinkCore` library split | Touches imports in every file and would collide with all four tracks. C3 shares only the search SQL. |
| F16 release packaging, DMG, universal binary claim | Needs an owner decision on how releases are built. |
| F17 FTS5 search and search off the main thread | Measure first; no slowness reported at current sizes. |
| F19 rest: key glyph for function keys, un-archive UI, `maclink://search` and `show` routes, undo of rich clipboard content, stale comments in files no track touches | Small and independent; none blocks 0.3. |
| `FileResolver` ignores the `Bool` from `NSWorkspace.open` | The file was just checked to exist, so failure is rare; would need track B's new error case inside track C. |
| CLI `latest --org` title escaping | The CLI cannot use the app's `ClipboardFormatter` without the library split above. |
| The `if let repaired` write in `LinkService.open` | Unused for files after C2, but kept for the `Resolver` protocol (section 2.1 item 2). |
| Suspected S1 to S8 (NSAppleScript threads, AX timeouts, repeated AX prompt, bookmark UI on background thread, pasteboard off main, inode reuse, Mail subject error, URL-scheme capture trigger) | Not confirmed by the audit. |

---

## 9. Track table

| Track | Items | Complete file list | Estimated size |
|---|---|---|---|
| A: Build, CI, hotkey warning, docs | A1 Find Xcode or fail clearly; A2 GitHub Actions build and test; A3 Warn on hotkey registration failure; A4 Update README and SPEC docs | `Scripts/require-xcode.sh` (new), `Scripts/build-app.sh`, `Scripts/install-cli.sh`, `.github/workflows/ci.yml` (new), `Tests/maclinkTests/AutomationServiceTests.swift`, `Sources/maclink/App/HotkeyService.swift`, `README.md`, `SPEC.md` | S to M: about 150 lines (half docs) |
| B: Capture and reopen | B1 Surface capture errors, no fallback; B2 Normalize web URLs before storage; B3 Chromium browser capture and reopen; B4 Report failed opens, fix warning | `Sources/maclink/Core/CaptureEngine.swift`, `Sources/maclink/Core/URLNormalizer.swift` (new), `Sources/maclink/Capture/Capturer.swift`, `Sources/maclink/Capture/SafariCapturer.swift`, `Sources/maclink/Capture/ChromiumCapturer.swift` (new), `Sources/maclink/Capture/MailCapturer.swift` (comment only), `Sources/maclink/Resolve/Resolver.swift`, `Sources/maclink/Resolve/MailResolver.swift`, `Sources/maclink/Resolve/URLResolver.swift`, `Sources/maclink/Resolve/GenericResolver.swift`, `Tests/maclinkTests/SafariCapturerTests.swift` (delete), `Tests/maclinkTests/URLNormalizerTests.swift` (new), `Tests/maclinkTests/ChromiumCapturerTests.swift` (new), `Tests/maclinkTests/CaptureEngineTests.swift` (new) | M: about 350 lines (half tests) |
| C: Store, search, file repair, CLI | C1 Spotlight query on main actor; C2 Narrow repair write, capped picker; C3 Search values, share search SQL; C4 Recent ordered by last capture; C5 Skip undecodable rows, keep lists; C6 CLI get archived, limit check | `Package.swift`, `Sources/MaclinkShared/SearchSQL.swift` (new), `Sources/maclink/Store/LinkStore.swift`, `Sources/maclink/Store/Migrations.swift`, `Sources/maclink/Models/Payload.swift`, `Sources/maclink/Models/LinkRecord.swift`, `Sources/maclink/Resolve/FileRelinker.swift`, `Sources/maclink/Resolve/FileResolver.swift`, `Sources/maclink-cli/main.swift`, `raycast-extension/src/db.ts`, `Tests/maclinkTests/LinkStoreTests.swift`, `Tests/maclinkTests/SearchSQLTests.swift` (new), `Tests/maclinkTests/FileRepairTests.swift` (new) | L: about 450 lines (40% tests) |
| D: Clipboard, toast, Finder service | D1 One escaping clipboard formatter everywhere; D2 More copy actions in dropdown; D3 Toast adds tags, shows existing; D4 Edit title in toast first; D5 Finder Services Copy maclink item; D6 Clearer script and open errors; D7 Replace diagnostic log with OSLog | `Sources/maclink/Core/ClipboardFormatter.swift` (new), `Sources/maclink/Core/LinkService.swift`, `Sources/maclink/UI/SearchPanelView.swift`, `Sources/maclink/App/StatusItemController.swift`, `Sources/maclink/UI/CaptureToastController.swift`, `Sources/maclink/UI/CaptureToastView.swift`, `Sources/maclink/App/ServicesProvider.swift` (new), `Sources/maclink/App/AppDelegate.swift`, `Sources/maclink/Capture/FinderCapturer.swift`, `Sources/maclink/Models/ResourceType.swift`, `Resources/Info.plist`, `Tests/maclinkTests/ClipboardFormatterTests.swift` (new), `Tests/maclinkTests/CaptureToastTests.swift` (new) | L: about 500 lines (30% tests) |
