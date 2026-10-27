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

- F | port-2a backup model | Claude (cloud) | lane-f/port-backup-model | `Core/Support/SettingsBackup.swift`, `Tests/Unit/SettingsBackupTests.swift` | pbxproj (8 entries) | 2026-10-27
- C | Q-input-a | Claude (this session) | main (integrator-direct) | `App/Composition/KeyGuardService.swift`, `Tests/Unit/KeyGuardTests.swift` | none | 2026-10-20

## Unknown
Which lanes Freebuff or another agent is using is not known until they add a line here.
