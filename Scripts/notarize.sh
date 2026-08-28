#!/bin/bash
# Documents (does not automate) the steps to sign, notarize, and staple a
# real release build once you have a paid Apple Developer account. This is
# deliberately not wired into the normal build loop: it needs credentials
# nobody but you has, and running it against the wrong identity would
# produce a build that silently fails to launch for anyone else. Copy
# these commands into your shell one at a time rather than running this
# file directly, so you can fix any environment-specific detail as you go
# (identity name, notarytool profile name, and so on).
set -euo pipefail
echo "This script documents the notarization process. Read it, don't run it blindly." >&2
exit 1

# 1. One-time setup: create a keychain profile holding an app-specific
#    password (or API key) for notarytool, so it isn't typed every time.
#    See: https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution
xcrun notarytool store-credentials "maclink-notary" \
    --apple-id "you@example.com" \
    --team-id "YOUR_TEAM_ID" \
    --password "an-app-specific-password"

# 2. Build and sign with your real Developer ID Application identity
#    instead of ad-hoc (find it with: security find-identity -v -p codesigning).
#    Note this deliberately does not reuse Scripts/build-app.sh's "hardened"
#    codesign call, since that one signs ad-hoc for local testing --
#    swap "-" for your identity string here.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/build/maclink.app"
swift build --package-path "$ROOT" -c release
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT/.build/release/maclink" "$APP_DIR/Contents/MacOS/maclink"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"
codesign --force --sign "Developer ID Application: Your Name (YOUR_TEAM_ID)" \
    --options runtime \
    --entitlements "$ROOT/Resources/maclink.entitlements" \
    --identifier com.tilak.maclink \
    --timestamp \
    "$APP_DIR"

# 3. Zip it (notarytool wants a zip, dmg, or pkg, not a bare .app) and submit.
ditto -c -k --keepParent "$APP_DIR" "$ROOT/build/maclink.zip"
xcrun notarytool submit "$ROOT/build/maclink.zip" --keychain-profile "maclink-notary" --wait

# 4. Staple the notarization ticket to the app so it works offline too,
#    then verify.
xcrun stapler staple "$APP_DIR"
spctl --assess --type execute --verbose "$APP_DIR"
