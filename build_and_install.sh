#!/bin/bash
# Build both apps (Release) and install the manager to /Applications.
# Fails loudly with the real error if a build breaks, and shows progress so it
# never looks like it "closed in the middle."

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PRODUCTS="build/Build/Products/Release"
LOG_DIR="$SCRIPT_DIR/build-logs"
mkdir -p "$LOG_DIR"

# Build one scheme. Streams concise phase/error lines to the console, tees the full
# output to a log, and stops the whole script with the real error if xcodebuild fails.
build() {
    local name="$1" dir="$2"; shift 2
    local log="$LOG_DIR/$name.log"

    echo ""
    echo "=== Building $name (Release) ==="
    echo "    full log: $log"

    # Show compile phases + any errors/warnings as they happen; keep the full log on disk.
    # PIPESTATUS[0] is xcodebuild's real exit code (grep would otherwise mask it).
    ( cd "$dir" && xcodebuild "$@" ) 2>&1 \
        | tee "$log" \
        | grep -E '^(=== |CompileSwift|Compiling|Linking|CodeSign|\*\* )|error:|warning: ' \
        || true
    local rc=${PIPESTATUS[0]}

    if [ "$rc" -ne 0 ]; then
        echo ""
        echo "✗ $name build FAILED (xcodebuild exit $rc). Last 30 lines of the log:"
        echo "------------------------------------------------------------------"
        tail -30 "$log"
        echo "------------------------------------------------------------------"
        exit "$rc"
    fi
    echo "✓ $name build OK"
}

# Build the runtime first (the manager embeds it), then the manager.
build ServerAppBundle    "$SCRIPT_DIR/ServerAppBundle"    -scheme ServerAppBundle    -configuration Release -derivedDataPath build clean build
build LocalServerWrapper "$SCRIPT_DIR/LocalServerWrapper" -scheme LocalServerWrapper -configuration Release -derivedDataPath build build

WRAPPER_APP="$SCRIPT_DIR/LocalServerWrapper/$PRODUCTS/LocalServerWrapper.app"
SERVER_APP="$SCRIPT_DIR/ServerAppBundle/$PRODUCTS/ServerAppBundle.app"
SERVER_FW="$SCRIPT_DIR/ServerAppBundle/$PRODUCTS/ServerRuntime.framework"

# Verify all products exist before touching /Applications.
for product in "$WRAPPER_APP" "$SERVER_APP" "$SERVER_FW"; do
    if [ ! -d "$product" ]; then
        echo "✗ Expected build product missing: $product"
        echo "  (the build reported success but the product isn't where we expect it)"
        exit 1
    fi
done

# Make the installed copy self-contained, exactly like a released build: inject
# the Sparkle feed keys, embed the runtime products into the app (so
# ProductLocator finds them without dev build folders), then ad-hoc re-sign so
# the changes are sealed.
echo ""
echo "=== Preparing app (Sparkle keys + embedded runtime, distribution parity) ==="
ENTITLEMENTS="$SCRIPT_DIR/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper.entitlements"
"$SCRIPT_DIR/inject-sparkle-keys.sh" "$WRAPPER_APP"
"$SCRIPT_DIR/embed-runtime.sh" "$WRAPPER_APP" "$SCRIPT_DIR/ServerAppBundle/$PRODUCTS"
codesign --sign - --force --options runtime --entitlements "$ENTITLEMENTS" "$WRAPPER_APP"
codesign --verify --verbose "$WRAPPER_APP"
echo "✓ App prepared"

echo ""
echo "=== Installing to /Applications ==="

if [ -d "/Applications/LocalServerWrapper.app" ]; then
    echo "Removing old LocalServerWrapper.app..."
    rm -rf "/Applications/LocalServerWrapper.app"
fi

if ! cp -R "$WRAPPER_APP" "/Applications/LocalServerWrapper.app"; then
    echo "✗ Failed to copy to /Applications (permissions?). Try: sudo ./build_and_install.sh"
    exit 1
fi

echo "✓ Installed to /Applications/LocalServerWrapper.app"

# Keep the shared runtime updated for legacy thin launchers. Newly generated launchers embed it.
echo ""
echo "=== Installing shared ServerRuntime.framework to ~/Library/Frameworks ==="
mkdir -p "$HOME/Library/Frameworks"
rm -rf "$HOME/Library/Frameworks/ServerRuntime.framework"
if cp -R "$SERVER_FW" "$HOME/Library/Frameworks/"; then
    echo "✓ Installed compatibility runtime for legacy launchers"
else
    echo "✗ Failed to install ServerRuntime.framework to ~/Library/Frameworks"
    exit 1
fi
echo ""
echo "Launch: open /Applications/LocalServerWrapper.app"
