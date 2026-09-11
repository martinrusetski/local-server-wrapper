#!/bin/bash
# Configure this app's release credentials without printing private key material.
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO=martinrusetski/local-server-wrapper
TAP=martinrusetski/homebrew-tap
TOOLS="${SPARKLE_BIN_DIR:-${LSW_BUILD_ROOT:-$ROOT/.build/distribution}/manager/SourcePackages/artifacts/sparkle/Sparkle/bin}"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
PUBLIC_KEY="$("$TOOLS/generate_keys" --account local-server-wrapper -p)"
test "$PUBLIC_KEY" = "$(tr -d '[:space:]' < "$ROOT/Resources/sparkle_public_key.txt")" || { echo 'Sparkle key does not match'; exit 1; }
"$TOOLS/generate_keys" --account local-server-wrapper -x "$TEMP/sparkle-key" >/dev/null
gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO" < "$TEMP/sparkle-key"
SECRETS="$(gh secret list --repo "$REPO" --json name --jq '.[].name')"
if ! printf '%s\n' "$SECRETS" | grep -qx HOMEBREW_TAP_DEPLOY_KEY; then
    ssh-keygen -q -t ed25519 -N '' -C 'local-server-wrapper release' -f "$TEMP/tap-key"
    gh repo deploy-key add "$TEMP/tap-key.pub" --repo "$TAP" --allow-write --title 'Local Server Wrapper releases'
    gh secret set HOMEBREW_TAP_DEPLOY_KEY --repo "$REPO" < "$TEMP/tap-key"
fi
echo 'Release secrets configured. No release has been published.'
