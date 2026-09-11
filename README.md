# Local Server Wrapper

Turn a local web server into a standalone Mac app. Open the app to start its server and use its web interface in a dedicated window. Quit it to stop the server.

Useful for tools you normally launch in Terminal and open at `localhost`, such as development servers, notebooks, and self-hosted utilities. Each generated app gets its own icon, browser storage, and saved logins.

The first public release is being prepared. The installation links and commands below become available when it is published.

## Requirements

- macOS 13.5 or later, on Apple Silicon or Intel.
- The server software and its dependencies must already be installed. Local Server Wrapper does not install Node, Python, or the tools you want to wrap.

## Install

### Homebrew

```sh
brew tap martinrusetski/tap
brew trust martinrusetski/tap
brew install --cask martinrusetski/tap/local-server-wrapper
```

### Download

Download the latest DMG from [Releases](https://github.com/martinrusetski/local-server-wrapper/releases/latest), open it, and drag `LocalServerWrapper.app` into Applications.

The app is ad-hoc signed and is not notarized by Apple. If macOS blocks the first launch, open **System Settings > Privacy & Security > Open Anyway**. Alternatively, remove the quarantine flag in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/LocalServerWrapper.app
```

The Homebrew cask handles this step during installation.

## Create an app

1. Open Local Server Wrapper and click **New App…**.
2. Give it a name and enter the shell command you normally use to start the server. Multi-line scripts are supported.
3. Choose **Run in folder** if the command needs to run inside a particular project. You can also select a script file and a custom icon.
4. Leave **Server** blank to detect its URL and port automatically, or enter a fixed URL. A fixed URL waits for an HTTP response before opening.
5. Use **Test Launch** to check the command, then save the setup.
6. Click **Generate App**, choose where to save it, and open the resulting `.app`.

For an npm project, for example, enter `npm run dev` and select the project folder under **Run in folder**. The app uses a non-interactive shell environment. Tools configured only in your interactive shell, such as an nvm installation, may need their setup commands included in the script or an explicit executable path.

Editing and saving a setup updates its last generated copy in place if that copy is still at the saved location. Renaming a setup does not rename that exported file. Deleting a setup removes its internal cached app; exported copies remain on disk and can still use their embedded configuration.

## Using a generated app

- Opening it starts the server and loads its web interface when readiness is detected.
- The terminal sidebar shows output and lets you send input. It is available with **⌘⇧T**.
- Login credentials can be saved in macOS Keychain. They are separated by generated app and matched to the page's exact origin.
- Browser requests made through intercepted `open` commands are redirected into the app window.
- Quitting stops the launched process tree. Commands that intentionally detach into background services should be run in their foreground mode instead.

| Shortcut | Action |
| --- | --- |
| ⌘R | Restart server |
| ⌘⇧R | Reload page |
| ⌘[ / ⌘] | Back / forward |
| ⌘⇧T | Toggle terminal sidebar |
| ⌥⌘T | Toggle toolbar |

## Updates

Use **Local Server Wrapper > Check for Updates…** in the manager. Sparkle checks the project's update feed and verifies downloaded updates against the app's embedded signing key. Automatic checks follow the preference you choose in Sparkle's prompt.

Generated apps contain their own runtime. After updating the manager, use **Generate App** again for each setup to include the latest runtime fixes. Their existing configuration and app identity are retained.

## Data and troubleshooting

Setups and custom icons live in:

```text
~/Library/Application Support/LocalServerWrapper/
```

The previous configuration file is backed up under `Backups` before each save. If the manager cannot read your library, it blocks changes and offers to show its folder. Restore `configurations.json` from a backup or correct its permissions, then reopen the manager.

If startup fails, inspect the terminal output and check the command and working folder. **Advanced > Run without a terminal** is available for servers that behave incorrectly with a pseudo-terminal. If URL detection picks the wrong address, enter the intended URL explicitly.

The generated app runs your command with your account's permissions. Use commands and server software you trust.

## Build from source

Use Xcode 26.4 or later with its command-line tools selected:

```sh
./make-dmg.sh
```

This builds both architectures, embeds the runtime and Sparkle, verifies signatures and resources, and creates `dist/LocalServerWrapper-v0.1.0.dmg`. It does not install the app.

Run the unit-test suite with `./scripts/test.sh`. See [release maintenance](docs/RELEASING.md) for versioning, signing, and the shared Homebrew tap.

## License

[MIT](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for bundled software.
