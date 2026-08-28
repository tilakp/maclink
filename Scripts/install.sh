#!/bin/bash
# Builds maclink (ad-hoc, the verified signing path — see build-app.sh's
# "hardened" mode for the unverified alternative) and installs it into
# /Applications, quitting any running copy first so the copy doesn't fail
# with the app's own binary in use.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/maclink.app"

echo "==> building"
"$ROOT/Scripts/build-app.sh" debug adhoc

echo "==> quitting any running copy"
osascript -e 'tell application id "com.tilak.maclink" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -f "$DEST/Contents/MacOS/maclink" >/dev/null 2>&1 || true
pkill -f "$ROOT/build/maclink.app/Contents/MacOS/maclink" >/dev/null 2>&1 || true
sleep 1

echo "==> installing to $DEST"
rm -rf "$DEST"
cp -R "$ROOT/build/maclink.app" "$DEST"

echo "==> refreshing Launch Services registration"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST" >/dev/null 2>&1 || true

echo "==> installed: $DEST"
echo "    Launch it from Applications, Spotlight, or: open '$DEST'"
