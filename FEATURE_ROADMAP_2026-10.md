# KatiKati — Feature Roadmap, Quality Audit & Parallel-Work Guide (Phases 49–58, Track Q)

> Written 2026-10-20 against `main` @ `dac5606` (clean tree; code identical to `1ce7963` — `dac5606` only touched
> `.gitattributes` + `graphify-out/*`). Owner: Emmanuel Baraka.
> **Rev 3, 2026-10-20 (re-grounded on `14092d5`):** seven commits landed after `dac5606`. Q2 (the gate-text retirement) is
> done (`896f8f6`); the other agent added a multi-metric menu-bar readout and rebuilt the General page (`4b3b735`); counts
> are re-measured (1.1, 3.3); the reference project's latest releases were read (7.2: Vorssaint `551f4db`, v3.4.2-beta.1
> plus unreleased) and add two slices (53i, 55g) and design notes on existing ones. Superseded text is struck through.
> **Rev 2, 2026-10-20 (owner decisions):** the settings page-height gate is **abandoned with no replacement** (settings are
> fluid; see 4.4-2); per-lane string tables and pbxproj synchronized folders are dropped (section 5); a reference-repo
> licence gate, a secure-input prerequisite, four added slices and a 2–3-lane concurrency cap are in (3.4, 6, 7.1).
> Companion to `HYBRID_PLAN.md` (the map and tracker), `STANDING_RULES.md` and `BASELINE_RULES.md`.
> **Location:** repo root, beside those three, on purpose. `.gitignore` excludes `Docs/*.md` (working-tree-only), so a
> doc under `Docs/` would not exist in the git worktrees the lanes in section 3 use. Committing this file publishes it —
> the owner's call (the ignore comment: a missed ignore "cannot be taken back once pushed"). Same for `LANES.md` (49a).
> File names below are given bare where unique; find one with `git ls-files | grep <name>`.
> **This file plans; it changes no code.** Every status below was checked against the tree on the date above (rev 3: re-checked at `14092d5`).
> Where something could not be checked without a live run or the owner's eyes it says **UNVERIFIED** or **OWED** —
> never PASS. The wishlist it grew from (hivinz-style edge bar, Vorssaint, Maccy, SlowQuit, KeyCastr, AltTabby,
> PingPlace, Loadout, Cobalt, …) was partly stale; section 2 lists the corrections.

## 0. How to use this file

1. **Pick a slice, not a phase.** A slice is one concern, ≤ ~300 diff lines (`STANDING_RULES §1.1`, `§1.7f`),
   pure logic in `Core/Support` first with a test, then wired into UI (`§2.2`). Over budget → split before starting.
2. **Slice contract** (every slice below states these):
   *lane* · *files* · *pure seam + test* · *`com.katikati.*` key (if any)* · *permission (if any)* · *hot-file touches
   (section 3.3)* · *done when*.
3. **Ponytail rule for every slice** (smallest complete change): reuse what exists (section 1 names it) before
   writing anything; no registry, wrapper, option or abstraction nobody asked for; a shortcut with a known limit gets a
   `shortcut: <limit>, <when to upgrade>` comment; end the slice note with what was skipped / not verified and the risk.
4. **Per-step notes** go in `HYBRID_PLAN.md` under the phase heading, as the work happens (`§1.8`). That file is a hot
   file — see 3.3 for who writes it when several agents run.
5. **Status words:** BUILT · PARTIAL · PLANNED (already in HYBRID_PLAN, not built) · MISSING · UNVERIFIED · OWED.
6. **Gate** (every slice; section 8): `xcodebuild test` (CI command) + `check_localization.py` +
   `check_debug_switches.py` + `check_availability_warnings.py`; dev loop only through `Scripts/build_and_run.sh`.

## 1. Ground truth (what the code actually contains)

### 1.1 Shape
`Core/Support` (pure, no AppKit/AX, dual-compiled into the test target) → `Platform/*` (OS adapters) →
`App/Composition` (services, stores) → `App/Scenes` (SwiftUI) → `App/Entry` (panel controllers, `AppDelegate`).
227 files in `Tests/Unit` (225 at rev 2, plus `MenuBarStatModelTests`, `StartupUIPolicyTests`). One dependency (Sparkle).
1013 localization keys × 12 languages, `check_localization.py` green at `14092d5`. `SettingsTab` has **18** cases (`App/Scenes/SettingsTab.swift`; sidebar shell in `App/Scenes/Settings/`).
Four independent `CGEventTap`s: `HyperkeyService`, `KeyGuardService`, `ScrollReverserMonitor`, `FullscreenIntentMonitor`.

### 1.2 Wishlist item → reality
| Wishlist item | Status | Evidence / what is left |
|---|---|---|
| Per-tool Settings pages, sidebar | BUILT | 18 tabs, `SettingsWindowView.swift` pane switch; no `NavigationSplitView` rewrite needed |
| Settings page-height gate (1074 pt clamp) | ABANDONED 2026-10-20 | script + probe already deleted in `d0aa73a`; the owner retired the rule, no replacement (4.4-2). Pages scroll; window min 640×440 |
| Menu-bar system readout (CPU / RAM / disk / network / GPU / battery) | BUILT (new in rev 3, `4b3b735`) | `MenuBarSystemItem.swift`, pure `MenuBarStatModel.swift`, `Platform/SystemMonitor/SystemMonitorSampler.swift`; off by default; its 1 s sampler runs only while at least one metric is on. Idle-CPU cost per metric UNVERIFIED (Q1) |
| General page: startup, Hide Dock icon, language | BUILT (new in rev 3) | pure `StartupUIPolicy.swift` (`launchHidden`, `hideDockIcon`; the Welcome guide shows on first run or when not launching hidden), `AppLanguageOption.swift`; the panes are in `SettingsWindowView.swift` |
| SlowQuit (hold ⌘Q) | BUILT | `KeyGuardService`, `KeyGuard.swift` (`SlowQuitTiming`), `SlowQuitOverlay.swift` |
| KeyCastr-style key overlay | BUILT | `KeyVisualizerBuffer` (`KeyGuard.swift`), `KeyVisualizerOverlay.swift`; secure-input behaviour UNVERIFIED (Q-input) |
| Input pause / keyboard cleaning | BUILT | `KeyGuardPipeline`, `cleaningTimer` in `KeyGuardService` |
| Hyperkey | BUILT | `HyperkeyService` + pure `Core/Support/HyperkeyEngine.swift`; Caps Lock→F18 via `hidutil`; firing "not live-tested" per HYBRID_PLAN Phase 9 |
| Caps Lock *protection* (accidental press) | MISSING | no guard in `KeyGuardPipeline` |
| Finder keys (⌘X / ⌘V move, Return rename) | MISSING | |
| System-wide snippet expansion | MISSING | snippets exist only as command-bar entries (`CustomCommands.swift`, key `com.katikati.commandbar.snippets`) |
| "One event tap for everything" | NOT RECOMMENDED YET | rewrites behaviour-frozen code; extend pure `KeyGuardPipeline` instead, measure first (53e) |
| Action registry (`KatiKatiActionRegistry`) | NOT NEEDED | `ShortcutAction` (`Core/Support/Shortcuts.swift`), `BarActionService`, `LauncherCommands` already route actions |
| Screenshot CLI wrapper | BUILT as a method | `/usr/sbin/screencapture` already used in `App/Entry/RadialDialPanelController.swift`; text/QR result in `Edge/CaptureResultView.swift` |
| Notification relocation (PingPlace) | BUILT | `NotificationMoveService`, `NotificationMirrorService` (Phase 25) |
| Clipboard history (Maccy) | BUILT | `ClipboardHistory.swift`, `ClipboardPlus.swift`, `Platform/Clipboard/ClipboardMonitor.swift`, `Edge/ClipboardFlyoutView.swift`; concealed types skipped; pinned entries exist, cap 50 unpinned (`ClipboardHistory.swift:22`). Copy/paste sound + toast MISSING; age-based retention MISSING (55g) |
| Command bar (SuperCmd-style) | BUILT | Phases 27–30, `CommandBarTests` |
| Translate / define | BUILT | `Edge`/`TranslateCardView.swift`, `DictionaryService` |
| Shelf: reduce PDF, share | BUILT | `PDFReducePlan.swift`, `ShelfActions.swift` (`NSSharingService`). Image reduce, LocalSend MISSING |
| Tiling, snap, radial dial | BUILT | Phases 26, 31; `TilingTree/Layout`, `SnapRects`, `RadialDial*` tests |
| Notch pages: AI, storage, downloads, calendar/music, teleprompter, mirror, notifications | BUILT | `Core/Support/NotchSectionPaging.swift` (`NotchPage`, `visible(...)`, `NotchPagingPolicy.defaultPage`), `App/Scenes/Notch/*`. User reorder/remove MISSING |
| Notch: avoid camera cutout ("ears") | PARTIAL | `NotchGeometry.cameraKeepoutBox` exists; whether views honour it UNVERIFIED (Q-notch) |
| Notch: battery buddy, artwork glow, compact now-playing toast | MISSING | |
| Music: tap / double-tap opens player, artwork accent | MISSING | `NowPlayingChip.swift` has the popup/turntable; current tap behaviour UNVERIFIED |
| Music: lyrics, equalizer | MISSING | ~~no data source~~ (rev 3: Vorssaint's lyrics are an opt-in `lrclib.net` lookup, so a source exists — a network + privacy call, 7.2); the equalizer needs an audio tap. Parked (50g) |
| Now Playing source | BUILT, health UNVERIFIED | `NowPlayingService` (isolated MediaRemote, `#available`) + `AppleScriptNowPlaying`; which path works on this macOS is Q-music's first question |
| AI usage page (Claude/Codex/Copilot/OpenCode) | BUILT | `AgentUsageService`, `Core/Support/AgentUsage/*`, `NotchAIPageView`. Live "status" (working/idle) MISSING; Loadout MISSING |
| Calendar panel: countdown, alarms, timer, stopwatch, reminders | BUILT | `Docs/WIDGET_INVENTORY.md`, `CalendarPanelModels.swift` (`NextEventCountdown`). **Year-in-progress MISSING** |
| Calculator keypad tile, mic recorder tile | BUILT (new, `8391671`, `be52384`) | `CalculatorTile.swift`, `AudioRecorderTile.swift` (split out of `CalendarPanelView` by 49c, `8d89397`); mic permission added; Q-widgets checks the denied-permission path |
| Weather widget | BUILT | Phases 43/46; 3 size presets UNVERIFIED |
| Battery / AirBattery-style multi-device | PARTIAL | `Core/Support/BluetoothDevices.swift` parser exists; redesign MISSING |
| Smart tasks | PARTIAL | `Edge/TasksFlyoutView.swift` exists; smart sorting MISSING |
| Pause / Hydrate reminders | UNVERIFIED | `DailyHelpersService` (Phase 36) — check what it already covers first |
| Control Center: scroll to change volume, Bluetooth icon | UNVERIFIED | `ControlCenterLayout.swift`, `SettingsLayoutPane+ControlCenter.swift`, `Platform/SystemStatus/AudioOutputSwitcher.swift` |
| Dock hover previews, dock-click actions | MISSING | not found in `DockStripView*` |
| ⌘Tab switcher (AltTabby) | MISSING | AltTabby is Windows-only: design reference, no code to port |
| Fixed Space order | MISSING | reusable seam: `NativeDockPreferencesService` |
| Focus-follows-mouse, green-button zoom override, quit-on-last-window-close | MISSING | |
| Launcher modes (fullscreen / centred / popover), Orb | MISSING | one presentation today (`LauncherView`, `App/Entry/LauncherPanelController.swift`) |
| First-launch glass intro | MISSING | extends `WelcomeGuideView.swift` |
| Scheduled cleaner | MISSING | seam: `StorageScanService` + `StorageScanMath.swift` |
| Cobalt media download, LocalSend | MISSING | licence / network decisions (section 7) |

## 2. Corrections to the pasted plans
1. "Split Settings into per-tool pages" — already done (18 tabs). Do not re-plan it.
2. "Add SlowQuit / KeyCastr / Hyperkey" — all three exist. Plan refinements only.
3. "A single `KatiKatiActionRegistry`" — duplicates `ShortcutAction` + `BarActionService`. Extend those.
4. "Use `screencapture -i -c`" — already the implementation.
5. "Add a countdown widget" — a Countdown tile exists; only the year-in-progress ring is new.
6. "One event tap" — the repo has four, each with its own timeout re-enable (verified). Merging is a rewrite of
   behaviour-frozen code, not a refactor; decide from a measurement (53e), not an assumption.
7. The pasted 6-phase "Claude Code execution plan" ignores that HYBRID_PLAN already holds Phases 0–48 and the
   rules in `STANDING_RULES §1.7`. Numbering here continues at **49**.
8. "Restore `check_settings_page_heights.py`" / "the 1074 pt limit" — retired. The script was deleted in `d0aa73a` and the
   owner abandoned the rule on 2026-10-20. Do not restore it, and do not cite 1074 pt as a reason for any design.
9. "43 dirty files to land first" — stale: the tree is clean at `dac5606` and the work is committed.
10. The pasted licence list was wrong in places: KatiKati is **GPL-3.0-or-later** (not proprietary/MIT), AirBattery is
    AGPL-3.0 (not MIT), SlowQuitApps is GPL-2.0 (not 3.0). The corrected table is in 7.1.
11. "Per-lane string tables" and "pbxproj synchronized folders" — dropped (section 5, "Skipped on purpose").
12. "Add a 19th Settings tab for gestures" — not needed; a pinch-gesture section already lives in
    `SettingsLayoutPane+Shortcuts.swift` (~`:148`). See 53h.
13. Code indexes (and the file map some tools print) list `AgentOpenCodeParser.swift`, `AgentCodexParser.swift` and
    `AgentCopilotParser.swift` as files. In the tree they are three enums inside
    `Core/Support/AgentUsage/AgentStoreParsers.swift` (111 lines). `git ls-files` is the authority.

## 3. Parallel-work protocol (several AI IDEs / agents at once)

### 3.1 Honest answer
Yes, but only with discipline. The code is layered well enough that *feature* files rarely collide. Collisions happen on
a short list of shared files (3.3). One working tree edited by two agents is the failure mode (it happened on
2026-10-20: Freebuff and Claude Code both active in `main`; four commits landed mid-session — `8569d39`…`1ce7963` —
and `1ce7963` had to repair test-target membership). The rules below remove that.

### 3.2 Lanes — each lane owns a disjoint file set
| Lane | Owns |
|---|---|
| **A Notch & Music** | `App/Scenes/Notch/*`, `NotchIslandView.swift`, `NotchMusicPanel`, `Core/Support/Notch*`, `NowPlaying*`, `AppleScriptNowPlaying`, `App/Entry/NotchPanelController.swift` |
| **B Bar, Edge, Launcher, Control Center** | `DockStripView*`, `App/Scenes/Edge/*`, `Launcher*`, `RadialDial*`, `ControlCenter*`, `WindowLift*` (behaviour-frozen: pure-move edits only) |
| **C Input & Windows engines** | `KeyGuard*`, `Hyperkey*`, `ShortcutService`, `Core/Support/Shortcuts.swift`, `Platform/*`, `Tiling*`, `WindowSnapService`, notification move/mirror |
| **D Utilities** | clipboard, snippets/`CustomCommands`, command bar, shelf, capture, downloads/torrent, storage/cleaner, translate, agent usage |
| **E Widgets** | `CalendarPanelView` (+ tiles), weather, battery, tasks, daily helpers |
| **F Shell & Onboarding** | `SettingsTab`, `SettingsWindowView`, `Settings/*`, `WelcomeGuideView`, `Scripts/*`, `Docs/*` |
| **Integrator** (one agent or the owner) | the hot files in 3.3 and merges |

A slice never edits a file outside its lane's list; if it must, the touch goes in its *hot-file touches* line and the
integrator applies it (or the slice waits).

### 3.3 Hot files — one writer at a time (the integrator)
| File | Why it collides | Protocol |
|---|---|---|
| `Resources/Localizable.xcstrings` | one catalog, keys appended unsorted at the tail (1013 keys) → two branches append in the same hunk | lane writes its entries on its branch; integrator merges by hand (keep both), then runs `check_localization.py`. **Do not use `merge=union`** — it can corrupt JSON. Translations are human-reviewed drafts (`§1.7b`) |
| `KatiKati.xcodeproj/project.pbxproj` | 765 `PBXFileReference` entries, `objectVersion 56` | hand-append only (`§1.7a`); a file addition ≈ 4 lines; > ~30 lines for one file = reject. Pure moves/splits are their own slice so they never ride along with logic |
| `AppSettingsStore.swift` (1586 lines, ~86 `@Published`) | every feature adds a key | new features ship as **self-contained** blocks with their own `com.katikati.*` key constants and a tiny observable (patterns: `TorrentSettingsBlock` in `UtilitySettingsBlock.swift`; `CustomCommands`). A store edit is a hot-file touch |
| `AppComposition.swift` (1170), `App/Entry/AppDelegate.swift` (1295) | service wiring | lazy, gated singletons (`§1.7e`); wiring line goes in the slice's hot-file touches |
| `SettingsTab.swift` + `SettingsWindowView.swift` | adding a page edits both (and `SettingsTabTests`) | batch new tabs: one integrator slice per release, not per feature |
| `HYBRID_PLAN.md` (5907 lines) | per-step note log | each lane keeps its notes in its slice commit message + a draft note block; the integrator pastes them under the phase heading in one commit |
| `graphify-out/*` | rewritten whole on every build (`dac5606`: 9 files, +3597/−1504) | lanes do **not** commit it; integrator runs `graphify update .` once per merge. `.gitattributes` (`graph.json merge=graphify`, committed in `dac5606`) needs the matching local merge driver on each clone, or it silently falls back to a normal merge |

### 3.4 Working rules
1. **One agent per worktree and branch** (`lane-<x>/<slice-id>`), cut from current `main`. Never two agents in the
   same checkout. The main checkout is the integrator's.
2. **One writer per lane at a time.** Two agents in the same lane = serialise.
3. **Claim before starting:** append one line to `LANES.md` (root, 49a): lane, slice id, branch, files. Claims live on
   `main`, so the integrator commits them; an agent reads the file from `main`, not from its own stale branch.
4. **Explicit `git add <paths>`, never `-A`/`.`** (`§1.7c`). Commit message carries scope receipts (`§1.7d`).
5. **Rebase on `main` before handing to the integrator;** the integrator merges in this order: Core/pure slices →
   Platform → Composition → Scenes → Settings → strings/pbxproj/graph → docs.
6. **Pure first:** the Core file + its test can be merged long before the UI slice, which removes most overlap.
7. **Behaviour-frozen files** (`WindowLiftAvoidanceController` 2754 lines, `AppTracker` 2607, `DragController` 1988,
   `AccessibilitySource` 1343, `FullscreenIntentMonitor` 1010): bug fixes with a regression test only. Splits are
   pure-move slices, never mixed with edits.
8. **Before any lane starts (pre-flight):** `git status` clean on `main` (it is, at `14092d5`, apart from `graphify-out/*`, which every build rewrites); the 2 stale stashes
   (`phase-12 slice1`, `4u-a-superseded`, both labelled superseded) and the prunable `/private/tmp/kk-tip` worktree
   (detached `bad2303`) cleared **by the owner**; worktree `.claude/worktrees/hopeful-gauss-9a1c88` (also detached
   `bad2303`) either adopted or removed. Local branches `claude/hopeful-gauss-9a1c88`, `phase-11-18-layout-placement`,
   `fix/force-unwrap-hardening`, `release/0.17.0-beta.3` are all already merged into `main` (`git branch --merged`).
9. **If a file changed under you** (another agent): stop, re-read, rebase; never overwrite.
10. **At most 2–3 lanes active at once** (not all six): one integrator owns the hot files (3.3), and which lanes
    Freebuff or another agent is using is unknown until `LANES.md` exists. Start with two lanes whose files do not
    touch (e.g. A Notch & Music + D Utilities), add a third only when the integrator is keeping up.

### 3.5 Execution flow
```
main (clean)  ──►  Q0  gate on HEAD ............ done at `14092d5`: 2559 tests, 0 failures (section 9)
                   Q1  idle-CPU baseline ........ owed
                   Q2  gate-text cleanup + sidebar smoke test ... done (`896f8f6`); live smoke run owed
                    │
                    ▼
                   Phase 49  done (`8d89397`): 49a LANES.md ─► 49b / 49c pure splits ─► 49e batching rule
                    │
                    ▼
        2–3 lanes at a time, one worktree + branch each, claim in LANES.md
        per lane: its Q-slice first ─► then its feature phase (4 / 6)
                    │
                    ▼
        integrator: rebase ─► merge in the 3.4-5 order ─► gate (section 8) ─► graphify update .
```

## 4. Track Q — quality audit of what is already built (past and present)

Q work is read-and-measure first: each slice produces PASS / FIX / OWED rows with the evidence; fixes are separate
slices ≤ 300 lines. **Q0–Q2 run before any new-feature phase;** the lane Q-slices run ahead of the feature phase that
touches the same files (Q-music → 50, Q-notch → 51, Q-input → 53, Q-bar → 54/57, Q-widgets → 56).

### 4.1 Four gates for every feature
1. **Static** — its pure tests exist and the CI command is green; the three checkers are clean.
2. **Live** — a named recipe on a real build (`Scripts/build_and_run.sh`, then
   `open --env DOCK_OPEN_SETTINGS=<tab> --env DOCK_DEV_SKIP_PERMISSIONS=1 <app>`), with a screenshot or log.
   A unit test alone is never PASS for UI or OS behaviour.
3. **Resource** — idle CPU with the feature on vs off, and every `Timer`/poll it owns (~35 `Timer` sites, incl. one-shots, in
   `App/Composition` + `Platform`; `KeyGuardService` alone has 3: 1 s cleaning, 0.05 s hold, 0.05 s visualizer).
4. **Care** — permission-denied path, privacy/secrets, Reduce Motion (12 files handle it; 31 `withAnimation` in `App`),
   VoiceOver (51 `.accessibilityLabel`), 12 languages, multi-display / Spaces / fullscreen.

### 4.2 Present work: the tree was committed by another agent during this investigation
`8569d39` (Settings tabs split; "Live Island" → "Dynamic Notch") · `8391671` (calculator + mic recorder tiles) ·
`be52384` (mic permission; catalogs reconciled) · `1ce7963` (test target: `QuickAddState` dual-compiled,
`NotchMirrorPageView` membership fixed) · `dac5606` (graph rebuild + `.gitattributes`). The tree is clean.
**Q0 checks that this HEAD is actually green** — the membership repair in `1ce7963` means the suite was red or
un-buildable at some point in between. The CI-command run on `1ce7963` has since finished green (2548 tests, 2 skipped, 0 failures) — see section 9;
the three checkers and the live recipes are still to be recorded.
**Rev 3 — since `dac5606` (seven commits, `main` = `14092d5`, in sync with `origin/main`):** `bb3a1f7`/`358cf57` this
document; `896f8f6` the gate-text retirement (Q2); `a943a13` and `3fb752f` release-script fixes (strip verification,
library-validation opt-out for the fallback identity); `4b3b735` "Pass 2" — multi-metric menu-bar readout and rebuilt General
page (12 files, +1025/−202 outside `graphify-out`; adds `MenuBarStatModel`, `StartupUIPolicy` and their tests);
`14092d5` the language picker reads the exact app domain. The CI-command run on `14092d5` is green (section 9); the three
checkers are recorded there too. The live recipes are still owed.

### 4.3 Past work: checks the repo already admits are owed (HYBRID_PLAN line refs)
| Where | Not done | Slice |
|---|---|---|
| Phase 9 (`:2266`) | Hyper firing, custom-key shortcuts not live-tested | Q-input |
| Phases 7A/8 (`:1907–1912`) | drag-reorder, ⌥-drag pill, outside-click dismissal, multi-display, fullscreen/Spaces, iCloud, Windows snap on a real window, Capture region selector, Reminders prompt, Instruments idle-CPU number (`:1762`) | Q-bar, Q-widgets, Q1 |
| Phase 10 (`:2317`) | translation review sheet deferred to a pre-release gate (7 CSVs in `Docs/`) | Q-l10n |
| Phase 16 (`:2897`) | Control Center live check owed to the owner | Q-bar |
| Phase 41 (`:4985`) | slice 41e owed | Q-bar |
| Phase 46 (`:1317`) | weather animations seen live only for Drizzle | Q-widgets |
| Phase 48 (`:5332`) | notch pages not live-checked | Q-notch |

### 4.4 Findings from this investigation (verified unless marked)
1. **Key visualizer and secure input.** **Done in `e1a6ec6` (Q-input-a):** `KeyGuardShared.record` reads
   `IsSecureEventInputEnabled()` only while the visualizer is on and keeps/clears nothing under secure input; the live
   password-field check is still OWED. Any feature that reads typed text (snippet expansion 53c) sits on that guard.
2. **Settings page-height gate — abandoned (owner, 2026-10-20), no replacement.** `Scripts/check_settings_page_heights.py`
   and the `DOCK_SETTINGS_PAGE_HEIGHT` probe were removed by `d0aa73a` (sidebar redesign; window resizable, min 640×440,
   each page in a vertical `ScrollView`: `SettingsShell.swift:68`). What remained at rev 2 was stale text that sent agents to a
   script that no longer exists: `Docs/SETTINGS.md` (rule 10 `:87`, §5.3 `:174`; published), `Docs/DEBUG_SWITCHES.md`
   (`:17`), the "ten toolbar items" comment (`SettingsWindowView.swift:6`) and the `live_check_settings_tabs.py`
   docstring. `HYBRID_PLAN.md` and `CHANGELOG.md` keep it as history (one dated "superseded" line, `STANDING_RULES §6.3`).
   **Settings stay fluid: no fit, height or clamp rule, and no replacement fit-check.** The `SettingsMetrics` grid
   (rules 1–9 in `Docs/SETTINGS.md`, pinned by `SettingsMetricsTests`) stays as soft guidance — owner may relax it later.
   ~~`live_check_settings_tabs.py` clicks `toolbar 1` buttons from a 15-name list, so it is likely broken against the
   sidebar (UNVERIFIED); Q2 turns it into a smoke test that every tab opens, driven from the `SettingsTab` list.~~
   **Done in `896f8f6` (rev 3):** `Docs/SETTINGS.md` rule 10 now says the window is fluid and §5.3 is gone; the dated
   superseded line is in `HYBRID_PLAN.md`; `live_check_settings_tabs.py` reads its tab names from `SettingsTab.swift`, opens
   each with `DOCK_OPEN_SETTINGS=<tab>` and checks a window of at least 600×400 (it does not read which page is showing).
   Its live run over the 18 tabs is **OWED** (needs the Accessibility grant for the terminal). `Docs/DEBUG_SWITCHES.md`
   no longer lists `DOCK_SETTINGS_PAGE_HEIGHT`; the remaining hits are `Docs/Archive/**` evidence, kept as history.
3. **Event taps.** All four re-enable on `tapDisabledByTimeout`/`…ByUserInput`. Refinement: surface "tap alive" in
   Advanced and log a one-line note when a tap had to be re-enabled.
4. **Hyperkey remap.** `restoreRemap()` runs on turn-off (`HyperkeyService.swift:103`). UNVERIFIED: after `kill -9`
   with Hyperkey on, does Caps Lock stay F18? If so, restore a stale remap at launch. `HyperkeyEngineTests` lives
   inside `Tests/Unit/ShortcutsTests.swift` — move to its own file (helps parallel edits).
   **CONFIRMED and FIXED (Q-input, 2026-10-20):** a stale Caps→F18 entry was live on this Mac with Hyperkey off. Two causes: nothing
   cleared it at launch, and on macOS 27 `hidutil --get` prints a table with string-valued numbers, so `currentMapping()` always
   returned `[]` (user remaps were never preserved either). Now parsed by `HyperkeyRemap.parse` and cleared once per launch while
   off; live check: entry present before relaunch, absent after. Tests moved to `Tests/Unit/HyperkeyTests.swift`.
5. **Clipboard.** Concealed/transient/auto-generated types are skipped (`ClipboardHistory.swift:26`); poll is 0.7 s
   and only while recording. UNVERIFIED: where history persists, clear-on-quit, per-app ignore (`ClipboardIgnoreRules`
   in `ClipboardPlus.swift`). Age-based retention does not exist (grep finds only the 50-unpinned cap and the shelf's own
   auto-expire); Vorssaint added "keep items N days, pinned stay" (7.2) → slice 55g.
6. **Localization.** 1013 × 12, all present (re-run at `14092d5`, still 40 literals); `check_localization.py` also reports **40 Chinese string literals** left
   in source (mostly `ContentView`, `DragController`, `AppTracker`, `DockStripView`) — confirm none is user-visible.
   The checker proves completeness, not quality (`§1.7b`); add a check that flags a translation identical to its
   English source.
7. **Skipped tests.** The CI-command run on `1ce7963` skipped 2: both live-torrent tests in `DownloadManagerTests`
   (need `KK_LIVE_TORRENT=1` + `aria2c`). An earlier static count of 6 also named a CI-only skip
   (`DragControllerConversionTests`) and a precondition skip in `WindowLiftAvoidanceTests`; those did not skip in this
   run — UNVERIFIED why. Run the torrent tests before each release.
8. **"Service has no test" is not a gap by itself.** Hyperkey, KeyGuard, NotificationMove, StorageScan, AgentUsage,
   Dictionary, Bookmark and others have no test naming the *service* because their decisions live in tested Core
   types. Q checks the Core type is covered and the glue has a live recipe.
9. **File growth.** `CalendarPanelView.swift` grew by 226 lines in `8391671` alone (calculator + recorder tiles);
   `NowPlayingChip.swift` was 1375 lines holding six views. **Both split in `8d89397` (49b/49c):** the chip is now
   `NowPlayingChip` / `NowPlayingPopup` / `TurntableView` / `ExpandedMediaCardView`, the tiles are `CalculatorTile` and
   `AudioRecorderTile`. Pure move — the only old line not carried over verbatim is `ExpandedMediaCardView`'s `private`,
   which the split had to drop so the other files can see it.
10. **Reduce Motion / VoiceOver** coverage is partial (counts in 4.1); sweep notch, launcher, dock, radial dial,
    settings, calendar tiles.
11. **New since rev 2 — menu-bar readout (`4b3b735`).** `MenuBarSystemItem` samples every 1 s while at least one metric is
    on. Q1 records idle CPU with 0, 1 and all metrics on; VoiceOver and Reduce Motion are not yet swept for it. Its pure
    parts are tested (`MenuBarStatModelTests`, `StartupUIPolicyTests`).
12. **Hypothesis from Vorssaint's changelog: a tap stopped on purpose must stay stopped.** Ours re-enable on
    `tapDisabledByTimeout`/`…ByUserInput` (item 3). Check that this path does not restart a tap that `KeyGuardService` or
    `HyperkeyService` stopped deliberately (permission revoked, quit, cleaning mode). Q-input.
    **Q-input (inspection only):** `stop()` disabled the tap and stopped its run loop but left `shared.port` set; both services now
    nil it, so a late callback cannot re-enable. Not reproduced live.

### 4.5 Per-feature audit rows
| Lane | Feature | Live recipe | Refinement to evaluate (hypotheses, not claims) |
|---|---|---|---|
| C | KeyGuard: pause, SlowQuit, visualizer | hold ⌘Q 3×; type in a password field; all guards off ⇒ nothing swallowed | secure-input suppression, per-app allow list, tap-health row |
| C | Hyperkey | Caps Lock→F18, Hyper shortcut fires, `kill -9` recovery | stale-remap restore at launch |
| C | Notification move/mirror | banner lands in each corner after a fresh macOS banner | auto-disable after repeated AX failures + status line in Settings |
| C | Tiling, snap, radial dial | 2 displays, Spaces, fullscreen, Accessibility revoked mid-run | clean disable when the grant is revoked |
| A | Notch (geometry, pages, hover, gestures) | notch Mac, no-notch Mac, external display, fullscreen, menu-bar auto-hide | none until the Phase 48 live check is recorded |
| A | Now Playing & music surfaces | Spotify, Apple Music, browser audio, nothing playing | which source works; error text; artwork fallback |
| A/D | Agent usage page | real Claude/Codex/Copilot/OpenCode logs | date-stamp `AgentPricing`; parser fixtures from each tool's current log format; Vorssaint now reads per-Codex-account limits and Claude limits through Claude Code — check `AgentCodexParser` (its own comment says the envelope evolves) against current logs |
| D | Clipboard, command bar, snippets | password-manager copy; 500 items; snippet paste | clear-on-quit, per-app ignore, snippet placeholders |
| D | Downloads / BitTorrent | the opt-in live test; idle CPU engine off | peer-IP privacy note, port/firewall prompt, bandwidth cap |
| D | Shelf, PDF reduce, translate, dictionary | 20 MB PDF; offline translate | cancel + progress, size-saved readout |
| E | Weather, Calendar panel, calculator, recorder | location denied; offline; EventKit denied; **mic denied** | explicit denied/empty states (Phase 43: never invent data) |
| B | Dock strip, edge bars, Control Center | multi-display, hover, drag-reorder, CC volume + Bluetooth | the owed owner eyeballs |
| F | Settings shell (18 tabs), General page, menu-bar readout, onboarding | smoke test that every tab opens; readout metrics on/off against idle CPU; Welcome guide with permissions revoked; eyeball a new card at 640×440 | none (no height gate, by owner decision) |
| all | l10n, a11y, Reduce Motion, idle CPU | scripts + one Instruments run | identical-to-English check |

### 4.6 Q slices
| ID | Slice | Lane | Output |
|---|---|---|---|
| **Q0** | Gate on HEAD: CI test command + 3 checkers; check `1ce7963`'s pbxproj/test-target state | F + integrator | **done at `14092d5` (rev 3, section 9):** test command and all three checkers |
| **Q1** | Baseline: one idle-CPU run with defaults (Instruments or `ps`), timers inventory | F | the number every later Resource gate compares to; repeat once with the menu-bar readout's metrics on (4.4-11) |
| **Q2** | **DONE `896f8f6` (rev 3).** Retire the page-height gate text (4.4-2): `Docs/SETTINGS.md` rule 10 + §5.3 → one soft line, `Docs/DEBUG_SWITCHES.md` row, "ten toolbar items" comment, `HYBRID_PLAN.md` superseded line; `live_check_settings_tabs.py` becomes a sidebar smoke test over `SettingsTab`. **No fit or height check is added** | F | `git grep check_settings_page_heights` hits history only; ✅ checked at `14092d5` (only `Docs/Archive/**`, `HYBRID_PLAN.md`, `CHANGELOG.md` mention it); smoke run over 18 tabs **OWED** (Accessibility) |
| **Q-input-a** | **Done `e1a6ec6`:** `KeyGuardShared.record` probes `IsSecureEventInputEnabled()` lazily (only while the visualizer is on) and clears/keeps nothing under secure input; `testSecureInputClearsAndRecordsNothing` pins it. Was: pure `SecureInputPolicy` (+ test); the visualizer clears its buffer under secure input. Hard prerequisite of 53c | C | test table; live check in a password field **OWED** |
| **Q-input** | KeyGuard + Hyperkey rows; `kill -9` check; deliberate-stop vs re-enable check (4.4-12); what hold-⌘Q does with Screen Sharing frontmost (53i); move `HyperkeyEngineTests` | C | rows + fixes if confirmed |
| **Q-notch** | Phase 48 live check; camera-keepout check on notch + no-notch Macs; hypotheses from Vorssaint's fixes (7.2): menu bar taller than the notch, a no-notch external display, a custom width on every page, closing after a Shelf drag-out | A | rows |
| **Q-music** | which Now Playing source works; tap behaviour today; error states | A | rows |
| **Q-bar** | owed eyeballs (Phases 7A, 16, 41); Control Center volume/Bluetooth | B | rows |
| **Q-widgets** | weather animation sweep; denied-permission states incl. mic | E | rows |
| **Q-utils** | clipboard privacy; torrent live test; agent-usage fixtures | D | rows + fixtures |
| **Q-l10n** | identical-to-English check; 40 literals; translation CSV review gate | F | rows |
| **Q-a11y** | Reduce Motion + VoiceOver sweep | all | rows |

## 5. Phase 49 — Parallel-work foundation (structure only, zero behaviour change)
| ID | Slice | Lane | Est. | Test / gate | Done when |
|---|---|---|---|---|---|
| 49a | **Done.** Root `LANES.md`: section 3.2/3.3 as the live claim board (one line per active slice). Root, not `Docs/` — see header | F | ~60 | none (docs) | every active agent has a line; file is tracked |
| 49b | **Done 2026-10-21** (`8d89397`, together with 49c). Split `NowPlayingChip.swift` into one file per view (`NowPlayingChip`, `NowPlayingPopup`, `TurntableView`, `ExpandedMediaCardView`, …) — **pure move** | A | ~0 net + ~20 pbxproj | CI command | no logic diff: every removed line reappears except the one `private` the split had to drop, and the 27 added lines are file headers/imports |
| 49c | **Done 2026-10-21, same commit.** Move the calculator and recorder tiles out of `CalendarPanelView.swift` into their own files — pure move | E | ~0 net + ~8 pbxproj | CI command | same |
| 49e | **Done.** Decide the Settings-registration pattern: batched tab additions through the integrator | F | docs only | — | rule written in `LANES.md` (§ settings pages) |

(Ids 49d and 49f are retired, not reused. Phase 49 is complete: all four live rows landed.)

**Skipped on purpose** (each would cost more than it saves; revisit only on a measured problem or an owner override):
- **Per-lane string tables** (was 49d) — the one-catalog merge is handled by the integrator rule in 3.3; splitting the
  catalog changes the localization checker and every `String(localized:)` call site.
- **pbxproj synchronized folders** (was 49f) — needs `objectVersion` 77; conflicts with `STANDING_RULES §1.7a`.
- **A single event-tap hub** — rewrites behaviour-frozen code; 53e measures first.
- **`KatiKatiActionRegistry`** — duplicates `ShortcutAction` + `BarActionService` (section 2).
- **`NavigationSplitView` rewrite of Settings** — the sidebar shell already works.
- **Settings page-height gate or any replacement fit-check** — abandoned by the owner, 2026-10-20 (4.4-2).

## 6. Phases 50–58 — new features (each slice ≤ ~300 lines; "Est." is a first guess)

### Phase 50 — Music surfaces (Lane A; starts after Q-music, 49b)
| ID | Slice | Seam / files | Key / permission | Est. | Done when |
|---|---|---|---|---|---|
| 50a | **Done 2026-10-21** (5 tests; app layer not wired, 50c does that). Pure `ArtworkAccent`: reduce an artwork's average colour to a readable accent (clamp saturation/contrast, fallback to theme) | Core `ArtworkAccent.swift` + test; pixel read stays in the app layer | none | ~90 | table test incl. near-black, near-white, grey art |
| 50b | `NowPlayingTapPolicy`: tap vs double-tap → {play/pause, open player, open source app} | Core pure + test; wire in the chip | `com.katikati.nowplaying.tapAction` | ~120 | policy table-tested; chip honours the setting. **Done 2026-10-21** (default click = play/pause, double-click = player; single click waits the double-click interval) |
| 50c | Accent on the dock chip + progress ring (reuse `NowPlayingProgress`) | `NowPlayingChip` files | none | ~100 | owner screenshot. **Done 2026-10-21** (capsule glyph + ring; screenshot owed) |
| 50d | Notch: artwork glow on the right ear; drop the song text from the collapsed notch | depends on 51b | `com.katikati.notch.musicGlow` | ~150 | owner screenshot; Reduce Motion path. **Done 2026-10-21, reshaped by owner**: song text kept (fits better); track-change popup replaced by a brightening glow; style halo/pulse/edge, default halo (screenshot owed) |
| 50e | **Done 2026-10-21 (reshaped, screenshots owed):** track change drops a USB-eject-style pill (`NotchTrackPill`) under the notch, skipped while expanded; music page gains accent progress, elapsed/remaining times and an equalizer. Policy/setting not built. Was: `NowPlayingToastPolicy` + compact toast on track change while collapsed | Core pure + test; `NotchMusicPanel` | `com.katikati.notch.trackToast` | ~160 | shown once per track; suppressed in fullscreen/Do Not Disturb (verify how existing code reads those) |
| 50f | Dock/edge chips reuse the accent (consistency pass). **Owner design call first:** a single artwork accent (50a) vs a multi-colour dock palette; the colour-reduction function is 50a either way | Lane B hot-file touch | — | ~80 | owner screenshot; a "none/theme" setting stays |
| 50g | **Parked:** lyrics, equalizer. ~~No data source~~ — lyrics have one (rev 3): Vorssaint looks them up opt-in from `lrclib.net` (`musicbrainz.org` optional) and states it in its privacy notes. That is an outbound request naming the track, so it needs an owner call and a Settings privacy line first. The equalizer needs an audio tap | — | lyrics: network (opt-in); equalizer: audio capture | — | owner decision (7, item 12) |

### Phase 51 — Notch geometry, motion, pages (Lane A; after Q-notch)
| ID | Slice | Seam / files | Key | Est. | Done when |
|---|---|---|---|---|---|
| 51a | **Audited 2026-10-21, no code change (live check on a notch Mac owed):** header, ears and rest chips already leave `closedSize.width` clear (wider than the 160pt keepout box), and every panel sits below the cutout. Was: Honour `cameraKeepoutBox` in the views (no content under the cutout) — fix only what Q-notch finds | `NotchHeaderView`/`NotchHomeView`, `NotchGeometryTests` | — | ~100 | live check on a notch Mac |
| 51f | **Done 2026-10-21:** `NotchDesign` (notch / wideBar / off) per display id, default notch on a notch screen, wide bar elsewhere (external-display bar, owner request) | `NotchBehavior`, `NotchGestureTests` | `com.katikati.notch.displayDesigns` | ~60 | done
| 51g | **Done 2026-10-21 (live check on 2 displays owed):** `NotchPanelCoordinator` keeps one `NotchPanelController` per non-off display; Settings "Notch Behavior" lists a Notch / Wide bar / Off menu per display (replaces the old Display picker). Wide bar still draws the notch until 51h | `NotchPanelController`, `AppDelegate`, `LiveIslandSettingsBlock` | same | ~120 | live
| 51h | **Done 2026-10-21 (live check on an external display owed):** wide bar closed view with date+time, now playing, battery, storage + Wi-Fi/volume, running-timer chip, weather, CPU/RAM (items drop by width via `NotchWideBarSpec`) | `NotchWideBarView`, `NotchWideBarSpec` | — | ~120 | live
| 51i | Wide bar open: needs no code — same `NotchModel`/pages panel grows from the bar, and the pills anchor to `model.closedSize.height`. Live check owed | `NotchPanelController`, `NotchTrackPill` | — | 0 | live
| 51b | **Done 2026-10-21** (`NotchLayoutSpec.earZones`, 2 tests; no view uses it yet, 50d will). Split-ear zones: extend the **existing** `NotchLayoutSpec` (153 lines: sizes, `headerHeight`, `openPanelSize`) with a pure "what may sit left/right of the cutout" function; test in the existing `NotchLayoutSpecTests` | `NotchLayoutSpec.swift` + `NotchLayoutSpecTests.swift` | — | ~120 | |
| 51c | **Done 2026-10-21 (live check owed):** `NotchPageLayout` in `NotchSectionPaging.swift`, drag list + eye in Settings, hidden default page falls back to first shown, hiding the last page warns then turns the notch off. Was: Page order / hide: pure `NotchPageOrder.apply` feeding `NotchPage.visible`; settings list | `NotchSectionPaging.swift` + test | `com.katikati.notch.pageOrder` | ~180 | `defaultPage` still valid when its page is hidden |
| 51d | **Done 2026-10-21, reshaped (live check owed):** `BatteryBuddyPolicy` (≤20%, once per dip) + a pill under the notch instead of an ear, since the ears exist only during an activity; no charging trigger, `system_profiler` has no charging flag; polls every 5 min. Was: Battery buddy on an ear when a Bluetooth device charges/low (reuse `BluetoothDevices`) | Core pure + view | `com.katikati.notch.batteryBuddy` | ~150 | |
| 51e | Motion tuning in `NotchMotionSpec` (live: `NotchIslandView:105`, `LiveIslandSettingsBlock:117`, pinned by `NotchDesignSpecTests:87-93`) — only against an owner screen recording. **First delete the dead duplicate** `NotchLayoutSpec.openSpring/closeSpring` (0.42/0.8 and 0.45/1.0 — zero references anywhere, and they disagree with the live 0.38/0.82 and 0.32/1.0) | `NotchMotionSpec.swift`, `NotchLayoutSpec.swift` | — | ~40 | owner approves feel; one source of truth for the springs |

### Phase 52 — AI status (Lanes A/D; after Q-utils)
| ID | Slice | Notes |
|---|---|---|
| 52a | **Done 2026-10-21.** Fixture tests per provider parser from current real logs. **Codex:** the 2026 rollout envelope (`ordinal` + `payload`: `session_meta`, `task_started`, `message`, `item_completed`, `task_complete`) carries no usage and yields nothing; `token_count` is read from `last_token_usage` deterministically, never the cumulative `total_token_usage`, and now understands `cached_input_tokens`, `cache_write_input_tokens` and `reasoning_output_tokens`; a rate-limit-only `info:null` is ignored. **Claude:** current assistant line (nested `cache_creation` / `output_tokens_details`), cache writes whose parent total is 0, all-zero `<synthetic>` lines, millisecond timestamps, and plan history taking the newest sample. 8 new tests (23 in `AgentUsageTests`). Real-data check: all 29 local transcripts (7,911 turns) parsed and matched an independent count to the token; this Mac's Codex logs held no `token_count`, so that envelope is from the upstream protocol (`openai/codex` `main`) | feeds Q-utils; Core/Tests only |
| 52b | **Done 2026-10-21 (record only, no code).** The notch AI page's ACTIVE/IDLE already comes from `AgentUsageService`'s `activeTurn`: the newest Claude turn whose transcript mtime is under 300 s (`isRecent` in `refreshAsync`), with `lastMeasuredModel` as the idle title. Verified by reading `NotchAIPageView` and the service. Known lag: a finished turn keeps reading ACTIVE for up to five minutes — 52c removes it. | no new code; read-only |
| 52c | **Done 2026-10-21; live-checked.** Opt-in Claude hook. Pure `ClaudeHookConfig`: merge/remove two marker-tagged entries (`UserPromptSubmit` = working, `Stop` = idle) in `~/.claude/settings.json`, every unknown key and other people's hooks kept, a second install changes nothing. Pure `ClaudeHookStatus`: newest `<epoch> <event>` line → working/idle, no override once it is older than 300 s, junk lines skipped. `ClaudeHookInstaller`: reads, plans, writes atomically, one-time `settings.json.katikati-backup`, refuses a file that is not a JSON object without writing. `AgentUsageService` reads the newest event, so `Stop` ends the Claude turn at once and `UserPromptSubmit` keeps it active. Off-by-default toggle in **Tools** (`com.katikati.agent.claudeHook`) carrying the write warning and the Claude Code restart note. 5 new tests (28 in `AgentUsageTests`) | owner decision: approved 2026-10-21; outward-facing config write |
| 52d | Loadout-style presets — port or skip | owner scope decision |

**Phase 52 notes (2026-10-21).** 52a is in (8 new tests; full suite 2638 tests, 2 skipped, 0 failures; three checkers green). What the fixtures caught, all fixed in the parsers: Codex read the cumulative session total per `token_count` line (inflating a day by the turn count) and ignored the current `cached_input_tokens` / `cache_write_input_tokens` / `reasoning_output_tokens` names; Claude dropped cache writes whose parent total was zero (7,494 tokens across the local corpus), turned `<synthetic>` zero-token lines into turns, and could not parse the millisecond timestamps every real line carries (all 7,922 were falling back to file mtime). Not verified: this Mac's Codex logs contained no `token_count` event, so that envelope is asserted from the upstream protocol rather than a local sample; the repeated-update double count stays as a documented `shortcut:`. 52d untouched.

**Phase 52 notes (2026-10-21, second pass).** 52b was already built (record only). 52c is in: 5 new tests (28 in `AgentUsageTests`), full suite 2643 tests, 2 skipped (live torrent), 0 failures, exit 0; three checkers green. **Live check, on this Mac's real settings:** with the app on the Tools page, an AX click on the toggle added only `hooks` to `~/.claude/settings.json` (every other key unchanged) and wrote the 960-byte `settings.json.katikati-backup`; the two installed commands then appended `<epoch> UserPromptSubmit` and `<epoch> Stop` to the log exactly as `ClaudeHookStatus` reads them; an AX click off left the file semantically identical with the `hooks` key gone, and the test's log and backup were removed so the file is back to its original bytes. **Not verified (OWED):** the notch flipping ACTIVE → IDLE from a real Claude Code turn — it needs a Claude Code session the owner starts while watching the notch. **Risks:** enabling rewrites the file through `JSONSerialization`, so spacing and key order are normalised even though no key changes; the hook takes effect only after Claude Code restarts; a session that is killed never sends `Stop`, so the page reads IDLE until the next prompt, and after 300 s the old mtime rule returns anyway; `UserPromptSubmit` also fires for slash commands. 52d was not built — "Loadout-style presets" has no spec in the repo, so it stays an owner scope call rather than invented code.

### Phase 53 — Input features (Lane C; after Q-input; all through the pure `KeyGuardPipeline`)
| ID | Slice | Seam | Key / permission | Est. | Done when |
|---|---|---|---|---|---|
| 53a | **Done 2026-10-21 (live check owed):** Caps Lock protection — `CapsLockGuard` swallows the key and toggles it once a 0.15 s hold passes; a shorter tap does nothing. The toggle is a posted key event, so the guard stays inert without event-posting permission, and while Hyperkey is on (Caps Lock is F18 before the tap). Was: ignore a tap shorter than N ms; interplay table with Hyperkey (Caps→F18) | `KeyGuard.swift` + `KeyGuardTests`; toggle in `KeyGuardService` | `com.katikati.keyguard.capsHold`; Input Monitoring + event posting | ~140 | table covers Hyperkey on/off |
| 53b | **Done 2026-10-21 (live check owed):** Finder key map — `FinderKeyMap` rewrites ⌘X → ⌘C and, after a cut, ⌘V → ⌘⌥V, so copy-then-move needs no synthetic keys. Return already renames in Finder, so it is untouched. `shortcut:` the rewrite also hits Finder text fields. Was: Finder key map (⌘X/⌘V move, Return rename) gated on frontmost = Finder | pure `FinderKeyMap` + test; frontmost gate in `KeyGuardService` | `com.katikati.keyguard.finderKeys` | ~150 | nothing swallowed when off (`testNothingSwallowedWhenAllGuardsOff` stays) |
| 53c | **Done 2026-10-21 (live check owed):** system-wide snippet expansion — `SnippetExpander` (beside `CustomCommands.parseSnippets`) builds the current word from plain key events and completes it on space / return / tab; `KeyGuardService` deletes the typed trigger with tagged backspaces and pastes the expansion, cancelling if a newer copy replaced the pasteboard first. `shortcut:` triggers are one word of 2+ characters, only those three delimiters complete them, the deny list (1Password, Bitwarden, Keychain) is fixed, and insertion needs event posting. Was: pure `SnippetExpander` over typed buffer + `CustomCommands.parseSnippets` | Core + test; insertion via pasteboard-and-paste | `com.katikati.snippets.expand` | ~220 | disabled in secure input and for ignored apps; the paste cancels if a newer copy replaced the pasteboard first (a race Vorssaint fixed) |
| 53d | **Done 2026-10-21 (runtime check owed):** quit-on-last-window-close — `QuitOnLastWindowPolicy` (opt-in bundle-ID list, default empty, Finder/Dock/SystemUIServer/KatiKati always ignored) plus `QuitOnLastWindowService`, which watches the opted-in apps with its own `AXObserver` (window-created on the app, element-destroyed on each window) instead of touching the behaviour-frozen `AppTracker`/`AccessibilitySource`. It quits only on a *successful* read that went from ≥1 window to 0, waits 0.25 s for a replacement window, and calls `terminate()` so the app's own save prompt still runs. Settings row in **Tiling**. Was: pure `QuitOnLastWindowPolicy`, **opt-in per app, default empty** (unsaved work risk) | Core + own AX observer | `com.katikati.windows.quitOnClose` | ~200 | settings row live-checked; the quit itself is **OWED** (no safe host app: every app we could launch without the owner's data self-terminates on last-window close on this macOS, so no controlled A/B) |
| 53e | Tap-hub measurement: input latency + CPU with 1 vs 4 taps. **No code.** | notes | — | — | owner decides whether a hub is worth a rewrite |
| 53g | Paste a clipboard image into the front Finder window as a `.png` file: pure `PasteImageNaming` (unique filename, no overwrite) + test; Finder target-folder lookup and file write in the service. Own slice: touches the user's files | Core + service (Lane D, Finder hot touch with 53b) | `com.katikati.clipboard.pasteImage`; Automation (Apple Events → Finder) | ~150 | never overwrites; clear message when no Finder folder is frontmost; owner sign-off |
| 53h | Keyboard \| Mouse & Gestures segmented control inside the Shortcuts page (no 19th tab). **Deferred** until ≥ 2 gesture settings exist — today there is one (the four-finger pinch section, `SettingsLayoutPane+Shortcuts.swift` ~`:148`) | Lane F | — | ~80 | |
| 53i | **Done 2026-10-21 (live check with Screen Sharing owed):** SlowQuit pass-through — `SlowQuitPassthrough` (default: Screen Sharing, Parallels, VMware Fusion, UTM; editable list in Settings) keeps its native ⌘Q instead of holding it. `shortcut:` no hold-to-confirm replay — that would need synthetic keys. Was: forward a ⌘Q confirmed by holding or double-pressing | `KeyGuard.swift`, `KeyGuardTests`, service + Settings row | `com.katikati.keyguard.passthroughApps` | ~120 | table test; live check with Screen Sharing frontmost; owner picks the default app list |

**Phase 53 notes (2026-10-21).** 53a, 53b, 53c, 53d and 53i are in (`CapsLockGuard`, `FinderKeyMap`, `SnippetExpander`, `QuitOnLastWindowPolicy`/`Service`, `SlowQuitPassthrough`; 19 new tests; full suite 2630 tests, 2 skipped, 0 failures; three checkers green). Q-input-a was already merged in `e1a6ec6`. **53d recommendation:** staying running stays the default; the owner types bundle IDs, the service is inert while the list is empty, and quitting uses `terminate()` rather than `kill`, so an unsaved-changes prompt is allowed to appear. It deliberately does not hook `AccessibilitySource` — its own observer keeps the input path's frozen behaviour untouched. Verified live: the Tiling row renders with its empty field. Not verified: the actual quit (every safe host app on this macOS self-terminates on last-window close, so there was no app for a controlled A/B) and every earlier live run (Caps Lock hold in a real field, ⌘X/⌘V in Finder, a snippet typed in TextEdit and in a password field, Screen Sharing frontmost) — that needs the owner and the permissions. Risks: caps protection and snippet insertion depend on event-posting trust and are silently inert without it; the Finder rewrite also applies inside Finder's rename/search fields; passthrough is native ⌘Q with no hold confirmation; snippet paste is cancelled rather than replayed if the clipboard changes mid-paste; 53d is silently inert without Accessibility and a typo in the list simply matches nothing. **Still open:** 53e (owner measurement, no code), 53g (owner sign-off, writes files), 53h (deferred).

### Phase 54 — Window management (Lanes C+B; after Q-bar)
| ID | Slice | Notes |
|---|---|---|
| 54a | **Done 2026-10-21 (modifier click live check OWED).** Verified today's behaviour first: a window chip's plain click already toggles — frontmost app + active window → minimise, otherwise activate (`LifecycleActionPlanner`) — and a persistent `app-` chip hides its app (Finder excepted, which always activates). Those paths are untouched. What was missing is the modifier pair: ⌥ hides the app, ⌘ minimises the window, both together fall back to the plain click. Pure `DockClickPolicy` + one call site in `ChipView.performPrimaryTap()`, reading the flags at tap time because the tap gesture carries none. On a grouped chip the modifiers act on the chip's `actionWindowID` instead of cycling. 1 test. **OWED:** a real ⌥/⌘ click on a chip — the strip's chips have no AX title, so a click has to be aimed by hand | Core + test |
| 54b | **Spike 2026-10-21, no code.** Measured here (screen recording already granted): one 920×492 window thumbnail through `SCScreenshotManager` = **median 33.5 ms, max 85.1 ms**; `CGWindowListCopyWindowInfo` = **median 0.16 ms, max 12.4 ms**. So a hover preview must never capture on the pointer's path: 33 ms is several frames, and the 85 ms tail is what a first capture after a permission change or display wake looks like. Recommendation: only behind off-by-default, capture off-main with one in-flight job per window and a stale-cache-first paint, gated on `CGPreflightScreenCaptureAccess()` plus sleep/lock. No code until the owner asks. | **Screen Recording permission**; idle-CPU gate vs Q1 |
| 54c | **Spike 2026-10-21, no code — recommendation: do not build.** Overriding ⌘Tab needs a session-level `CGEventTap` with `.headInsertEventTap`: Accessibility, re-posting every keystroke we do not handle, and a hard stop under secure input. Secure input is off right now (`IsSecureEventInputEnabled()` = false) but turns on in password fields and some terminals, and that is exactly the documented failure (Vorssaint's switcher went dead until fixed). If it is ever built it must hand ⌘Tab back to the system the moment secure input is on. | spike only |
| 54d | **Done 2026-10-21; live-checked.** `spaceOrderCommands(fixed:original:)` is one `defaults write com.apple.dock mru-spaces` plus exactly one `killall Dock`; `setFixedSpaceOrder` remembers the user's own value once in `com.katikati.nativeDock.mruSpacesOriginal` and writes it back when switched off — with nothing remembered it writes nothing at all. `readMruSpaces` reads a missing key as automatic and a non-boolean as unreadable. Settings → Tools → Shelf card → System Dock gains a confirmed **Fixed Space Order** switch (the confirmation covers the macOS change and the one Dock restart; turning it off needs none). 4 tests. **Live on this Mac:** staged `mru-spaces` 1 → switch on wrote 0 and restarted the Dock (pid 47540 → 47583) → switch off wrote 1 back and restarted again (47583 → 47610); the machine's own 0 was then restored. | changes a macOS setting → explicit in-app confirmation, restore on off |
| 54e | **Done 2026-10-21 (raise live check OWED).** Pure `FocusFollowPolicy` + `FocusFollowService`: a global mouse-moved monitor installed only while the switch is on and Accessibility is granted, a 120 ms throttle, skipping drags (`pressedMouseButtons`), our own key window, our own pid and the app already in front; AX hit test at the pointer, walk up to the `AXWindow` ancestor, `activate()` + `kAXRaiseAction`. Off by default (`com.katikati.windows.focusFollow`), started at launch only when set, row in **Tiling** with the rules in its note. 4 tests. **Live:** the row renders and the switch persists; the raise itself could not be exercised — a scripted `CGWarpMouseCursorPosition` + synthetic `CGEvent.mouseMoved` reaches no global monitor on this Mac (a bare `addGlobalMonitorForEvents` observer saw zero events), so it needs a physical mouse move. Pop-ups are not kept open against a move to their window yet | pure policy + test |
| 54f | **Spike 2026-10-21, no code — recommendation: no override.** Probe result: the green button *is* reachable through the public AX API — on a real Finder window `kAXZoomButtonAttribute` resolved (AXError 0) and the button advertises `AXPress`. That buys programmatic zoom/full-screen, not a new meaning for a click on the green button: intercepting that click still needs an event tap above every app. If the owner wants a shortcut that zooms the frontmost window, it can be built on the AX press path with no private API. | probe only |

**Phase 54 notes (2026-10-21).** 54a, 54d and 54e are in (`DockClickPolicy`, `spaceOrderCommands`/`setFixedSpaceOrder`, `FocusFollowPolicy`/`FocusFollowService`; 9 new tests). **Recommendations from the three spikes:** build none of them yet. Hover previews are affordable only off the pointer's thread and off by default (33 ms median per thumbnail); the ⌘Tab override is a secure-input trap; the green button already has a public AX path, so an override would add risk for nothing. **Live:** the `mru-spaces` round trip is measured above end to end, and both new Settings rows were read back through the AX tree (Tools → Fixed Space Order, Tiling → Focus Follows the Mouse). **OWED:** a real ⌥/⌘ chip click (chips have no AX title) and the focus-follow raise (scripted pointer moves never reach a global monitor on this Mac). **Risks:** fixed order rewrites a system preference — the remembered value is our only undo, and a failed Dock read means turning the switch off writes nothing back; focus-follow moves another app's window without a click (mitigated: 120 ms, no drags, no own panel, never the frontmost app) and is silently inert without Accessibility; the chip modifier read is global keyboard state at tap time.

### Phase 55 — Clipboard, capture, drawer (Lane D)
| ID | Slice | Notes |
|---|---|---|
| 55a | **Done (already in the tree; recorded 2026-10-21):** copy sound (`soundsKey`, Tink), `ClipboardToastPolicy` and the notch toast wired through `liveEventCenter.deliver` in `AppDelegate` | `com.katikati.clipboard.sounds` / `…notchToast`, ~120 |
| 55b | **Done 2026-10-21 (live check owed):** the `screencapture` runner moved to `CaptureController.captureAreaToClipboard()` / `captureWindowToClipboard()` (the dial now calls it), and `.captureArea` is a `ShortcutAction` (hot key id 42, default off) that fires it from `AppDelegate` | lane B/D hot touch, ~100 + ~80 |
| 55c | **Done 2026-10-21 (live check owed):** `ImageReducePlan` (quality 0.2–0.9, longest edge capped at 75 %) + `ShelfActions.reduceImage` writing `name reduced.jpg` / `.heic` next to the original; shelf bar button and context-menu item | Core + test, ~150 |
| 55d | **Done 2026-10-21 (live check owed):** review-first cache cleaner — `CleanupPlan` (user cache/log roots, direct children only, ≥7 days old, ≥50 MB, never `com.apple.*`, `com.katikati.*` or `*.noindex`) and `CleanerService.scan()/clean()`. The notch Storage page's **Review Caches…** builds the dry-run list, an `NSAlert` names the count, total and first eight folders, and only its **Move to Trash** button runs `trashItem` (never `unlink`). **No timer and no automatic deletion**: the recommendation was opt-in per press rather than a schedule, so the unimplemented part is a background job that deletes while nobody is watching. Was: scheduled cleaner with `StorageScanService` + schedule; dry-run first, Trash only | `CleanupPlan` + service + notch page, ~220 | live: storage page needs the notch hover, **OWED**; pure plan has 3 tests |
| 55e | LocalSend / AirDrop-style send | network feature → owner decision + licence; parked |
| 55f | Cobalt media download | licence/legal decision; parked |
| 55g | **Done 2026-10-21 (live check owed):** clipboard retention — pure `ClipboardRetention.prune(entries, now:, days:)` (pinned entries never pruned, 0 = off) + 3 tests, run after every recorded copy. Settings → Tools picker **Keep Clipboard History** with Forever (default) / 7 days / 30 days; changing it prunes what is already in memory. There is nothing to prune at launch because history is memory-only. Destructive actions now ask first: **Clear History** in the clipboard flyout and **Clear Unpinned** in Settings → Tools → Shelf. Was: retention rev 3 with owner sign-off; key `com.katikati.clipboard.keepDays`, **default off** | `ClipboardHistory.swift` + `ClipboardMonitor` + Tools rows; ~110 | default shows live as **Forever**; the pruning itself is unit-tested, not waitable live |

**Phase 55 notes (2026-10-21).** 55a was already built (it is recorded here now); 55b and 55c are new (full suite 2621 tests, 2 skipped, 0 failures; three checkers green). Not verified: the area shortcut needs Screen Recording plus the owner's selector drag, the reduce action needs a real image comparison, and the copy toast needs a real copy with the setting on. **Blocked on the owner:** 55d (scheduled cleaner: deletes files), 55g (clipboard retention: deletes history) — both are designed to run only with explicit sign-off; 55e/55f stay parked on the licence/network calls.

**Phase 55 notes (2026-10-21).** 55a (already in the tree), 55b, 55c, 55d and 55g are in. **55d recommendation:** no schedule and no background deletion — a timer that removes caches while nobody is watching is the one part of the original slice whose risk outweighs its convenience, so the page exposes a review button instead; everything it lists is still a directory under `~/Library/Caches`, `~/Library/Logs`, `~/Library/Developer/Xcode/DerivedData`, `~/.cache`, `~/.npm` or `~/.gradle`, and every item goes to the Trash. **55g recommendation:** retention is opt-in and defaults to Forever, pinned entries never expire, and the two bulk deletes (clipboard history, unpinned shelf items) now confirm first; single-item remove stays immediate. Verified live: Shortcuts → **Capture Area** row present and unassigned (Off), Tools → **Keep Clipboard History** shows **Forever**, Tools → Shelf → **Clear Unpinned** present, and the Tiling → **Quit when the last window closes** row present. Not verified: the notch Storage page and its Review Caches confirmation (needs the notch hover), the shelf's Reduce Image item (needs the shelf panel), Capture Area with Screen Recording, and image reduce output — all **OWED** to the owner. Risks: the cleaner's Trash move is recoverable but apps rebuild caches (slower first launch); the `com.apple.*`/own-app exclusions are name-based; retention holds the whole history in memory, so a 30-day window still costs RAM; 55e/55f stay parked on licence calls.

### Phase 56 — Widgets (Lane E; after 49c, Q-widgets)
| ID | Slice | Notes |
|---|---|---|
| 56a | **Done 2026-10-21 (live check owed):** pure `YearProgress` + 2 tests, `YearProgressTile`, opt-in toggle `com.katikati.widgets.showYearProgress` (default off) adds it to the Tall layout. Was: Year-in-progress tile | ~120 |
| 56b | **Done 2026-10-21 (Modern chip S/M/L live check owed):** weather size presets verified and reshaped as Phase 56 W0–W13 below | — |
| 56-W | **Weather redesign, all shipped 2026-10-21, live checks owed.** W0–W7 fixes and tiles (stale/offline notice, detail bands, UV/wind/sun); W8 Modern chip + rail tile (default); W9 Modern panel; W10 `WeatherLayoutPreset.fullScreen` (Glance), old Glance renamed Overview, `WeatherGlanceSpec`, migration `c09189d`; W11 full-screen panel host, `PanelGeometry.fullScreenFrame`, Esc, no outside-click close `5aa06d5`; W12 Glance view + scenery, default layout `e03a688`; W13 Overview shows the one-page panel, setting `com.katikati.weather.overviewOnePage` `65ec146`. Notch/music slices are in Phase 50–51 | tests 2595, 0 failures |
| 56c ✅ | Battery redesign + multi-device list (reuse `BluetoothDevices`) | ~200; Vorssaint's Power card also lists accessory batteries without its menu-bar item (7.2) |
| 56d | **Done 2026-10-21 (live check owed), reshaped:** `[TaskItem].smartOrdered` (running, important, open, done; list order kept inside each group) used by the tasks flyout. Tasks have no due date, so there is no due sort; adding one needs a `TaskItem` field + UI (new slice if wanted). Was: Smart tasks | ~120 |
| 56d2 | **Done 2026-10-21 (live check owed):** `TaskItem.due` (start of day, lenient decode), `TaskList.setDue`, `TaskDue` (overdue / today / tomorrow / later), context-menu Due Today / Due Tomorrow / Clear Due Date, a due badge on each row, and `smartOrdered` now ranks running, dated (earliest first, important on a tie), important, rest, done. No date picker or notification yet | ~150 |
| 56e ✅ | Pause / Hydrate prompts — first read `DailyHelpersService`; add only what is missing | ~120 |

### Phase 57 — Launcher modes & Control Center (Lane B; after Q-bar)
| ID | Slice | Notes |
|---|---|---|
| 57a | **Done 2026-10-21 (device-gesture live check OWED).** **Bluetooth half verified unnecessary:** the `.bluetooth` tile already draws `id.symbolName`, fills with the accent when on, dims to 0.35 when the private IOBluetooth symbol is missing and flashes a checkmark, so no icon art was added. Scroll-to-volume: pure `ControlCenterScroll` (6 pt of precise travel = 1.25 %, one notched click = 2.5 %, clamped 0–1, one step per 60 ms, leftover travel kept), wired to `ControlCenterView.volumeRow` by a `VolumeScrollCatcher` `NSViewRepresentable` whose `hitTest` claims `.scrollWheel` only, so the slider keeps its drag and clicks. Two things the live run caught: the catcher needs `noIntrinsicMetric` plus a flexible frame or SwiftUI sizes it 171.5 × 40 instead of the row's 408 × 40, and `status.volume.level` lags a write by one listener hop, so fast steps read a stale base (three 2.5 % steps moved the volume 3 points, not 7.5) — `SystemStatusService.currentVolumeLevel` reads the device instead. 6 tests. `ControlCenterLayout.swift`, `StatusTrioView.swift`, `SystemStatusService.swift` |
| 57b | **Done 2026-10-21 (frames live-verified).** Pure `LauncherPresentation` (fullscreen default — the old behaviour — centred, popover) plus `LauncherPanelFrame.rect(mode:screen:visible:anchor:)` in `Core/Support/LauncherLayout.swift`: fullscreen is the screen rect, centred is 80 % of `visibleFrame` capped at 1200 × 760, popover is 640 × 520 hanging `popoverGap` under the pointer and pulled inside the screen. `LauncherPanelController` reads it at each summon, sizes `model.screenInsets` from the panel (a windowed card needs no menu-bar inset) and rounds the backdrop's corners to 22 pt; fullscreen stays pixel-identical. Settings → Launcher gains the segmented row, in 12 languages. 7 tests. **Live frames** (`CGWindowList`): 1710 × 1112 at 0,0 (fullscreen) · 1200 × 760 at 255,195 (centred) · 640 × 520 at 585,468 (popover); the card renders icons and the search field in all three. **Limit:** a windowed card no longer catches clicks outside itself, so it closes on Esc/⌥Space or a background click inside the card, not by clicking the desktop | `com.katikati.launcher.presentation`, ~200 |
| 57c | **Done 2026-10-21 (live: default corner, drag, click, relaunch).** Owner call: a draggable floating orb. Pure `LauncherOrbPlacement` (56 pt orb, 8 pt margin, bottom-right default, clamped into `visibleFrame`, 4 pt drag slop) in `Core/Support/LauncherLayout.swift`; `LauncherOrbController` (`App/Entry/LauncherOrbController.swift`) owns one borderless non-activating `.floating` panel on every Space, an `OrbHitView` that drags the panel and treats a press without travel as a click (VoiceOver: one button), and a glass `LauncherOrbView` drawing the same glyph as the dock's FAB. Position in `com.katikati.launcher.orb.position`, toggle `com.katikati.launcher.orb` (default **off**) in Settings → Launcher, wired to the launcher's own `toggle()`. 5 tests. **Live:** orb at 1646,1048 (56 × 56, bottom-right above the dock) → dragged to 1072,572 with the pointer, stored `1072.0,484.0` → click opened the launcher (1710 × 1112) → Esc closed it → after relaunch the orb came back at 1072,572. Screenshot + pixel grid confirm the glass disc and glyph. **Limit:** a `.floating` orb also floats over full-screen video; it is opt-in and default off, and the setting is the escape hatch (no full-screen monitor) | after 57b; owner screenshot |
| 57d | **Done 2026-10-21, owner-directed.** Menu-bar menu cleanup (`StatusMenuController.swift`). Verified when written (superseded by Rev 4): `Show Shelf` / `Show Trash` (`:93-94`) are toggled **only** from this menu (no Settings pane has them), so removing them needs a Settings home first (Dock Items page) or users lose the switch. "Show App Name on hover" (`:95`) maps to `hoverStyle`, whose default is `.quiet` **by an owner decision of 2026-09-01** (`AppSettingsStore.swift:64`) — making it default-on reverses that, so it is an owner call (existing users keep their stored value either way). Then move the Dock / KatiKati toggles to General and keep Taskbar Size in Dock Items | `StatusMenuController.swift`, the Settings panes, `SettingsMenu*` tests if any; one slice per move, ≤ ~150 each. **Rev 3: half-landed in `4b3b735`** — the General page now holds the Startup (launch hidden) and Hide Dock icon toggles (`SettingsWindowView.swift`, `StartupUIPolicy`), but the menu still carries `Open at Login`, `Show Shelf`, `Show Trash` and `Show app name on hover` (`StatusMenuController.swift:55,93-95`) and Shelf/Trash still have no Settings home. **Rev 4 (2026-10-21), owner-directed:** Show Shelf, Show Trash, Show app name on hover (default flipped to on) and Keep windows above the taskbar now live in Settings › Dock Items; the menu lost those four rows plus the KatiKati / Dock wake-delay sliders and Dock Settings…, and keeps Open at Login, Taskbar Size and Layout. Free-floating (non-tiled) windows under the bar are **not** covered — tiles already lift by default; that needs a new eligibility class in `WindowLiftAvoidance` and a live run. **Status checked in the tree 2026-10-21:** `StatusMenuController.swift` no longer carries any of the four rows, `SettingsLayoutPane+Widgets.swift:51-70` holds the four toggles, and `HoverStyle.default` is `.standard` (`AppSettingsStore.swift:76`). The live run on a free-floating window is still OWED |
| 57e | Control Center: swap the RAM / Background Apps slot and redo the icon art | **verify first** — ~~the slot and the icon assets are not located in code yet~~ — rev 3 candidates: `DynamicGaugeFABView.swift` (RAM/CPU tooltip), `BackgroundAppsStore.swift`, `BackgroundAppClassifier.swift`, `DrawerView.swift`, `DrawerCapsuleButton.swift`, `BehaviourSettingsBlock.swift`; which surface the owner means is still UNVERIFIED — get a screenshot before touching them |

### Phase 58 — Onboarding (Lane F)
| ID | Slice | Notes |
|---|---|---|
| 58a | **Mostly built** (`d258b3c` welcome step, `154fa7c` Settings block with mic); 2026-10-21: Grant on Screen Recording / Input Monitoring now also opens the Privacy pane, since the prompt shows only once. **Done 2026-10-21 for the mic row** (live check OWED, see below): the Permissions step lists Microphone with `AVCaptureDevice.authorizationStatus(for:)` / `requestAccess`, the `Privacy_Microphone` pane on Grant, and the existing 1 s poll flips it to Granted; `NSMicrophoneUsageDescription` was already in `Resources/Info.plist`. Live attempt: `tccutil reset Accessibility|ScreenCapture|ListenEvent|Microphone com.katikati.app` all returned 0, and the guide itself could not be reached under automation — with the system Dock auto-hiding (this Mac) `WelcomeGuideDecision` correctly skips the guide and marks it seen, and forcing it open needed a temporary `autohide false` + Dock restart; the window then appeared (520 × 485) but System Events exposes no walkable AX tree in it, a Calendar TCC prompt from an unrelated feature took focus, and the four **Grant** clicks are the owner's by design. Machine restored afterwards (`autohide 1`, `launchHidden 1`, `hasSeenWelcome 1`); KatiKati's four grants stay reset until the owner re-grants them in the guide or System Settings. One more gap: a fresh-TCC walkthrough is still owed. Original note: Permissions page after the Phase 9 live test (Accessibility, Screen Recording, Input Monitoring, mic) — already on the owner's list. **Schedule it before 54b (Screen Recording) and before 53a–53c (Input Monitoring) ship** | extend `WelcomeGuideView.swift`; follow `Docs/ONBOARDING_TEST_CHECKLIST.md`; respect `StartupUIPolicy.shouldPresentWelcomeGuide` (guide on first run or when not launching hidden) |
| 58b | Glass intro animation (GlassIntroKit-style) — licence check before any code is borrowed | native re-implementation by default |

## 7. Owner decisions needed
1. Run Q0–Q1 **before** new features (recommended) or in parallel? (Q2 is done, `896f8f6`; Q0's test command and checkers are recorded in section 9.)
2. Who performs the OWED eyeball/grant checks (4.3)? Agents cannot grant Accessibility/Screen Recording.
3. Clear the 2 stale stashes, `/private/tmp/kk-tip`, and decide the fate of `.claude/worktrees/hopeful-gauss-9a1c88`.
4. Set up the `merge=graphify` driver on each clone/worktree; decide whether `FEATURE_ROADMAP_2026-10.md` and `LANES.md`
   are committed (published) at the root or kept untracked.
5. Input: extend `KeyGuardPipeline` (recommended) vs build a single tap hub — decide after 53e.
6. ~~Per-lane string tables (49d): adopt or skip.~~ Decided 2026-10-20: skipped (section 5).
7. Licence/scope calls before any code is borrowed: use the gate in 7.1. Default: native re-implementation.
8. Privacy-sensitive features: hook-based Claude status (writes `~/.claude`), scheduled cleaner, quit-on-close,
   fixed Space order (changes a macOS setting), paste-image-as-PNG in Finder (53g, writes files), clipboard retention (55g, deletes history), lyrics lookup (50g, outbound request). Each needs explicit sign-off.
9. Priority order of Phases 50–58, and the cut list (suggested cut: 50g, 54c, 54f, 55e, 55f). Recommended order:
   Q0–Q1 → 49 → **Q-input-a** → 58a → 51 (51b before 50d) → 50 → 53 → 56 → 55 → 54 → 52 → 57 (57d/57e late, they
   need your calls below). Run at most 2–3 lanes at once (3.4-10).
10. Design call the dock accent needs (50f): one artwork accent or a multi-colour dock palette? (The 57d questions are
    answered and landed — "Show app name on hover" default was flipped to on by the owner on 2026-10-21, and Show Shelf /
    Show Trash now live in Settings › Dock Items.)
11. Settings grid rules 1–9 (`Docs/SETTINGS.md`): keep as soft guidance (recommended) or relax them too? The height
    gate itself is already abandoned (4.4-2).
12. Un-park lyrics (50g)? It means an opt-in outbound lookup (`lrclib.net`) and a privacy line in Settings. Default: stay parked.
13. Rev 3 additions 53i (SlowQuit pass-through) and 55g (clipboard retention): keep both, defaults off / empty list? Default: yes.

### 7.1 Reference-repo licence gate
KatiKati is **GPL-3.0-or-later** (`LICENSE`, `NOTICE`, `STANDING_RULES §5.1`). The real gate is already in the repo: a
donor enters only through a HYBRID_PLAN §5 allow-list row (`STANDING_RULES §2.6`), with a `NOTICE` entry (§5.3) and a
pinned source commit. Licences below were read from GitHub's API labels on 2026-10-20, **not** from source headers (except Vorssaint, whose header was also read) —
re-check the file header of anything actually borrowed. Not legal advice.

| Project | Licence (API label) | Use |
|---|---|---|
| Maccy | MIT | code may be adapted with attribution; clipboard is already built natively |
| KeyCastr | BSD-3-Clause | same; key overlay is already built natively |
| Easydict | GPL-3.0 | GPL-compatible; adapt only through the §5 allow-list |
| SlowQuitApps | **GPL-2.0** | **do not copy** — if the headers say "only", GPL-2.0 cannot be combined into a GPLv3 work; SlowQuit is already built natively |
| Cobalt | **AGPL-3.0** | **do not copy** — network-use clause would bind the combined work; media download stays parked (55f) |
| AirBattery | **AGPL-3.0** | **do not copy** — design reference for the battery widget only (56c) |
| GlassIntroKit | Apache-2.0 (search hit `Jiaxu-Li/GlassIntroKit`; **repo identity unconfirmed**) | GPLv3-compatible; confirm the repo before relying on it; re-implement natively by default (58b) |
| Vorssaint (`vorssaint-utils`) | **GPL-3.0** (SPDX headers read `GPL-3.0-or-later`) | GPL-compatible. Already credited in `NOTICE:91-94` (Dynamic Island settings design). `HYBRID_PLAN.md:1602` says ideas only, rewritten; `:4102` records AgentUsage as ported — any further borrowing needs a §5 allow-list row, a `NOTICE` line and a pinned commit (read at `551f4db`, 2026-10-20, v3.4.2-beta.1 + unreleased) |
| Loadout, claude-status-bar, LocalSend, PingPlace, AltTabby | not checked | check before any code is borrowed; AltTabby is Windows-only (design reference) |

### 7.2 Vorssaint — what shipped recently and where it lands (rev 3)
Read 2026-10-20 at `551f4db` (v3.4.2-beta.1 plus the unreleased section of its `CHANGELOG.md`). A design reference only:
ideas rewritten, nothing copied (licence in 7.1). "Hypothesis" means check it in the named Q-slice — it is **not** a claim
that our code has the same bug.

| Vorssaint change | Lands in | Ours today |
|---|---|---|
| Clipboard items expire after N days; pinned stay | 55g | no age-based retention; pinned + 50-unpinned cap exist |
| Secure input has no change notification; sample only while needed; name the app active when it turned on | Q-input-a, 53c | done (`e1a6ec6`): probe only while the visualizer is on |
| Paste-as-plain-text and snippets cancel if a newer copy replaced the clipboard | 53c, 53g | n/a until those exist |
| Its ⌘Tab replacement went dead under secure input | 54c | no ⌘Tab replacement |
| ⌘Q hold / double-press passed through to Screen Sharing and VMs | 53i | no remote/VM exclusion in `KeyGuard*` (grep) |
| Focus-follows-mouse keeps pop-ups open | 54e | feature MISSING |
| Dock Preview / switcher: pause capture on a slow permission check, display sleep or lock; do not wait on a frozen app; right process instance | 54a, 54b | features MISSING |
| Input taps stopped for cleanup or shutdown no longer restart | 4.4-12, Q-input | hypothesis |
| Notch: not below the physical notch when the menu bar is taller; custom width on every page; no-notch display options; close after a Shelf drag-out | Q-notch | hypothesis |
| Lyrics via opt-in `lrclib.net` (+ optional `musicbrainz.org`) with a privacy note | 50g | parked; owner call (7, item 12) |
| AI Agents: per-Codex-account limits; Claude limits via Claude Code | 52a, Q-utils | parsers in `AgentStoreParsers.swift`; hypothesis |
| Power card lists accessory batteries without the menu-bar item | 56c, 51d | `BluetoothDevices` parser exists; redesign MISSING |
| Command Bar keeps meaningful digits in large calculator results | Q-utils | `CalculatorEngine` — hypothesis |

Not mapped (not on the wishlist, no roadmap item): volume mixer, screenshot-editor tools, App Updates catalog, What's New
window, Firefox cover art, window-switcher options.

## 8. Gate and evidence checklist (copy into each slice note)
- [ ] Files touched ⊆ lane list; every outside touch has a scope-receipt line (`§1.7d`).
- [ ] `xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` → "Executed N tests, with 0 failures" (CI's exact command, `.github/workflows`).
- [ ] `python3 Scripts/check_localization.py` · `python3 Scripts/check_debug_switches.py` · `python3 Scripts/check_availability_warnings.py <log>`.
- [ ] New Core logic has a test; new `DOCK_*` switch registered in `Core/Support/DebugSwitch.swift`; new strings in all 12 languages (human-reviewed).
- [ ] `git diff --stat` ≤ ~300 lines; pbxproj ≤ ~30 lines per file addition; no regenerated generated files.
- [ ] Live recipe run and recorded, or marked **OWED** with the reason (never PASS from a unit test alone).
- [ ] Step note written (3.3); `CHANGELOG.md` updated for user-visible changes.
- [ ] Ended with: what was skipped / not verified, and the risk.

## 9. Baseline record (Q0 fills this in)
| Date | HEAD | `xcodebuild test` | Checkers | Idle CPU (Q1) | Notes |
| 2026-10-21 | `0de204a` (Phase 57b) | ✅ 2667 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1081 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 7 new tests. Live: the three panel frames read from `CGWindowList` — fullscreen 1710 × 1112 at 0,0; centred 1200 × 760 at 255,195; popover 640 × 520 at 585,468 — and a screenshot of each mode shows the grid and search field drawn (the Launcher settings page is captured too). **Not exercised:** clicking the new segmented **Presentation** row itself (System Events exposes no walkable AX tree inside this window on macOS 27 — `entire contents` returns 0), so the store setter is verified by code and by writing the same default the picker writes. |
| 2026-10-21 | `4b87483` (Phase 57a) | ✅ 2660 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1077 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 6 new tests. Live in the running app: the catcher lands on the volume row at **408 × 40** (it was **171.5 × 40** before the flexible-size fix) and driving the real catcher moved the system volume 50→58 (3 notched up), 50→42 (3 down), 50→53 (4 × 3 pt precise), 0→0 and 100→100 (clamp). **OWED:** a physical wheel/trackpad gesture over the panel — synthetic scroll CGEvents are not delivered to the app on this macOS 27 (the app's own global scroll monitor logged nothing with the panel open, and `NSApp.postEvent` of a scroll never reached `hitTest`), so AppKit's routing to the overlay is the one link the probe could not exercise; it called `scrollWheel(with:)` on the live view instead. |
|---|---|---|---|---|---|
| 2026-10-20 | `dac5606` (code = `1ce7963`; `bb3a1f7` adds only this doc) | ✅ `1ce7963`: 2548 tests, 2 skipped (live torrent), 0 failures, exit 0 | `check_localization.py` ✅ (993 keys × 12; 40 source literals); `check_debug_switches.py`, `check_availability_warnings.py` _not yet recorded_ | _owed_ | the 7 `error:` lines in the log are macOS `linkd.autoShortcut` runtime noise, not compile errors |
| 2026-10-20 | `14092d5` (rev 3) | ✅ 2559 tests, 2 skipped (same two live-torrent tests), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1013 keys × 12; 40 source literals); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's complete log | _owed_ | the 7 `error:` lines are `[Connection]`/`xctest` runtime noise (`Unable to get synchronousRemoteObjectProxy…`), not compile errors; +11 tests vs `1ce7963`; live smoke run of the 18 tabs still OWED |
| 2026-10-20 | `c46d6ae` (Q1) | — | — | **Debug build, M3, macOS 27.0.1, `ps %cpu` 60 s after 10 s settle:** defaults avg 17.5 (max 25.4); cpu metric on 15.8; all 5 metrics on 15.4; re-sampled later 18.2. Metric toggles made no visible difference (set via `defaults write`; live pickup unverified). Instruments/Release run _owed_. | Idle ~15-18 % is high. One 3 s `sample` put the hot frames in `WindowLiftAvoidanceController.probeTrackedFrames` → `WindowLiftCGWindowProbe.frames(for:)` (`CGWindowListCopyWindowInfo` per tracked window on a repeating timer, :799). Lead only, not a diagnosis. `git grep` finds 35 `Timer` sites in `App/Composition` + `Platform`, not 16 (includes one-shots). |
| 2026-10-20 | `4c6836b` (Q1 correction) | — | — | **Supersedes the row above.** `ps -o %cpu` on macOS is a lifetime average, so the 15–18 % there was inflated by launch. Instantaneous (`cputime` delta over 30 s, Debug, M3, macOS 27.0.1): **~10.7 % steady** from minute 3 to 5, window lift **off** (lift on measured 18.6 vs off 13.8 on the lifetime-average column, so lift is at most a few points). _owed:_ Release build and Instruments. | `sample` (10 s) saw only ~2–3 % of the 10–16 % that `cputime` reports, so it cannot attribute the load; the "probe timer" lead in the row above is **weak and should not drive a fix**. Visible work in the sample: `SystemMonitorController.refresh` → `SystemMonitorSampler.disk()` (1 Hz, runs even when no Disk metric is shown; held open by edge-bar/FAB views), `RunningApplicationStore` policy rechecks, `AppTracker.reconcile`, SwiftUI image prep. Idle target is unset. |
| 2026-10-21 | `6bcf104` (Phase 53a/53b/53i) | ✅ 2613 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1044 keys × 12; 40 source literals); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 11 new tests. Live checks for all three guards **OWED** (Caps Lock hold, Finder ⌘X/⌘V, Screen Sharing frontmost) — they need the owner and the grants |
| 2026-10-21 | `b55676f` (Phase 53c + 55b/55c) | ✅ 2622 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1048 keys × 12; 40 source literals); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 9 new tests (snippets 7, image plan 2). Live checks **OWED** for snippets (TextEdit + a password field), the Capture Area shortcut and image reduce; 53d/53g and 55d/55g await the owner | 
| 2026-10-21 | `0bd7e01` (Phase 53d + 55d/55g) | ✅ 2630 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 — CI command with `build/DerivedData` and `CODE_SIGNING_ALLOWED=NO` | `check_localization.py` ✅ (1066 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on a clean-build log (1 log); `Scripts/build_and_run.sh --verify` ✅ (BUILD SUCCEEDED, app running) | _owed_ | 8 new tests (53d 2, 55d 3, 55g 3). Live via AX: Tiling quit-on-close row, Shortcuts → Capture Area (Off), Tools → Keep Clipboard History (Forever), Tools → Clear Unpinned. **OWED**: the actual quit (no safe host app — every candidate self-terminates on last-window close here), notch Review Caches, shelf Reduce Image, Capture Area with Screen Recording, image reduce, snippets/password field, Caps Lock/Finder/Screen Sharing. 53e, 55e and 55f parked. |
| 2026-10-21 | `dd16cf7` (Phase 52a) | ✅ 2638 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1066 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 8 new tests: Codex `token_count` now counts the turn, not the session total; Claude counts 0-parent cache writes, skips `<synthetic>` zero-token lines and reads millisecond timestamps. Real corpus: 29 transcripts, 7,911 turns matched an independent count. Codex envelope asserted from the upstream protocol — the local logs held no `token_count` event. |
| 2026-10-21 | `10c8d60` (Phase 52b record + 52c) | ✅ 2643 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1070 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log; `Scripts/build_and_run.sh --verify` ✅ | _owed_ | 5 new tests (28 in `AgentUsageTests`). Live via AX on the Tools page: the switch added only `hooks` to the real `~/.claude/settings.json` and wrote the one-time backup, the installed commands appended `<epoch> UserPromptSubmit` / `<epoch> Stop`, and switching off left the file semantically identical (test log and backup then removed, original bytes restored). **OWED:** the notch ACTIVE→IDLE flip from a real Claude Code turn. |
| 2026-10-21 | `fb36a50` (Phase 54: 54a, 54d, 54e; 54b/54c/54f spikes) | ✅ 2652 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1077 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log; `Scripts/build_and_run.sh --verify` ✅ | _owed_ | 9 new tests (54d 4, 54a 1, 54e 4). Live: the `mru-spaces` round trip through the Tools switch (1 → on wrote 0, Dock 47540→47583 → off wrote 1, 47583→47610; the machine's own 0 then restored) and both new Settings rows read back through AX. **OWED:** a real ⌥/⌘ chip click (chips carry no AX title) and the focus-follow raise (scripted pointer moves reach no global monitor here). Spike numbers: SCK thumbnail 33.5 ms median / 85.1 ms max, window list 0.16 ms median, green button advertises `AXPress`, secure input off. |
| 2026-10-21 | `12c24f5` (track pill text fix, owner report; `03c9895` + the rounded-face measurement) | ✅ 2654 tests, 2 skipped (live torrent), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1077 keys × 12); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's log | _owed_ | 2 new tests. The pill sizes itself with `NSHostingView.fittingSize` and `MarqueeText` takes only the width it is offered: the pre-fix body measured **76 pt** (`VStack` + `maxWidth(170)` gave the column ~4 pt, so both lines rendered as slivers), the fixed body **242 pt** — probed by temporarily rendering the old body inside the test target, then removed. An offscreen render of “Midnight City” / “M83” puts **78.5 pt of ink in an 83 pt column**; a caption pill reads 177 × 48 pt. **OWED:** a screenshot of the live pill on a real track change; the Music library on this machine holds 0 tracks, so nothing can trigger one. |
