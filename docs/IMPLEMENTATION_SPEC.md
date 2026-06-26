# Implementation Spec — Bug Fixes, Security, Cleanup

> **For the implementing agent.** Read this whole file before editing. It is self-contained:
> it describes the architecture, the build/verify steps, and each task with enough mechanism
> that you can fix the root cause rather than the symptom. When done, report back what you
> changed and what you skipped (see "Reporting back"). This work will be code-reviewed against
> the acceptance criteria below.

---

## 1. Context

This repo contains **two separate Xcode projects** that work as a pair:

1. **LocalServerWrapper** (Configuration Manager)
   - Path: `LocalServerWrapper/LocalServerWrapper.xcodeproj`
   - Source root: `LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/` (yes, triple-nested)
   - SwiftUI/MVVM app to CRUD "server configurations" and generate standalone `.app` bundles.
   - Key file: `Services/AppBundleGenerator.swift` — copies a prebuilt `ServerAppBundle.app`,
     injects `configuration.json` + Info.plist + icon, then ad-hoc signs.

2. **ServerAppBundle** (the runtime embedded in every generated bundle)
   - Path: `ServerAppBundle/ServerAppBundle.xcodeproj`
   - Source root: `ServerAppBundle/ServerAppBundle/`
   - Launches the configured process, streams stdout/stderr into a terminal view, watches
     output for a "ready" signal + port, then swaps to a `WKWebView` at the localhost URL.
   - Adds credential save/autofill, system-browser interception, and stdin auto-answering.

### ⚠️ The duplicated-file trap (read this twice)

These files exist as **two physical copies**, one per project, and have already drifted:

| File | Copy A (runtime) | Copy B (manager) |
|------|------------------|------------------|
| `ServerConfiguration.swift` | `ServerAppBundle/ServerAppBundle/ServerConfiguration.swift` | `LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/Models/ServerConfiguration.swift` |
| `ScriptResolver.swift` | `ServerAppBundle/ServerAppBundle/ScriptResolver.swift` | `LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/Utilities/ScriptResolver.swift` |

The manager's `ServerConfiguration` is `Hashable`; the runtime's is not — they are NOT identical.
**Any change to these models or to script resolution must be applied to both copies** (or
consolidated per Task 5) or the embedded `configuration.json` will silently mismatch at runtime.

### Anchors, not line numbers

This spec references **symbols** (`ProcessManager.start`, `KeychainManager.encrypt`, etc.),
not line numbers, because line numbers will shift as you edit. Locate by symbol.

### Build & run

```bash
# Build the runtime first (the manager embeds it), then the manager:
cd ServerAppBundle && xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
cd ../LocalServerWrapper && xcodebuild -scheme LocalServerWrapper -configuration Release -derivedDataPath build build

# Convenience scripts at repo root (do the same thing):
./build_and_run.sh        # builds both, launches the manager
./build_and_install.sh    # builds both, installs manager to /Applications
```

Tests exist under `ServerAppBundleTests/` and `LocalServerWrapperTests/`. Run with
`xcodebuild test -scheme <Scheme>`. Update/extend tests where a task changes tested behavior.

---

## 2. Tasks

Severity legend: **P0** = core promise broken, **P1** = security or data-loss, **P2** = quality/correctness.

Recommended order: **1, 2, 3, 7, 8, then the rest.** Tasks 1 and 2 are independent and can land first.

---

### TASK-1 (P0) — Bare commands (`npm`, `python3`) don't run

**Files:** `ServerAppBundle/ServerAppBundle/ScriptResolver.swift` (and manager copy / shared module),
`ServerAppBundle/ServerAppBundle/ProcessManager.swift`

**Problem:** Every documented example (Command = `npm`, `python3`) fails with `commandNotFound`.

**Mechanism:** `ProcessManager.start` guards on `FileManager.default.isExecutableFile(atPath: command)`
and sets `executableURL = URL(fileURLWithPath: command)`. Foundation's `Process` does **not** do
`PATH` lookup for `executableURL`. With `command == "npm"`, `isExecutableFile(atPath: "npm")` is false
(relative to cwd), so it throws before launching. The `PATH` you build in `environment` only benefits
processes the *child* spawns — never the top-level command.

**Fix:** In `.command` mode, resolve a bare command name (no `/`) to an absolute path via a
`which`-style lookup over the same `PATH` `ProcessManager` constructs (Homebrew + system dirs +
`additionalPathDirectories`). Keep absolute/relative paths working as-is. Put the resolution where
the PATH is known — either centralize the PATH list so `ScriptResolver` can use it, or do the lookup
in `ProcessManager.start` before the `isExecutableFile` guard. Do **not** shell out to `/bin/sh -lc`
as the default (it changes quoting/signal semantics); prefer explicit path resolution.

**Acceptance:**
- A config with command `npm`, args `["run","dev"]` (npm on PATH) launches without `commandNotFound`.
- A config with an absolute path still launches.
- A genuinely missing command still throws `commandNotFound` with a clear message.
- Bare-command resolution covered by a unit test.

---

### TASK-2 (P0) — Orphaned child processes; port stays held after quit/restart

**Files:** `ServerAppBundle/ServerAppBundle/ProcessManager.swift`

**Problem:** Quitting or restarting leaves grandchild processes alive holding the port, so the next
launch fails to bind.

**Mechanism:** `terminate()` sends `SIGTERM` to the **direct child only**. `npm run dev` spawns `node`;
killing `npm` orphans `node`, which keeps the port. There is no process-group handling and no `SIGKILL`
escalation (the existing `forceKill()` is never called by normal flows).

**Fix:**
- Put the child in its **own process group** at launch (`setpgid` via `Process` posix_spawn attrs, or
  equivalent), and on terminate send the signal to the **group**: `kill(-pgid, SIGTERM)`.
- Add a **SIGKILL escalation**: if the group is still alive after a grace period (e.g. 3s), `kill(-pgid, SIGKILL)`.
- Ensure the app's quit path (`AppState.stopServer` / close confirmation in `ContentView`) waits for
  actual termination instead of a blind delay (see TASK-4).

**Acceptance:**
- After Quit, no orphaned child of the launched server remains (verify with `pgrep`/Activity Monitor).
- Restart of a server that binds a fixed port succeeds without "address in use."
- A process ignoring SIGTERM is SIGKILLed after the grace period.

---

### TASK-3 (P2) — O(n²) output scanning + unbounded memory

**Files:** `ServerAppBundle/ServerAppBundle/ProcessManager.swift`,
`ServerAppBundle/ServerAppBundle/ReadinessDetector.swift`,
`ServerAppBundle/ServerAppBundle/TerminalView.swift`

**Problem:** A chatty long-running server degrades the UI and grows memory without bound.

**Mechanism:** `ProcessManager.output` is one ever-growing `String` (`output += text`). `AppState`
pipes the full `$output` into `ReadinessDetector.monitor`, which re-runs its regex over the **entire**
accumulated buffer on every chunk. `TerminalView` renders the whole buffer in a single `Text`.

**Fix:**
- Cap the retained terminal buffer (ring buffer / trim to last N KB or N lines; keep a sensible default
  like 256 KB and trim from the front on overflow).
- Stop feeding the whole buffer to readiness detection. Either scan only newly-appended chunks, or stop
  scanning entirely once `isReady` (the detector early-returns on `isReady`, but `AppState` still calls
  `monitor` with the full string each time before readiness — make it incremental).
- Keep terminal auto-scroll behavior intact.

**Acceptance:**
- Sustained high-volume output keeps memory bounded (buffer does not grow without limit).
- Readiness/port detection still fires correctly on the trimmed/incremental input.
- Terminal still auto-scrolls and shows the exit-code footer.

---

### TASK-4 (P2) — Restart race

**Files:** `ServerAppBundle/ServerAppBundle/AppState.swift`

**Problem:** Restart intermittently throws `.alreadyRunning` and shows an error alert.

**Mechanism:** `restartServer()` calls `terminate()`, waits a fixed `0.5s`, then `startServer()`.
If the process hasn't died in 0.5s, `isRunning` is still true and `start` throws `.alreadyRunning`.

**Fix:** Drive the restart off the actual termination signal (the `Process.didTerminateNotification`
path / `handleProcessTermination`) instead of a fixed delay — e.g. start the new process once the old
one is confirmed terminated. Coordinate with TASK-2's termination handling.

**Acceptance:** Repeated rapid restarts never produce an `.alreadyRunning` error; the new process
always starts after the old one is gone.

---

### TASK-5 (P2) — Duplicated, drifting source models

**Files:** the two copies of `ServerConfiguration.swift` and `ScriptResolver.swift` (see §1 table).

**Problem:** Model/resolution changes must be made twice; the copies have already diverged.

**Fix (preferred):** Consolidate into a single shared source of truth — a small shared Swift package
or a shared file group referenced by both Xcode targets. If a shared module is too invasive for this
pass, the **minimum** acceptable outcome is to re-sync the two copies so they are byte-identical except
for the header comment, reconcile the `Hashable` difference (add it to both), and add a prominent
comment in each file pointing at its twin.

**Acceptance:**
- Either one shared file feeds both targets, **or** the two copies are identical modulo header and both
  build. `diff` of the two `ServerConfiguration.swift` shows only the header comment differing.
- Both schemes still build.

---

### TASK-6 (P2) — Dead code + hardcoded personal path

**Files:** `LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/Services/AppBundleGenerator.swift`

**Problem:** Unused methods and a hardcoded developer path ship in the binary.

**Mechanism:** `generate()` uses `signAdHoc`. `signBundle`, `verifySignature`, and
`createBundleStructure` are never called. `signBundle` contains a hardcoded
`/Users/martinr/Developer/terminal-web-wrapper/...ServerAppBundle.entitlements` fallback. The
"not found" error message references `SIMPLE_SOLUTION.md`, which does not exist.

**Fix:** Delete the unused `signBundle`, `verifySignature`, and `createBundleStructure` (and any
helpers only they use). Remove the hardcoded absolute path. Fix or remove the `SIMPLE_SOLUTION.md`
reference in the error string. Do not change the working `signAdHoc` path.

**Acceptance:** No absolute personal paths remain in source (`grep -r "/Users/martinr" --include=*.swift`
returns nothing). Manager still builds and still generates a working, launchable bundle.

---

### TASK-7 (P1) — "Encrypted" credential fallback is not real encryption

**Files:** `ServerAppBundle/ServerAppBundle/KeychainManager.swift`

**Problem:** The UserDefaults fallback that stores passwords is trivially decryptable.

**Mechanism:** `KeychainManager.encrypt` derives the AES-GCM key from `SHA256(bundleIdentifier)`. The
bundle identifier ships in every copy's Info.plist — it's public. So anyone with the (public) bundle ID
can decrypt stored credentials. This is obfuscation, not encryption.

**Fix:** Generate a random per-install symmetric key, store **that key** in the Keychain, and use it for
the AES-GCM fallback. If the key can't be stored/retrieved from Keychain, do **not** silently fall back
to a guessable key — surface a clear "couldn't store credentials securely" error to the user and skip
persistence. Preserve the existing decrypt path for already-stored data only long enough to migrate it
(re-encrypt under the new key on next save), then it can age out.

**Acceptance:**
- New credentials in the fallback path are encrypted under a per-install random key held in Keychain.
- The key is not derivable from public bundle metadata.
- If secure storage is impossible, the user is told and nothing is written in a guessable form.
- Existing saved credentials still load (migration path verified).

---

### TASK-8 (P1) — Credentials bound to URL *path* only, never origin

**Files:** `ServerAppBundle/ServerAppBundle/Credential.swift`,
`ServerAppBundle/ServerAppBundle/CredentialDetector.swift`,
`ServerAppBundle/ServerAppBundle/CredentialAutoFill.swift`

**Problem:** A saved login can be autofilled on a different origin that happens to share a URL path.

**Mechanism:** `Credential` stores `pagePath`/`formActionPath` but **no host**. Autofill matches on
`pagePath === window.location.pathname`. The `WKWebView` allows all navigation
(`WebView.Coordinator ... decidePolicyFor` always `.allow`) and `allowUniversalAccessFromFileURLs`
is on, so autofill can fire cross-origin.

**Fix:**
- Add an origin field (scheme + host + port) to `Credential`. Capture it in `CredentialDetector`
  (from `window.location`) and require an **origin match** (not just path) in `CredentialAutoFill`
  before offering/filling.
- Handle decoding of older credentials that lack the field (optional + sensible default; do not crash
  on existing stored data).
- This is a model change — remember the duplicated-file rule does NOT apply here (`Credential` is
  runtime-only), but Keychain-stored JSON is — ensure backward-compatible decoding.

**Acceptance:**
- Autofill only offers credentials whose stored origin matches the current page origin.
- Existing stored credentials (no origin) still decode and behave safely (treated as no-match or
  prompted to re-save, your call — document which).
- New saves record the origin.

---

### TASK-9 (P1) — Web security weakened globally via private SPI

**Files:** `ServerAppBundle/ServerAppBundle/WebView.swift`

**Problem:** Same-origin protections are relaxed app-wide, in Release, using undocumented keys.

**Mechanism:** `WebView.makeNSView` sets `allowFileAccessFromFileURLs`,
`allowUniversalAccessFromFileURLs`, and `developerExtrasEnabled` via private KVC `setValue(_:forKey:)`.

**Fix:** Remove `allowUniversalAccessFromFileURLs` and `allowFileAccessFromFileURLs` unless a concrete
feature needs them (none currently does — the app loads `http://localhost`, not `file://`). Gate
`developerExtrasEnabled` to debug builds only (`#if DEBUG`). If file access is genuinely required later,
re-add it behind an explicit, documented opt-in.

**Acceptance:** Loading the localhost app still works. `allowUniversalAccessFromFileURLs` is gone.
`developerExtrasEnabled` is not enabled in Release builds.

---

### TASK-10 (P1) — Auto-answer sends blind newlines to stdin by default

**Files:** `ServerAppBundle/ServerAppBundle/ProcessManager.swift`,
`ServerAppBundle/ServerAppBundle/TerminalView.swift`

**Problem:** Blindly pressing Enter on interactive prompts can confirm destructive defaults (e.g. a
`[Y/n]` prompt).

**Mechanism:** `ProcessManager.startAutoAnswering` is invoked from `start()`, so a `\n` is written to
the child's stdin every 3s from launch, regardless of what the process prompts.

**Fix:** Make auto-answer **opt-in** — do not start it automatically in `start()`. The terminal already
has a UI toggle (`TerminalView`); default to manual input, and let the user enable auto-answer
explicitly. (Optional, only if cheap: restrict auto-answers to recognized safe prompts — but the
primary fix is making it off by default.)

**Acceptance:** A freshly launched server does **not** receive automatic newlines unless the user
turns auto-answer on. The toggle still works both directions.

---

### TASK-11 (P2) — Doc/reality mismatch on sandboxing + stale docs

**Files:** `ServerAppBundle/SANDBOX_CONFIGURATION.md`, `README.md`,
`ServerAppBundle/ServerAppBundle.entitlements`, `LocalServerWrapper/HOW_TO_RUN.md`

**Problem:** Docs describe the runtime as "Sandboxed," but `ServerAppBundle.entitlements` has
`com.apple.security.app-sandbox = false` (necessary — you can't spawn arbitrary processes sandboxed).

**Fix:** Do **not** enable the sandbox (it would break process launching). Instead correct the docs to
state the runtime is intentionally **not** sandboxed and why. Fix the stale `open ...` path in
`HOW_TO_RUN.md` to match the current directory layout. This is a docs-only task — no entitlement change.

**Acceptance:** README, SANDBOX_CONFIGURATION.md, and HOW_TO_RUN.md accurately reflect the unsandboxed
runtime and the real run paths. No entitlements changed.

---

### TASK-12 (P2) — Small UI/UX correctness

**Files:** `ServerAppBundle/ServerAppBundle/ContentView.swift`,
`ServerAppBundle/ServerAppBundle/AppState.swift` (+ a small new view for credential management)

Three small items; each is independent:

1. **Misleading lock icon.** The principal toolbar shows `lock.fill` for plain `http://localhost`.
   Replace with a neutral indicator (e.g. `globe` / no padlock) so it doesn't imply TLS.
2. **Racy autofill injection.** `AppState.setupAutoFill` injects after a fixed `1.0s` delay for SPA
   rendering. Replace the fixed delay with a retry loop or `MutationObserver` in the injected JS so it
   re-attempts until the fields exist (bounded retries).
3. **Unreachable credential management.** `AppState.deleteCredential` exists but there is no UI to view
   or delete saved credentials. Add a minimal sheet/menu listing saved usernames (+ origin from TASK-8)
   with a delete action.

**Acceptance:** No padlock on http; autofill appears reliably on slow SPAs without depending on a fixed
delay; user can view and delete saved credentials from the generated app.

---

## 3. Out of scope / do NOT touch

- **Do not** add the feature ideas (multi-tab, health-check readiness, env-var injection, crash-restart,
  log export, port pre-flight). Those are a separate later pass.
- **Do not** enable App Sandbox (TASK-11 is docs-only).
- **Do not** reformat or restyle files unrelated to a task. No mass renames, no import reordering, no
  whitespace churn. Keep diffs minimal and reviewable.
- **Do not** change the working `signAdHoc` generation path beyond the dead-code removal in TASK-6.
- **Do not** bump tooling/Swift versions or add third-party dependencies.

---

## 4. Verification (run before handing back)

```bash
# Both schemes must build clean in Release:
cd ServerAppBundle && xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
cd ../LocalServerWrapper && xcodebuild -scheme LocalServerWrapper -configuration Release -derivedDataPath build build

# Run tests for both:
xcodebuild test -scheme ServerAppBundle
xcodebuild test -scheme LocalServerWrapper   # run from the LocalServerWrapper dir

# No personal paths leaked:
grep -rn "/Users/martinr" --include=*.swift . || echo "clean"
```

Manual smoke test (generate a bundle and launch it):
1. Build both (above), open the manager, create a config with command `npm` args `run dev` (or
   `python3` args `-m http.server 8000`), generate a bundle.
2. Launch the generated `.app`: confirm it starts, terminal shows output, browser swaps in on ready.
3. Quit: confirm no orphaned child processes remain (`pgrep -fl node` / Activity Monitor).
4. Save a credential on a login page, reload: confirm autofill offers it; navigate to a different
   origin and confirm it does **not** autofill.

---

## 5. Commit / PR conventions (so review is tractable)

- Work on a single branch off `main`. **One atomic commit per TASK-N**, message prefixed with the task
  id, e.g. `TASK-2: kill server process group on terminate`.
- Keep each commit limited to that task's files. No drive-by changes.
- End each commit message with the project's trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Do not push or open a PR unless explicitly asked; leave commits on the branch for review.

---

## 6. Reporting back (required)

When finished, produce a short written summary for the reviewer containing:

- **Per task:** done / partial / skipped, and for partial/skipped — why.
- **Decisions made** where this spec left a choice (e.g. TASK-5 shared-module vs re-sync; TASK-8
  behavior for legacy credentials).
- **Anything you changed that wasn't in the spec**, and why it was necessary.
- **Verification results:** did both schemes build? did tests pass? paste the relevant tail of output.
- **Known gaps / follow-ups** you noticed but intentionally did not address.

Do not claim a task is done if its build or tests failed — say so plainly with the error.
