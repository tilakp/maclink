# maclink

A local-first macOS menu-bar utility that turns whatever you're looking at into a durable, pasteable deep link. A file selected in Finder. An email open in Mail. The current tab in Safari.

Press a hotkey. maclink figures out what's active in the frontmost app, records it with metadata in a local database, and puts a `maclink://` URL on your clipboard. Paste that link into an org-mode file, a note, a chat message, anywhere. Click it later and you're back at that exact resource.

It's a personal, stripped-down alternative to [Hookmark](https://hookproductivity.com/), built specifically so its primary inbox for links can be Emacs org-mode.

See [`SPEC.md`](./SPEC.md) for the full product and technical spec this was built from.

## Status

The MVP capture/resolve pipeline is complete and verified live against real Finder, Mail, Safari, and arbitrary other apps. Still to come: a signed and notarized release build. See the build-order checklist in `SPEC.md` §12-13 for exact scope.

## What works today

- **Global hotkeys**, fully configurable in Settings (default `⌃⌥⌘L` to capture, `⌃⌥⌘K` to search)
- **Capture**: Finder (selection or front window), Mail.app (selected message), Safari (current tab), and a generic Accessibility-based fallback for everything else. Bonus: any document-based app (TextEdit, Preview, Pages, Xcode, and more) gets a full file link for free via `kAXDocumentAttribute`.
- **Resolve**: opening a `maclink://open/<uuid>` URL brings you back to the exact file (bookmark-based, survives renames and moves), email (via the `message:` URL scheme), web page, or reactivates the source app
- **Search dropdown**: the search hotkey opens a menu-bar-anchored search box over everything you've captured
- **Capture toast**: a quick confirmation with inline tagging and an undo action
- **Settings window**: clipboard format, launch at login, hotkey rebinding (including turning a hotkey off entirely), a permissions health check, and database tools (reveal in Finder, export as JSON)
- **Local SQLite database**: plain, queryable `~/Library/Application Support/com.tilak.maclink/maclink.sqlite`. No cloud, no account.
- **Dedupe**: recapturing the same file, email, or URL reuses the existing link instead of creating a duplicate
- **Emacs integration**: works with zero configuration, described below

## Building and running

Requires Xcode (for the Swift toolchain) on macOS 14 or later.

```sh
swift build
Scripts/build-app.sh debug   # assembles build/maclink.app and re-registers it with Launch Services
open build/maclink.app
```

The app is `LSUIElement` (no Dock icon) and lives in your menu bar. First use of each integration (Finder, Mail, Safari, Accessibility) prompts for the relevant macOS permission. That's expected.

Run the test suite with `swift test`.

### Distribution note

This is built as an ad-hoc-signed, non-sandboxed app for personal use. App Sandbox would break Apple Events and Accessibility access, which the whole app depends on. See `SPEC.md` §3.4. There's no App Store build and none is planned.

## Using it from Emacs

This is the reason the project exists. A `maclink://` link needs no Emacs package to be openable: org-mode's link opener falls through to `browse-url` for unrecognized schemes, and on macOS that shells out to `/usr/bin/open`, which Launch Services routes straight to maclink.

1. Capture something. The link is now on your clipboard.
2. Paste it into an org buffer, plain or bracketed: `maclink://open/<uuid>` or `[[maclink://open/<uuid>][a description]]`.
3. Put point on it and run `C-c C-o` (`org-open-at-point`). The original file, email, or page opens.

If your Emacs config overrides `browse-url-browser-function` to something that doesn't know about arbitrary URL schemes, such as `eww`, add:

```elisp
(setq browse-url-handlers
      (append '(("\\`maclink://" . browse-url-default-macosx-browser))
              browse-url-handlers))
```

`contrib/maclink.el` adds two optional pieces of sugar, neither required for links to open:

- `maclink-insert-from-clipboard`: inserts the link just captured as a proper org link
- A real `maclink` org link type for nicer display, completion, and export, with completion querying the database directly through the `sqlite3` CLI

See `SPEC.md` §10 for the full design.

## Architecture, briefly

A global hotkey (Carbon `RegisterEventHotKey`, no Accessibility permission needed) triggers `CaptureEngine`, which picks a per-app `Capturer` (Finder, Mail, Safari, or the generic AX fallback). Each capturer runs an `NSAppleScript` through `AutomationService`, a single serial queue that keeps every script call off the main thread and bounded by a timeout, since `NSAppleScript` isn't thread-safe and a hung target app shouldn't hang maclink.

The captured resource becomes a `LinkRecord` in `LinkStore` (GRDB/SQLite), keyed by a UUID that's also the `maclink://open/<uuid>` URL. The scheme is registered via `CFBundleURLTypes` and handled through `NSAppleEventManager`. Opening that URL routes through `ResolveEngine` to the matching `Resolver`, which brings you back to the resource and repairs anything that moved, file bookmarks in particular.

Full detail in `SPEC.md`.

## License

Personal project, no license file yet. Treat as all rights reserved until one is added.
