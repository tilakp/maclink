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
