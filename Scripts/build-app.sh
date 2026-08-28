#!/bin/bash
# Builds the maclink SwiftPM executable and assembles it into a real .app
# bundle so LSUIElement + CFBundleURLTypes actually register with Launch
# Services. (SwiftPM alone can't produce a bundle; Xcode isn't used here so
# the build stays fast and CLI-scriptable — see spec §3.1 discussion.)
set -euo pipefail

CONFIG="${1:-debug}"
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

echo "==> ad-hoc codesigning"
codesign --force --sign - --identifier com.tilak.maclink "$APP_DIR"

echo "==> refreshing Launch Services registration"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true

echo "==> built: $APP_DIR"
