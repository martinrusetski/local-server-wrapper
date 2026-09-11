#!/bin/bash
# Sign and independently verify a DMG before adding it to the update feed.
set -euo pipefail
[[ $# == 4 ]] || { echo "usage: $0 <version> <build-number> <dmg> <download-url>" >&2; exit 1; }
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$1"
BUILD_NUMBER="$2"
DMG="$3"
URL="$4"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || exit 1
EXPECTED_URL="https://github.com/martinrusetski/local-server-wrapper/releases/download/v${VERSION}/LocalServerWrapper-v${VERSION}.dmg"
[[ "$URL" == "$EXPECTED_URL" ]] || { echo "Unexpected release URL" >&2; exit 1; }
SPARKLE_BIN_DIR="${SPARKLE_BIN_DIR:-${LSW_BUILD_ROOT:-$ROOT/.build/distribution}/manager/SourcePackages/artifacts/sparkle/Sparkle/bin}"
SIGN_UPDATE="$SPARKLE_BIN_DIR/sign_update"
test -x "$SIGN_UPDATE"
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
    SIGNATURE="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGN_UPDATE" --ed-key-file - -p "$DMG")"
else
    SIGNATURE="$("$SIGN_UPDATE" --account local-server-wrapper -p "$DMG")"
fi
swift "$ROOT/scripts/verify-update.swift" "$ROOT/Resources/sparkle_public_key.txt" "$DMG" "$SIGNATURE"
python3 "$ROOT/scripts/update-appcast.py" "${APPCAST_PATH:-$ROOT/appcast.xml}" "$VERSION" "$BUILD_NUMBER" "$DMG" "$URL" "$SIGNATURE"
