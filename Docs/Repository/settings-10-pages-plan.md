# Plan: finish Phase 12 — 10-page Settings, built first, checked at the end

## Context
Done so far (pushed, main = 8791a12): sweep baseline, Permissions in General, Widgets tab, Edge Bars tab, Live Island/helpers/behaviour toggles moved to Advanced, Dock Style merged into Layout Mode, theme-grid wrap, width-slider floors, VoiceOver labels (partly), macOS-12 Now Playing parity.
New direction from owner: 10 user-friendly pages; build all moves now, **run all checks at the end**. Every slice: build (Release cmd) + `check_localization` + `check_debug_switches` + `check_availability_warnings`, commit, push branch, fast-forward main, HYBRID_PLAN.md log line. Each pane change is made in both the macOS 13+ and macOS 12 copies where General/Advanced/About are duplicated. New strings: add catalog entries in all 12 languages with English placeholder, non-English `needs_review` (owner does the language pass later). Nothing deleted without a yes.

## Target pages (10)
| # | Page | Contents (source today) |
|---|------|------------------------|
| 1 | **General** | language, light/dark, show/hide shortcut, **Preview + Layout Mode + Size (Position/Bar Height/Spacing + Fine-tune)** (from Layout), drawer position, scroll reverse, Permissions, setup guide |
| 2 | **Appearance** | theme grid, icon set/shape, wallpaper (already trimmed) |
| 3 | **Widgets** | widget list/sizes/presets/styles (done) **+ Widget Layout, Widget Colors, Clock Style, Glass, Weather block, Now Playing Theme (moved from General)** |
| 4 | **Notch** (title proposal; see decision) | `LiveIslandSettingsBlock` (dock island, notch island, style, event alerts, system banners) + Teleprompter notch page toggle + hide-from-capture/Caps-Lock/charge/USB/privacy indicators (helpers that surface in the notch) |
| 5 | **Edge Bars** | done |
| 6 | **Window Management** | rename of Tiling + Window Chips (from Layout) + Option-Tab switcher + restore-layout-after-sleep (from Behaviour) |
| 7 | **Launcher & Tools** | Launcher (from Layout), Control Center (from Layout), Clipboard, Commands, Snippets, Shelf, Fast file index (from Utility block) |
| 8 | **Shortcuts** | Shortcuts section, Keyboard/input (Hyper key, pause keyboard, hold ⌘Q, show keys, pinch), Radial Dial (all from Layout) |
| 9 | **Advanced** | fullscreen-intent, Behaviour leftovers (Hold Control memory, system helpers, CPU/memory menu bar), notification-banner move, debug-adjacent |
| 10 | **About** | unchanged |

`SettingsTab` gains: `.notch`, `.windowManagement` (replaces `.tiling`; keep a raw-value alias so a stored selection can't crash), `.launcherTools`, `.shortcuts`; Layout tab dissolves (its remaining parts all have a home above). Reuse the `SettingsLayoutPane.Mode` trick (one view, per-tab section groups) rather than new files, except where a block already is its own file. New Swift files need hand-added pbxproj entries.

## Decisions to confirm (defaults chosen so work can proceed)
- Notch page title: default **"Notch"** (what NotchNook/Boring Notch call it); "Live Island" stays as the section header inside. Alternative: "Live Activities".
- Control Center goes to Launcher & Tools; Radial Dial goes to Shortcuts; Notification banner mover goes to Advanced. Say if you want them elsewhere.
- Toolbar: 10 tabs may not fit the window width; if not, tab titles shrink to icons+short labels or the toolbar overflows — handled in slice 0.

## Slices (each ships alone; build only, no live checks until slice 8)
0. **Tab infrastructure:** extend `SettingsTab` (10 cases, symbols, titles), tab routing in `SettingsWindowContent`, window-width fit for 10 toolbar items, migrate `.tiling` rawValue. Empty/placeholder panes route to existing content so nothing is lost mid-way.
1. **General absorbs Preview/Layout Mode/Size:** move the three sections out of Layout into General (both macOS copies; Fine-tune disclosure moves with Size). Layout tab removed once empty (last of slices 4–6 empties it).
2. **Widgets absorbs widget settings from General:** Widget Layout/Colors/Clock Style/Glass/Weather/Now Playing Theme → Widgets (both copies; the macOS 12 Now Playing picker moves with it).
3. **Notch page:** new pane with Live Island block + notch-surfacing helper toggles split out of `UtilitySettingsBlock`; removes them from Advanced.
4. **Window Management:** rename Tiling, add Window Chips (Layout) and the switcher/restore toggles (Behaviour).
5. **Launcher & Tools:** Launcher + Control Center (Layout) and Clipboard/Commands/Snippets/Shelf/File-index (Utility) into a new pane; split `UtilitySettingsBlock` into notch vs tools halves.
6. **Shortcuts:** Shortcuts, Keyboard/Input, Radial Dial sections out of Layout into a new pane. This also completes the deferred 12c Shortcuts item and empties Layout.
7. **Advanced/About tidy:** Advanced = fullscreen intent + remaining behaviour + notification banners; remove empty Layout tab; headers where a group has none; update doc comment ("five tabs").
8. **Close-out checks (all live, with your permission):** rebuild/install; per-page AX dump + screenshot of all 10 pages; every control exercised (Layout geometry, Tiling, wallpaper, shortcut recorders, About update check, language relaunch); VoiceOver label re-audit (Layout/Tiling/Appearance checkboxes); settings window height vs dock reserved edge; unit tests (`xcodebuild test`, incl. DockStyle/SettingsTab tests); Better Design `get-review-rules`, `check-comprehension`, `inspect-spacing`; 12f theme refinement screenshots for your choice; centered-vs-full-width confirm; 37e teleprompter check then Phase 9 Hyper-key/custom-shortcut checks.
9. **Registry + cleanup (asks first):** `Docs/Repository/` entries for every dead/broken item; list for your yes/no: DownloadManagerService demo downloads, `stash@{0}`, stale worktrees, stale comments `AppSettingsStore.swift:177,179`, unbounded gap/margin setters, unused `DockStylePicker`/style presets if the welcome guide drops them. Update HYBRID_PLAN.md statuses; Phase 38 stays on hold.

## Risks
- 10 toolbar tabs may crowd the window; slice 0 decides the fit before any content moves.
- General becomes the tallest page (Preview + Mode + Size + Permissions); window height must be re-measured at close-out.
- Every moved block exists twice (macOS 13/12); parity drift is the main bug source — build checks only, so drift is caught at slice 8.
- Reinstalls reset TCC grants and re-prompt Location; owner re-grants.

## Verification
Per slice: three gates + Release build green. Final (slice 8): all pages exercised live, zero unexplained dead controls, full test suite green, installed app matches HEAD, HYBRID_PLAN.md updated.
