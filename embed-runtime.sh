#!/bin/bash
# Copies the two ServerAppBundle build products the manager needs at runtime —
# the thin launcher template (ServerAppBundle.app) and the shared
# ServerRuntime.framework — into the manager app's Contents/Resources.
#
# This is what makes a *distributed* copy of the manager self-contained:
# ProductLocator's first search case looks for these inside the app bundle, so a
# fresh install can install the shared runtime to ~/Library/Frameworks and stamp
# out generated server bundles without any dev build folders present.
#
# The caller MUST code-sign the manager app AFTER this runs — adding files to
# Contents/Resources invalidates the app's existing signature seal.
#
# Usage: ./embed-runtime.sh <path/to/Manager.app> <path/to/ServerAppBundle/Products/Release>
set -euo pipefail

APP="$1"
PRODUCTS_DIR="$2"

if [ ! -d "$APP" ]; then
    echo "embed-runtime: manager app not found: $APP" >&2
    exit 1
fi

LAUNCHER="$PRODUCTS_DIR/ServerAppBundle.app"
FRAMEWORK="$PRODUCTS_DIR/ServerRuntime.framework"

for product in "$LAUNCHER" "$FRAMEWORK"; do
    if [ ! -d "$product" ]; then
        echo "embed-runtime: expected build product missing: $product" >&2
        echo "  (build the ServerAppBundle scheme in Release first)" >&2
        exit 1
    fi
done

RES="$APP/Contents/Resources"
mkdir -p "$RES"

echo "Embedding ServerAppBundle.app + ServerRuntime.framework into $RES"
rm -rf "$RES/ServerAppBundle.app" "$RES/ServerRuntime.framework"
# ditto preserves each product's own code signature and internal symlinks.
ditto "$LAUNCHER" "$RES/ServerAppBundle.app"
ditto "$FRAMEWORK" "$RES/ServerRuntime.framework"

echo "Embedded. Remember to re-sign $APP after this."
