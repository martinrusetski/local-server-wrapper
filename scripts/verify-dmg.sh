#!/bin/bash
# Verify the app inside the disk image, including on a release retry.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:?Pass a DMG}"
MOUNT="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    rmdir "$MOUNT" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach "$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT" >/dev/null
"$ROOT/scripts/verify-app.sh" "$MOUNT/LocalServerWrapper.app" "${2:-}" "${3:-}"
test -L "$MOUNT/Applications"
test -f "$MOUNT/README.txt"
echo 'Mounted DMG contents verified.'
