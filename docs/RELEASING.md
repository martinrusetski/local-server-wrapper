# Releasing Local Server Wrapper

This project ships as a downloadable `.dmg` and a Homebrew cask, and updates itself in place using [Sparkle](https://sparkle-project.org). Cutting a release is a single tagged push — GitHub Actions does the rest.

## One-time setup

### 1. Add the Sparkle signing key as a GitHub secret

Every update is signed with a private EdDSA key so the app can verify a download really came from you before installing it. The matching public key is baked into the app (`Info.plist` → `SUPublicEDKey`) and lives in `Resources/sparkle_public_key.txt`. The **private** key must never be committed — it goes into a GitHub Actions secret.

1. Open `https://github.com/martinrusetski/local-server-wrapper/settings/secrets/actions`.
2. Click **New repository secret**.
3. Name: `SPARKLE_PRIVATE_KEY`
4. Value: the private key string (44 characters, ends with `=`). Ask Claude for it, or export it yourself with the Sparkle tools: `generate_keys --account local-server-wrapper -x key.txt`.
5. Click **Add secret**.

Without this secret the release build still runs, but signing the update fails, so leaving it unset will break the release job.

### 2. (Optional) The Homebrew tap

Users can install with Homebrew straight from this repo:

```
brew tap martinrusetski/lsw https://github.com/martinrusetski/local-server-wrapper
brew install --cask local-server-wrapper
```

The cask lives at `Casks/local-server-wrapper.rb` and is updated automatically on every release.

## Cutting a release

1. Decide the new version number, e.g. `0.1.0`. Versions use [semver](https://semver.org): bump the last number for fixes, the middle for features.
2. Create an annotated tag whose message becomes the release notes, and push it:

   ```
   git tag -a v0.1.0 -m "First public release"
   git push origin v0.1.0
   ```

   The tag **must** start with `v`. That is what triggers the release workflow.

3. Watch the run at `https://github.com/martinrusetski/local-server-wrapper/actions`. When it finishes it will have:
   - built both Xcode projects (the manager and the shared runtime),
   - packaged and ad-hoc-signed `LocalServerWrapper-v0.1.0.dmg`,
   - signed the update and added it to `appcast.xml` (so existing installs auto-update),
   - updated `Casks/local-server-wrapper.rb`,
   - committed those two files back to `main`,
   - created the GitHub Release with the DMG attached.

That's it. Existing users get the update automatically the next time the app checks; new users download the DMG or `brew install`.

## Testing the build locally before tagging

`./make-dmg.sh` runs the exact same sequence CI does and drops a `LocalServerWrapper.dmg` in the repo root, without touching `/Applications`, `~/Library/Frameworks`, or the appcast. Use it to confirm a build is good before you tag.

## Why the app isn't notarized (and what users see)

Releases are **ad-hoc signed**, not signed with an Apple Developer ID and notarized. That keeps releases free and CI simple, but macOS blocks an ad-hoc app on first launch. The DMG's `README.txt` and the Homebrew cask both handle this: the cask clears the quarantine flag automatically, and DMG users run `xattr -cr /Applications/LocalServerWrapper.app` once. After the first launch, Sparkle updates install silently — users never repeat the step.

If you later enroll in notarization, the switch is: sign with your Developer ID instead of `-`, add a notarization step to `release.yml`, and drop the `xattr` note.

## How the pieces fit together

| File | Role |
| --- | --- |
| `.github/workflows/release.yml` | The whole release pipeline, triggered by a `v*` tag. |
| `inject-sparkle-keys.sh` | Writes `SUFeedURL` + `SUPublicEDKey` into the built app's `Info.plist`. |
| `embed-runtime.sh` | Copies `ServerRuntime.framework` + `ServerAppBundle.app` into the manager so a fresh install can install the shared runtime and generate server apps. |
| `update-appcast.sh` | Signs a DMG and prepends a new entry to `appcast.xml`. |
| `make-dmg.sh` | Local dry run of the whole build + package sequence. |
| `appcast.xml` | The Sparkle update feed the installed app polls. |
| `Casks/local-server-wrapper.rb` | The Homebrew cask. |
| `Resources/sparkle_public_key.txt` | The public half of the update-signing key. |
