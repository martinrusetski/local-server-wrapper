# ServerAppBundle Sandbox Configuration

## Overview

The ServerAppBundle runtime is intentionally **NOT** sandboxed. This is a deliberate design decision, not an oversight: the whole purpose of the runtime is to launch an arbitrary user-configured process (e.g. `npm run dev`, `python3 -m http.server`) from a path the user chooses. The macOS App Sandbox forbids spawning arbitrary executables outside the app container, so enabling it would break the app's core function.

This document used to claim the runtime was sandboxed. That was incorrect — it never matched the entitlements file — and has been corrected here.

## Actual entitlements

The entitlements file (`ServerAppBundle/ServerAppBundle.entitlements`) disables the sandbox:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
</dict>
</plist>
```

`com.apple.security.app-sandbox = false` means the generated app runs with the same file-system and process-spawning capabilities as the launching user. There is no per-app container under `~/Library/Containers/`.

## Why not sandboxed

- **Arbitrary process launch.** The runtime runs whatever command/script the configuration specifies, from the user's chosen working directory. A sandboxed app cannot `posix_spawn`/`Process.run` executables outside its container, so a sandbox would make the app unable to start dev servers — its only job.
- **PATH-based tool resolution.** The runtime resolves commands like `npm`/`node`/`python3` from Homebrew and system paths and runs them with the user's environment. This requires unrestricted execution.

## Security posture without a sandbox

Because there is no OS sandbox boundary, security is handled at the application level instead:

- Credentials are stored in the Keychain, with an encrypted UserDefaults fallback keyed by a per-install random key held in the Keychain (never a key derivable from the public bundle identifier).
- The embedded `WKWebView` does **not** relax same-origin protections (no `allowUniversalAccessFromFileURLs` / `allowFileAccessFromFileURLs`), and Web Inspector is enabled only in Debug builds.
- Credential autofill is bound to the page **origin** (scheme + host + port), not just the URL path.

## Distribution note

Because the app is not sandboxed, it is **not** eligible for the Mac App Store. It is intended for direct distribution (ad-hoc signed). Generated bundles are ad-hoc signed via `codesign --force --sign -` so the Keychain item ACL is stable across launches.
