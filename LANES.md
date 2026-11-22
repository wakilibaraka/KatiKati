# LANES.md — live claim board

Source of truth for who is editing what. Rules live in `FEATURE_ROADMAP_2026-10.md` §3 (lanes, hot files, working
rules); this file only holds the claims. It sits at the repo root because `.gitignore` excludes `Docs/*.md`.

## How to use
1. Read this file **from `main`**, not from your own branch.
2. Pick a slice whose lane has no open claim (one writer per lane; at most 2–3 lanes active at once).
3. Ask the integrator (the owner, or the one agent they name) to commit your claim line to `main` before you start.
4. Work in your own worktree and branch `lane-<x>/<slice-id>`, cut from current `main`. Explicit `git add <paths>` only.
5. When the slice is merged or abandoned, the integrator deletes your line (history keeps it).

A slice never edits a file outside its lane. Anything it must touch outside goes in **Hot-file touches**, and the
integrator applies it.

## Lanes (what each owns)
| Lane | Owns |
|---|---|
| A Notch & Music | `App/Scenes/Notch/*`, `NotchIslandView.swift`, `NotchMusicPanel`, `Core/Support/Notch*`, `NowPlaying*`, `AppleScriptNowPlaying`, `App/Entry/NotchPanelController.swift` |
| B Bar, Edge, Launcher, Control Center | `DockStripView*`, `App/Scenes/Edge/*`, `Launcher*`, `RadialDial*`, `ControlCenter*`, `WindowLift*` (behaviour-frozen) |
| C Input & Windows engines | `KeyGuard*`, `Hyperkey*`, `ShortcutService`, `Core/Support/Shortcuts.swift`, `Platform/*`, `Tiling*`, `WindowSnapService`, notification move/mirror |
| D Utilities | clipboard, snippets/`CustomCommands`, command bar, shelf, capture, downloads/torrent, storage/cleaner, translate, agent usage |
| E Widgets | `CalendarPanelView` (+ tiles), weather, battery, tasks, daily helpers |
| F Shell & Onboarding | `SettingsTab`, `SettingsWindowView`, `Settings/*`, `WelcomeGuideView`, `Scripts/*`, `Docs/*`, this file |
| Integrator | the hot files below, and all merges |

## Hot files (integrator only)
`Resources/Localizable.xcstrings` · `KatiKati.xcodeproj/project.pbxproj` (hand-append only) · `AppSettingsStore.swift` ·
`AppComposition.swift` · `App/Entry/AppDelegate.swift` · `SettingsTab.swift` + `SettingsWindowView.swift` ·
`HYBRID_PLAN.md` · `graphify-out/*` (never commit it from a lane).
Behaviour-frozen (bug fix + regression test only; splits are pure-move slices): `WindowLiftAvoidanceController`,
`AppTracker`, `DragController`, `AccessibilitySource`, `FullscreenIntentMonitor`.

## Settings pages: batched (49e)
A new Settings tab edits `SettingsTab.swift`, `SettingsWindowView.swift` and `SettingsTabTests` together. Lanes therefore
never add a tab on their own: they ship the page view as a self-contained file in their lane and list "add tab" in their
hot-file touches. The integrator registers all pending tabs in **one slice per release**.

## Claims
One line per active slice: `lane | slice | agent | branch | files | hot-file touches | since`

_(OpenTaskbar A and B landed 2026-11-17; E/G/D were never started, so no claim is held. Re-claim before starting them: `Localizable.xcstrings`, `DockWidgetLogicTests.swift`, `SettingsLayoutPane+Widgets.swift` and `DockStripView*` are the hot files.)_

PHN (B+E+C+F) | pause·hydrate·pingplace | Buffy (Freebuff) | main, direct per plan §1.9 | `Core/Support/DailyHelpersRules.swift` · `HydrationController.swift` · `NotificationPlacement.swift` · `DockWingModels.swift` · `App/Composition/DailyHelpersService.swift` · `NotificationMoveService.swift` · `App/Entry/AppDelegate.swift` · `App/Scenes/DockWidgets/DockWidgetKit.swift` · `DockII/DockWingHostView.swift` · `App/Scenes/Notch/NotchAIPageView.swift` · `App/Scenes/Edge/DeckRichCards.swift` · `App/Scenes/SettingsLayoutPane{,+ControlCenter,+EdgeBars}.swift` · `App/Scenes/SettingsWindowView.swift` · `App/Scenes/UtilitySettingsBlock.swift` · `Tests/Unit/{DailyHelpersRulesTests,NotificationPlacementTests}.swift` | **`Resources/Localizable.xcstrings`** (15 PHN keys × 12 locales, hand-appended) · **`HYBRID_PLAN.md`** (PHN section) · **`CHANGELOG.md`** (`## [Unreleased]` → Changed) | 2026-11-22 — landed `3ed09b3b`, hot files already applied by me, integrator can drop this line

PHN-6 (B) | wing visibility + wing sizes | Buffy (Freebuff) | main, direct | `App/Composition/PanelGeometry.swift` · `App/Entry/PanelCoordinator+Layout.swift` · `App/Scenes/DockWidgets/DockWidgetKit.swift` · `Core/Support/DockWingModels.swift` · `App/Scenes/SettingsLayoutPane+ControlCenter.swift` · `Tests/Unit/IslandPanelGeometryTests.swift` | none — no new strings, `project.pbxproj` untouched | 2026-11-22

NP-1 (D+F) | quiet Clothesline defaults + Settings opt-in | Buffy (Freebuff) | main, direct per plan | `Core/Support/EdgeBarPrefs.swift` · `Core/Support/ClipboardPlus.swift` · `App/Scenes/Edge/ClipboardFlyoutView.swift` · `App/Composition/WindowDrawerController.swift` · `App/Composition/AppSettingsStore.swift` · `App/Scenes/UtilitySettingsBlock.swift` · `App/Scenes/WelcomeGuideView.swift` · `Tests/Unit/EdgeBarPrefsTests.swift` | **`Resources/Localizable.xcstrings`** (1 NP key × 12 locales, hand-appended) · **`HYBRID_PLAN.md`** (NP section) · `App/Entry/AppDelegate.swift` (integrator hot file: the three toast defaults now read one helper) | 2026-11-22 — landed, hot files applied, integrator can drop this line

NP-2…4 (A) | Notch pages: one card surface, one top bar, page content | Buffy (Freebuff) | main, direct per plan | `App/Scenes/Notch/*` · `App/Scenes/NotchIslandView.swift` · `Core/Support/Notch*` · `Tests/Unit/Notch*Tests.swift` | **`Resources/Localizable.xcstrings`** (no new keys: every label reused an existing one; the dead `Background run` entry was pruned) · **`HYBRID_PLAN.md`** (NP section) | 2026-11-22 — landed, live-checked on all nine pages (`build/shots/np-*.png`), integrator can drop this line

MC-12 (C+F) | keyboard control opt-ins | other Freebuff session (finished + committed by Buffy) | main | `Core/Support/SpaceSwitchPlan.swift` · `App/Entry/PanelCoordinator+Spaces.swift` · `App/Scenes/SettingsTilingPane.swift` · `Tests/Unit/SpaceSwitchPlanTests.swift` | none — the slice's `Text(verbatim:)` note was restored to its catalogued localized string, so no new strings to register | 2026-11-22 — landed `428612b2`; `build/mc12` worktree left in place (holds a pre-fix copy)

## Unknown
Which lanes Freebuff or another agent is using is not known until they add a line here.

## Live-check notes (2026-11-22)
Dock II wings on a bottom strip are hidden by `DockWingLadder` whenever the strip plate already spans the
usable width: `wingPanelFrames` measures only the room outside the plate, so a dock whose widget sections
fill the bar gets `leftAvailable = rightAvailable = 0` and both sides resolve to `.hidden`. They appear only
after hiding `weather`/`music`/`clockCalendar` in `com.katikati.dock.slotLayout.v1`. Screenshots at
small/medium/large: `build/shots/wings-*.png`.
