#!/bin/bash
# Builds the maclink SwiftPM executable and assembles it into a real .app
# bundle so LSUIElement + CFBundleURLTypes actually register with Launch
# Services. (SwiftPM alone can't produce a bundle; Xcode isn't used here so
# the build stays fast and CLI-scriptable. See spec §3.1 discussion.)
#
# Usage: Scripts/build-app.sh [debug|release] [adhoc|hardened]
#
#   adhoc (default)   Ad-hoc signature, no hardened runtime. What every
#                      development session in this repo has actually run
#                      and been verified against.
#   hardened           Adds the hardened runtime and the Apple Events
#                      entitlement (maclink.entitlements), matching what a
#                      real Developer ID release build needs (spec §3.4).
#                      NOT verified live as of this script's introduction.
#                      Hardened runtime changes how Apple Events are
#                      authorized, so re-test Finder/Mail/Safari capture
#                      after building this way before trusting it.
set -euo pipefail

CONFIG="${1:-debug}"
SIGN_MODE="${2:-adhoc}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="maclink"
APP_DIR="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> swift build -c $CONFIG"
swift build --package-path "$ROOT" -c "$CONFIG"

BIN_PATH="$ROOT/.build/$CONFIG/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
    echo "error: built binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "==> assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BIN_PATH" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

case "$SIGN_MODE" in
    adhoc)
        echo "==> ad-hoc codesigning"
        codesign --force --sign - --identifier com.tilak.maclink "$APP_DIR"
        ;;
    hardened)
        echo "==> ad-hoc codesigning with hardened runtime + entitlements"
        codesign --force --sign - --options runtime \
            --entitlements "$ROOT/Resources/maclink.entitlements" \
            --identifier com.tilak.maclink "$APP_DIR"
        ;;
    *)
        echo "error: unknown sign mode '$SIGN_MODE' (expected adhoc or hardened)" >&2
        exit 1
        ;;
esac

echo "==> refreshing Launch Services registration"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true

echo "==> built: $APP_DIR ($SIGN_MODE)"
