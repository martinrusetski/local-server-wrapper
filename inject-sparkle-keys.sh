#!/bin/bash
# Writes the Sparkle update-feed keys into a built app's Info.plist.
#
# GENERATE_INFOPLIST_FILE=YES produces the Info.plist during the Xcode build, and
# Xcode's user-script sandbox blocks mutating it from an in-project build phase.
# So every packaging path (CI, make-dmg.sh, build_and_install.sh) calls this
# right BEFORE code-signing instead — the keys land in the signed seal.
#
# SUPublicEDKey is read from Resources/sparkle_public_key.txt (single source of
# truth, shared with the Info.plist public key and CI).
#
# Usage: ./inject-sparkle-keys.sh <path/to/App.app>
set -euo pipefail

APP="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$APP/Contents/Info.plist"
FEED_URL="https://raw.githubusercontent.com/martinrusetski/local-server-wrapper/main/appcast.xml"
PUB_KEY="$(tr -d '[:space:]' < "$SCRIPT_DIR/Resources/sparkle_public_key.txt")"

if [ ! -f "$PLIST" ]; then
    echo "inject-sparkle-keys: Info.plist not found at $PLIST" >&2
    exit 1
fi
if [ -z "$PUB_KEY" ]; then
    echo "inject-sparkle-keys: Resources/sparkle_public_key.txt is empty" >&2
    exit 1
fi

set_key() {
    /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PLIST" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"
}

set_key SUFeedURL "$FEED_URL"
set_key SUPublicEDKey "$PUB_KEY"

echo "Injected Sparkle keys into $PLIST"
echo "  SUFeedURL     = $FEED_URL"
echo "  SUPublicEDKey = $PUB_KEY"
