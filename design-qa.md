# One-pane app library design QA

- Source visual truth: `docs/design-qa/source-one-pane-mock.png`
- Initial implementation capture: `docs/design-qa/implementation-one-pane-iteration-1.jpg`
- Final implementation capture: `docs/design-qa/implementation-one-pane-final.jpg`
- Export-state implementation capture: `docs/design-qa/implementation-one-pane-export-state-final.png`
- Compact editor capture: `docs/design-qa/implementation-compact-editor-final.png`
- Source pixels: 1487 x 1058
- Export-state implementation pixels: 800 x 652
- Viewport: native macOS window at 800 x 652 physical screenshot pixels
- CSS size: not applicable; this is a native SwiftUI app
- Density normalization: none. The comparison evaluates hierarchy and native proportions rather than pixel-for-pixel scale because the generated source mock and live macOS window use different canvas sizes.
- State: dark mode, idle app-library state showing one existing exported app and two setups without an export

## Full-view comparison evidence

The implementation retains the source's defining structure: a single native pane, `Server Apps` title, toolbar search, labeled `New App…` action, lightweight list separators, icon/name/command rows, one state-aware primary action per row, and a trailing ellipsis menu. Setups without an exported bundle show `Generate App…`; an existing exported bundle shows `Show in Finder`, per the revised product requirement. There is no sidebar, detail inspector, Network card, Detection card, metadata footer, or prominent launch button.

The live app intentionally uses denser system row metrics than the generated mock. This is appropriate for the actual 824 x 652 macOS utility window and preserves the mock's information hierarchy without reproducing its oversized concept-render proportions.

## Focused comparison evidence

A separate crop was not needed: the toolbar and all row controls are clearly readable at original resolution in both source and implementation captures. The toolbar label, row typography, command subtitles, generation buttons, separators, and overflow controls were checked directly in the full-resolution images.

## Required fidelity surfaces

- Fonts and typography: passed. The implementation uses San Francisco system text and a monospaced command subtitle, matching the target hierarchy. Names remain visually dominant and long commands truncate without wrapping.
- Spacing and layout rhythm: passed. The live layout is more compact than the concept but maintains consistent row padding, alignment, separators, and generous unused canvas space.
- Colors and visual tokens: passed. Native dark materials, secondary text, system separators, and restrained accent styling match the source direction and the existing app.
- Image quality and asset fidelity: passed. Existing custom app icons render sharply; missing icons use the native SF Symbol fallback already established by the product. No raster placeholders or fabricated decorative assets were introduced.
- Copy and content: passed. `Server Apps`, `New App…`, `Generate App…`, `Show in Finder`, `Test Launch`, `Open App`, and `Regenerate App` follow the agreed generator-first vocabulary and expose bundle state without explanatory copy.

## Interaction evidence

- Opened and cancelled the `Generate App` save panel. It defaults to Applications, uses `Generate` as the confirmation label, and did not modify user data during QA.
- Opened and cancelled the `New App` editor. The sheet title and save action use app-oriented language.
- Opened the row overflow menu. `Edit…`, `Test Launch`, and `Delete…` are secondary; no prominent Run action remains.
- Verified an app with a valid exported path displays `Show in Finder` as its row action, while setups without exports continue to display `Generate App…`.
- Verified the generated-app overflow menu contains `Edit…`, `Test Launch`, `Open App`, `Regenerate App`, and `Delete…`.
- Added and passed an integration-style unit test proving that saving an edited configuration regenerates its existing exported bundle at the same path with the updated embedded configuration.
- Verified the live accessibility tree exposes the app rows, search field, New App action, and secondary menu actions.
- No web console applies to this native app.

## Comparison history

### Iteration 1

- [P2] The native toolbar collapsed `New App…` to an unlabeled plus icon, weakening the creation affordance compared with the source mock.
- Fix: replaced the toolbar `Label` with an explicit icon-and-text button using a bordered style.
- Post-fix evidence: `implementation-one-pane-final.jpg` visibly shows `+ New App…` beside the search field.

### Final pass

- No remaining P0, P1, or P2 visual findings.
- [P3] The source mock uses taller rows and larger icons than the live app. The denser live metrics are an intentional native adaptation rather than an unresolved usability problem.

### Export-state revision

- Revised requirement: replace the row's `Generate App…` action with `Show in Finder` once an exported bundle exists, and regenerate that existing bundle automatically after edits.
- Fix: made the primary row action conditional on the persisted exported path, routed editor saves through the library view model, and staged bundle replacement before updating the exported copy in place.
- Post-fix evidence: `implementation-one-pane-export-state-final.png` shows both row states together. The live accessibility tree confirms the labels, and the generated-app overflow menu exposes manual regeneration as a secondary recovery action.
- No new P0, P1, or P2 visual findings.

### Compact editor follow-up

- Replaced the vertically loose grouped form with a compact native stack, reduced the command editor to a comfortable 68-point height, shortened supporting copy, and moved file selection beside the Launch heading.
- The default editor now renders at 580 x 525 outer pixels with App name, Launch, Server, Advanced options, Cancel, and Save Changes visible at once and no vertical scrollbar.
- Expanding Advanced options grows the sheet content height from 460 to 500 points; the toggle and its explanation remain visible without scrolling.
- Live accessibility inspection confirmed every editor control remains present and reachable. No P0, P1, or P2 visual findings were introduced.

### Compact main-window follow-up

- Reduced the main content minimum from 800 x 600 to 560 x 340 points and set a 640 x 420 default. Existing installations receive the compact default once, after which normal macOS window-size restoration remains user-controlled.
- Retained the native searchable toolbar presentation so Search and New App remain visually separate controls at the compact width.
- Moved generation, success, and failure feedback beneath each app's command subtitle. Rows no longer reserve a separate status column between the app details and primary action.
- Applied the native plain-list style with a 6-point toolbar gap and compact row insets. This removes the list style's built-in outer margins while leaving the rows borderless and uniformly styled.
- Aligned both ends of the system-provided row separators to the full row content bounds using SwiftUI's `listRowSeparatorLeading` and `listRowSeparatorTrailing` guides. The separators now have equal leading and trailing insets while retaining the native thickness and color.
- Live inspection at 560 x 420 confirmed all three rows, the separated toolbar controls, primary actions, and overflow menus remain readable without horizontal clipping. Evidence: `implementation-compact-main-window-final.jpg`.

## Verification limits

The focused unit tests pass and the app builds. The repository's earlier full UI-test command failed before executing UI tests because XCTest timed out while enabling macOS automation mode. Direct Computer Use inspection covered the primary non-destructive interactions instead. Automatic regeneration was verified with an isolated temporary exported bundle, not by modifying the user's existing generated app.

## Implementation checklist

- [x] Replace the split view with one native app list.
- [x] Make `Generate App…` the recurring row action.
- [x] Move launch and management actions into the overflow menu.
- [x] Add per-app generating, success, and failure presentation.
- [x] Remember valid exported bundle paths for `Open App` and `Show in Finder`.
- [x] Replace `Generate App…` with `Show in Finder` when a valid exported bundle exists.
- [x] Regenerate an existing exported bundle automatically after editor saves.
- [x] Stage replacement so a failed regeneration leaves the previous exported app intact.
- [x] Update editor and empty-state vocabulary.
- [x] Verify the live app against the selected source mock.

final result: passed
