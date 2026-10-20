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
| Calculator keypad tile, mic recorder tile | BUILT (new, `8391671`, `be52384`) | in `CalendarPanelView.swift`; mic permission added; Q-widgets checks the denied-permission path |
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
                   Phase 49  49a LANES.md ─► 49b / 49c pure splits ─► 49e batching rule
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
1. **Key visualizer and secure input.** grep finds no secure-input/password handling in `KeyGuard.swift`,
   `KeyGuardService.swift`, `KeyVisualizerOverlay.swift`, and no `IsSecureEventInputEnabled` anywhere in
   `App/Core/Platform`. Verify live what the overlay shows in a password field (macOS may already withhold the text);
   if it shows anything, suppress + clear the buffer. **Whatever the overlay does today, the guard is mandatory before
   any feature that reads typed text (snippet expansion 53c):** slice Q-input-a.
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
   `NowPlayingChip.swift` is 1375 lines holding six views. Both are split by 49b/49c before more lands in them.
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
| **Q-input-a** | Secure-input guard: pure `SecureInputPolicy` (+ test) deciding when typed-key consumers must stay blind; one `IsSecureEventInputEnabled` call in the service; the visualizer clears its buffer under secure input. Hard prerequisite of 53c. Design notes from Vorssaint (7.2): macOS posts no change notification for secure input, so read it only while a consumer needs it (visualizer on, expansion on), not on a timer; when Settings names the holder, name the app that was active when it turned on, never KatiKati itself | C | test table; live check in a password field |
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
| 49a | Root `LANES.md`: section 3.2/3.3 as the live claim board (one line per active slice). Root, not `Docs/` — see header | F | ~60 | none (docs) | every active agent has a line; file is tracked |
| 49b | Split `NowPlayingChip.swift` into one file per view (`NowPlayingChip`, `NowPlayingPopup`, `TurntableView`, `ExpandedMediaCardView`, …) — **pure move** | A | ~0 net + ~20 pbxproj | CI command; byte-identical code | no logic diff; `git diff -M` shows moves only |
| 49c | Move the calculator and recorder tiles out of `CalendarPanelView.swift` into their own files — pure move | E | ~0 net + ~8 pbxproj | CI command | same |
| 49e | Decide the Settings-registration pattern: batched tab additions through the integrator | F | docs only | — | rule written in `LANES.md` |

(Ids 49d and 49f are retired, not reused.)

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
| 50a | Pure `ArtworkAccent`: reduce an artwork's average colour to a readable accent (clamp saturation/contrast, fallback to theme) | Core `ArtworkAccent.swift` + test; pixel read stays in the app layer | none | ~90 | table test incl. near-black, near-white, grey art |
| 50b | `NowPlayingTapPolicy`: tap vs double-tap → {play/pause, open player, open source app} | Core pure + test; wire in the chip | `com.katikati.nowplaying.tapAction` | ~120 | policy table-tested; chip honours the setting |
| 50c | Accent on the dock chip + progress ring (reuse `NowPlayingProgress`) | `NowPlayingChip` files | none | ~100 | owner screenshot |
| 50d | Notch: artwork glow on the right ear; drop the song text from the collapsed notch | depends on 51b | `com.katikati.notch.musicGlow` | ~150 | owner screenshot; Reduce Motion path |
| 50e | `NowPlayingToastPolicy` + compact toast on track change while collapsed | Core pure + test; `NotchMusicPanel` | `com.katikati.notch.trackToast` | ~160 | shown once per track; suppressed in fullscreen/Do Not Disturb (verify how existing code reads those) |
| 50f | Dock/edge chips reuse the accent (consistency pass). **Owner design call first:** a single artwork accent (50a) vs a multi-colour dock palette; the colour-reduction function is 50a either way | Lane B hot-file touch | — | ~80 | owner screenshot; a "none/theme" setting stays |
| 50g | **Parked:** lyrics, equalizer. ~~No data source~~ — lyrics have one (rev 3): Vorssaint looks them up opt-in from `lrclib.net` (`musicbrainz.org` optional) and states it in its privacy notes. That is an outbound request naming the track, so it needs an owner call and a Settings privacy line first. The equalizer needs an audio tap | — | lyrics: network (opt-in); equalizer: audio capture | — | owner decision (7, item 12) |

### Phase 51 — Notch geometry, motion, pages (Lane A; after Q-notch)
| ID | Slice | Seam / files | Key | Est. | Done when |
|---|---|---|---|---|---|
| 51a | Honour `cameraKeepoutBox` in the views (no content under the cutout) — fix only what Q-notch finds | `NotchHeaderView`/`NotchHomeView`, `NotchGeometryTests` | — | ~100 | live check on a notch Mac |
| 51b | **Done 2026-10-21** (`NotchLayoutSpec.earZones`, 2 tests; no view uses it yet, 50d will). Split-ear zones: extend the **existing** `NotchLayoutSpec` (153 lines: sizes, `headerHeight`, `openPanelSize`) with a pure "what may sit left/right of the cutout" function; test in the existing `NotchLayoutSpecTests` | `NotchLayoutSpec.swift` + `NotchLayoutSpecTests.swift` | — | ~120 | |
| 51c | Page order / hide: pure `NotchPageOrder.apply` feeding `NotchPage.visible`; settings list | `NotchSectionPaging.swift` + test | `com.katikati.notch.pageOrder` | ~180 | `defaultPage` still valid when its page is hidden |
| 51d | Battery buddy on an ear when a Bluetooth device charges/low (reuse `BluetoothDevices`) | Core pure + view | `com.katikati.notch.batteryBuddy` | ~150 | |
| 51e | Motion tuning in `NotchMotionSpec` (live: `NotchIslandView:105`, `LiveIslandSettingsBlock:117`, pinned by `NotchDesignSpecTests:87-93`) — only against an owner screen recording. **First delete the dead duplicate** `NotchLayoutSpec.openSpring/closeSpring` (0.42/0.8 and 0.45/1.0 — zero references anywhere, and they disagree with the live 0.38/0.82 and 0.32/1.0) | `NotchMotionSpec.swift`, `NotchLayoutSpec.swift` | — | ~40 | owner approves feel; one source of truth for the springs |

### Phase 52 — AI status (Lanes A/D; after Q-utils)
| ID | Slice | Notes |
|---|---|---|
| 52a | Fixture tests per provider parser from current real logs | feeds Q-utils; Core/Tests only, ~150; first targets `AgentCodexParser` (per-account limits, evolving envelope) and the Claude-limits path — all provider parsers are in `AgentStoreParsers.swift` |
| 52b | "Working / idle" indicator from transcript file activity (read-only, reuse `AgentClaudeParser` inputs) | **no writing to the user's Claude settings/hooks** in this slice |
| 52c | Hook-based status (claude-status-bar style) — would write to `~/.claude` config | owner decision + licence check first (outward-facing config change) |
| 52d | Loadout-style presets — port or skip | owner scope decision |

### Phase 53 — Input features (Lane C; after Q-input; all through the pure `KeyGuardPipeline`)
| ID | Slice | Seam | Key / permission | Est. | Done when |
|---|---|---|---|---|---|
| 53a | Caps Lock protection: ignore a tap shorter than N ms; interplay table with Hyperkey (Caps→F18) | extend `KeyGuardPipeline` + `KeyGuardTests` | `com.katikati.keyguard.capsHold`; Input Monitoring (already used) | ~140 | table covers Hyperkey on/off |
| 53b | Finder key map (⌘X/⌘V move, Return rename) gated on frontmost = Finder | pure `FinderKeyMap` + test | `com.katikati.keyguard.finderKeys` | ~150 | nothing swallowed when off (`testNothingSwallowedWhenAllGuardsOff` stays) |
| 53c | System-wide snippet expansion: pure `SnippetExpander` over typed buffer + `CustomCommands.parseSnippets` | Core + test; insertion via pasteboard-and-paste | `com.katikati.snippets.expand` | ~220 | disabled in secure input and for ignored apps; the paste cancels if a newer copy replaced the pasteboard first (a race Vorssaint fixed); **blocked until Q-input-a is merged** |
| 53d | Quit-on-last-window-close: pure `QuitOnLastWindowPolicy`, **opt-in per app, default empty** (unsaved work risk) | Core + `AccessibilitySource` observation | `com.katikati.windows.quitOnClose` | ~200 | |
| 53e | Tap-hub measurement: input latency + CPU with 1 vs 4 taps. **No code.** | notes | — | — | owner decides whether a hub is worth a rewrite |
| 53g | Paste a clipboard image into the front Finder window as a `.png` file: pure `PasteImageNaming` (unique filename, no overwrite) + test; Finder target-folder lookup and file write in the service. Own slice: touches the user's files | Core + service (Lane D, Finder hot touch with 53b) | `com.katikati.clipboard.pasteImage`; Automation (Apple Events → Finder) | ~150 | never overwrites; clear message when no Finder folder is frontmost; owner sign-off |
| 53h | Keyboard \| Mouse & Gestures segmented control inside the Shortcuts page (no 19th tab). **Deferred** until ≥ 2 gesture settings exist — today there is one (the four-finger pinch section, `SettingsLayoutPane+Shortcuts.swift` ~`:148`) | Lane F | — | ~80 | |
| 53i | SlowQuit pass-through (rev 3): when the frontmost app is a remote-desktop or virtual-machine app (Screen Sharing, VM hosts), forward a ⌘Q confirmed by holding or double-pressing to it instead of quitting it. Pure `SlowQuitPassthrough` (app list + decision) + test. **Verify first:** `KeyGuard*` has no remote/VM exclusion (grep), so check what hold-⌘Q does there today | `KeyGuard.swift`, `KeyGuardTests` | `com.katikati.keyguard.passthroughApps` | ~120 | table test; live check with Screen Sharing frontmost; owner picks the default app list |

### Phase 54 — Window management (Lanes C+B; after Q-bar)
| ID | Slice | Notes |
|---|---|---|
| 54a | Dock-click actions: pure `DockClickPolicy` (click frontmost → minimise/hide, modifier variants); first verify today's behaviour; act on the right instance of an app that runs as several processes | Core + test, ~150 |
| 54b | Hover previews: ScreenCaptureKit thumbnails, cached, off by default | **Screen Recording permission**; idle-CPU gate vs Q1; spike first. Design input from Vorssaint's Dock Preview fixes (7.2): pause capture while macOS is slow to answer the permission check and while displays sleep or the screen is locked, and never wait on a frozen neighbouring app |
| 54c | ⌘Tab switcher | spike only — overriding ⌘Tab is high-risk; decide after 54b; a replacement must keep working while another app has secure input on (Vorssaint's went dead until fixed) |
| 54d | Fixed Space order via `NativeDockPreferencesService` (`mru-spaces`) | changes a macOS setting → explicit in-app confirmation, restore on off |
| 54e | Focus-follows-mouse: throttled AX hit-test, idle-CPU rule | pure policy + test, ~180; keep pop-ups open when the pointer moves between them and their window (Chrome's address-bar suggestions — a Vorssaint fix) |
| 54f | Green-button zoom override | **probe first**; likely private API; owner decision |

### Phase 55 — Clipboard, capture, drawer (Lane D)
| ID | Slice | Notes |
|---|---|---|
| 55a | Copy/paste sound + notch toast on clipboard change (`ClipboardMonitor` event → pure toast policy) | `com.katikati.clipboard.sound`, ~120 |
| 55b | Extract the `screencapture` runner from `RadialDialPanelController` (pure move) then add a `ShortcutAction` for region→clipboard | lane B/D hot touch, ~100 + ~80 |
| 55c | Image reduce (`ImageReducePlan`, mirrors `PDFReducePlan`) for the shelf | Core + test, ~150 |
| 55d | Scheduled cleaner: `StorageScanService` + schedule; **dry-run list first, Trash only, never permanent delete** | owner sign-off, ~220 |
| 55e | LocalSend / AirDrop-style send | network feature → owner decision + licence; parked |
| 55f | Cobalt media download | licence/legal decision; parked |
| 55g | Clipboard retention (rev 3): pure `ClipboardRetention.prune(entries, now:, days:)` — pinned entries never pruned, 0 = off — + test; run at launch and on each add | `ClipboardHistory.swift` neighbour + a self-contained settings block; key `com.katikati.clipboard.keepDays`, **default off**; ~110; it deletes history → owner sign-off |

### Phase 56 — Widgets (Lane E; after 49c, Q-widgets)
| ID | Slice | Notes |
|---|---|---|
| 56a | Year-in-progress tile: pure `YearProgress` + test; tile in its own file | ~120 |
| 56b | Weather size presets (verify the existing 3 first) | UNVERIFIED today |
| 56c | Battery redesign + multi-device list (reuse `BluetoothDevices`) | ~200; Vorssaint's Power card also lists accessory batteries without its menu-bar item (7.2) |
| 56d | Smart tasks: pure due/priority sort over the existing tasks flyout | ~120 |
| 56e | Pause / Hydrate prompts — first read `DailyHelpersService`; add only what is missing | ~120 |

### Phase 57 — Launcher modes & Control Center (Lane B; after Q-bar)
| ID | Slice | Notes |
|---|---|---|
| 57a | Control Center: scroll-to-volume + Bluetooth icon (verify first) | `ControlCenterLayout.swift`, ~100 |
| 57b | `LauncherPresentation` (fullscreen / centred / popover) as a pure enum + routing in `LauncherPanelController` | `com.katikati.launcher.presentation`, ~200 |
| 57c | Orb summon | after 57b; owner screenshot |
| 57d | **Menu-bar menu cleanup** (`StatusMenuController.swift`). Verified today: `Show Shelf` / `Show Trash` (`:93-94`) are toggled **only** from this menu (no Settings pane has them), so removing them needs a Settings home first (Dock Items page) or users lose the switch. "Show App Name on hover" (`:95`) maps to `hoverStyle`, whose default is `.quiet` **by an owner decision of 2026-09-01** (`AppSettingsStore.swift:64`) — making it default-on reverses that, so it is an owner call (existing users keep their stored value either way). Then move the Dock / KatiKati toggles to General and keep Taskbar Size in Dock Items | `StatusMenuController.swift`, the Settings panes, `SettingsMenu*` tests if any; one slice per move, ≤ ~150 each. **Rev 3: half-landed in `4b3b735`** — the General page now holds the Startup (launch hidden) and Hide Dock icon toggles (`SettingsWindowView.swift`, `StartupUIPolicy`), but the menu still carries `Open at Login`, `Show Shelf`, `Show Trash` and `Show app name on hover` (`StatusMenuController.swift:55,93-95`) and Shelf/Trash still have no Settings home. **Rev 4 (2026-10-21), owner-directed:** Show Shelf, Show Trash, Show app name on hover (default flipped to on) and Keep windows above the taskbar now live in Settings › Dock Items; the menu lost those four rows plus the KatiKati / Dock wake-delay sliders and Dock Settings…, and keeps Open at Login, Taskbar Size and Layout. Free-floating (non-tiled) windows under the bar are **not** covered — tiles already lift by default; that needs a new eligibility class in `WindowLiftAvoidance` and a live run |
| 57e | Control Center: swap the RAM / Background Apps slot and redo the icon art | **verify first** — ~~the slot and the icon assets are not located in code yet~~ — rev 3 candidates: `DynamicGaugeFABView.swift` (RAM/CPU tooltip), `BackgroundAppsStore.swift`, `BackgroundAppClassifier.swift`, `DrawerView.swift`, `DrawerCapsuleButton.swift`, `BehaviourSettingsBlock.swift`; which surface the owner means is still UNVERIFIED — get a screenshot before touching them |

### Phase 58 — Onboarding (Lane F)
| ID | Slice | Notes |
|---|---|---|
| 58a | **Mostly built** (`d258b3c` welcome step, `154fa7c` Settings block with mic); 2026-10-21: Grant on Screen Recording / Input Monitoring now also opens the Privacy pane, since the prompt shows only once. Still open: mic row in the welcome step, live check on a fresh TCC reset. Original note: Permissions page after the Phase 9 live test (Accessibility, Screen Recording, Input Monitoring, mic) — already on the owner's list. **Schedule it before 54b (Screen Recording) and before 53a–53c (Input Monitoring) ship** | extend `WelcomeGuideView.swift`; follow `Docs/ONBOARDING_TEST_CHECKLIST.md`; respect `StartupUIPolicy.shouldPresentWelcomeGuide` (guide on first run or when not launching hidden) |
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
10. Design calls the menu-bar cleanup and dock accent need (57d, 50f): is making "Show App Name" default-on a
    deliberate reversal of the 2026-09-01 quiet default? Where do Show Shelf / Show Trash live once they leave the menu?
    One artwork accent or a multi-colour dock palette?
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
| Secure input has no change notification; sample only while needed; name the app active when it turned on | Q-input-a, 53c | no secure-input code at all (grep) |
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
|---|---|---|---|---|---|
| 2026-10-20 | `dac5606` (code = `1ce7963`; `bb3a1f7` adds only this doc) | ✅ `1ce7963`: 2548 tests, 2 skipped (live torrent), 0 failures, exit 0 | `check_localization.py` ✅ (993 keys × 12; 40 source literals); `check_debug_switches.py`, `check_availability_warnings.py` _not yet recorded_ | _owed_ | the 7 `error:` lines in the log are macOS `linkd.autoShortcut` runtime noise, not compile errors |
| 2026-10-20 | `14092d5` (rev 3) | ✅ 2559 tests, 2 skipped (same two live-torrent tests), 0 failures, `** TEST SUCCEEDED **`, exit 0 | `check_localization.py` ✅ (1013 keys × 12; 40 source literals); `check_debug_switches.py` ✅ (85 switches); `check_availability_warnings.py` ✅ on this run's complete log | _owed_ | the 7 `error:` lines are `[Connection]`/`xctest` runtime noise (`Unable to get synchronousRemoteObjectProxy…`), not compile errors; +11 tests vs `1ce7963`; live smoke run of the 18 tabs still OWED |
| 2026-10-20 | `c46d6ae` (Q1) | — | — | **Debug build, M3, macOS 27.0.1, `ps %cpu` 60 s after 10 s settle:** defaults avg 17.5 (max 25.4); cpu metric on 15.8; all 5 metrics on 15.4; re-sampled later 18.2. Metric toggles made no visible difference (set via `defaults write`; live pickup unverified). Instruments/Release run _owed_. | Idle ~15-18 % is high. One 3 s `sample` put the hot frames in `WindowLiftAvoidanceController.probeTrackedFrames` → `WindowLiftCGWindowProbe.frames(for:)` (`CGWindowListCopyWindowInfo` per tracked window on a repeating timer, :799). Lead only, not a diagnosis. `git grep` finds 35 `Timer` sites in `App/Composition` + `Platform`, not 16 (includes one-shots). |
| 2026-10-20 | `4c6836b` (Q1 correction) | — | — | **Supersedes the row above.** `ps -o %cpu` on macOS is a lifetime average, so the 15–18 % there was inflated by launch. Instantaneous (`cputime` delta over 30 s, Debug, M3, macOS 27.0.1): **~10.7 % steady** from minute 3 to 5, window lift **off** (lift on measured 18.6 vs off 13.8 on the lifetime-average column, so lift is at most a few points). _owed:_ Release build and Instruments. | `sample` (10 s) saw only ~2–3 % of the 10–16 % that `cputime` reports, so it cannot attribute the load; the "probe timer" lead in the row above is **weak and should not drive a fix**. Visible work in the sample: `SystemMonitorController.refresh` → `SystemMonitorSampler.disk()` (1 Hz, runs even when no Disk metric is shown; held open by edge-bar/FAB views), `RunningApplicationStore` policy rechecks, `AppTracker.reconcile`, SwiftUI image prep. Idle target is unset. |
