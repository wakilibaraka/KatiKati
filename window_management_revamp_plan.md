# Window Management Revamp — Audit & 5-Slice Plan

Status: **plan only, no production edits**.
Scope: hybrid extension of the existing Window Management surfaces; nothing below is removed unless an existing control is superseded by a clearer control for the same setting.

## 1. Audit

### 1.1 What already exists

| Area | Existing implementation | What is missing |
| --- | --- | --- |
| Switcher HUD | `App/Composition/WindowSwitcherController.swift`: `⌥Tab` (Carbon hot keys), optional `⌘Tab` takeover through `CommandTabTakeover`, grid/sidebar layouts, MRU order, live thumbnails, type-to-search, 1–9 direct selection, close/minimize/quit, sidebar “Always visible” | Five presets (thumbnail/list/icons/classic/carousel), style config, keep-open-on-release outside the sidebar, predictive frequency ranking, pinned app hotkeys |
| Switcher logic | `Core/Support/WindowSwitcherModel.swift`: pure MRU update/order, selection stepping, query matching, grid columns, numbered model | Style/config models, predictive ranker, filter policy, pinned-hotkey data model |
| Thumbnail capture | `App/Composition/WindowThumbnailCapture.swift`: ScreenCaptureKit `SCScreenshotManager`, only called while a surface is open, permission fallback | Reuse for all five layouts; explicit capture cancellation/generation on dismiss |
| Filtering | Controller admits `.active/.inactive/.minimized/.hidden`; `WindowRecord` already carries `displayUUID` and `isOnDesktop` | Current-display/current-Space policy, minimized/hidden toggles, ignored bundle-ID list |
| Window snap | `Core/Support/WindowSnap.swift`: 15 `SnapPosition` zones incl. thirds/center/maximize; `Platform/Windows/WindowSnapService.swift`: AX frame writes, Dock/visible-frame reserve, maximize toggle, next-display; `ShortcutAction.snap*` bindings; radial-dial ghost preview | Edge/corner drag planner, drag preview/snap-on-release, snap preview style setting |
| Green button | `Platform/CoreGraphics/FullscreenIntentMonitor.swift` already owns the only session event tap and identifies `AXFullScreenButton` clicks for fullscreen pre-hide; `WindowSnapService.apply(.maximize)` already performs space-free maximize | No interception path that consumes the green click and routes it to `WindowSnapService`; no `⌥` fallback rule in the snap layer |
| Hover preview | `App/Entry/ChipPanelController.swift`, `App/Scenes/ChipPanel/ChipPanelModel.swift`, `App/Scenes/ChipPanel/ChipPanelView.swift`: floating thumbnails, hover delay 150/350/600 ms, width 140/180/240, hover close; `PanelCoordinator+ChipPanel.swift` injects settings | Preset model for shape/tint/theme, minimize/maximize quick actions, preset-driven view metrics, settings UI |
| Settings | `App/Scenes/SettingsWindowView.swift` `windowManagementPane`: `SettingsLayoutPane(.chips)` + `DockLayeringSettingsBlock` + `WindowBehaviourSettingsBlock`; switcher settings live in `App/Scenes/BehaviourSettingsBlock.swift` | AltTabby-style top sub-nav, 3×2 style card grid, inline gear popover, behavioral/filtering/hover sections, page-height probe for this tab |
| Metrics | `SettingsMetrics` documents the 1074 pt window ceiling and shared row/card grid; `SettingsPageHeightProbe` exists but is not attached to Window Management | Measure this page with `DOCK_SETTINGS_PAGE_HEIGHT=1` after the redesign |

### 1.2 Files that must remain behavior-frozen

Do not edit these in this revamp:

- `App/Composition/WindowLiftAvoidanceController.swift`
- `App/Composition/AppTracker.swift`
- `App/Composition/DragController.swift`
- `Platform/Accessibility/AccessibilitySource.swift`
- `Platform/CoreGraphics/FullscreenIntentMonitor.swift`

Use their public/pure seams instead:

- `AXWindowReader` for frame/attribute reads where a new path is unavoidable.
- `WindowSnapService` for AX frame writes.
- `AppRuntime` snapshot/activate/minimize/close/quit for switcher actions.
- `WindowSpaceMembershipReader` (call only, never edit) if current-Space filtering is approved.
- `WindowThumbnailCapture` for all live thumbnails.

### 1.3 Repository constraints

1. **No `project.pbxproj` churn and no new Swift files.** All new types and views go into existing tracked files; tests go into existing tracked test files:
   - `Core/Support/WindowSwitcherModel.swift`
   - `Core/Support/WindowSnap.swift`
   - `Core/Support/Shortcuts.swift`
   - `App/Composition/WindowSwitcherController.swift`
   - `App/Composition/WindowThumbnailCapture.swift`
   - `App/Entry/ChipPanelController.swift`
   - `App/Entry/PanelCoordinator+ChipPanel.swift`
   - `App/Scenes/ChipPanel/ChipPanelModel.swift`
   - `App/Scenes/ChipPanel/ChipPanelView.swift`
   - `App/Scenes/SettingsWindowView.swift`
   - `App/Scenes/BehaviourSettingsBlock.swift`
   - `App/Composition/AppSettingsStore.swift`
   - `Tests/Unit/WindowSwitcherModelTests.swift`
   - `Tests/Unit/WindowSnapTests.swift`
   - `Tests/Unit/ShortcutsTests.swift`
2. **Pure core first.** Ranking, filtering, presets, and snap-zone geometry are pure and get synchronous `-only-testing:` tests before UI wiring.
3. **Zero idle CPU.** Thumbnails exist only while the switcher/hover panel is visible. Each open gets a generation token; dismiss cancels pending captures.
4. **1074 pt clamp and 12 locales.** Attach `SettingsPageHeightProbe(tab: .windowManagement)` and run `DOCK_SETTINGS_PAGE_HEIGHT=1`; add every new UI string to all 12 `Resources/Localizable.xcstrings` locales and pass `python3 Scripts/check_localization.py`.
5. **≤300 diff lines per commit.** Large slices are split into sub-commits; the five slice boundaries remain reviewable on their own.

### 1.4 Architectural gates that need owner approval

**G1 — Green-button interception (blocking for “no new Space” maximize).**
`FullscreenIntentMonitor` is the only session event tap and is behavior-frozen. Swallowing the green click cannot be done from `WindowSnapService` or a second monitor without either editing that file or running a competing event tap. Recommended: approve one narrow, default-off hook in `FullscreenIntentMonitor` (e.g. a green-click decision closure returning `.native`/`.consumeAndMaximize`), keeping its existing pre-hide behavior unchanged. If that exception is not approved, ship green-button behavior as a **deferred gate** and keep `⌃⌘F`/existing maximize shortcut as the only space-free maximize path. Do not add a second CGEvent tap.

**G2 — Current-Space filtering data.**
`WindowRecord` has `displayUUID` but no Space ID. Use the existing `WindowSpaceMembershipReader.spaceIDs(forWindowNumber:)` on switcher open only (off-main, per-open cache), or defer the `Current Space Only` toggle. No edits to `FullscreenIntentMonitor`; the reader is callable from the existing file.

**G3 — Drag-to-edge interception.**
`DragController` is frozen and already owns drag state. The recommended path is a non-intercepting global `leftMouseDragged`/`leftMouseUp` monitor used only while the setting is enabled: it draws a preview and applies the snap after release, never mutates the drag. No changes to `DragController`. If the project’s “no resident global monitor” rule is interpreted strictly, this gate must be resolved before WM-4.

## 2. Slice Plan

### WM-1 — Pure switcher, ranking, filtering, and hover models

**Files:** `Core/Support/WindowSwitcherModel.swift`, `Core/Support/WindowSnap.swift`, `Core/Support/Shortcuts.swift`, `Tests/Unit/WindowSwitcherModelTests.swift`, `Tests/Unit/WindowSnapTests.swift`, `Tests/Unit/ShortcutsTests.swift`.

Add, without changing existing behavior:

- `WindowSwitcherStyle` (`.thumbnail`, `.list`, `.icons`, `.classicIcons`, `.carousel`, `.disabled`) and `WindowSwitcherStyleConfig` (`iconSize`, `spacing`, `rows`, `columns`, `opacity`, `accentColor`, `animationSpeed`, `keepOpenOnRelease`) — Codable.
- `WindowPredictiveRanker`: normalized recency decay + frequency score per `(bundleID, windowTitle)`, deterministic tie-breaker, `resetLearnedData()`.
- `WindowFilterPolicy`: display UUID, current-Space IDs, show-minimized, show-hidden, ignored bundle IDs; pure `filter(_:context:)`. `WindowRecord.displayUUID` already exists.
- `DockHoverPreviewPreset`: size `.compact/.standard/.large`, shape `.roundedCard/.squircle/.borderlessGlass`, tint `.liquidGlass/.darkObsidian/.appAccent`, quick-action flags.
- `SnapZonePlanner`: pointer-to-zone resolver for halves, quarters, thirds, center, maximize; returns a `SnapPosition?` plus preview rect in the display work area.
- `GreenButtonBehavior`: `.nativeFullscreen`, `.maximizeInCurrentSpace`; Codable defaults.
- `PinnedAppHotkey` Codable model (bundle ID + existing `ShortcutKey`) and validation that rejects duplicates.

Tests:

```bash
xcodebuild -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS' \
  -only-testing:KatiKatiTests/WindowSwitcherModelTests \
  -only-testing:KatiKatiTests/WindowSnapTests \
  -only-testing:KatiKatiTests/ShortcutsTests test
```

Commit target: model + tests only, ≤300 lines.

### WM-2 — Five-layout switcher, predictive order, filters, pinned hotkeys

Split into three ≤300-line commits.

**WM-2a — Controller / ordering**
Files: `App/Composition/WindowSwitcherController.swift`, `App/Composition/WindowThumbnailCapture.swift`, `App/Composition/AppSettingsStore.swift`.
- Read style/config from defaults; migrate existing `"grid"`/`"sidebar"` without losing the current choice.
- Apply `WindowPredictiveRanker` after MRU order; persist frequency counters; expose clear action.
- Apply `WindowFilterPolicy` at open time; preserve current behavior when filters are off.
- Capture generation token; cancel/ignore stale captures on close; thumbnails only while panel is visible.

**WM-2b — Thumbnail / List / Icons / Classic views**
Files: `App/Composition/WindowSwitcherController.swift`.
- Add the four layouts as private SwiftUI views in the existing file; reuse `Tile`, `thumbnails`, `selection`, search, numbering and actions.
- Preserve `⌘W/⌘M/⌘Q`, arrows, Return, Esc, 1–9.
- Thumbnail view uses live images; list view deliberately no thumbnails; icons/classic are icon-led grids/rows.
- `keepOpenOnRelease` generalizes the sidebar `pinned` behavior.

**WM-2c — Carousel and pinned app hotkeys**
Files: `App/Composition/WindowSwitcherController.swift`, `Core/Support/Shortcuts.swift`, `App/Composition/ShortcutService.swift` (only if the dynamic monitor belongs there), settings store.
- 3D angled carousel with bottom app-icon strip; reduced-motion fallback to flat thumbnails.
- Dynamic per-app hotkeys use `GlobalHotKeyMonitor` and validate collisions; no new `ShortcutAction` cases unless they are added to the existing enum.
- Keep the existing Option/Command takeover untouched; pinned hotkeys are additive.

Verify each sub-commit with `WindowSwitcherModelTests` plus the existing `WindowSwitcherShortcutTests`.

### WM-3 — Dock hover preview presets and quick actions

Files: `App/Scenes/ChipPanel/ChipPanelModel.swift`, `App/Scenes/ChipPanel/ChipPanelView.swift`, `App/Entry/ChipPanelController.swift`, `App/Entry/PanelCoordinator+ChipPanel.swift`, `App/Composition/AppSettingsStore.swift`.

- Map the preset to `thumbWidth`, card corner radius, backdrop treatment/tint, spacing and animation; preserve 150/350/600 ms delay and 140/180/240 widths as the compact/standard/large presets.
- Shape: rounded card, squircle, borderless glass; tint: adaptive liquid glass, dark obsidian, app-dominant accent.
- Add hover-reveal close (`×`), minimize (`–`) and maximize (`+`) buttons. Existing `ChipPanelModel` already has close; add minimize via `AppRuntime` and maximize via `WindowSnapService`.
- Respect `accessibilityReduceMotion`; no capture while hidden.
- Rollout defaults keep current look until the user chooses a preset.

Verify: build + focused settings/model tests; live hover check with Screen Recording denied (icon fallback) and allowed (thumbnail path); no captures after dismiss.

### WM-4 — Snap drag planner and green-button behavior

Files: `Core/Support/WindowSnap.swift`, `Platform/Windows/WindowSnapService.swift`, `App/Composition/WindowSwitcherController.swift` (only if shared state), settings store, existing snap tests.

**WM-4a — Snap zones / preview**
- `SnapZonePlanner` maps pointer-in-display work area to a zone with hysteresis/edge margins; preview overlay uses the existing `SnapPosition.frame(in:)` and Dock reserve.
- Keyboard chords continue through `ShortcutAction.snap*`; no changes to `ShortcutsTests` semantics beyond new zone cases.

**WM-4b — Drag monitor and apply**
- Non-intercepting monitor behind a setting (G3). On release, resolve the frontmost other app’s focused window through `WindowSnapService` and apply the planned zone.
- Multi-display awareness via `NSScreen.screens` and `DockReserve.workArea`; never touch `DragController`.

**WM-4c — Green button (G1)**
- Recommended: one tiny `FullscreenIntentMonitor` hook that lets the existing tap consume a green click and call `WindowSnapService.apply(.maximize)`; `⌥`-click or `⌃⌘F` falls through to native fullscreen.
- If G1 is denied: do not duplicate the tap; ship WM-4a/4b and leave the green-button toggle disabled with an explanatory row until approved.

Verify live: snap left/right/quarter/third on two displays; maximize and restore; `⌥` green click still enters native fullscreen only if G1 is approved.

### WM-5 — AltTabby-style Window Management settings

Files: `App/Scenes/SettingsWindowView.swift`, `App/Scenes/BehaviourSettingsBlock.swift`, `App/Scenes/SettingsLayoutPane.swift`, `App/Composition/AppSettingsStore.swift`, `Resources/Localizable.xcstrings`.

- Add a top segmented sub-nav inside `windowManagementPane`: **Style · Hotkeys · Behaviour · Filtering · Snap & Hover**. Keep a `@State` selection; no new sidebar tab.
- **Style:** 3×2 card grid (Thumbnail, List, Icons, Classic, Carousel, Disable); selected card gets an inline `⚙` popover for icon size, spacing, rows/columns, opacity, accent, animation speed; checkbox “Keep switcher open when hotkeys are released”.
- **Hotkeys:** existing switcher/hotkey rows + secondary switcher chord + pinned hotkey table + snap shortcuts. Reuse `SettingsLayoutPane` shortcut binding editors rather than duplicating them.
- **Behaviour:** predictive toggle + clear learned data; green-button toggle + `⌥` fallback; grouping; drag-snap toggle + preview style. Preserve `DockLayeringSettingsBlock`, window strip, border, restore-after-sleep rows (move, don’t delete).
- **Filtering:** current display, current Space, minimized, hidden, ignore list with app picker.
- **Snap & Hover:** hover enable/delay/preset picker and quick-action toggles; snap margin/preview style.
- Attach `SettingsPageHeightProbe(tab: .windowManagement)` in `SettingsWindowView`.
- Add all strings to 12 locales; no English-only labels.

Verification:

```bash
DOCK_SETTINGS_PAGE_HEIGHT=/tmp/katikati-settings-heights.txt \
  ./.build/.../KatiKati.app/Contents/MacOS/KatiKati   # or the project’s documented livecheck launcher
grep '^windowManagement ' /tmp/katikati-settings-heights.txt   # must be ≤ 1074
python3 Scripts/check_localization.py
python3 Scripts/check_debug_switches.py
xcodebuild ... -only-testing:KatiKatiTests/WindowSwitcherModelTests \
  -only-testing:KatiKatiTests/WindowSnapTests \
  -only-testing:KatiKatiTests/ShortcutsTests test
graphify update .
```

Livecheck must confirm all five sub-tabs, the 3×2 grid, gear popover, keep-open checkbox, hover preview presets, and the untouched existing Window Management rows.

## 3. Order of work and review gates

1. WM-1 pure models + tests — **approval gate before UI**.
2. WM-2a/2b/2c switcher — approve each sub-commit; check Option/Command takeover and capture teardown.
3. WM-3 hover presets — approve after live hover check.
4. WM-4a/4b snap; WM-4c only after G1 decision.
5. WM-5 settings UI + localization + page-height gate.

No production code has been changed by this audit. Awaiting approval of the plan and decisions on **G1 (green-button hook)**, **G2 (current-Space filter)**, and **G3 (drag monitor)** before starting WM-1.

## 4. Tiling follow-ups — plan only, no code change (2026-11-20)

The owner split Window Management into two panes (**Window Switcher** — Option-Tab/⌘Tab — and
**Dock & Desktop**) and turned the always-visible strip into a **desktop window box**: a 264 pt glass
card in the top-left of the main display's work area, at window level `normal − 1`, so it is drawn
underneath every app window and can never cover one. Everything below is tiling work and is
deliberately **not implemented** in this change.

1. **Retire or resize `WindowStripReserve`.** `TilingEngine.workArea` still trims 56 pt off the
   primary display's left edge whenever `com.katikati.strip.enabled` is on. That number was the old
   icon rail; the box is a 264 pt card. Today the reserve therefore stops tiled windows inside the
   card instead of clear of it. Decide between (a) deleting the reserve entirely — the box lives
   under windows and needs no work-area reservation — and (b) reserving the card's real width and
   margin.
2. **Per-display work areas.** If a reserve stays, it must follow the box's display rather than
   `NSScreen.screens.first`, and recompute when the box moves.
3. **Tiling rows' home.** Neither new pane carries tiling controls. Gaps, presets, per-display
   layouts and retile belong on the existing **Tiling** page when they get a home in this revamp.
4. **Layout restore vs. the box.** `WindowLayoutRestoreController` re-applies frames from the last
   sleep; restored frames must be clamped to the same work area tiling computes once the reserve
   changes.
5. **Read §2 accordingly.** WM-2/WM-5 describe "five sub-tabs"; the shipped page is two panes with
   four sections each — *Window Switcher*: Style, Hotkeys, Filtering, Ordering; *Dock & Desktop*:
   Hover Preview, Desktop, Windows, Snap Preview.
