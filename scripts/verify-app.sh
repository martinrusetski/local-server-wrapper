#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?Pass the assembled manager app}"
for bundle in "$APP" "$APP/Contents/Resources/ServerAppBundle.app" \
    "$APP/Contents/Resources/ServerAppBundle.app/Contents/Frameworks/ServerRuntime.framework" \
    "$APP/Contents/Resources/ServerRuntime.framework"; do
    codesign --verify --deep --strict --verbose=2 "$bundle"
done
for binary in "$APP/Contents/MacOS/LocalServerWrapper" \
    "$APP/Contents/Resources/ServerAppBundle.app/Contents/MacOS/ServerAppBundle" \
    "$APP/Contents/Resources/ServerAppBundle.app/Contents/Frameworks/ServerRuntime.framework/ServerRuntime"; do
    lipo -archs "$binary" | python3 -c 'import sys; assert {"arm64", "x86_64"}.issubset(sys.stdin.read().split()), "Missing architecture"'
    if otool -l "$binary" | grep -E '^[[:space:]]+(name|path) ' | grep -E '/Users/|DerivedData|/Build/Products/' >/dev/null; then
        echo "Build-machine dependency in $binary" >&2; exit 1
    fi
done
python3 - "$ROOT" "$APP" "${2:-}" "${3:-}" <<'PY'
import base64, pathlib, plistlib, sys
root, app = map(pathlib.Path, sys.argv[1:3])
with (app / 'Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
key = (root / 'Resources/sparkle_public_key.txt').read_text().strip()
assert len(base64.b64decode(key, validate=True)) == 32
assert info['SUPublicEDKey'] == key
assert info['SUFeedURL'] == 'https://raw.githubusercontent.com/martinrusetski/local-server-wrapper/main/appcast.xml'
assert info['LSMinimumSystemVersion'] == '13.5'
if sys.argv[3]: assert info['CFBundleShortVersionString'] == sys.argv[3]
if sys.argv[4]: assert info['CFBundleVersion'] == sys.argv[4]
for resource in ['DefaultAppIcon.icns', 'LICENSE.txt', 'Sparkle-LICENSE.txt', 'THIRD_PARTY_NOTICES.md']:
    assert (app / 'Contents/Resources' / resource).is_file(), resource
sparkle = app / 'Contents/Frameworks/Sparkle.framework/Versions/B'
assert (sparkle / 'Updater.app').is_dir()
assert (sparkle / 'Autoupdate').is_file()
print('App signatures, architectures, resources, versions, and Sparkle configuration verified.')
PY
