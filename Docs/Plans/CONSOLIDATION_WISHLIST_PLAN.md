# KatiKati Consolidation Wishlist Audit & Easiest → Hardest Roadmap

**Branch:** `main` (audited at `d76e0201`)  
**Target Floor:** macOS `15.0` (`KatiKati.xcodeproj/project.pbxproj:4905`) · Swift `5.0` · Bundle ID `com.katikati.app` · Defaults `com.katikati.*`  
**Entitlements / Signing Posture:** Non-sandboxed (`Resources/KatiKati.entitlements` holds only `com.apple.security.automation.apple-events = true`)  
**Scope Rule:** Read-only audit of `Core/`, `Platform/`, `App/Composition/`, `App/Entry/`, `App/Scenes/`, `Resources/`, and `Tests/Unit/`. No `.swift` files or `KatiKati.xcodeproj/project.pbxproj` are modified by this plan.

---

## 0. Governance Contract & Architectural Constraints

### Repository & Build Gates
- **Diff Budget:** `<= 300` lines per atomic slice (`STANDING_RULES.md` §1.1, §1.7f).
- **Zero `project.pbxproj` Churn:** `KatiKati.xcodeproj/project.pbxproj` does **not** use `PBXFileSystemSynchronizedRootGroup`. Every slice below targets **existing registered files** across `Core/Support/`, `Platform/`, `App/Composition/`, `App/Entry/`, `App/Scenes/`, and `Tests/Unit/` for zero `project.pbxproj` churn. Where `Resources/Info.plist` entries are required (`T2.3`, `T4.2`) or where a standalone new file is optionally split out, it is explicitly flagged (hand-append `<= 25` lines max per `STANDING_RULES.md` §1.7a if ever added).
- **Pure Core + Synchronous Unit Tests First:** Pure logic lives in `Core/Support/` (no `AppKit`, no `AX`, no clocks), verified first with synchronous `-only-testing:KatiKatiTests/<Suite>` runs, then wired into `Platform/` and `App/`.
- **12-Locale & Switch Gates:** Every user-facing string is localized across all 12 languages in `Resources/Localizable.xcstrings` (`en`, `zh-Hans`, `zh-Hant`, `ja`, `de`, `fr`, `es`, `es-419`, `pt-BR`, `pt-PT`, `it`, `ko` per `Scripts/check_localization.py:21`). Every slice ends with:
  ```bash
  python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```
- **Zero Idle CPU:** All event taps, timers, and listeners stay default-OFF or strictly gated on active feature state / visible surfaces (`0 Hz` at rest).
- **Ponytail Discipline:** Reuse existing KatiKati primitives first (`MenuBarStatModel`, `ClipboardMonitor`, `URLCleaner`, `WindowSnapService`, `QuitOnLastWindowService`, `AppRemovalPlanner`, `CleanerService`, `QuickToggleEngine`, `KeyGuardService`, `HyperkeyService`, `RadialDialPanelController`, `FocusFollowService`, `ScrollReverserMonitor`, `GestureDispatcher`, `SpaceTransitionController`, `AudioOutputSwitcher`).

### Behavior-Frozen Files (Strictly Untouched Across All Tiers)
Per `STANDING_RULES.md` §2.3 and `CLAUDE.md`, the following 5 files **must remain untouched** across every slice in Tiers 1–4:
1. `App/Composition/WindowLiftAvoidanceController.swift`
2. `Platform/AppTracking/AppTracker.swift`
3. `App/Composition/DragController.swift`
4. `Platform/Accessibility/AccessibilitySource.swift`
5. `Platform/CoreGraphics/FullscreenIntentMonitor.swift`

---

## 1. Live Progress Tracker

### Tier 1 — Easiest (`S`: ≤1–2 days per slice, existing engines/models)
- [x] **Slice T1.1** — Nested Battery Pill (`[ 87% ]`), Dynamic Battery Symbol Fix & Retina Menu Bar Polish (#20) *(DONE 2026-11-24)*
- [ ] **Slice T1.2** — Unified Clean URL Pasteboard Poll & Per-Event Clipboard Audio Cues (#12, #24a)
- [ ] **Slice T1.3** — Text Snippet Clipboard Restore & `ignoreNextCopy` Guard (#24b)
- [ ] **Slice T1.4** — Command X (`FinderKeyMap`) Focused Text-Field AX Guard & Cut-Pending Toast (#6)
- [ ] **Slice T1.5** — Snap Outer Border Padding, Inner Gaps & Dock Clearance Parity (#15)
- [ ] **Slice T1.6** — Quitter Per-App Idle Timeouts & Standalone Per-App Rules (#11)
- [ ] **Slice T1.7** — Fast Vision OCR Mode + OCR / Window / Color Picker / Quick-Toggle Shortcuts & Shelf Auto-Stash (#19, #24c–e)
- [ ] **Slice T1.8** — OnlySwitch Screen Test & Clean Mode (Multi-Display R/G/B/W/K/Gray Cycler + Cleaning Lock) (#19)

### Tier 2 — Medium (`M`: multi-surface wiring, UX controls, or `Info.plist` Services)
- [ ] **Slice T2.1a / T2.1b** — Rectangle-Style Keyboard Snap Layout Cycling & Shared-Key Cycle Groups (#13)
- [ ] **Slice T2.2a / T2.2b** — Dock Hover Media Transport Controls & Opt-In Pinned Folder Hover Preview (#3)
- [ ] **Slice T2.3a / T2.3b** — Right-Click `"Uninstall with KatiKati"` (`NSServices` in `Info.plist`) & Unified App + Leftover Checklist (#18)
- [ ] **Slice T2.4a / T2.4b** — Focus App Blocker / Throttler (Pause-Style Mindful Activation Curtain) (#22)
- [ ] **Slice T2.5a / T2.5b** — Menuist-Style Menu Bar Quick-Path Browser & Fast `FileMover` Actions (#7)
- [ ] **Slice T2.6** — Mission Control / App Exposé / Show Desktop Trigger Hooks & Instant Overlay Wake (#23)

### Tier 3 — Hard (`L`: `CGEventTap` / AX dwell engines & multi-layer input routing)
- [ ] **Slice T3.1a / T3.1b** — AutoRaise Dwell Delay, Per-App Ignore List, Modifier Bypass & Focus-Only Mode (#17)
- [ ] **Slice T3.2a / T3.2b** — LinearMouse Smooth Scroll Interpolation, Speed Curves & Per-Axis Toggle (#1)
- [ ] **Slice T3.3a / T3.3b** — Mac Mouse Fix Global Extra Mouse Button (3/4/5) Remapper & Drag Gestures (#2)
- [ ] **Slice T3.4a / T3.4b** — Hyperkey Multi-Layered Chord Layers (HUD Legend) & Multi-Step Macro Sequencer (#14)
- [ ] **Slice T3.5a / T3.5b** — Kando Marking-Menu Drag-Through Trails, Custom Actions & Per-App Radial Profiles (#10)

### Tier 4 — Hardest (`XL`: continuous Multitouch scrubbing & CoreAudio Process Taps)
- [ ] **Slice T4.1a / T4.1b** — Touch-Tab / Windowbunny Continuous 3-/4-Finger Trackpad App Switcher Scrubbing (#16)
- [ ] **Slice T4.2a / T4.2b / T4.2c** — Black Music App Per-App Volume Mixer & Isolated Output Routing (`AudioHardwareCreateProcessTap`) (#9)

---

## 2. Complete 24-Item Code-Grounded Status Matrix

**Audit Totals:** `4 Already Complete` (#4, #5, #8, #21 — plus #24c Color Picker) · `18 Partial / Needs Polish` (#1, #3, #6, #7, #10, #11, #12, #13, #14, #15, #16, #17, #18, #19, #20, #22, #23, #24) · `2 Missing` (#2, #9).

| # | Wishlist Item | Status | Existing Code Anchors (`file:line`) | Verified Gaps | Slice(s) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **LinearMouse** | `Partial / Needs Polish` | `Platform/CoreGraphics/ScrollReverserDecision.swift:5-47` (`ScrollWheelDeltas`, discrete-only `shouldReverse`), `Platform/CoreGraphics/ScrollReverserMonitor.swift:17-193` (dedicated `CGEventTap` + circuit breaker), `App/Entry/AppDelegate.swift:1294-1298, 1658-1665`, `App/Scenes/SettingsLayoutPane+Shortcuts.swift:426` | Lacks smooth scroll interpolation/momentum for notched mice, per-axis vertical/horizontal inversion, and scroll speed/acceleration curves | `T3.2` |
| **2** | **Mac Mouse Fix** | `Missing` | Reusable refs only: `App/Entry/RadialDialPanelController.swift:433-488` (buttons 2/3/4 for Radial Dial only), `App/Scenes/GestureMonitorInstaller.swift:44-47` (local dock middle-click) | No general global extra mouse button (3/4/5) remapper, click/double/hold/button+drag gesture recognizer, or swallowing `CGEventTap` | `T3.3` |
| **3** | **Dockdoor** | `Partial / Needs Polish` | `App/Entry/ChipPanelController.swift:10-250`, `App/Scenes/ChipPanel/ChipPanelView.swift:6-277` (live thumbnails, min/max/close hover actions, jump list), `App/Scenes/FolderGridPopupView.swift:8-250`, `Core/Support/NowPlayingService.swift`, `App/Scenes/NowPlayingPopup.swift` | (1) `ChipPanelView.previewBody` (`L42-61`) has no embedded media controls for active media apps; (2) `DockStripView.chipHoverRequest` (`App/Scenes/DockStripView+Hover.swift:119-125`) excludes `.pinnedFolder` chips from hover preview | `T2.2` |
| **4** | **AltTab / Altar** | `Already Complete` | `Core/Support/WindowSwitcherModel.swift:6-339` (5 styles: `.thumbnail`, `.list`, `.icons`, `.classicIcons`, `.carousel`; MRU + `WindowPredictiveRanker`; `NumberedWindowSwitcherModel` 1–9; `WindowFilterPolicy`), `App/Composition/WindowSwitcherController.swift:12-350`, `App/Composition/CommandTabTakeover.swift:9-78` (`⌘Tab` & `⌘\``) | Complete feature parity shipped (optional future polish: inline close/quit hover buttons on tiles) | `Complete` |
| **5** | **Swift Quit** | `Already Complete` | `Core/Support/QuitOnLastWindow.swift:4-66` (`QuitOnCloseMode`, `alwaysIgnored`, `clampDelay`), `App/Composition/QuitOnLastWindowService.swift:17-373` (event-driven `AXObserver` on window created/destroyed), `App/Scenes/SettingsLayoutPane+Shortcuts.swift:939-1030` (`QuitAppRulesTable`) | Complete; zero idle timers when idle-quit threshold is `0` | `Complete` |
| **6** | **Command X** | `Partial / Needs Polish` | `Core/Support/KeyGuard.swift:127-177` (`FinderKeyMap`: `⌘X`→`⌘C`, pending `⌘V`→`⌘⌥V`), `App/Composition/KeyGuardService.swift:92, 356-361, 440` | Documented `shortcut:` (`KeyGuard.swift:130-131`): rewrites `⌘X`/`⌘V` inside Finder rename/search text fields; lacks AX focused-role check & optional cut-pending feedback | `T1.4` |
| **7** | **Menuist** | `Partial / Needs Polish` | `App/Composition/DriveMenuBarItem.swift:7-129` (mounted drive menu bar + Eject), `App/Composition/FileMover.swift:38-121` (atomic cross-volume move/copy), `App/Composition/FileItemMenuBuilder.swift:13-141`, `Core/Support/FolderContentsLoader.swift`, `Platform/Finder/FinderWindowContentsReader.swift` | No menu bar favorite-folder navigator with cascading submenus, "Move Finder Selection Here" fast path, New File, or Open in Terminal | `T2.5` |
| **8** | **Dropover** | `Already Complete` | `App/Composition/DragShakeWatcher.swift:14-167` (`ShelfDropTargetPanel` on drag shake), `Core/Support/ShakeDetector.swift`, `App/Composition/ShelfStore.swift`, `App/Composition/ShelfActions.swift` (Vision cutout, PDF merge/reduce, convert, ZIP), `App/Scenes/ShelfGridPopupView.swift` | Complete (`DragShakeWatcher` runs a 5 Hz `pressedMouseButtons` check with zero IPC while button is up, gated on Shake-to-Shelf) | `Complete` |
| **9** | **Black Music App** | `Missing` | Reusable: `Platform/SystemStatus/AudioOutputSwitcher.swift:13-94` (global default output/input switcher only), `Platform/SystemStatus/PrivacyUseProbe.swift` | Zero per-app volume/mute mixer or per-app audio output routing; requires macOS 14.2+ CoreAudio Process Taps (`AudioHardwareCreateProcessTap`) | `T4.2` |
| **10** | **Kando** | `Partial / Needs Polish` | `Core/Support/RadialDialModel.swift:5-217` (recursive `RadialSliceNode` tree, 4 themes, `tapToggle`/`holdRelease`/`hotkeyHold`, mouse + trackpad edge triggers), `Core/Support/RadialDialGeometry.swift`, `Core/Support/RadialDialPresets.swift`, `App/Entry/RadialDialPanelController.swift:7-489`, `App/Scenes/SettingsLayoutPane+Shortcuts.swift:742-835` | (1) `RadialDialActionType.custom` is a no-op (`RadialDialPanelController.swift:378-379`); (2) no continuous marking-menu drag-through gesture trails across submenus; (3) no per-app contextual radial profiles | `T3.5` |
| **11** | **Quitter** | `Partial / Needs Polish` | `Core/Support/QuitOnLastWindow.swift:223-320` (`IdleAppAction` `.off`/`.notify`/`.hide`/`.quit`/`.keep`, `IdleAppAutoQuitPolicy`, media/agent guards), `App/Composition/QuitOnLastWindowService.swift:46-52, 90-100, 166-259`, `App/Composition/IdleAppNotifier.swift`, `App/Scenes/SettingsLayoutPane+Shortcuts.swift:1022-1030` | Single global `idleThresholdSeconds` only (no per-app timeout minutes); setting global threshold `0` disables per-app `.hide`/`.quit` overrides | `T1.6` |
| **12** | **Clipboard Audio Cues** | `Partial / Needs Polish` | `Platform/Clipboard/ClipboardMonitor.swift:9, 86-89, 170` (`com.katikati.clipboard.sounds`, plays `"Tink"` on external Copy, `"Pop"` on `pastePlain`/global `⌘V`), `App/Entry/AppDelegate.swift:695-697` | Single boolean only: no per-event toggles (Copy / Paste / History Updated / Link Cleaned), no sound preset/volume picker, and flyout `copy(_:)` (`L51-56`) is silent | `T1.2` |
| **13** | **Shortcut Layout Cycling (Rectangle)** | `Partial / Needs Polish` | `Core/Support/KeyGuard.swift:750-788` (`SnapWidthCycle` `half→third→twoThirds` + `SnapCycleState` for trackpad), `Platform/Windows/WindowSnapService.swift:14-48` (`apply(.maximize)` toggles restore) | Keyboard snap hotkeys do not cycle on repeat press; `ShortcutValidator.check` (`Core/Support/Shortcuts.swift:515-517`), `ShortcutConflictDetector` (`L753-776`), and `ShortcutService.apply` (`App/Composition/ShortcutService.swift:34-51`) treat shared keys as duplicates | `T2.1` |
| **14** | **Hyperkey & Macro Engine** | `Partial / Needs Polish` | `Core/Support/HyperkeyEngine.swift:8-181`, `App/Composition/HyperkeyService.swift:14-274` (CapsLock/R⌘/R⌥ → F18 via `hidutil`, Hyper/Superkey, tap-if-alone `Esc`/`CapsLock`, `forwardToSystem`, per-app exclusions), `Core/Support/Shortcuts.swift:780-800` | No multi-layer chord sub-layers with HUD legend, no multi-step macro sequencer, and no mouse gesture profiles (paired with `T3.3`) | `T3.4` |
| **15** | **Dock Awareness & Outer Border Padding** | `Partial / Needs Polish` | `Core/Support/TilingGaps.swift:4-42` (`TilingGaps(inner, outer)`, `DockReserve.workArea`), `App/Entry/AppDelegate.swift:1216-1222` (wires `dockFrame` to `TilingEngine` & `WindowSnapService`), `Core/Support/TilingLayout.swift:155-251` | `WindowSnapService.apply(_:)` (`Platform/Windows/WindowSnapService.swift:27-28`) & `SnapDragMonitor.dragged()` (`L230-237`) respect `DockReserve` but apply `0pt` outer padding and `0pt` inner gaps (`SnapPosition.frame(in:)` at `Core/Support/WindowSnap.swift:33-39`) | `T1.5` |
| **16** | **3-/4-Finger Trackpad App Switcher** | `Partial / Needs Polish` | `Core/Support/PinchGesture.swift:5-227`, `Platform/Pinboard/MultitouchPinchMonitor.swift:7-66`, `Core/Support/KeyGuard.swift:513-800`, `App/Composition/KeyGuardService.swift:1066-1343`, `App/Composition/WindowSwitcherController.swift:84-87` (`show()`) | `GestureClassificationReducer` only fires a one-shot swipe (`firedInCurrentTouch = true` at `PinchGesture.swift:160`) to open a pinned switcher; no continuous live scrubbing while fingers stay on pad + lift-to-commit | `T4.1` |
| **17** | **AutoRaise (Focus-Follows-Mouse)** | `Partial / Needs Polish` | `Core/Support/FocusFollowPolicy.swift:6-19`, `App/Composition/FocusFollowService.swift:8-102`, `App/Entry/AppDelegate.swift:626`, `App/Scenes/SettingsLayoutPane+Shortcuts.swift:418`, `App/Scenes/SettingsTilingPane.swift:209` | Raises immediately on mouse-move (`minimumInterval = 0.12s` cooldown only); lacks configurable hover dwell delay, per-app ignore list, modifier-hold bypass, and focus-only vs. focus+raise | `T3.1` |
| **18** | **Right-Click Uninstaller** | `Partial / Needs Polish` | `Core/Support/AppRemoval.swift:4-56` (`AppRemovalPlanner`), `Core/Support/StorageScanMath.swift` (`AppLeftoverScanPlan`), `App/Composition/AppRemovalService.swift:6-44`, `App/Composition/CleanerService.swift:53-106`, `App/Scenes/Notch/NotchStoragePageView.swift` | (1) No `NSServices` in `Resources/Info.plist` / `servicesProvider` in `AppDelegate` for Finder right-click; (2) `AppRemovalPlanner.plan` (`L28-33`) separates `.uninstall` and `.deleteData` instead of one combined review checklist with sizes | `T2.3` |
| **19** | **OnlySwitch Toggles & Screen Clean Mode** | `Partial / Needs Polish` | `Core/Support/QuickToggles.swift:4-64` + `Platform/Pinboard/QuickToggleEngine.swift:12-338` (18 toggles incl. `.hideDesktopIcons` `L100, 134`), `Core/Support/DailyHelpersRules.swift:63-89` (`CleaningLock`), `App/Composition/KeyGuardService.swift:138-207` (`startCleaningLock`) | Lacks full-screen solid R/G/B/W/K/Gray Screen Test & Clean Mode cycler (paired with keyboard lock), and lacks `ShortcutAction` bindings for individual quick toggles | `T1.7`, `T1.8` |
| **20** | **Menu Bar Polish & Nested Battery Pill** | `Partial / Needs Polish` | `Core/Support/MenuBarStatModel.swift:7-185`, `App/Composition/MenuBarSystemItem.swift:9-163`, `App/Entry/StatusMenuController.swift:564-599` | (1) No `.nestedPill` (`[ 87% ]` in Green/Yellow/Red battery shell); (2) Bug at `MenuBarSystemItem.swift:92-93`: `.percentage`/`.remainingTime`/`.watts` uses static `symbolName(metric: .battery)` (`"battery.75"`) instead of dynamic `batterySymbol`; (3) `barImage`/`pieImage` (`L132-162`) use fractional `y: 5.5` rects | `T1.1` |
| **21** | **Slow Quit** | `Already Complete` | `Core/Support/KeyGuard.swift:33-49, 81-125, 183-198, 252-297`, `App/Composition/KeyGuardService.swift:43-63, 209-266, 538-606`, `App/Scenes/SlowQuitOverlay.swift:8-152`, `App/Scenes/SettingsLayoutPane+Shortcuts.swift:939-1030` | Complete: hold (`0.2–5.0s`) & double-tap `⌘Q`, Ring/Bar HUDs, allow/deny & passthrough lists, Secure Input bypass, Esc cancel. *(Note: `quitKeyCode = 12` at `KeyGuard.swift:84` is US-layout-specific.)* | `Complete` |
| **22** | **Focus Timer / App Throttler (Pause)** | `Partial / Needs Polish` | `App/Composition/CalendarService.swift:239-260` (`FocusTimerController`), `Core/Support/ScreenTime.swift:133-193`, `Platform/ScreenTime/ScreenTimeController.swift:9-130`, `App/Entry/ScreenTimeAlertPresenter.swift:7-82`, `App/Composition/DailyHelpersService.swift:102-126` | Focus timer and Screen Time limits are advisory only (`ScreenTimeAlertPresenter` banner); cannot block, auto-hide, or show a Pause-style mindful delay curtain on distracting app launch/activation | `T2.4` |
| **23** | **Mission Control Integration** | `Partial / Needs Polish` | `Core/Support/SpaceSwitchPlan.swift:1-1276` (complete OpenMissionControl color/badge/hover/filter/space-naming model), `App/Entry/PanelCoordinator+Spaces.swift:100-658` (`MissionControlSession`), `App/Composition/SpaceTransitionController.swift:17-186`, `Platform/CoreGraphics/DockSwipeEventPoster.swift:12-179` | Lacks `ShortcutAction`, `GestureActionTarget`, and `RadialDialActionType` trigger hooks to invoke Mission Control / App Exposé / Show Desktop directly and wake `MissionControlSession.shared.refresh()` immediately | `T2.6` |
| **24a** | **Clean URL** | `Partial / Needs Polish` | `Core/Support/URLCleaner.swift:11-42`, `App/Composition/LinkCleanerService.swift:7-41`, `Core/Support/ClipboardPlus.swift:146` (`ClipboardToastBadge`) | Runs a duplicate 0.7s pasteboard poll alongside `ClipboardMonitor` (`Platform/Clipboard/ClipboardMonitor.swift:117`) and doesn't emit `linkCleaned: true` toast/cue | `T1.2` |
| **24b** | **Text Snippets** | `Partial / Needs Polish` | `Core/Support/CustomCommands.swift:64-249` (`TextSnippetItem`, `SnippetVariableExpander`, `SnippetExpander`), `App/Composition/KeyGuardService.swift:612-640` (`insertSnippet`) | `insertSnippet` overwrites `NSPasteboard.general` without restoring `priorClipboard` after paste or calling `ignoreNextCopy()` on `ClipboardMonitor` | `T1.3` |
| **24c** | **Color Picker** | `Already Complete` | `App/Composition/ColorPickerService.swift:6-28` (`NSColorSampler`), `Core/Support/ColorFormat.swift` | Complete (`NSColorSampler`, zero permissions, copies `#RRGGBB` + toast; optional `ShortcutAction.pickColor` bundled in `T1.7`) | `Complete` (`T1.7` shortcut) |
| **24d** | **Fast Vision OCR** | `Partial / Needs Polish` | `Platform/Capture/CaptureController.swift:8-73`, `Core/Support/CaptureRules.swift:6-42` | Hardcodes `.accurate` + all `Locale.preferredLanguages` + unconditional barcode scan + PNG temp file roundtrip; lacks direct `ShortcutAction.captureOCR` to clipboard | `T1.7` |
| **24e** | **Screenshot Workflow** | `Partial / Needs Polish` | `Platform/Capture/CaptureController.swift:43-44` (`captureAreaToClipboard`, `captureWindowToClipboard`), `Platform/Clipboard/ClipboardMonitor.swift:180-244` (`ClipboardImagePaster`) | Missing `ShortcutAction.captureWindow` and optional auto-stash of captured screenshots onto the Shelf (`ShelfStore`) | `T1.7` |

---

## 3. Easiest → Hardest Implementation Roadmap (Tiers 1–4)

### Tier 1 — Easiest (`S`)

#### [x] DONE (2026-11-24) · Slice T1.1 — Nested Battery Pill (`[ 87% ]`), Dynamic Battery Symbol Fix & Retina Menu Bar Polish (#20)
- **Effort:** `S` | **Covers:** #20 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` at rest (only updates on existing 1 Hz `SystemMonitorController` subscription when menu bar stats are enabled)
- **Files to Touch:**
  - `Core/Support/MenuBarStatModel.swift:12-16, 69-133, 166-177`
  - `App/Composition/MenuBarSystemItem.swift:74-162`
  - `Tests/Unit/MenuBarStatModelTests.swift`
  - `Resources/Localizable.xcstrings` (12 locales for `"Battery Pill"` style label)
- **Atomic Scope (`<= 140` lines):**
  - [ ] Add `.nestedPill` to `MenuBarMetricStyle` (`Core/Support/MenuBarStatModel.swift:12-16`), expose it in `styles(for: .battery)` (`L86`), add localized `"Battery Pill"` display name (`L69-80`), and add a pure `MenuBarStatModel.batteryPillColor(for:)` threshold helper (`>= 50%` green, `20–49%` yellow, `< 20%` red, charging tint) returning empty `statusText` (`L120`) so the button draws image-only.
  - [ ] Fix bug in `MenuBarSystemItem.image(metric:style:values:)` (`App/Composition/MenuBarSystemItem.swift:92-93`) so `metric == .battery` uses `MenuBarStatModel.batterySymbol(values.battery)` across `.percentage`/`.remainingTime`/`.watts` instead of static `"battery.75"`.
  - [ ] Render crisp Retina-aligned `nestedPillImage(_ battery:)` (`NSImage` with integer/half-point Retina backing, `isTemplate = false`, dynamic Green/Yellow/Red outer battery shell with terminal nub + embedded monospaced `87%` label + subtle bolt glyph when charging), and snap `barImage` / `pieImage` (`L132-162`) coordinates to integer/0.5pt bounds.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/MenuBarStatModelTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.2 — Unified Clean URL Pasteboard Poll & Per-Event Clipboard Audio Cues (#12, #24a)
- **Effort:** `S` | **Covers:** #12, #24a | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** **Reduces** idle timers (`-1` 0.7s pasteboard timer)
- **Files to Touch:**
  - `Core/Support/ClipboardPlus.swift` (audio cue event/preset model + `ClipboardToastBadge.badge(for:linkCleaned: true)`)
  - `Platform/Clipboard/ClipboardMonitor.swift:8-13, 50-89, 148-175`
  - `App/Composition/LinkCleanerService.swift:7-41` & `App/Entry/AppDelegate.swift` (fold link cleaning into `ClipboardMonitor.poll()` when enabled; retain standalone fallback only when clipboard recording is off)
  - `App/Scenes/UtilitySettingsBlock.swift` (per-event sound toggles + cue sound selector)
  - `Tests/Unit/URLCleanerTests.swift`, `Tests/Unit/ClipboardHistoryTests.swift`, `Tests/Unit/ClipboardCardMetadataTests.swift`, `Tests/Unit/MaccyClipboardTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 180` lines):**
  - [ ] Add pure `ClipboardAudioCue` (`onCopy`, `onPaste`, `onHistoryUpdated`, `onLinkCleaned`) and sound preset enum (`systemTinkPop`, `subtleClick`, `softChime`, `silent`) in `Core/Support/ClipboardPlus.swift` with unit tests.
  - [ ] Fold `URLCleaner.clean` into `ClipboardMonitor.poll()` (`Platform/Clipboard/ClipboardMonitor.swift:148-172`) when `LinkCleanerService` is enabled so only one `changeCount` poll runs, rewrite pasteboard before storing, play the `onLinkCleaned` cue, and emit `linkCleaned: true` to `onRecorded` / `ClipboardToastBadge`.
  - [ ] Play configured `onCopy` / `onHistoryUpdated` / `onPaste` cues in `ClipboardMonitor.copy(_:)`, `poll()`, `pastePlain(_:)`, and `handleExternalPaste()`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/URLCleanerTests -only-testing:KatiKatiTests/ClipboardHistoryTests -only-testing:KatiKatiTests/ClipboardCardMetadataTests -only-testing:KatiKatiTests/MaccyClipboardTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.3 — Text Snippet Clipboard Restore & `ignoreNextCopy` Guard (#24b)
- **Effort:** `S` | **Covers:** #24b | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz`
- **Files to Touch:**
  - `Core/Support/CustomCommands.swift` (pure restore-eligibility helper if needed)
  - `App/Composition/KeyGuardService.swift:612-640` (`insertSnippet`)
  - `App/Entry/AppDelegate.swift` (wire `ClipboardMonitor.ignoreNextCopy()` callback onto `KeyGuardService`)
  - `Tests/Unit/KeyGuardTests.swift` (`SnippetExpanderTests`)
- **Atomic Scope (`<= 90` lines):**
  - [ ] Snapshot existing `NSPasteboard.general` items/string (`priorClipboard`) before writing the expanded snippet in `KeyGuardService.insertSnippet` (`L614-618`).
  - [ ] Call `onBeforeSnippetPaste?()` (wired to `ProductivityServices.shared.clipboard.ignoreNextCopy()`) so snippet paste never pollutes `ClipboardHistory` or triggers a false `onRecorded` toast/sound.
  - [ ] After `postCommandV()` (and optional `cursorLeftArrows`) completes (~150 ms settle), restore `priorClipboard` only if `pasteboard.changeCount == ours`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/SnippetExpanderTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.4 — Command X (`FinderKeyMap`) Focused Text-Field AX Guard & Cut-Pending Toast (#6)
- **Effort:** `S` | **Covers:** #6 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (runs only on `⌘X` keyDown inside Finder)
- **Files to Touch:**
  - `Core/Support/KeyGuard.swift:127-177` (`FinderKeyMap` + `isEditingText` guard parameter)
  - `App/Composition/KeyGuardService.swift:697-1053` (`KeyGuardShared` callback path; read `AXIsProcessTrusted()` + `kAXFocusedUIElementAttribute` role `AXTextField`/`AXTextArea`/`AXSearchField`/`AXComboBox` only when `finderKeysActive && code == FinderKeyMap.cutKey`)
  - `Tests/Unit/KeyGuardTests.swift` (`FinderKeyMapTests`)
- **Atomic Scope (`<= 110` lines):**
  - [ ] Pay the documented `shortcut:` at `Core/Support/KeyGuard.swift:130-131`: pass `isTextInputFocused: Bool` into `FinderKeyMap.handle(_:isTextInputFocused:)` so `⌘X` / `⌘V` inside Finder rename, Get Info, or search fields passes through as normal text cut/paste.
  - [ ] Query the focused AX element's role (`kAXFocusedUIElementAttribute` → `kAXRoleAttribute`) strictly on `keyDown` for `⌘X`/`⌘V` when `finderKeysActive` is true (never on every keystroke).
  - [ ] Optionally fire a subtle non-intrusive cut-pending callback (`"Cut for Move"`) via `ShortcutToastPresenter` when `FinderKeyMap` arms `cutPending`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/FinderKeyMapTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.5 — Snap Outer Border Padding, Inner Gaps & Dock Clearance Parity (#15)
- **Effort:** `S` | **Covers:** #15 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz`
- **Files to Touch:**
  - `Core/Support/WindowSnap.swift:32-45, 88-105` (`SnapPosition.frame(in:outerPadding:innerGap:)` and `SnapZonePlanner.previewFrame`)
  - `Platform/Windows/WindowSnapService.swift:14-48, 230-243`
  - `App/Scenes/SettingsTilingPane.swift` (share or add Snap Padding slider backed by `com.katikati.snap.outerPadding` / `innerGap` or reuse `TilingGaps` toggle `"Match Tiling Gaps"`)
  - `Tests/Unit/WindowSnapTests.swift`, `Tests/Unit/TilingLayoutTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 150` lines):**
  - [ ] Extend `SnapPosition.frame(in:)` (`Core/Support/WindowSnap.swift:33-39`) with pure `outerPadding: CGFloat = 0` and `innerGap: CGFloat = 0` parameters: inset `visible` by `outerPadding` on all four sides (staying clear of `DockReserve.workArea` for left/right/bottom/top Docks) and inset shared split edges by `innerGap / 2`.
  - [ ] Pass stored outer padding / inner gap into both `WindowSnapService.apply(_:)` (`L27-28`) and `SnapDragMonitor.dragged()` (`L230-237`) so ghost snap previews match landed window frames pixel-for-pixel.
  - [ ] Keep `0pt` default padding so existing behavior and tests remain unchanged unless configured.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/WindowSnapTests -only-testing:KatiKatiTests/TilingLayoutTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.6 — Quitter Per-App Idle Timeouts & Standalone Per-App Rules (#11)
- **Effort:** `S` | **Covers:** #11 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` when both global threshold and per-app map are empty
- **Files to Touch:**
  - `Core/Support/QuitOnLastWindow.swift:223-320` (`IdleAppAutoQuitPolicy`, `IdleAppRule` with per-app `action` + optional `thresholdMinutes: Int?`)
  - `App/Composition/QuitOnLastWindowService.swift:90-100, 186-259`
  - `App/Scenes/SettingsLayoutPane+Shortcuts.swift:1022-1030` (per-app idle timeout picker alongside Keep/Notify/Hide/Quit)
  - `Tests/Unit/WindowSnapTests.swift` (`QuitOnLastWindowPolicyTests`, `QuitAppRulesTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 160` lines):**
  - [ ] Add optional per-app `thresholdSeconds` parsing (`bundleID=action:minutes`, backward-compatible with `bundleID=action`) in `IdleAppAutoQuitPolicy` (`Core/Support/QuitOnLastWindow.swift:301-319`).
  - [ ] Fix `QuitOnLastWindowService.updateIdleTimer()` (`L90-100`) and `evaluateIdleApps` (`L215`) so the 60s timer runs if `idleThresholdSeconds > 0 || !perAppActions.isEmpty`, allowing users to auto-hide/auto-quit specific noisy apps (e.g., Slack/Xcode/Safari) without setting a global timer on every app.
  - [ ] Add a compact per-app idle delay submenu (`Global Default`, `5m`, `15m`, `30m`, `60m`) in `QuitAppRulesTable` (`App/Scenes/SettingsLayoutPane+Shortcuts.swift:1022-1030`).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/QuitOnLastWindowPolicyTests -only-testing:KatiKatiTests/QuitAppRulesTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.7 — Fast Vision OCR Mode + OCR / Window / Color Picker / Quick-Toggle Shortcuts & Shelf Auto-Stash (#19, #24c–e)
- **Effort:** `S` | **Covers:** #19, #24c, #24d, #24e | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz`
- **Files to Touch:**
  - `Core/Support/CaptureRules.swift` (pure `OCRSpeedMode` `.fast`/`.accurate` + `CaptureDestination` prefs)
  - `Core/Support/Shortcuts.swift:5-239, 691-723` (add `.captureWindow`, `.captureOCR`, `.pickColor`, `.toggleHideDesktopIcons`)
  - `Platform/Capture/CaptureController.swift:22-73` (skip barcode request when OCR-only, support `.fast` `VNRecognizeTextRequest` + `CGImage` direct handoff without PNG re-encode where possible)
  - `App/Composition/BarActionService.swift` & `App/Entry/AppDelegate.swift` (wire new `ShortcutAction` cases)
  - `Tests/Unit/CaptureRulesTests.swift`, `Tests/Unit/CaptureRecognitionTests.swift`, `Tests/Unit/ShortcutsTests.swift`, `Tests/Unit/ColorFormatTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 220` lines):**
  - [ ] Add `CaptureOCRSpeed` (`.fast` vs `.accurate`, default `.fast` for instant clipboard OCR; keep `.accurate` option) and skip `VNDetectBarcodesRequest` in quick-OCR mode so `CaptureController.recognise` finishes in minimal latency.
  - [ ] Add `ShortcutAction.captureWindow`, `.captureOCR` (select region → copy recognized text + toast), `.pickColor` (`ColorPickerService.pick()`), and `.toggleHideDesktopIcons` (`QuickToggleEngine.shared.perform(.hideDesktopIcons)`), all defaulting to `.off`.
  - [ ] Add an opt-in `"Add Screenshots to Shelf"` toggle in `CaptureController` / `ShelfStore` when interactive screenshot saves a file.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/CaptureRulesTests -only-testing:KatiKatiTests/CaptureRecognitionTests -only-testing:KatiKatiTests/ShortcutsTests -only-testing:KatiKatiTests/ColorFormatTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T1.8 — OnlySwitch Screen Test & Clean Mode (Multi-Display R/G/B/W/K/Gray Cycler + Cleaning Lock) (#19)
- **Effort:** `S` | **Covers:** #19 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` when closed (reuses `KeyGuardService.startCleaningLock` only while active)
- **Files to Touch:**
  - `Core/Support/QuickToggles.swift` (pure `ScreenTestColor` cycle model: black → white → red → green → blue → gray, plus optional `.screenTest` / `.screenClean` helper entry)
  - `Core/Support/DailyHelpersRules.swift:63-89` (pair `CleaningLock` duration with screen clean mode)
  - `App/Scenes/KeyVisualizerOverlay.swift` or `App/Scenes/SlowQuitOverlay.swift` / `App/Entry/ScreenIdentifyOverlayController.swift` (host full-screen `.screenSaver` / `.mainMenu + 1` borderless panels across `NSScreen.screens`, click/Space/Arrow to cycle, Esc or `⌃⌥⌘P` to exit)
  - `App/Scenes/UtilitySettingsBlock.swift` & `App/Composition/BarActionService.swift`
  - `Tests/Unit/QuickTogglesTests.swift`, `Tests/Unit/DailyHelpersRulesTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 210` lines):**
  - [ ] Add pure `ScreenCleanModeModel` (`ColorStep` sequence: Black, White, Red, Green, Blue, Dark Gray; `next()`, `previous()`, subtle HUD hint visibility toggle) in `Core/Support/QuickToggles.swift`.
  - [ ] Present one borderless `NSWindow` per `NSScreen` (covering notch/menu bar area for true dead-pixel & smudge inspection), optionally calling `KeyGuardService.shared.startCleaningLock(seconds:)` when launched in **Clean Screen** mode (keyboard locked while wiping; Esc exits **Test Mode**, `⌃⌥⌘P` or timer unlocks **Clean Mode**).
  - [ ] Expose entry points in Control Center / Command Bar (`screen test`, `clean screen`) and `UtilitySettingsBlock`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/QuickTogglesTests -only-testing:KatiKatiTests/DailyHelpersRulesTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

---

### Tier 2 — Medium (`M`)

#### [ ] Slice T2.1 — Rectangle-Style Keyboard Snap Layout Cycling & Shared-Key Cycle Groups (#13)
- **Effort:** `M` | **Covers:** #13 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz`
- **Split:** `T2.1a` (Core cycling + conflict model, `<= 180` lines) → `T2.1b` (`ShortcutService` + `WindowSnapService` + Settings UI, `<= 180` lines)
- **Files to Touch:**
  - `Core/Support/WindowSnap.swift` (per-action cycle sequence: e.g., `.leftHalf → .leftTwoThirds → .leftThird`, `.rightHalf → .rightTwoThirds → .rightThird`, `.center → .maximize`, `.topHalf → .topLeft → .topRight`, etc.)
  - `Core/Support/Shortcuts.swift:510-527, 753-776` (allow-list or cycle-group exemption so snap actions sharing a key or repeating a snap key don't raise `.warn("Already used by ...")` / `.internalDuplicate` when `snapCyclingEnabled`)
  - `Platform/Windows/WindowSnapService.swift:14-48` (detect if focused window's current frame already matches `position.frame` within tolerance; if so, advance `SnapCycleState` / cycle sequence)
  - `App/Composition/ShortcutService.swift:34-51` & `App/Scenes/SettingsLayoutPane+Shortcuts.swift`
  - `Tests/Unit/WindowSnapTests.swift`, `Tests/Unit/ShortcutsTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T2.1a:** Add pure `SnapActionCyclePlanner.nextPosition(for:currentFrame:workArea:windowID:lastCycle:now:)` in `Core/Support/WindowSnap.swift`, and add `ShortcutCycleGroup` support in `ShortcutValidator` / `ShortcutConflictDetector` (`Core/Support/Shortcuts.swift`) so multiple snap zones bound to the same `ShortcutTrigger` form an ordered cycle rather than a conflict error.
  - [ ] **T2.1b:** Wire `WindowSnapService.apply(_:cycling:)` (`Platform/Windows/WindowSnapService.swift`), deduplicate Carbon `GlobalHotKeyMonitor` registration per physical `ShortcutKey` in `ShortcutService.apply` (`App/Composition/ShortcutService.swift`) so repeated presses cycle through all bound actions for that trigger, and add a `"Cycle Snap Widths on Repeat"` toggle in `SettingsTilingPane` / `SettingsLayoutPane+Shortcuts`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/WindowSnapTests -only-testing:KatiKatiTests/ShortcutsTests -only-testing:KatiKatiTests/ShortcutRedesignCoreTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T2.2 — Dock Hover Media Transport Controls & Opt-In Pinned Folder Hover Preview (#3)
- **Effort:** `M` | **Covers:** #3 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` at rest (`ChipPanelController.pollTimer` runs only while hovered/visible)
- **Split:** `T2.2a` (Hover media controls in `ChipPanelView`, `<= 160` lines) → `T2.2b` (Opt-in pinned folder hover preview, `<= 180` lines)
- **Files to Touch:**
  - `Core/Support/ChipPanelLayout.swift` & `App/Scenes/ChipPanel/ChipPanelModel.swift`
  - `App/Scenes/ChipPanel/ChipPanelView.swift:42-61, 208-277`
  - `App/Entry/ChipPanelController.swift:179-191` & `App/Entry/PanelCoordinator+ChipPanel.swift`
  - `App/Scenes/DockStripView+Hover.swift:119-125` (`chipHoverRequest`) & `App/Scenes/BehaviourSettingsBlock.swift`
  - `Tests/Unit/ChipPanelTests.swift` (`ChipPanelHoverMachineTests`, `ChipPanelLayoutTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T2.2a:** When hovering a chip whose `bundleIdentifier` matches `NowPlayingService` active player (Spotify, Apple Music, or browser media session), render a compact transport strip (artwork/track title + Previous / Play-Pause / Next buttons) at the bottom of `ChipPanelView.previewBody`, accounted for in `ChipPanelLayout` height math so the panel frame never clips.
  - [ ] **T2.2b:** Behind an opt-in `"Hover to Preview Pinned Folders"` toggle, allow `DockStripView.chipHoverRequest` (`L119-125`) to report `.pinnedFolder(path)` chips so `ChipPanelController` displays a compact read-only preview grid (top 6–8 items via existing `FolderContentsLoader` + `FolderIconResolver`) without opening the full editable popup until clicked.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/ChipPanelHoverMachineTests -only-testing:KatiKatiTests/ChipPanelLayoutTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T2.3 — Right-Click `"Uninstall with KatiKati"` (`NSServices`) & Unified App + Leftover Checklist (#18)
- **Effort:** `M` | **Covers:** #18 | **`project.pbxproj` Impact:** None (uses `Resources/Info.plist` `NSServices`, **not** a separate `.appex` target) | **Idle CPU Impact:** `0 Hz`
- **Split:** `T2.3a` (Core unified `AppRemovalPlanner` + leftover size aggregation, `<= 150` lines) → `T2.3b` (`Info.plist` `NSServices` + `AppDelegate.servicesProvider` + review sheet UI, `<= 220` lines)
- **Files to Touch:**
  - `Core/Support/AppRemoval.swift:4-56` (`AppRemoval.uninstallWithData` + grouped `AppRemovalPlan` items with categories & byte sizes)
  - `Core/Support/StorageScanMath.swift` (`AppLeftoverScanPlan`)
  - `App/Composition/AppRemovalService.swift:6-44` & `App/Composition/CleanerService.swift:53-86`
  - `Resources/Info.plist` (add `NSServices` dict accepting `public.application-bundle` / `NSFilenamesPboardType` for `"Uninstall with KatiKati"`)
  - `App/Entry/AppDelegate.swift` (register `NSApp.servicesProvider` handler receiving selected `.app` URLs)
  - `App/Scenes/Notch/NotchStoragePageView.swift` (reuse review-first leftover checklist sheet)
  - `Tests/Unit/AppRemovalPlannerTests.swift`, `Tests/Unit/StorageScanMathTests.swift` (`AppLeftoverScanPlanTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T2.3a:** Extend `AppRemovalPlanner` (`Core/Support/AppRemoval.swift:24-55`) with `.uninstallWithData` combining `[appPath]` + `AppLeftoverScanPlan.candidatePaths` while protecting system/Apple bundles (`AppLeftoverScanPlan.isProtected`) and KatiKati itself.
  - [ ] **T2.3b:** Add `NSServices` entry in `Resources/Info.plist` (`NSSendTypes` = `NSFilenamesPboardType` / `NSRequiredContext` = `NSTextContent` / `NSApplicationBundle` file filter) + `@objc func uninstallWithKatiKati(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>)` on a `servicesProvider` registered in `AppDelegate`, launching a review-first modal checklist showing `.app` + each `~/Library` item's byte size with per-item checkboxes and `Move to Trash` (`FileManager.default.trashItem`, never `unlink`).
- **Architecture Note (`pbxproj` Tradeoff):** Using `NSServices` in `Resources/Info.plist` keeps `project.pbxproj` at **zero churn** and avoids adding an App Sandbox `.appex` target. It appears in Finder under **Right-Click → Services → Uninstall with KatiKati** (or Quick Actions if enabled). Promoting it to a top-level Finder context menu item later would require adding a separate Finder Sync Extension target in `project.pbxproj` + XPC.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/AppRemovalPlannerTests -only-testing:KatiKatiTests/AppLeftoverScanPlanTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T2.4 — Focus App Blocker / Throttler (Pause-Style Mindful Activation Curtain) (#22)
- **Effort:** `M` | **Covers:** #22 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (event-driven via `NSWorkspace.didActivateApplicationNotification`, active only during an active Focus session or enforced Screen Time limit)
- **Split:** `T2.4a` (Pure `FocusBlockPolicy` & breather countdown state machine, `<= 160` lines) → `T2.4b` (`NSWorkspace` activation observer + full-screen translucent Pause curtain `NSPanel`, `<= 220` lines)
- **Files to Touch:**
  - `Core/Support/ScreenTime.swift:131-193` (or `Core/Support/DailyHelpersRules.swift`) — add `FocusAppBlockPolicy` (distracting bundle IDs, mode `.hardHide` vs `.mindfulDelay(seconds:)`, temporary unlock grant with TTL)
  - `App/Composition/CalendarService.swift:239-260` (`FocusTimerController` exposes `isFocusBlockingActive`)
  - `Platform/ScreenTime/ScreenTimeController.swift` & `App/Entry/ScreenTimeAlertPresenter.swift` (subscribe to `didActivateApplicationNotification` only while Focus block or hard limit is active; hide distracting app or show Pause-style countdown curtain with `"Take a breath… (5s)"`, `"Close App"`, `"Allow 5 min"`)
  - `App/Scenes/Edge/ProductivityFlyouts.swift` / `App/Scenes/Edge/ScreenTimeViews.swift`
  - `Tests/Unit/ScreenTimeTests.swift` (`ScreenTimeLimitTests`), `Tests/Unit/DailyHelpersRulesTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T2.4a:** Model `FocusAppBlockPolicy` (`blockedBundleIDs`, `delaySeconds`, `unlockGrants: [String: Date]`, `evaluateActivation(bundleID:focusActive:now:)`) purely in `Core/Support/ScreenTime.swift`.
  - [ ] **T2.4b:** When `FocusTimerController` is in a `.focus` phase (or a Screen Time hard limit is reached) and blocking is enabled, observe `NSWorkspace.didActivateApplicationNotification`. On blocked app activation, either `app.hide()` immediately (`.hardHide`) or present a non-blocking mindful breathing curtain (`NSPanel`) over that screen offering `"Return to Focus"` (hides app) or `"Continue Anyway"` after the countdown expires.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/ScreenTimeLimitTests -only-testing:KatiKatiTests/DailyHelpersRulesTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T2.5 — Menuist-Style Menu Bar Quick-Path Browser & Fast `FileMover` Actions (#7)
- **Effort:** `M` | **Covers:** #7 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (menu contents populate lazily in `NSMenuDelegate.menuNeedsUpdate(_:)` only when clicked)
- **Split:** `T2.5a` (Pure `MenuBarQuickPathModel` + lazy depth-bounded folder tree planner, `<= 150` lines) → `T2.5b` (`DriveMenuBarItem` / `MenuBarQuickPathItem` + `FileMover` Finder selection transfer, `<= 220` lines)
- **Files to Touch:**
  - `Core/Support/DriveInventory.swift` (or `Core/Support/FolderContentsLoader.swift`) — add `QuickPathEntry` & `QuickPathStore` (`~/Desktop`, `~/Downloads`, `~/Documents`, custom favorites)
  - `App/Composition/DriveMenuBarItem.swift` (or sibling item hosted inside `DriveMenuBarItem` / dedicated menu bar quick-paths item toggled via `com.katikati.menuBar.quickPaths.enabled`)
  - `App/Composition/FileMover.swift:38-121` & `Platform/Finder/FinderWindowContentsReader.swift` (read current Finder selection via Apple Events when user clicks `"Move Finder Selection Here"`)
  - `App/Scenes/SettingsLayoutPane+Widgets.swift` (Menu Bar settings card toggle + favorite folders list)
  - `Tests/Unit/DriveInventoryTests.swift`, `Tests/Unit/FileMoverTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T2.5a:** Add `QuickPathBookmarks` model (`parse`/`serialize`, max submenu depth guard, dotfile toggle) in `Core/Support/DriveInventory.swift`.
  - [ ] **T2.5b:** Render a lazy cascading `NSMenu` (`menuNeedsUpdate`) for each favorite folder: clicking a file opens it (`NSWorkspace.shared.open`), Option-click reveals in Finder, and each folder header includes `"Move Finder Selection Here"` (backed by `FileMover`), `"Copy Path"`, `"New Folder"`, and `"Open in Terminal"`. Zero polling timers when menu is closed.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/DriveInventoryTests -only-testing:KatiKatiTests/FileMoverTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T2.6 — Mission Control / App Exposé / Show Desktop Trigger Hooks & Instant Overlay Wake (#23)
- **Effort:** `M` | **Covers:** #23 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz`
- **Files to Touch:**
  - `Core/Support/Shortcuts.swift` (add `.missionControl`, `.appExpose`, `.showDesktop`)
  - `Core/Support/KeyGuard.swift:532-553, 714-748` (`GestureActionTarget.missionControl`, `.appExpose`)
  - `Core/Support/RadialDialModel.swift:102-116` (`RadialDialActionType.missionControl`)
  - `App/Entry/PanelCoordinator+Spaces.swift:100-250` (`MissionControlSession.triggerOverview(_:)`) & `App/Composition/BarActionService.swift` / `App/Entry/RadialDialPanelController.swift`
  - `Tests/Unit/ShortcutsTests.swift`, `Tests/Unit/SpaceSwitchPlanTests.swift`, `Tests/Unit/KeyGuardTests.swift` (`GestureDispatchReachabilityTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope (`<= 200` lines):**
  - [ ] Add `.missionControl`, `.appExpose`, `.showDesktop` to `ShortcutAction`, `GestureActionTarget`, `GestureDispatchRoute`, and `RadialDialActionType`.
  - [ ] Launch Mission Control via public `NSWorkspace.shared.openApplication` (`/System/Applications/Mission Control.app`, Launchpad/Mission Control binary) and trigger `MissionControlSession.shared.refresh()` immediately after a short 80 ms animation settle so OpenMissionControl overlays appear instantaneously without waiting for the 1.5s `idleProbe`. For App Exposé / Show Desktop, use dynamic `dlopen`/`dlsym` `CoreDockSendNotification` (fail-closed if symbol absent, flagged per `STANDING_RULES.md` §5.3).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/ShortcutsTests -only-testing:KatiKatiTests/SpaceSwitchPlanTests -only-testing:KatiKatiTests/GestureDispatchReachabilityTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

---

### Tier 3 — Hard (`L`)

#### [ ] Slice T3.1 — AutoRaise Dwell Delay, Per-App Ignore List, Modifier Bypass & Focus-Only Mode (#17)
- **Effort:** `L` | **Covers:** #17 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (pointer dwell timer runs as one-shot only after `.mouseMoved` enters a new candidate window and cancels immediately on raise or exit)
- **Split:** `T3.1a` (Core `FocusFollowPolicy` dwell + ignore list + mode rules, `<= 140` lines) → `T3.1b` (`FocusFollowService` debounce/dwell `DispatchWorkItem` + AX ignore + Settings UI, `<= 190` lines)
- **Files to Touch:**
  - `Core/Support/FocusFollowPolicy.swift:6-19`
  - `App/Composition/FocusFollowService.swift:8-102`
  - `App/Scenes/SettingsTilingPane.swift` & `App/Scenes/SettingsLayoutPane+Shortcuts.swift:418`
  - `Tests/Unit/FocusFollowTests.swift` (`FocusFollowPolicyTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T3.1a:** Extend `FocusFollowPolicy` with `hoverDelaySeconds: TimeInterval` (0–1.0s), `ignoredBundleIDs: Set<String>`, `bypassModifiers: KeyModifiers`, `raiseWindow: Bool` (focus-only vs. focus-and-raise), and pure `evaluateHover(candidatePID:candidateWindowID:...)` returning `.ignore`, `.scheduleDwell(delay)`, or `.raiseNow`.
  - [ ] **T3.1b:** Update `FocusFollowService` (`L34-101`) to coalesce `.mouseMoved` into a single cancellable `DispatchWorkItem` dwell timer keyed by `CGWindowID`, skip ignored apps and modifier holds, and avoid raising docked/floating utility panels. Add delay slider + ignored-apps field in Settings. *(Strictly leaves `AccessibilitySource.swift` and `AppTracker.swift` untouched.)*
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/FocusFollowPolicyTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T3.2 — LinearMouse Smooth Scroll Interpolation, Speed Curves & Per-Axis Toggle (#1)
- **Effort:** `L` | **Covers:** #1 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` at rest (`CVDisplayLink` / interpolation timer starts on discrete wheel tick and automatically stops once remaining residual delta reaches `0`)
- **Split:** `T3.2a` (Pure `ScrollSmootherState` + axis/multiplier math, `<= 160` lines) → `T3.2b` (`ScrollReverserMonitor` interpolation loop + synthetic continuous `CGEvent` posting + Settings UI, `<= 240` lines)
- **Files to Touch:**
  - `Platform/CoreGraphics/ScrollReverserDecision.swift:5-47`
  - `Platform/CoreGraphics/ScrollReverserMonitor.swift:17-193`
  - `App/Composition/AppSettingsStore.swift` & `App/Scenes/SettingsLayoutPane+Shortcuts.swift:426`
  - `Tests/Unit/ScrollReverserDecisionTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T3.2a:** Add pure `ScrollWheelProfile` (separate `reverseVertical`, `reverseHorizontal`, `smoothScrollEnabled`, `speedMultiplier`, `smoothingDuration`) and `ScrollInterpolatorStep` decay math in `ScrollReverserDecision.swift`, keeping trackpad/Magic Mouse (`isContinuous == true`, untagged by us) untouched.
  - [ ] **T3.2b:** When `smoothScrollEnabled` is on, tag synthesized continuous wheel events with a dedicated `eventSourceUserData` marker in `ScrollReverserEventTapThread` (`ScrollReverserMonitor.swift`) to avoid re-entrancy, run an adaptive interpolation timer only while velocity > epsilon, and stop immediately at rest. Preserve `FullscreenEventTapRecoveryPolicy` circuit-breaker discipline. *(Never touch `FullscreenIntentMonitor.swift`.)*
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/ScrollReverserDecisionTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T3.3 — Mac Mouse Fix Global Extra Mouse Button (3/4/5) Remapper & Drag Gestures (#2)
- **Effort:** `L` | **Covers:** #2 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` when unconfigured (tap exists only while ≥1 mouse button binding is active)
- **Split:** `T3.3a` (Pure `MouseButtonActionEngine` state machine for click/double-click/hold/button+drag, `<= 200` lines) → `T3.3b` (Event tap + action dispatcher + Settings UI, `<= 250` lines)
- **Files to Touch:**
  - `Core/Support/KeyGuard.swift` (pure `MouseButtonID` `.middle`/`.button4`/`.button5`, `MouseTriggerKind` `.click`/`.doubleClick`/`.hold`/`.drag(Direction)`, `MouseButtonTarget` e.g. Mission Control, App Exposé, Space Left/Right, Browser Back/Forward, Radial Dial, Snap, `ShortcutAction`)
  - `App/Composition/KeyGuardService.swift` (or `Platform/CoreGraphics/ScrollReverserMonitor.swift` / `App/Entry/RadialDialPanelController.swift` integration so Radial Dial mouse triggers never conflict with button remaps)
  - `App/Scenes/SettingsLayoutPane+Shortcuts.swift`
  - `Tests/Unit/KeyGuardTests.swift` (`KeyGuardPipelineTests`, `KeyGuardSharedTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T3.3a:** Implement `MouseButtonStateMachine` in `Core/Support/KeyGuard.swift` resolving `.otherMouseDown` / `.otherMouseUp` / `.otherMouseDragged` deltas into click, hold, or 4-way button+drag gestures without AppKit/CGEvent dependencies.
  - [ ] **T3.3b:** Install a dedicated `CGEventTap` (listening only to `.otherMouseDown`, `.otherMouseUp`, and `.otherMouseDragged` while at least one mouse button rule is active) so bound buttons are cleanly **swallowed** (`return nil`) before reaching the frontmost app, posting synthetic Back/Forward (`⌘[`/`⌘]`), Space switches (`DockSwipeEventPoster`), or KatiKati actions.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/KeyGuardPipelineTests -only-testing:KatiKatiTests/KeyGuardSharedTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T3.4 — Hyperkey Multi-Layered Chord Layers (HUD Legend) & Multi-Step Macro Sequencer (#14)
- **Effort:** `L` | **Covers:** #14 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (runs only inside existing `HyperkeyService` key tap when active)
- **Split:** `T3.4a` (Pure `HyperkeyLayerStack` & `MacroStep` sequencer model, `<= 190` lines) → `T3.4b` (`HyperkeyService` sub-layer execution, macro runner & layer HUD overlay, `<= 250` lines)
- **Files to Touch:**
  - `Core/Support/HyperkeyEngine.swift:8-181`
  - `App/Composition/HyperkeyService.swift:14-274`
  - `App/Scenes/ShortcutCheatSheetOverlay.swift` (reuse overlay chrome for transient layer legend HUD while a sub-layer is active)
  - `App/Scenes/SettingsLayoutPane+Shortcuts.swift`
  - `Tests/Unit/HyperkeyTests.swift` (`HyperkeyEngineTests`, `HyperkeyRemapTests`)
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T3.4a:** Extend `HyperkeyEngine` (`Core/Support/HyperkeyEngine.swift`) with pure multi-layer state (`root` + named sub-layers e.g. `Window`, `Media`, `Apps`, entered via `Hyper + <leader>` with optional sticky/one-shot mode and Esc exit) plus `MacroSequence` (`[MacroStep]` of `.keystroke`, `.delayMs`, `.openURL`, `.runShortcutAction`, `.pasteText`).
  - [ ] **T3.4b:** Execute `MacroSequence` asynchronously on `MainActor` using tagged `KeyGuardShared.syntheticTag` events so macros never re-trigger `HyperkeyService` or `KeyGuardService`, and optionally show a lightweight corner HUD listing keys available in the active layer.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/HyperkeyEngineTests -only-testing:KatiKatiTests/HyperkeyRemapTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T3.5 — Kando Marking-Menu Drag-Through Trails, Custom Actions & Per-App Radial Profiles (#10)
- **Effort:** `L` | **Covers:** #10 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` (pointer monitors installed only while `RadialDialPanelController.isShown`)
- **Split:** `T3.5a` (Pure `RadialMarkingTrail` geometry + per-app profile resolver, `<= 180` lines) → `T3.5b` (`RadialDialPanelController` + `RadialDialView` drag-through + `.custom` actions, `<= 240` lines)
- **Files to Touch:**
  - `Core/Support/RadialDialModel.swift:101-217` & `Core/Support/RadialDialGeometry.swift`
  - `App/Entry/RadialDialPanelController.swift:116-381`
  - `App/Scenes/RadialDial/RadialDialView.swift` & `App/Scenes/SettingsLayoutPane+Shortcuts.swift:742-835`
  - `Tests/Unit/RadialDialGeometryTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T3.5a:** Add `RadialAppProfile` (`bundleID: String`, `nodes: [RadialSliceNode]`) resolution and Kando-style marking-menu trail geometry (detect crossing `outerRadius` into a submenu wedge to re-anchor the submenu ring at the cursor without lifting the mouse/key).
  - [ ] **T3.5b:** Wire `.custom(id:title:)` (`RadialDialPanelController.swift:378-379`) to `CustomCommand` / `ShortcutAction` / AppleScript/shell runner, render subtle vector trail line in `RadialDialView`, and select the matching `RadialAppProfile` for `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` on `show()`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/RadialDialGeometryTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

---

### Tier 4 — Hardest (`XL`)

#### [ ] Slice T4.1 — Touch-Tab / Windowbunny Continuous 3-/4-Finger Trackpad App Switcher Scrubbing (#16)
- **Effort:** `XL` | **Covers:** #16 | **`project.pbxproj` Impact:** None | **Idle CPU Impact:** `0 Hz` when disabled (Multitouch device callback registered only while `GestureDispatcher.syncMonitor` needs it)
- **Split:** `T4.1a` (Pure `TouchTabScrubSession` continuous touch-frame state machine, `<= 180` lines) → `T4.1b` (`GestureDispatcher` streaming feed + `WindowSwitcherController` live scrub/commit/cancel hooks + Settings conflict warnings, `<= 230` lines)
- **Files to Touch:**
  - `Core/Support/PinchGesture.swift:86-227` (continuous scrub reducer alongside one-shot `GestureClassificationReducer`)
  - `Core/Support/WindowSwitcherModel.swift`
  - `App/Composition/KeyGuardService.swift:1216-1268` (`GestureDispatcher`)
  - `App/Composition/WindowSwitcherController.swift:83-87, 246-300` (add `beginTrackpadScrub(mode:)`, `updateTrackpadScrub(deltaX:)`, `commitTrackpadScrub()`, `cancelTrackpadScrub()`)
  - `App/Scenes/SettingsLayoutPane+Shortcuts.swift:1256-1487`
  - `Tests/Unit/PinchGestureTests.swift`, `Tests/Unit/KeyGuardTests.swift` (`MultitouchClassifierTests`), `Tests/Unit/WindowSwitcherModelTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T4.1a:** Implement pure `TouchTabScrubSession` taking `MultitouchPoint` frames: arms after `N` (3 or 4) fingers settle and exceed initial horizontal deadzone (`abs(dx) > threshold`), emits proportional step offsets (`stepDelta`) as centroid slides across trackpad, emits `.cancel` on downward flick, and emits `.commit` when fingers lift (`points.count < N`).
  - [ ] **T4.1b:** Connect `GestureDispatcher` to `WindowSwitcherController` when Touch-Tab Scrubbing is enabled (supports switching all windows or grouped apps), surface `TrackpadConflictDetector` clash badges if macOS 3-/4-finger swipe is still enabled in System Settings Trackpad, and ensure `MultitouchSupport` soft-fails cleanly if symbols change.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/PinchGestureTests -only-testing:KatiKatiTests/MultitouchClassifierTests -only-testing:KatiKatiTests/WindowSwitcherModelTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

#### [ ] Slice T4.2 — Black Music App Per-App Volume Mixer & Isolated Output Routing (`AudioHardwareCreateProcessTap`) (#9)
- **Effort:** `XL` | **Covers:** #9 | **`project.pbxproj` Impact:** None if extending existing files (or `<= 25` hand-appended lines if adding a dedicated `Platform/SystemStatus/PerAppAudioTapEngine.swift` per `STANDING_RULES.md` §1.7a) | **Idle CPU Impact:** `0 Hz` when disabled or when no app has a non-100% volume / custom output override (only active-override apps hold an `AudioObjectID` tap + `AudioDeviceIOProc`)
- **Split:**
  - `T4.2a` (Pure `AppAudioMixRule`, gain curve math, and process-grouping planner, `<= 160` lines)
  - `T4.2b` (`Platform/SystemStatus/AudioOutputSwitcher.swift` / CoreAudio Process Tap engine using macOS 14.2+ `AudioHardwareCreateProcessTap` + `CATapDescription` + aggregate device IOProc + `Resources/Info.plist` `NSAudioCaptureUsageDescription`, `<= 260` lines)
  - `T4.2c` (Control Center / Dock II Audio Mixer UI + teardown/crash-recovery guards, `<= 220` lines)
- **Files to Touch:**
  - `Core/Support/QuickToggles.swift` or `Core/Support/SystemStatus.swift` (pure `PerAppAudioSettings` + logarithmic gain curve + Chromium/Electron/WebKit helper PID grouping)
  - `Platform/SystemStatus/AudioOutputSwitcher.swift:13-94` (enumerate active CoreAudio process objects via `kAudioHardwarePropertyProcessObjectList`, create/destroy `CATapDescription` + private aggregate device + lock-free/allocation-free `AudioDeviceIOProc` volume scaling and mute)
  - `Resources/Info.plist` (add `NSAudioCaptureUsageDescription`)
  - `App/Scenes/DockWidgets/DockII/DockControlCenterWidgetView.swift` & `App/Scenes/UtilitySettingsBlock.swift`
  - `Tests/Unit/SystemStatusTests.swift`
  - `Resources/Localizable.xcstrings`
- **Atomic Scope:**
  - [ ] **T4.2a:** Model pure `PerAppAudioRule` (`volume: Double` `0...1.5`, `isMuted: Bool`, `outputDeviceUID: String?`), perceptual dB/cubic gain scaling, and parent-bundle process grouping (e.g., Chrome/Safari WebContent audio processes grouped under their app bundle ID).
  - [ ] **T4.2b:** Implement CoreAudio Process Tap lifecycle (`AudioHardwareCreateProcessTap` with `CATapDescription(stereoMixdownOfProcesses:)` and `muteBehavior = .mutedWhenTapped` so tapped app audio is routed exclusively through our aggregate device IOProc to the chosen output device at scaled gain). Destroy taps and aggregate devices synchronously on `AppDelegate.applicationWillTerminate` and whenever rules reset to 100%/default so no app stays muted after quit.
  - [ ] **T4.2c:** Expose per-app sliders, mute buttons, and output-device pickers inside Control Center / Dock II Audio popover, gating process discovery lazily on popover open or active tap rules.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/SystemStatusTests && python3 Scripts/check_localization.py && python3 Scripts/check_debug_switches.py
  ```

---

## 4. Honest macOS API, TCC, Signing & Sandbox Constraints

| Feature / Slice | Underlying macOS Mechanism | TCC / Signing / OS Constraints & Honest Tradeoffs |
| :--- | :--- | :--- |
| **Finder Right-Click Uninstaller** (`T2.3`) | `NSServices` in `Resources/Info.plist` + `NSApplication.shared.servicesProvider` | **Zero `project.pbxproj` churn** and works in-process because KatiKati is non-sandboxed (`Resources/KatiKati.entitlements`). Appears under Finder's **Services / Quick Actions** menu (user may need to enable it once in System Settings › Keyboard › Keyboard Shortcuts › Services). A top-level Finder context menu entry would instead require a separate **Finder Sync Extension (`.appex`)** target in `project.pbxproj`, App Sandbox entitlement, and XPC IPC. |
| **Per-App Volume & Output Routing** (`T4.2`) | Public CoreAudio Process Taps (`AudioHardwareCreateProcessTap`, `CATapDescription`) | Available since macOS 14.2 (natively within KatiKati's `MACOSX_DEPLOYMENT_TARGET = 15.0`, **no kext / no virtual HAL driver**). Requires `NSAudioCaptureUsageDescription` in `Resources/Info.plist`, triggering a **"System Audio Recording Only"** TCC prompt when first enabled. Real-time `AudioDeviceIOProc` must remain lock-free and allocation-free; DRM/HDCP streams may resist tapping; browser/Electron helper PIDs must be grouped by parent bundle ID; app termination must cleanly destroy all taps so apps do not stay muted. |
| **3-/4-Finger Trackpad Scrubbing** (`T4.1`) | Private `MultitouchSupport.framework` via `dlopen`/`dlsym` (`MultitouchPinchMonitor` / `GestureDispatcher`) | **Listener-only:** cannot suppress or swallow macOS's own 3-/4-finger Mission Control / Space swipes. Users must disable or remap conflicting System Settings Trackpad gestures (`TrackpadConflictDetector` surfaces clash badges). Must soft-fail cleanly if symbols change and stay flagged in PRs per `STANDING_RULES.md` §5.3. |
| **Input Taps: Smooth Scroll, Extra Mouse Buttons, Hyperkey Layers** (`T3.2`, `T3.3`, `T3.4`) | Dedicated-thread `CGEventTap` + `hidutil` (`HyperkeyService`) | Requires **Input Monitoring** (`CGPreflightListenEventAccess`) and/or **Accessibility** (`AXIsProcessTrusted`). Every tap must use a dedicated run-loop thread, `FullscreenEventTapRecoveryPolicy` circuit breaker, and `eventSourceUserData` synthetic tagging to prevent event loops—strictly isolated from the 5 behavior-frozen files. |
| **Mission Control / Exposé Triggers** (`T2.6`) | `NSWorkspace` launch of `Mission Control.app` + optional dynamic `CoreDockSendNotification` | Launching `/System/Applications/Mission Control.app` is public API; App Exposé / Show Desktop programmatic triggers rely on dynamically loaded (`dlopen`/`dlsym`) `CoreDockSendNotification` (fail-closed if absent, flagged per `STANDING_RULES.md` §5.3). |

---

## 5. Recommended First 3 Tier 1 Slices to Execute

1. **Slice `T1.1` — Nested Battery Pill (`[ 87% ]`), Dynamic Battery Symbol Fix & Retina Polish:** High visual impact, zero new permissions, fixes the real `MenuBarSystemItem.swift:92-93` static `"battery.75"` bug, and ships cleanly in `MenuBarStatModel` + `MenuBarSystemItem`.
2. **Slice `T1.2` — Unified Clean URL Poll & Per-Event Clipboard Audio Cues:** **Eliminates** a duplicate 0.7s pasteboard polling timer (`LinkCleanerService`) while finishing both Clean URL toast integration (`linkCleaned: true`) and granular Copy/Paste/History audio cues.
3. **Slice `T1.5` — Snap Outer Border Padding, Inner Gaps & Dock Clearance Parity:** Unlocks Rectangle/AeroSpace-grade outer window margins and inner snap gaps for all 15 `SnapPosition` zones and `SnapDragMonitor` ghost previews with pure `WindowSnapTests` coverage.

*(Immediate follow-ups right behind these 3: `T1.3` Text Snippet clipboard restore and `T1.4` Command X AX text-field guard.)*
