# Release maintenance

Distribution follows TrueTone Manager: an ad-hoc signed DMG, Sparkle EdDSA signatures, and the shared [`martinrusetski/tap`](https://github.com/martinrusetski/homebrew-tap). The app supports macOS 13.5+, with universal Apple Silicon and Intel binaries.

## Repository setup

The repository must be public before its GitHub download URLs and raw Sparkle feed work for other users. Publishing is a separate step from preparing the build.

Required repository secrets:

- `SPARKLE_PRIVATE_KEY`: the existing Keychain key under account `local-server-wrapper`. It must match `Resources/sparkle_public_key.txt`.
- `HOMEBREW_TAP_DEPLOY_KEY`: an SSH key whose public half has write access as a deploy key on `martinrusetski/homebrew-tap`.

Use `scripts/setup-release-secrets.sh` after building once to configure these. It exports the existing Sparkle key into a private temporary directory, checks its public half, sends it to the repository's encrypted secret store, and removes the temporary files. It creates a dedicated tap deploy key only if that repository secret is absent. It does not reuse TrueTone Manager's private deploy key or change its setup.

GitHub Actions must be allowed to push `appcast.xml` to `main`. Branch rules must permit that bot update. The checkout's `Package.resolved` pins Sparkle; do not remove it or download signing tools from an unverified archive.

## Local verification

```sh
./scripts/test.sh
./make-dmg.sh
```

`VERSION` is the short app version. `make-dmg.sh` accepts optional version, numeric build number, and output path arguments. `LSW_BUILD_ROOT` selects an alternate build directory. The default output is under `dist`, which is ignored by Git. Local and CI packaging call the same script.

The verification checks both CPU architectures, bundle signatures, the embedded launcher and runtime, icons, licenses, minimum OS version, and Sparkle feed/public-key settings. The script also verifies the DMG container.

Test update signing without changing the committed feed:

```sh
cp appcast.xml /tmp/local-server-wrapper-appcast.xml
APPCAST_PATH=/tmp/local-server-wrapper-appcast.xml ./update-appcast.sh \
  0.1.0 1 dist/LocalServerWrapper-v0.1.0.dmg \
  https://github.com/martinrusetski/local-server-wrapper/releases/download/v0.1.0/LocalServerWrapper-v0.1.0.dmg
```

The signature is verified independently with CryptoKit using the public key from the app, before an item is written. The feed writer rejects reused build numbers with different metadata and refuses to publish an older build. Use a build number greater than existing feed entries when testing subsequent versions.

Before the first release, also test a fresh installation and a generated app outside the development checkout. A complete Sparkle replacement test needs an installed older build and an accessible newer signed update; signature validation alone does not prove that installation succeeds.

## Publish a release

1. Update `VERSION`, finish the changes, and commit them to `main`. Remove the first-release preparation notice from README when ready to publish.
2. Run the **Release** workflow manually to build a downloadable inspection artifact without publishing a release or changing the feed/tap.
3. After reviewing the artifact, create and push an annotated `v<version>` tag. Its complete message becomes the release notes. For example:

   ```sh
   git tag -a v0.1.0 -m "First public release"
   git push origin v0.1.0
   ```

The tagged workflow validates the version and secrets, runs the unit tests, builds the DMG, signs and verifies it, publishes the GitHub download, and only then updates the appcast and shared tap. `github.run_number` supplies the monotonically increasing Sparkle build number. Release jobs are serialized.

`Casks/local-server-wrapper.rb` is a reviewed template; its zero checksum is deliberately not installable. The workflow replaces it with the real DMG checksum in the shared tap after the archive is published. The public install command is:

```sh
brew install --cask martinrusetski/tap/local-server-wrapper
```

The cask uses [Homebrew's declarative `postflight_steps`](https://docs.brew.sh/Cask-Cookbook#stanza-flight_steps) and removes only the quarantine attribute. Homebrew accepts a major macOS version in `depends_on`, so the cask declares Ventura and states the 13.5 minimum in its caveat. The app and Sparkle feed enforce 13.5. The cask also declares the app's own updater.

If publication succeeds but a feed/tap push fails, rerun the job. It must reuse the already-published archive rather than replace bytes that installed Sparkle clients may already trust. Check the feed and tap commits as well as the release status.

## Updates to generated apps

Sparkle updates the manager. Generated apps are self-contained and do not run their own updater. Regeneration incorporates the manager's current runtime; the cache includes the manager version/build so an unchanged configuration cannot reuse a runtime from an older manager release.

## Signing limits

The app remains ad-hoc signed and unnotarized, matching TrueTone Manager. Sparkle's archive signature authenticates an update but does not provide Apple notarization. Keep the private key safe; do not replace the public key during an ordinary release.
