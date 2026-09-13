#!/bin/bash
# Builds and installs the `maclink` CLI (spec §10.3) to ~/.local/bin/maclink,
# where contrib/maclink.el's optional sugar expects to find it. Separate from
# install.sh, which installs the app itself.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$HOME/.local/bin/maclink"

echo "==> swift build -c release maclink-cli"
swift build --package-path "$ROOT" -c release --product maclink-cli

mkdir -p "$(dirname "$DEST")"
cp "$ROOT/.build/release/maclink-cli" "$DEST"

echo "==> installed: $DEST"
echo "    Make sure ~/.local/bin is on your PATH."
