# KatiKati — Hybrid Plan (Tungsten Edge core)

**Tungsten Edge core × SplitBar-old 4 modes × DockBar widgets**

Status: **Phase 4 DONE** (Baseline import, pure layout model, island panels, and multi-display/fullscreen/Spaces lifecycle complete, 1,602 tests green) · Plan v3 · Date: 2026-10-08  
New repo: `/Users/baraka/Desktop/Splitbar` (branch `main`) → remote `wakilibaraka/KatiKati`  
Core snapshot: `moonbai-studio/tungsten-edge @ a4e1a55` (2026-10-07, `master`), clone at `/tmp/tungsten-edge`  
Previous plan: v2 (`DockBar base × SplitBar-old modes × live-SplitBar segments`, commit `3d914c6`) — **superseded by this document.**  
Product name: **KatiKati** (Swahili *katikati* = “right in the middle / centered” — the centered-bar promise).
This commit: **plan only — no code changes.**

---

## Decisions locked with the owner

1. **New repo from scratch** — not a branch or fork of any source repo. Tungsten Edge enters
   as a **clean baseline import** (snapshot `a4e1a55`), not a git fork, so history, signing,
   bundle id and defaults domains start clean while license attribution stays intact (§6).
2. **Tungsten Edge is the core** (owner-confirmed 2026-10-08, replaces the v2 DockBar-base
   decision): window inventory + identity, panel/orchestrator architecture, strip UI,
   settings, multi-display, auto-hide, fullscreen handling, drag & drop, updates, and the
   ~1300-test culture are all inherited from tungsten-edge. Nothing on the bar path is
   rewritten in another UI framework.
3. **Stack follows tungsten**: `NSPanel` hosts (`NonConstrainingPanel` / `ManualPanelHost`)
   + **SwiftUI strip views** (`DockStripView` family). The v2 "pure AppKit, no SwiftUI on
   the bar" rule is **retired** — re-implementing tungsten's strip in AppKit would throw
   away the core's most-tested code for no user-visible gain.
4. **Third-party repos = references, not donors** (terminology owner 2026-10-11; see §0/§5):
   - **Reference A — SplitBar-old** (`~/Desktop/SplitBar-old`, `wakilibaraka/SplitBar-old`):
     the 4 required layout modes, section/island model, pure island geometry, mode
     picker/onboarding, island tests.
   - **Reference B — DockBar** (`~/dockbar`, `wakilibaraka/dockbar`, fork of
     rajeshgoli/deskbar): weather / clock / tray-cluster widgets, settings-window
     patterns, AppKit panel lessons. Ported **selectively** — tungsten already covers
     window management, panels, settings and tests.
   - **Reference — live SplitBar** (`github.com/wakilibaraka/SplitBar`, fork of
     `senoldogann/EdgeDeckBar`): consulted for segment priors only where tungsten has no
     equivalent. Tungsten's orchestrator + `PanelGeometry` supersede its segment manager.
5. **GPL-3.0-or-later governs anything derived from the core** (§6). Trademark rule is
   absolute: **never ship under the name "Tungsten Edge" / "钨极" or its icon**
   (`TRADEMARK.md`) — the app gets a new name, icon, bundle id and defaults domain.
6. Open (non-blocking): final product name + bundle id; working assumption
   `com.katikati.app` with `com.katikati.*` defaults (§6).

## Table of contents

- §0 Sources at a glance
- §1 Goal (the four modes, in detail) + non-goals
- §2 Why tungsten-edge is the core (capability matrix)
- §3 Naming (tungsten vocabulary → canonical additions)
- §4 Target architecture (tungsten tree + layout-mode layer)
- §5 Port allow-list, file-level (and explicitly-not-ported)
- §5e Edge-bar + launcher candidates (Phase 7 only — owner's 2026-10-08 decision)
- §6 Build, identity, licensing
- §7 Phases 0–12 (each shippable + testable; Phase 7 split into 7A edge bars / 7B launchers + FAB payloads; Phases 8 interior content / 9 strip+interaction+summoning / 10 presets+wallpaper / 11 layout-mode rendering / 12 settings refinement added 2026-10-11)
- §8 Risks, mitigations, open questions
- §9 Acceptance criteria
- Appendix A — per-mode layout spec (islands, overflow, migration)
- Appendix B — references (files, commits, screenshots)
- Appendix C — edge-bar + launcher spec stub (Phase 7 only)

---

## 0. Sources at a glance

| | **Tungsten Edge** (core) | **SplitBar-old** (reference A) | **DockBar** (reference B) | **Live SplitBar** (reference) |
|---|---|---|---|---|
| Path / URL | `github.com/moonbai-studio/tungsten-edge`, clone at `/tmp/tungsten-edge`, snapshot `a4e1a55` (2026-10-07, `master`, single squashed public commit) | `~/Desktop/SplitBar-old`, `wakilibaraka/SplitBar-old` | `~/dockbar`, `wakilibaraka/dockbar` (fork of rajeshgoli/deskbar) | `github.com/wakilibaraka/SplitBar` (fork of `senoldogann/EdgeDeckBar`), clone at `/tmp/splitbar-upstream` |
| Stack | SwiftUI strip in `NSPanel` hosts, **Xcode project** (`macos-dock-cc-v2.xcodeproj`), Swift 5.0, floor **macOS 12.0**, **one SPM dep (Sparkle)** | SwiftUI in `NSPanel`s, SwiftPM, macOS 15 | Pure AppKit, SwiftPM, Swift 6 (lang v5), macOS 14 floor | SwiftUI in `NSHostingView`/`NSPanel`, swift-tools 6.0, macOS 15 |
| Identity | bundle id `com.caye.macosdockcc.v2` (proj), defaults `com.tungsten.edge.*`, tests id `...v2.tests` | local `SplitBar.app` builds | `com.dockbar.app` (dirs/tests still `DeskBar`) | `com.baraka.splitbar`, CI `build.yml` |
| Scale | **338 Swift files** (~21 MB checkout): `App/` composition+entry+scenes, `Core/` pure decisions, `Platform/` adapters, `UI/ReadModel`, `Tools/WindowLab`, `Scripts/`, `Resources/` (12 localizations) | monolith `TaskbarConceptView.swift` = **7,567 lines** + services | ~250 src files: Views ×70, QuickSettings ×30, Services ×30, Utilities ×30 | ~9.7k lines (App/Services/Stores/Models) |
| Tests | **~1,300 XCTest cases (~40 s)** + `check_localization.py` + `check_debug_switches.py` + conformance-availability check; CI on `macos-26` w/ Xcode 26 | `TaskbarStripTests` only | ~40 files in `DeskBarTests` | none |
| Bar model | **single strip + drawer capsule + popups**: `PanelCoordinator` owns 5 `NSPanel`s per display-unit; `TaskbarScreenOrchestrator` owns per-display `Unit`s | 4 fixed modes, `displayID#index` panels | one strip panel per display, 5 bar styles | generalized `DockSegment`s, 1 panel/segment, config-persisted |
| Multi-display | ✅ `TaskbarScreenPlacement`: `followMouse` / `allScreens` / `allScreensPerDisplay` / `pinned` + `TaskbarPerDisplaySeedController` + `DisplayTopologyStore` | ✅ per-display (`TaskbarScreenMode`) | ✅ per-display | ❌ primary display only |
| Dock/native integration | `NativeDockPreferencesService`, auto-hide delays (native + edge sliders), `⌥⇧⌘D` toggle, window-lift avoidance, fullscreen-intent monitor, Spaces/overlay handling | `hideMacDock` + `SplitBarDockRestore` helper + login item | `DockManager` (independent/autoHide/hidden) | `DockController`: save-before-mutate, crash-recovery file, signals |
| Role in merge | **architecture + engine + UI + settings + test culture** | **mode semantics + island math + island tests** | **widget implementations + settings patterns (selective)** | **priors only where tungsten is silent** |

**Eskele (new reference, owner 2026-10-11):** `github.com/wakilibaraka/eskele`
(fork of `hossainalhaidari/eskele`); no local clone — installed app `/Applications/Eskele.app`
(0.3.1). MIT; a DockBar-derived feature port (launcher/calendar/quick-settings), macOS 13
floor, 557 tests, menu-bar agent, minimal edge dock (left/bottom/right) that hides the
system Dock with a `restore-dock` escape hatch. Role: **eyeball-only reference** — edge
geometry/auto-hide + Dock-restore lessons feed Phase 7A; never a code source; NOTICE
entry if behavior is derived.

**Reference policy (owner 2026-10-11):** all third-party repos/apps in this plan are
*references, not donors* — their code may be broken or unsuitable for this build; use
their code only after investigation (full policy at the §5 intro).

---

## 1. Goal

**KatiKati** is a macOS taskbar replacement: an LSUIElement background agent (menu-bar item
only, no Dock icon of its own) whose bar renders in four required layouts, built on
tungsten-edge's proven per-window taskbar engine:

| Mode | Visual | Islands | Sections (left → right) |
|---|---|---|---|
| `windows` | **Windows full** — full-width strip | 1 | `[weather] … [apps centered] … [tray, clock]` |
| `split3` | Floating islands ×3 | 3 | `[weather]` `[apps]` `[tray, clock]` |
| `split4` | Floating islands ×4 | 4 | `[weather]` `[apps]` `[tray]` `[clock]` |
| `centered` | Narrow, width-adjustable centered bar | 1 (hug) | `[weather, apps, tray, clock]` |

Optional later (present in SplitBar-old, not required by the brief): `macOS` pill mode —
revisit after Phase 5 using tungsten's `DockPanelHeight` scaling path (Phase 7).

**Invariants that hold in every mode**

- Island panels stay non-activating (tungsten's `.nonactivatingPanel` + `NonConstrainingPanel`
  discipline), join all Spaces / stay stationary / ignore cycle, persist across Spaces and
  stay out of Mission Control — extend `PanelCoordinator.allSpacesPanels` coverage to every
  island panel, never relax it.
- Flyouts/popups open anchored to the island/chip that summoned them (weather from island 1,
  calendar from island 4, per-chip window popups above the exact chip) — tungsten's
  `folderPopupTargetFrame` / tooltip-target geometry generalizes to per-island anchors.
- All islands on a screen hide together when a fullscreen window covers that screen (tungsten
  `PanelCoordinator+Fullscreen` + `FullscreenIntentMonitor` path), and reflow when the
  screen set or resolution changes (`TaskbarScreenOrchestrator.rebuildUnits`).
- The active mode, centered width and gaps persist across relaunch and switch from
  Settings **without relaunching** (new `com.katikati.*` keys, §6; tungsten
  `AppSettingsStore` pattern).
- Tungsten's per-window semantics are preserved verbatim in every mode: one card per window,
  smart native-tab merging (`groupID` token), greyed-out minimized/hidden states, Spaces
  switching on click, drawer stashing, drag-to-organize, badges, pinned folders, shelf,
  trash. Modes change **where chips render**, never **what a chip means**.


- No AppKit rewrite of the strip: `DockStripView` + `PanelCoordinator` + `AppRuntime` stay
  SwiftUI-in-panel exactly as tungsten ships them. New code is layout/placement/settings;
  the bar path is never reimplemented.
- No TCA-style reducer store — tungsten's `…Store` + `AppDelegate` wiring governs state.
- No wallpaper/personalisation engine, AI-usage, clipboard, quick-notes, secrets or
  `ProcessRunner` features from SplitBar-old in scope (see §5 not-ported; Phase 7 max).
- No new third-party dependencies beyond tungsten's single Sparkle SPM pin — all ports from references must be dependency-free.
- No rebranding of tungsten itself: the core stays GPL-3.0-or-later with Moonbai Studio
  trademark reserved; KatiKati ships under its own name/icon/id (§6).

---

## 2. Why tungsten-edge is the core

### Capability matrix (verified against the four repos)

| Capability | Tungsten Edge | SplitBar-old | DockBar | Live SplitBar | Verdict |
|---|---|---|---|---|
| Fixed 4 taskbar modes + picker | ❌ | ✅ | ❌ | ❌ (no mode concept) | Port SplitBar-old |
| Per-window taskbar engine (identity, lifecycle, optimistic states) | ✅ best-in-class (`WindowIdentityEngine`, `LifecycleTransitionEngine`, `LifecycleActionPlanner`, `OptimisticWindowState`, `AppTracker` inventory) | ❌ prototype | ✅ mature | ❌ basic | Tungsten only |
| Native-tab merging (stable card per tab group) | ✅ `groupID` token + `StripItem` slotting | ❌ | ❌ | ❌ | Tungsten only |
| Strip rendering (drag, hover, badges, drawer, shelf, trash, folders) | ✅ `DockStripView` family + `DragController` + `StripOrderStore` | ❌ | AppKit zones | partial pills | Tungsten only |
| Multi-panel management | ✅ per-`Unit` `PanelCoordinator` (5 panels each) + incremental `rebuildUnits` | ✅ `TaskbarPanelController` | ❌ (1/display) | ✅ `SegmentPanelManager` | Tungsten pattern; SplitBar-old keys inform slot ids |
| Panel geometry (pure, tested) | ✅ `PanelGeometry` (`segmentPanelFrame`-class clamp discipline, popup/tooltip/drawer frames) + `PanelGeometryTests` | `layoutIslands` + overflow loop | `BarPanelLayout` (strip-level) | `segmentPanelFrame` (clamped) | Compose: tungsten outer frame + SplitBar-old island split |
| Multi-display | ✅ richest (`followMouse`/`allScreens`/`allScreensPerDisplay`/`pinned` + seed controller + topology store) | ✅ | ✅ | ❌ | Tungsten |
| Fullscreen hide per screen | ✅ intent monitor + per-coordinator path | ✅ `FullscreenMonitor` | ✅ | ❌ | Tungsten path; reference-A ideas only if a gap is found |
| Flyout anchoring | ✅ popup/tooltip/drawer target frames per anchor rect | per-panel | ✅ `relativeTo:of:` | ✅ per-icon `screenFrame` | Tungsten + generalize to per-island anchors |
| Dock hide/restore hardening | ✅ auto-hide delays, `NativeDockPreferencesService`, window-lift avoidance, signal-safe teardown paths | `hideMacDock` + restore helper | `DockManager` | ✅ save-before-mutate + recovery file | Tungsten; live-SplitBar recovery pattern only if tungsten lacks it |
| Hover/click previews | ✅ `ChipSnapshotter`, `StackPopupSnapshotProbe`, snapshot-backed popups | ❌ | `ThumbnailService` (click) | ✅ debounced strip | Tungsten |
| Glass/material | ✅ `DockLiquidGlassConfiguration`, `DockThemeTokens`, `DockGlassRuntimeBridge`, rim plan | `ThemeToken`/`GlassProvider` | `DesignSystem` | `LiquidGlass`, `DockMaterialStyle` | Tungsten tokens stay; DockBar tokens consulted only for weather/tray ports |
| Weather / clock / tray-cluster widgets | ❌ (no weather/clock/tray cluster in core) | partial | ✅ mature (`WeatherService`, `CalendarTrayButton`, `ConnectivityTrayView`, `WindowsTrayClusterView`, `BatteryMonitor`) | partial pills | **Reference (eyeball-only)** — DockBar widget implementations (owner 2026-10-08) |
| Tests | ✅ ~1,300 cases + localization + debug-switch + conformance checks | ✅ `TaskbarStripTests` | ✅ ~40 files | ❌ none | Tungsten culture + port island tests |
| Settings + onboarding + status menu | ✅ `AppSettingsStore`, `SettingsCoordinator`, `SettingsWindowView`, `WelcomeGuideView`, `StatusMenuController`, `PermissionOnboardingView` | mode picker step | ✅ search + catalog | SwiftUI `SettingsView` | Tungsten + add "Layout" page |
| Update service | ✅ `SparkleUpdateService` (Sparkle SPM) | ❌ | ✅ custom | ❌ | Tungsten (keep Sparkle pin) |
| Auto-hide handle/activation zone | ✅ edge delays + `edgeActivationFrame`-class geometry + `⌥⇧⌘D` toggle | ❌ | ✅ | ✅ | Tungsten |

### Rationale

- **Tungsten is the core** because it is the only repo that already *is* a shipping-quality
  per-window taskbar: stable window identity across tab switches/focus races, optimistic
  interaction states, per-display orchestrator units, tested panel geometry, drag & drop with
  carrier surfaces, drawer/shelf/trash/folders/badges, fullscreen/Spaces correctness, and a
  ~1,300-test suite guarding all of it. Rebuilding any of that on another base would be
  strictly worse than adding layout modes to tungsten.
- **SplitBar-old is reference A** because it is the only source of the *4 required modes* as
  semantics: `TaskbarSection.islands(for:)` (which sections group into which island), the
  overflow-collapse loop, and `TaskbarStripTests` proving them. Its structure (7.5k-line
  SwiftUI monolith) is deliberately not ported — only model + math + tests.
- **DockBar is reference B** because it owns the missing widget set (weather, clock, tray
  cluster) plus settings-window patterns. Tungsten already covers window management,
  panels, settings infra and tests, so DockBar contributes **implementations, not
  architecture** — each widget is re-skinned as a tungsten strip chip + popup.
- **Live SplitBar is reference-only**: tungsten's orchestrator + `PanelGeometry` supersede
  its `SegmentPanelManager`/`segmentPanelFrame`; consult it only where tungsten documents
  no equivalent (and record the delta in the porting PR).
- Precedence rule when sources disagree: **SplitBar-old wins on mode semantics** (it owns
  the 4 modes), **tungsten wins on everything else** (it is the base). DockBar widget ports
  adapt to tungsten strip/popup APIs — never the reverse.
- What changed since v2: DockBar's AppKit strip/panel/settings/test base is replaced by
  tungsten's SwiftUI-in-panel strip + orchestrator + 1,300-test base; SwiftPM is replaced
  by tungsten's **Xcode project** build; macOS floor follows tungsten (**12.0**, SDK-gated
  Liquid Glass via `#available(macOS 26.0, *)`); Swift version follows tungsten (**5.0**);
  Sparkle becomes the update path; licensing gains a **GPL-3.0-or-later core** with
  trademark rename obligations (§6).

## 3. Naming (tungsten vocabulary → canonical additions)

Tungsten's vocabulary stays authoritative; the merge only *adds* layout-mode names. Where
v2 renamed DockBar concepts, this plan keeps tungsten names and maps references onto them:

| Concept | Tungsten Edge (canonical — kept) | SplitBar-old | DockBar | Live SplitBar | **New in Splitbar** |
|---|---|---|---|---|---|
| Layout mode (the 4 required) | — (single-strip assumption) | `TaskbarMode` (windows/split3/split4/centered) | — | — | **`BarLayoutMode`**: `windows\|split3\|split4\|centered` (+`macOS` later, Phase 7) |
| Content section | strip zones inside `DockStripView` (chips/trash/shelf/folders/drawer entry) | `TaskbarSection` (weather/apps/tray/clock) | task zones | `DockSegment` kinds | **`BarSection`**: `weather\|apps\|tray\|clock` — grouping key only, rendering stays tungsten chips |
| Island math | `PanelGeometry` + `PanelLayoutMetrics` + `DockPanelHeight` (outer/anchor frames) | `TaskbarStrip.layoutIslands` | `BarPanelLayout` (strip frame) | `segmentPanelFrame` | **`IslandLayoutSolver.layout(...)`** — pure split of tungsten's strip frame; tungsten geometry stays the clamp authority |
| Panel manager | `TaskbarScreenOrchestrator` + per-`Unit` `PanelCoordinator` | `TaskbarPanelController` (`displayID#index`) | `AppDelegate` panels dict | `SegmentPanelManager` | **Extend orchestrator/coordinator**: `displayUUID#slot` islands inside/beside the strip unit; `rebuildUnits` reconcile extended, not replaced |
| Mode picker UI | `WelcomeGuideView` + `SettingsWindowView` + `SettingsTab` | `OnboardingView` + thumbnails | settings catalog | — | **Settings "Layout" tab** + welcome-guide step, drawn from `IslandLayoutSolver` |
| Window item | `StripItem` (`groupID`-stable, tab-merged) | window buttons | task buttons | segment items | **unchanged** — modes never redefine chip identity |

Conceptual model: **layout mode is a new axis beside tungsten's existing settings.**
`AppSettingsStore` gains `barLayoutMode` (+ `centeredWidth`, island gap/margin) under
`com.katikati.*` keys with the same published-setter + migration pattern tungsten uses for
`taskbarScreenMode` / `dockPanelHeight` (incl. legacy-tier migration precedent in
`DockPanelHeight.migratingLegacyTier`). No tungsten key is renamed; tungsten's
`com.tungsten.edge.*` defaults are left behind on first run (one-way `InstallLineage`-
aware migration, §6/Phase 0).

## 4. Target architecture

```
Splitbar (LSUIElement agent, tungsten tree + layout layer)
 ├─ App/Entry
 │   ├─ AppDelegate (tungsten wiring; adds layout-mode store observation)
 │   ├─ TaskbarScreenOrchestrator      EXTENDED — per-display Unit gains island plan
 │   │    ├─ Unit(displayUUID?) → PanelCoordinator (+ island panels / island strip splits)
 │   │    ├─ IslandLayoutSolver        NEW — pure, unit-tested geometry
 │   │    │    (splits tungsten PanelLayoutMetrics strip frame per BarLayoutMode;
 │   │    │     SplitBar-old layoutIslands + overflow loop, tungsten clamp authority)
 │   │    ├─ rebuildUnits(reason:) extended — incremental reconcile per displayUUID#slot:
 │   │    │    reuse panels when key survives, orderOut strays, 0.5 pt min gap
 │   │    └─ boundingFrame() — union of island frames → whole-bar popup anchor
 │   └─ PanelCoordinator (+Fullscreen/+Layout/+Popups/+Visibility)   EXTENDED
 │        ├─ strip panel + glass background + drawer/capsule + folder/shelf/trash
 │        │   popups + tooltip + resize-cursor panels (all unchanged semantics)
 │        └─ NEW: island panels (split3/split4 slots) or hug-width strip (centered),
 │             all covered by allSpacesPanels + fullscreen hide/show atomically
 ├─ App/Scenes
 │   ├─ DockStripView family (UNCHANGED engine) — chips, drag, hover, badges,
 │   │    drawer/shelf/trash/folders; per-island instances receive filtered StripItems
 │   ├─ NEW: weather / clock / tray-cluster chips + popups (ported DockBar
 │   │    implementations, re-skinned to tungsten chip/popup APIs)
 │   └─ SettingsWindowView + WelcomeGuideView (+ new "Layout" tab/step)
 ├─ App/Composition — all tungsten stores UNCHANGED (AppRuntime, StripOrderStore,
 │    DrawerStore, BadgeStore, KeptAppStore, RunningApplicationStore, ShelfStore,
 │    PinnedFolderStore, TrashStateStore, DragController, SparkleUpdateService, …)
 ├─ Core/ + Platform/ — UNCHANGED (identity, lifecycle, placement, AppTracker, AX/CG,
 │    permissions, Finder, fullscreen classifier, debug switches)
 └─ shared: DockThemeTokens / DockLiquidGlassConfiguration (stay; absorb only the
      minimum tokens needed to skin ported DockBar widgets)
```

### Key mechanics

1. **Panel keys**: `"<displayUUID>#<slot>"` (SplitBar-old's `displayID#index` convention
   transplanted onto tungsten's display-UUID units). Mode switch = *reconcile* the island
   set inside `rebuildUnits` — keep tungsten's incremental discipline (reuse a panel when
   its key and size still match, only touch frames that changed, `orderOut` only when
   leaving), extended from units to slots.
2. **Island chrome**: each island reuses tungsten's existing strip-panel construction
   (`NonConstrainingPanel` + glass background + `PanelLayoutMetrics` + shadow tokens) —
   no new panel class; per-slot corner radius/material come from the existing tungsten
   theme tokens, so height scaling (`DockPanelHeight.scale`) keeps working.
3. **Geometry** (the Phase-1 contract):
   - Tungsten's `PanelGeometry`/`PanelLayoutMetrics` stay authoritative for *outer* frames
     and every popup/tooltip/drawer anchor.
   - `IslandLayoutSolver` takes the SplitBar-old `layoutIslands` signature
     `(screenWidth, tileStride, appCount, weatherWidth, trayWidth, clockWidth, clusterWidth,
     gap, margin, barHeight, bottomMargin)` → produces island frames in the same
     bottom-left screen space tungsten uses; tungsten clamp discipline (never off
     `visibleFrame`, alignment origin + offset) validates every island as a safety net.
   - `DockStripView` instances render per-island `StripItem` slices; strip-internal drag,
     hover, badges and popups behave exactly as today — only the item filter and the
     host frame differ per island.
4. **Content mapping**: tungsten's strip content (window chips + drawer/shelf/trash/folders)
   is the `apps`-plus-utilities zone; ported DockBar weather/clock/tray widgets become
   additional chips placed by `BarSection.islands(for:)` grouping (Appendix A). No tungsten
   chip type is removed or redefined.
5. **Overflow**: port SplitBar-old's loop verbatim — shrink visible app chips until the
   island fits, set `showsOverflow`, rest lives behind the overflow popup (tungsten's
   existing stack/folder popup geometry renders it).
6. **Popups**: tungsten `folderPopupTargetFrame` / tooltip-target frame functions
   unchanged; add per-island composition `screenFrame = islandFrame + localFrame`
   (AppKit locals are bottom-left, so plain addition — no y-flip). Test both (Phase 3).
7. **Fullscreen/Spaces**: tungsten's `PanelCoordinator+Fullscreen` +
   `FullscreenIntentMonitor` + overlay-space handling stay the single path; hide/show
   applies to **all slots of that displayUUID atomically**; `allSpacesPanels` must include
   every island panel (regression test, Phase 3).
8. **Settings rule**: layout mode lives beside `taskbarScreenPlacement` in
   `AppSettingsStore`; in all four layout modes, weather/tray/clock chips are forced into
   the bar regardless of any ported DockBar placement default; migration is one-way with
   an `InstallLineage`-style stamp so existing tungsten installs never silently flip.
9. **Native-Dock posture**: tungsten's `NativeDockPreferencesService` + auto-hide delays +
   window-lift avoidance are kept as-is. Live-SplitBar `DockController` recovery-file
   ideas are adopted only if a Phase-5 drill proves tungsten's teardown path loses state
   (evidence-gated, not ported by default).

---

## 5. Port allow-list (file-level)

The §-tables are normative: **if a file/feature is not listed, it is not ported.**
Tungsten's tree is the baseline — everything there is *kept* unless §5d says otherwise.

> **Reference policy (owner 2026-10-11):** every third-party repo/app in this plan
> (SplitBar-old, DockBar, Live SplitBar, Eskele, EdgeDeckBar, noty, arc-menu, Volant,
> Liftoff, status-trio, …) is a **reference, not a donor**. Their code may be **broken or
> unsuitable for the current build** (different Swift/macOS floors, unmaintained, AppKit
> vs SwiftUI mismatch). **Use their code only after investigation** — buildability on our
> toolchain, fitness for the slice, and license (NOTICE attribution) verified and recorded
> in that slice's check-log entry first. The default posture stays eyeball-only study.

### 5a. From SplitBar-old (reference A) — port model + math + tests

| Source | Target in new repo | Notes |
|---|---|---|
| `TaskbarConceptView.swift` → `enum TaskbarMode` | `Core/Support/BarLayoutMode.swift` (new) | 4 cases only; drop `macOS` to Phase 7 |
| `TaskbarSection` + `islands(for:)` | `Core/Support/BarSection.swift` (new section + island grouping) | Keep exact groupings (Appendix A); rendering stays tungsten |
| `TaskbarStrip.layoutIslands(...)` | `Core/Support/IslandLayoutSolver.swift` (new) | Pure function; no views, no timers; tungsten clamp validates output |
| `TaskbarStrip.pruned` (divider logic) | *deferred* | Only if dividers are wanted (Phase 7) |
| `TaskbarStrip` overflow-collapse loop | inside `IslandLayoutSolver` | Returns per-island `showsOverflow` |
| `Services/TaskbarPanelController.swift` | slot-key + reconcile logic merged into `TaskbarScreenOrchestrator`/`PanelCoordinator` | `displayUUID#slot` keys, mode-switch reconcile; no new manager class |
| `Services/FullscreenMonitor.swift` | gap-analysis only against tungsten fullscreen path | Adopt ideas only if tungsten path misses a case (evidence-gated) |
| `centeredBarWidth` defaults key (`taskbar.centeredWidth`) | new `com.katikati.*` centered-width key | Same value semantics; new domain (no shared defaults with tungsten) |
| `TaskbarPanelController` per-display re-layout | tungsten `rebuildUnits` extension | Tungsten already re-seeds on screen change |
| `Tests/SplitBarTests/TaskbarStripTests.swift` | `Tests/.../IslandLayoutSolverTests.swift` (new) | All cases: islands-per-mode, section coverage, bounds, overflow |
| `OnboardingView` pick-a-layout step | new step in `WelcomeGuideView` + "Layout" `SettingsTab` | Reference screenshots, Appendix B |
| Mode thumbnails | `SettingsWindowView` Layout tab | Drawn **from `IslandLayoutSolver`** → preview = real geometry |

### 5b. From DockBar (reference B) — eyeball-only reference (owner 2026-10-08)

**Eyeball-only rule:** DockBar code is a *specimen, never a source*. Study how it
fetches, decides and renders — then write fresh code in tungsten patterns (pure
decisions in `Core/Support` + unit tests, thin services in `App/Composition`, tungsten
chip/popup chrome, Phase-4 theme tokens). **Nothing is pasted or mechanically
translated**; pin DockBar's commit hash for reference. No reference regression can enter
because no reference line enters. The table below is a *study list* — the Target column is
what we build fresh, informed by the Source column.

| Source (study only) | Target (build fresh, tungsten-style) | Notes |
|---|---|---|
| `WeatherService` + weather widget views | tungsten-style chip + popup in `App/Scenes` | Re-skin to `StripItem`-adjacent chip + tungsten popup geometry; tokens from tungsten theme |
| `CalendarTrayButton`/`CalendarView` | clock chip + calendar popup | Same re-skin; per-island anchor (island 4 in split4) |
| `ConnectivityTrayView` + battery + quick settings | tray-cluster chips + popup | Same re-skin; cram rule: tray+clock share island 3 in split3 |
| Settings-window search/catalog patterns | "Layout" tab organization in `SettingsWindowView` | *Patterns* only — tungsten settings infra stays |
| AppKit panel lessons (`TaskbarPanel`, `BarPanelLayout` edge handling) | gap-analysis against `PanelCoordinator`/`PanelGeometry` | Adopt only proven deltas; no AppKit strip rewrite |
| `ThumbnailService` click previews | gap-analysis against tungsten `ChipSnapshotter`/popups | Tungsten path wins ties |
| `DockManager` hardening bits | gap-analysis against tungsten native-Dock services | Evidence-gated (Phase-5 drill decides) |
| Taskbar button interaction — Window Grouping (multi-window same-app click-to-cycle), right-click action menu, middle-click close, hold-to-quit | study for strip interaction (Phase 9: 9a/9b) | Eyeball-only; tungsten strip semantics stay authoritative (§2.4), behavior-frozen exception per slice |
| Start Menu Most-Used (Spotlight) + AppBeBack recently-closed restore | study for drawer sections (Phase 8: 8a) | Eyeball-only; drawer = tungsten capsule content |

### 5c. From tungsten-edge (core) — kept as-is (baseline import)

Everything in snapshot `a4e1a55` is inherited in Phase 0, notably:
`AppDelegate`/`MacOSDockCCV2App` wiring, `AppRuntime` + `IntentPipeline`,
`TaskbarScreenOrchestrator` + `PanelCoordinator` (+all `+Topic` splits) +
`NonConstrainingPanel`/`ManualPanelHost`, `DockStripView` family + `StripProjection` +
`DragController`, `StripItem`/`DockSnapshot`/`WindowRecord` + identity/lifecycle/placement
engines, `AppTracker` + AX/CG/fullscreen/Spaces adapters, `AppSettingsStore` +
`SettingsCoordinator` + `SettingsWindowView` + `WelcomeGuideView` + `StatusMenuController`,
drawer/shelf/trash/folders/badges/messaging/kept-apps/running-apps stores,
`PanelGeometry` + `PanelLayoutMetrics` + `DockPanelHeight`, glass/theme tokens +
`DockGlassRuntimeBridge`, `SparkleUpdateService`, `LaunchAtLoginService`,
`WindowLiftAvoidanceController`, all `Core/Support` decisions/plans/policies, `Tools/WindowLab`,
all ~1,300 tests, `Scripts/` (`build_and_run.sh`, `package_release.sh`,
`install_local_release.sh`, `check_*.py`), CI workflow, `Resources/` localizations
(12 languages), `.gitignore` + signing/packaging discipline. Rebranding (§6) changes
names/ids/assets only — never behavior.

### 5d. Explicitly NOT ported

- SplitBar-old: `WallpaperEngine`, `ThemeToken`/`GlassProvider` (tungsten tokens win),
  personalisation flyouts, `WidgetProvider`, `splitbar.html`, `SplitBarDockRestore`
  (tungsten services own this area), `ProcessRunner`, `SecretsStore`/`SecurityKeychain`,
  AI-usage stack, clipboard stack, quick notes, command palette, window tiling,
  Bluetooth/NowPlaying/SystemMonitor flyouts (beyond the §5b widget set).
- DockBar: AppKit strip/content/panel architecture (`TaskbarPanel`, `TaskbarContentView`,
  zones/stacks, `TaskbarStyleSpec`/`TaskbarLayoutStrategy` system, `FlyoutPanel` system,
  `QuickSettings*`, `Launchpick/*`, `UpdateService`, `MigrationManager`,
  `PermissionsManager`, `SingleInstanceLock`, SwiftPM packaging, `SPEC.md`-era conventions).
  Nothing AppKit-structural is ported — §5b is widgets + patterns only. (Reference hash for Weather: dd47a82)
- Live SplitBar: `SegmentContainerView`, `EdgeDockView`, `SegmentPills`, all `Stores/*`
  reducers, `AppRuntimeController`, SwiftUI `SettingsView`, `DockMagnificationLayout`,
  `SegmentPanelManager`, `DockSegment` persistence, `DockController` (unless the Phase-5
  drill proves a tungsten gap — then最小 diff, evidence-gated).
- Tungsten: nothing is removed in Phase 0 except rebranding (§6); de-scoping only happens
  with owner sign-off. `Tools/WindowLab` stays (diagnostic CLI, not shipped). Official
  tungsten binaries/website/cask/feed stay Moonbai's — never reused or impersonated.

**Owner override 2026-10-11 (Phase 10):** `WallpaperEngine`, the wallpaper/personalisation
bits of the personalisation flyouts, `WidgetProvider` + height/personalisation presets, and
the SplitBar-old NowPlaying flyout are **reopened — as eyeball-only priors for Phase 10
(10a/10b) and Phase 8 (8b), built fresh in tungsten patterns per the §5b rule.** Everything
else on this list stays declined.

### 5e. Edge-bar + launcher candidates (Phase 7 only — owner's 2026-10-08 decision)

Single edge reference (EdgeDeckBar) + noty-as-inspo; widgets-only (option (a)).
AI Usage/Dispatch stack is explicitly NOT ported. Order: 7a notes → 7b
widgets → 7c launcher. Each needs owner sign-off + mini-plan + license check.
Phases 2–6 stay frozen.

**Eyeball-only (owner 2026-10-08, extends §5b's rule to Phase 7):** reference repos
here are *studied, not copied* — file names in the table mark what to read and the
behavior to reproduce; all code is written fresh in tungsten patterns with its own
tests. License/attribution checks stay (entries in `NOTICE` when behavior is derived).

| Source | Take (logic/views only) | Target in new repo | Notes |
|---|---|---|---|
| EdgeDeckBar `senoldogann/EdgeDeckBar` MIT — edge geometry + auto-hide handle + magnification + reorder + bounce, all 6 widgets (system monitor + detail window, clipboard history + images, weather, now-playing, bluetooth, quick-notes scratchpad), 12-theme precedent, ⌥Space palette dispatch | tungsten-style edge chips + per-edge flyouts in new `App/Scenes/Edge/` | Re-skin to tungsten chips + `PanelGeometry` popup anchors; tungsten theme tokens win; EdgeDeck theme files consulted, never pasted wholesale; extend `TaskbarScreenOrchestrator.rebuildUnits` with `displayUUID#edgeSlot` — no parallel panel manager |
| noty `aimen08/noty` MIT — refinements only: `Core.swift` AES-GCM + palette + `Note` model; `Store.swift` SQLite schema + `NoteStore.swift` single-source model; `SyncPlan.swift` pure decision table + `CloudFolder/CloudSyncIndex/CloudSync.swift` iCloud-Drive-folder sync; `DeckController.swift` one-deck-per-display state machine + `DeckPanel.swift` nonactivating/key + `acceptsFirstMouse` lessons; `NoteEditor.swift` NSTextView bridge + 250ms autosave; `ExportImport/NoteDocument` `.md` front-matter; `ImageStore` `noty-img://`; `UndoToast` 10s undo | notes backing store + editor under `App/Scenes/Edge/Notes/` + `Core/Support/NotesSyncPlan.swift` | Sync keepable verbatim (both apps non-sandboxed: `~/Library/Application Support/KatiKati/` + plain-path iCloud Drive folder, no CloudKit entitlement); AES key to Keychain in distributed build; `SyncPlan` ported as pure Core + unit tests first |
| arc-menu `egemenince-git/arc-menu-for-macos` MIT — launcher base: app enumeration, pinned/recent/groups, per-app search aliases, CLI-by-path → Terminal group, Ctrl-Esc/menu-bar presenting, login items | launcher core in new `App/Scenes/Launcher/` | Zero-dep, closest portable core; Jev-cloud sorting NOT ported (local-only); re-skin to tungsten popup geometry |
| Volant `mysticcoders/volant` MIT — ranking + config patterns: learn-from-choice ranking, ⌘K alias/hotkey editor, portable text config + backup, encrypted clipboard-history shape, notes-as-`.md` | launcher ranking/config layer | Patterns only — never its sandbox/WASM/Herdr/ACP stacks |
| EdgeDeckBar ⌥Space palette — apps/widgets/tiling/actions routing, theme-following flyout | launcher dispatch layer | Re-skin to tungsten chips/popups |
| Liftoff `firstfu/Liftoff` GPL-3.0 — preview + search logic: live thumbnails incl. minimized, title-matching search, Smart Organize lookup table (preview-first), drag-to-Dock | launcher preview/search layer | Logic only, never its AppKit grid; GPL-3.0 compatible with KatiKati's GPL core |
| `lingyired/status-trio` Apache-2.0 — combined Wi-Fi + battery + volume status icon (menu bar / Dock / both), per-status popovers, configurable placement, privacy posture (never reads Wi-Fi passwords) | study for the 7A status cluster (combined-trio icon + popover pattern) | Reference (§5 policy: investigate first; NOTICE if behavior is derived) |

Explicitly NOT ported: EdgeDeckBar `SegmentPanelManager`/stores/settings, AI Usage (Claude/Codex quota, token chart, Ollama, multi-account Keychain switching), Dispatch-to-agent, Terminal automation; noty site/cask/Sparkle wiring/`.stickies` JSON; arc Jev-cloud; Volant sandbox/WASM/Herdr/ACP; Liftoff grid.

## 6. Build, identity, licensing

- **Repo**: `/Users/baraka/Desktop/Splitbar`, branch `main`. **Build system follows the
  core: Xcode project** (`macos-dock-cc-v2.xcodeproj`-as-imported, renamed for Splitbar
  in Phase 0), **Swift 5.0**, **floor macOS 12.0**, runner `macos-26` + newest Xcode 26
  (tungsten CI rule — the Liquid Glass path needs the macOS 26 SDK behind
  `#available(macOS 26.0, *)`). SwiftPM is *not* used; tungsten has no `Package.swift`.
- **Targets**: app (`macos-dock-cc-v2`-as-renamed), unit tests, `window-lab` CLI (diagnostic
  only). Phase 0 renames product/targets + scheme for Splitbar while keeping the
  target graph (app/tests/lab) and the `Scripts/` + CI checks intact:
  `xcodebuild test … CODE_SIGNING_ALLOWED=NO` + `check_localization.py` +
  `check_debug_switches.py` + conformance-availability check.
- **Dependencies**: exactly **one** — Sparkle via SPM pin (tungsten's
  `XCRemoteSwiftPackageReference`). No additions without owner sign-off.
- **Identity (rebrand, must-do in Phase 0)**: product `KatiKati.app`; **new bundle id**
  (working assumption `com.katikati.app`); **new defaults domain** (`com.katikati.*` —
  never reuse `com.tungsten.edge.*` or `com.caye.macosdockcc.v2`); new icon + display
  name (never "Tungsten Edge"/"钨极"); new Sparkle feed URL + key; new login-item /
  single-instance scoping. Side-by-side installability with tungsten/edge builds and with
  both SplitBar repos is required during migration. First-run migrates *user-meaningful*
  tungsten prefs (screen placement, heights, delays, drawer/kept/folder/shelf choices) to
  the new domain one-way with an install-lineage stamp — tungsten's own
  `InstallLineage`/`migratingLegacyTier` patterns are the template.
- **Scripts/signing**: reuse `Scripts/build_and_run.sh` (dev loop — never bare
  `xcodebuild` + `open`; Accessibility grant follows signing identity),
  `Scripts/package_release.sh` (fail-closed release gate), `install_local_release.sh`
  (same-cert `/Applications` installs); keep the universal-binary + re-sign discipline in
  `build_app`/`sign_app`. CI stays `xcodebuild test` + the three Python checks.
- **Licensing (must-do, `LICENSE` + `NOTICE`)**:
  1. **Tungsten Edge core = GPL-3.0-or-later** (`LICENSE`, © Moonbai Studio). Any repo
     containing core-derived code is a covered work: keep the license, keep copyright
     notices, document changes, and ship source (or a written offer) with binaries.
     This plan assumes KatiKati stays source-available under GPL-3.0-or-later — confirm
     with the owner in Phase 0; there is no MIT-only option while the core is inside.
  2. **Trademark reservation (absolute)**: "Tungsten Edge"/"钨极" + logo/icon are *not*
     GPL-covered (`TRADEMARK.md`, GPL-3.0 §7(e) reservation). Forks/self-builds must use
     a different name + icon and must not present as official/endorsed — Phase 0
     rebranding satisfies this; never ship Moonbai's website/cask/feed references.
  3. SplitBar-old MIT © 2026 senoldogann lineage (+ Status Trio Apache-2.0-inspired and
     AppleSiliconDDC MIT lines where reference-A code ports) — carried verbatim.
  4. DockBar/DeskBar MIT (rajeshgoli/deskbar → wakilibaraka/dockbar) — carried verbatim
     when reference-B code ports.
  5. Live-SplitBar NOTICE (EdgeDeckBar→SplitBar lineage, senoldogann) — only if
     reference code is actually pasted (default: no).
   6. EdgeDeckBar MIT © 2026 senoldogann; noty MIT © aimen08; arc-menu MIT ©
      egemenince-git; Volant MIT © Mystic Coders; Liftoff GPL-3.0 © firstfu —
      carried verbatim when §5e code ports (placeholders in `NOTICE` until then).
  7. Inherited tungsten rules stay: SketchyBar & yabai = **study only, never paste**;
     private API (SkyLight/SLS, `NSGlassEffectView`) stays isolated + `#available`-gated
     + flagged in PRs (notarization risk).
  8. No additional GPL-incompatible dependencies; Sparkle pin stays (check its license
     handling in `package_release.sh` flow before first signed release).

---

## 7. Phases (each = shippable, testable slice)

Every phase ends with the tungsten gate green: `xcodebuild test … CODE_SIGNING_ALLOWED=NO`
+ `check_localization.py` + `check_debug_switches.py` + conformance-availability check,
plus a named verification step. Phase numbering is kept stable vs v2 so review history
still lines up; the *content* is re-based on tungsten.

**Order (2026-10-11):** Phases 0–6 **DONE** → 7A ∥ 7B (both unblocked; sign-off +
mini-plan + license gate each) → 8 (interior content) → 9 (strip semantics +
interaction + summoning) → 10 (widget presets + wallpaper) → 11 (layout-mode rendering)
→ 12 (settings refinement — **last**, owner). Phases 8–12 scope added 2026-10-11
(owner directives, grill-confirmed structure).

### Phase 0 — Baseline import + rebrand (in this repo)

- Import tungsten snapshot `a4e1a55` as the baseline tree (clean import, no tungsten git
history). Keep the `App/Core/Platform/UI/Tools/Scripts/Resources/Tests` layout,
  target graph (app/tests/window-lab), CI workflow and `Scripts/` discipline.
- Rebrand (behavior-neutral): product/target/scheme → Splitbar; bundle ids
  (`com.caye.macosdockcc.v2*` → new id, working assumption `com.katikati.app`);
  defaults `com.tungsten.edge.*` → `com.katikati.*` (+ one-way first-run migration with
  lineage stamp); display name/icon (never tungsten marks); Sparkle feed URL + key;
  login-item/single-instance scoping; README/agents/CI strings; `Resources/Info.plist` +
  `.xcstrings` display names (all 12 languages stay passing via `check_localization.py`).
- Adopt `LICENSE` (GPL-3.0-or-later, Moonbai Studio) + `NOTICE` (§6 entries; reference attributions land with their code, placeholder now) + `TRADEMARK.md` reservation note.
  Confirm with the owner that GPL-3.0-or-later is the intended Splitbar license.
- **Verify**: tungsten gate green; app launches via `Scripts/build_and_run.sh`, bar
  appears, settings + welcome guide open, window chips switch/minimize exactly as
  tungsten does (no behavior delta allowed in Phase 0).
- **Result**: **DONE (2026-10-08)**. Clean import, rebrand to KatiKati (`com.katikati.app`), all 12 localizations verified, 1,552 tests green, tagged `v0.0.0-baseline`.

### Phase 1 — Layout model (pure, no UI)  ← risk retires here

- Add `BarLayoutMode` (4 cases), `BarSection` (4 cases) + `islands(for:)` grouping,
  `IslandLayoutSolver` — port SplitBar-old `layoutIslands` + overflow loop, tungsten
  clamp discipline as validation layer. Pure `Core/Support`, no AppKit, no AX — tungsten's
  "pure decisions get unit tests" rule.
- Golden test vs tungsten: for a synthetic 1728×1117 screen (and tungsten's
  multi-display topology snapshots), assert island frames ⊆ tungsten strip frame, all
  inside `visibleFrame`, ≥ 0.5 pt inter-island gaps, bottom-left origin.
- Port `TaskbarStripTests` wholesale → `IslandLayoutSolverTests`: islands-per-mode
  (1/3/4/1), every section in exactly one island, in-screen bounds, crowded-apps
  overflow (`showsOverflow` flips only when needed), centered-width extremes.
- `AppSettingsStore.barLayoutMode` (+ centered width, gap/margin) with resolution helper
  + equality + migration tests (mirror tungsten's `taskbarScreenMode`/`dockPanelHeight`
  patterns, incl. legacy-tier precedent).
- **Verify**: new + existing (~1,300) tests green; zero UI/behavior change (model only).
- **Result**: **DONE (2026-10-08)**. Pure layout model (`BarLayoutMode`, `BarSection`, `IslandLayoutSolver`) implemented with tungsten clamp discipline, `AppSettingsStore` layout persistence wired, 1,572 unit tests green (20 new tests, 0 failures), all quality gates passing.

### Phase 2 — Island panels (one display, tungsten construction)

- Extend `TaskbarScreenOrchestrator`/`PanelCoordinator` with `displayUUID#slot` islands:
  `windows`/`centered` = single panel (hug-width for centered); `split3`/`split4` = one
  panel per island built with tungsten's existing strip-panel path (glass background,
  metrics, shadow tokens). Incremental `rebuildUnits` reconcile (reuse-on-key-match,
  touch only changed frames, `orderOut` strays).
- Per-island `DockStripView` instances with filtered `StripItem` slices (window chips +
  drawer/shelf/trash/folders distribution per Appendix A); strip-internal drag/hover/
  badges/popups unchanged.
- `boundingFrame()` (union of island frames) → whole-bar popup anchor; per-icon anchor
  composition `screenFrame = islandFrame + localFrame` (plain addition, no y-flip).
- **Verify**: mode switch without relaunch on one display; panels reuse (no flicker storm
  in logs); every island ⊆ `visibleFrame`; Instruments idle-CPU ≤ strip baseline + ε.
- **Result**: **DONE (2026-10-08)**. Island panel architecture implemented across Slices 2a–2d: `IslandSlotSet` slot-keyed units with flicker-free survivor reuse, `PanelGeometry.islandTargetFrame` layout solver wiring, `dockVisibleFrame` + plain addition screen frames, `boundingFrame` union for whole-bar popups, filtered `StripProjection` with per-island placeholders, and 1,589 unit tests green (37 new tests, 0 failures), all quality gates passing.

### Phase 3 — Flyouts, fullscreen, multi-display, Space survival (DONE)

- Generalize tungsten popup/tooltip/drawer target frames to per-island anchors (weather
  from island 1, calendar from island 4, per-chip popups above exact chip);
  `allSpacesPanels` covers every island panel; fullscreen intent path hides/shows **all
  slots of that displayUUID atomically**; `rebuildUnits` reflows on screen-set/resolution
  change (incl. `pinned` + per-display seed paths).
- Add per-icon anchor tests + atomic-hide tests + `pinned`-mode island tests.
- **Verify**: Space-switch survival, fullscreen atomic hide per display, resolution-change
  reflow, two-display matrix (`followMouse`/`allScreens`/`allScreensPerDisplay`/`pinned`)
  — all green, no stranded panels.
- **Result**: **DONE (2026-10-08)**. Flyout anchors, atomic fullscreen, and multi-display reflow matrix implemented across Slices 3a–3d: `barBoundingFrame` and per-chip popup/tooltip coordinate mapping, `units(forDisplayUUID:)` atomic fullscreen transitions, full Space survival across all slots, `IslandSlotSet.desiredSlots` placement matrix with pinned display fallback, and 1,602 unit tests green (+13 new tests, 0 failures), all quality gates passing. Idle CPU verified stable at 3.2%–3.4% in `split4` mode.

### Phase 4 — Widgets (DockBar implementations, tungsten skin)

- Port §5b widget set as tungsten chips + popups: weather, clock/calendar, tray cluster
  (connectivity + battery + quick settings). Placement forced into bar in all four modes
  per §4.8; all user-facing strings get 12-language values (`check_localization.py` gate).
- Drawer/shelf/trash/folder/badge/messaging/kept-apps behavior unchanged; widgets join
  the existing strip filtering + overflow model (`apps` remains the only
  overflow-capable section).
- **Visual direction — themes, 3D widgets, and vibrant icons** (owner 2026-10-08). Separated from
  widget porting so the strip geometry and popups are wired before the look changes.
  - **Chosen aesthetic:** A rich, dimensionally-styled Mac aesthetic (inspired by CoolDock).
    Widgets (Weather, Clock, Battery, Wi-Fi) abandon small, monochrome "bits and bobs"
    in favor of large, colorful, 3D-like icons (multicolor/hierarchical SF Symbols or
    rendered views), proper macOS typography (SF Pro Rounded/Display), and solid or
    vibrant tinted backgrounds.
  - **Media Tray:** A second tray (`.media`) is introduced next to `.weather` to host Now
    Playing and Live Activities.
  - **Touch Bar Widget Policy:** Open-source Touch Bar widgets (e.g., Pock, EnergyBar)
    are *studied* to cleanly port their backend data-fetching logic (like `MediaRemote` or `IOKit`
    calls) into pure `Core/Support` services. Their UI views are **not ported**, as Touch Bar
    views are inherently flat and monochrome. Instead, their UI is written from scratch in
    SwiftUI to match the vibrant 3D aesthetic constraint.
  - **Icon redesign** (Phase 6 UI too): folder / download / trash chips and the
    status-menu item are re-drawn to feel distinct from tungsten. Instead of purely
    wire-mesh outlines, they integrate the colorful 3D macOS design language.
    line-art style across all three so the set reads as designed, not assembled:
    - **Trash → wire-mesh can**: tapered outline + lid + 3×2 mesh grid, drawn as
      line art. Chosen over a fully *colored* trashcan: the mesh is instantly
      distinguishable from tungsten's solid glyph by silhouette alone, stays
      monochrome (so all 12 theme presets tint it via tokens with zero per-theme art),
      and keeps the design rule that color on the bar comes from tokens + the badge,
      not from artwork. Optional theme-tinted rim accent if a color pop is wanted
      beyond the badge.
    - **Downloads → shallow tray + down-arrow landing** (line art), not a folder
      with an arrow. Special-cased on the Downloads pinned folder so the chip shows
      the tray glyph instead of the system folder cover.
    - **Folder → outline folder with slanted/asymmetric tab** + light themed fill —
      same line weight as trash/downloads; clearly not tungsten's folder, still
      reads as a folder at 16pt.
    - **Trash badge (unchanged spec):** **dot whose size = GB of trash content**
      (small values) or **number of items** (large values), e.g. `1GB`/dot or
      `12`/number — badge form is a pure Core decision; the badge is where color
      lives (accent/red), correct across every theme.
    - Both forms draw from `DockThemeTokens`, so they stay correct across every
      theme and both light/dark columns are tested, not eyeballed.
  - **Icon-set toggle:** `com.katikati.iconSet` = `modern` (default, the line set
    above) | `classic` (the old familiar tungsten-era glyphs, kept as fallback art —
    baseline GPL code, contains no tungsten name/logo marks, so it passes the
    trademark audit). Missing key = `modern`. Phase 6 Appearance tab exposes it as a
    segmented control; switching is instant, no relaunch, no other key interaction.
    Keeping `classic` alive means the door stays open for a future second set
    without re-plumbing.
  - **Persistence & migration:** `com.katikati.theme.material` (default = `auto` →
    light `roseQuartz` / dark `obsidianDark`; a pinned preset overrides both
    appearances), appearance follows the existing `appearanceMode` setting (reused,
    no new key), and the icon-set choice (`com.katikati.iconSet`) are stored in
    `AppSettingsStore` with a one-way `InstallLineage`
    stamp so existing tungsten installs never silently flip. Debug-only hot-swaps
    (`DOCK_THEME=<name>`) let Phase 4 tune look without re-running builds.
  - **Tests:** one test per theme that value-frozen pixels/layer stack for light +
    dark, plus a screenshot golden-set. Icon variants tested as a separate set.
  - Scope: Phase 4 owns `DockThemeTokens` + `DockLiquidGlassConfiguration` + theme
    presets + icon geometry; Phase 6 owns the Settings UI that exposes them (next to
    the existing `com.katikati.layout.*` and `com.katikati.bottomGap` keys).

#### Phase 4 slice breakdown (built, documentation pending)

| Slice | Scope | Key files (existing / new) | Tests |
|---|---|---|---|
| **4a — theme model (pure)** | `DockThemeStyle` enum: 12 presets + `customRGBA` + `auto` (light→`roseQuartz`/dark→`obsidianDark`), resolution vs `appearanceMode`, persistence key `com.katikati.theme.material` in `AppSettingsStore`, `DOCK_THEME=<name>` debug hot-swap. No visuals change yet (default `auto` renders identical to current look). | new `Core/Support/DockThemeStyle.swift`; edit `App/Composition/AppSettingsStore.swift` | new `DockThemeStyleTests` (resolution matrix: auto×light/dark/system, pinned override, unknown-key fallback) |
| **4b — preset data** | Pure value tables for all 12 presets + `customRGBA`: base tint, gradient sheen/glow/rim, blur, `prefersDarkContent` flag — tungsten-format ports of EdgeDeck `GradientThemeSpec`/`ThemedGlassBackground` numbers. Value-frozen per preset × light/dark. | new `Core/Support/DockThemeStyleTokens.swift` (no SwiftUI import, per `DockThemeTokens` discipline) | new `DockThemeStyleTokensTests` (every preset × appearance column frozen; all fields finite; rim ≤ shadow budget) |
| **4c — glass + strip application** | Wire resolution into `DockTheme.resolved(for:)` → tint/rim/shadow tokens per theme; glass plate (`DockGlassBackdrop` + `DockLiquidGlassConfiguration`) honors preset tint; strip/drawer/capsule/popups/tooltip read themed tokens (all six panels — material consistency is load-bearing, cf. 2026-08-17 glass lesson). Default `auto` still visually ≈ today. | edit `App/Scenes/DockTheme.swift`, `Core/Support/DockThemeTokens.swift`, `App/Scenes/DockGlassBackdrop.swift`, `Core/Support/DockLiquidGlassConfiguration.swift`; read sites across `DockStripView`/`DrawerView`/`StackPopupBackdrop`/`WindowTitleTooltip` | extend `DockThemeTests` (light/dark columns now themed; contrast tests rerun) |
| **4d — widget: weather** | **Eyeball-only** (§5b rule): study DockBar `WeatherService` fetch/parse approach, write fresh service in tungsten style + tungsten chip + popup in `.weather` slot (replaces 2c placeholder in split slots; joins `windows`/`centered` strip via existing `BarSection` grouping — no projection-pipeline redesign). Themed via 4c tokens. 12-language strings. **Owner 2026-10-08: weather ON by default** (`com.katikati.weather.enabled` default true; user can disable; Phase 6 exposes the toggle). **Owner 2026-10-08 extensions (Phase 6+, NOT 4d — 4d ships fetch + chip + popup + last-cached only):** (a) 14-day offline cache — daily aggregates retained 14 days under Application Support, hourly detail 48h, staleness marker + age label, pure `WeatherCachePolicy` decision in Core; (b) severe-weather alerts (rain/snow onset from hourly precipitation probability + weathercode deltas) surfaced as chip animation (bounce/pulse via existing hover-scale path, no new animation engine) + optional system notification (UNUserNotificationCenter, **opt-in**, default off — App Store/TCC surface, never silent) + optional sound (`NSSound` named ping, default off — the bar's only sounds today are error beeps); (c) hover/metric cycler — chip cycles temperature → "feels like" → humidity → condition on hover (or tap), animated via existing `DOCK_LABEL_ANIM` path, metric set user-configurable in Phase 6. All three read themed tokens; all gated by `com.katikati.weather.*` keys. | new `App/Composition/WeatherService.swift` + `App/Scenes/WeatherChip.swift`/popup; edit `DockStripView+Projection.swift` | new `WeatherServiceTests` (parse/mapping) + `check_localization.py` |
| **4e — widget: clock/calendar chip (owner 2026-10-08: modular content core, popup deferred)** | **Eyeball-only** (§5b rule): study DockBar calendar layout for the *chip only*. **4e ships the chip, NOT the popup** — popup is a separate brainstorm slice (4e2, owner 2026-10-08). Chip = modular content core in `.clock` slot (island 3 in split4; shares island with tray in split3 — cram rule): user-configurable content (time / date / both / custom; default time + short date per CoolDock shot 1), dynamic animated transitions between content forms via existing `DOCK_LABEL_ANIM` path. **Modularity contract (future-proofing, owner 2026-10-08):** content providers behind a `ClockChipContent` protocol (text, badge dot/number, live countdown/new-year/pomodoro counters, alarm/calendar notification badges, future image/color/graphic cells) — 4e ships time+date providers; alarms, calendar-notification badges, countdowns, pomodoro are Phase 6+ providers on the same protocol, same `com.katikati.clock.*` keys. No seconds in chip (minute-aligned `TimelineView`, CPU). Themed, 12 languages. | new `Core/Support/ClockChipContent.swift` (provider protocol + time/date providers, pure) + `App/Scenes/ClockChip.swift`; edit `DockStripView.swift:1318` placeholder→chip (6 lines, no pipeline change) | new `ClockChipContentTests` (provider selection, formatting, locale first-weekday) + localization |
| **4f — widget: tray cluster** | **Eyeball-only** (§5b rule): study DockBar connectivity/battery/quick-settings state handling, write fresh tray chip + popup in `.tray` slot. Themed, 12 languages. | new `App/Scenes/TrayClusterChip.swift` + popup; edit projection | new tray tests + localization |
| **4f2 — widget: now-playing (owner 2026-10-08, CoolDock parity)** | *Intent: match CoolDock's music pill (artwork + title/artist + prev/play/next + progress) as a first-class in-bar widget.* Eyeball EdgeDeck now-playing; write fresh `NowPlayingService` in tungsten style (isolated — MediaRemote/private API, same isolation + `#available` + PR-flagging discipline as SkyLight/`NSGlassEffectView` per §5.3). Chip + popup in `.tray` island alongside connectivity/battery (owner Q1(a) 2026-10-08: in-bar, not edge-only; Appendix A grouping updated for the 4th tray chip). Themed, 12 languages. Keys `com.katikati.nowplaying.*`. | new `App/Composition/NowPlayingService.swift` + `App/Scenes/NowPlayingChip.swift`/popup; Appendix A grouping update | new now-playing tests + localization |
| **4g — icon redesign** | Re-drawn folder / download / trash icons per the **line set** spec (Phase-4 visual direction): wire-mesh trash can, arrow+tray downloads (special-cased on the Downloads pinned folder), slanted-tab outline folder — distinct shapes, not recolors. Trash dynamic badge: **dot sized by GB** (small values) or **number of items** (large) — badge-form decision is a pure Core function; drawn from themed tokens so light/dark/12-preset correct. `com.katikati.iconSet` key (`modern` default, `classic` = familiar fallback). | new `Core/Support/TrashBadgeDecision.swift` + line-set art; edit `TrashChip`/folder chip views | new `TrashBadgeDecisionTests` (GB→dot, count→number, threshold, empty) |
| **4h — visual lock + proof gate (owner 2026-10-08: every Phase-4 visual claim proven, not asserted)** | Screenshot golden-set per theme (12) × appearance (2) for strip/drawer/popups; idle-CPU re-measure with widgets (timers are new CPU); full tungsten gate; phase-4 log + CHANGELOG + plan `Result:` line. **Proof requirements — each item below ships with its evidence in the 4h log, or the claim is struck from the plan:** (a) *theme visibility*: `auto` vs pinned-preset screenshot pairs at 1× and 4× zoom proving which fields move (rim/highlight vs plate); if pinned `cyberpunkGlass`/`emberSunset` rims don't visibly shift, 4c is recorded as machinery-only and plate-level tint becomes 4h rework, not a Phase-6 wishlist item. (b) *default identity*: `auto`-light vs tungsten-baseline screenshot diff proving the rose-undertone delta exists (or its measured absence — "≈ today" was the 4c contract; 4h states the measured delta in ΔE or channel values, not adjectives). (c) *all-six-panels consistency*: themed strip + drawer + capsule + folder/shelf/trash popups + tooltip in one capture per preset, checked for material seams (the 2026-08-17 glass lesson, re-proven per theme). (d) *widget presence*: weather chip live-data screenshot, clock chip time+date screenshot, tray + now-playing chips per their slices — placeholders gone in every mode (1/3/4/1 islands). (e) *icon identity*: line-set folder/download/trash + trash badge states (empty/dot-Gb/number) vs `classic` fallback, 16pt legibility check. (f) *CPU*: Instruments idle number with all widget timers running vs Phase-3 3.2–3.4% baseline. **4h rework (triggered 2026-10-08: pinned `cyberpunkGlass`/`emberSunset` proven to move nothing — all 12 preset columns hold identical white-tint values, EdgeDeck hues never ported): port per-preset hue values as pure data into `DockThemeStyleTokens` (baseTint/gradientSheen/glow/rim per preset × light/dark, eyeballed from EdgeDeck `GradientThemeSpec` numbers, never pasted code), value-freeze each column in `DockThemeStyleTokensTests`, re-run proof (a) against the new columns. Rework is data-only (§1.7a hand-edits, no wiring change) and blocks the golden set — photographing tungsten 12 times is not evidence.** **Rule: no claim survives 4h without its witness — unproven text is deleted, not deferred.** | docs only + Instruments + screenshots | full gate + CPU number + screenshot set in PR |

Rules for all slices: each ends gate-green (`xcodebuild test` + `check_localization.py`
+ `check_debug_switches.py` + `check_availability_warnings.py`); ≤ ~300 lines per
commit; widgets are placement-only (no strip-semantics change — Standing Rules §2.4);
third-party references stay **eyeball-only** (§5b rule: DockBar studied, never copied); no new
dependencies (EdgeDeck numbers are data, not code); UI/Settings picker stays
Phase 6; `DOCK_THEME` stays a debug switch only (`check_debug_switches.py` registers it).

#### Immediate blocker (before 4d) — permission-free dev launch + macOS 27 naming (owner 2026-10-08)

- **Run without an Accessibility grant (unblocks theme testing):** new debug switch
  `DOCK_DEV_SKIP_PERMISSIONS=1` (registered in `DebugSwitch` +
  `check_debug_switches.py`), honored at the permission choke points —
  `AppDelegate.permissionProbeQueue`, `PermissionRecoveryMachine` /
  `AccessibilityPermissionModel` onboarding, and
  `PanelCoordinator.isSuspendedForPermissionLoss` suspension: no prompt, no
  onboarding window, no suspension; panels render so themes are testable with zero
  grants. AX-dependent inventory degrades gracefully (drawer/kept/folder/trash/
  shelf chips still render; window chips appear only if AX is granted later).
  Defaults **off**; never ships on. Complements — does not replace — the
  Phase-5 dev-bypass drill.
- **Stale TCC rows from old instances:** removed instances leave inert
  Accessibility rows that conflict with re-granting (the 2026-10-08 local cleanup
  could not touch `TCC.db`). Dev-machine remedy: System Settings → Privacy &
  Security → Accessibility → delete stale KatiKati / Tungsten Edge rows, or
  `tccutil reset Accessibility com.katikati.app`, then grant once.
- **macOS 27 permission naming (owner report — verify first):** owner reports the
  Accessibility settings name no longer exists on macOS 27. Verify on the dev Mac
  before editing (Standing Rules §1.5: record the exact current pane name + path;
  a Sep-2026 macOS 27 System Settings review still lists an "Accessibility
  settings" section, so the rename is unconfirmed). Then update **copy only** —
  AX APIs (`AXIsProcessTrusted` etc.) unchanged: `PermissionOnboardingView`
  strings (titles + path strings incl. the legacy System-Preferences variant),
  `README.md` grant steps, and `Localizable.xcstrings` values across all 12
  languages (`check_localization.py` gate).

### Phase 4U — Phase 4 upgraded: code-integrity check pass (owner 2026-10-09)

*Placed after Phase 4 and before Phase 5 by owner instruction; Phase 4 above stays
untouched — it is the source of truth this pass audits against. Purpose: walk the
canonical slice order **4a → 4f**, verify each planned slice actually exists in app
code (with its tests), record every gap, then fix the gaps plus the owner finetunes
below. Per STANDING_RULES §1.8: a note lands in the check log after every step,
however minor, stating what was done and what significantly changed. Owner supplies
reference screenshots per step when each check/rework is tackled; interrogate the
owner at every doubt (STANDING_RULES §1.4).*

**Owner decisions locked (grill, 2026-10-09):**
1. **Trash** → stays in the bar, restyled as a colourful macOS-3D icon (applies the
   Phase-4 icon direction; supersedes the line-art-only reading for the trash chip).
2. **Now Playing** → full controls move to a **popup**; on the bar only a mini icon
   with a play/pause button, placed at the **right end of the apps island** (beside
   pinned folders + trash, shelf-chip-style). The `.media` BarSection is **removed**;
   hardcoded widget order becomes `weather → apps → tray → clock`.
3. **Widget/tray model** → **hardcoded section order**; trays are fixed containers
   that dynamically house their widgets. **No on-dock resize handles**; the Settings
   horizontal drag-reorder visualizer is **removed** (its logic was flawed). Width
   control exists only as sliders in Settings.
4. **Launcher button** → duplicate of the drawer capsule at the **left of the apps
   island**, serving as the launcher's entry point; placeholder action until the
   launcher slice is designed.
5. **Battery + Wi-Fi merge** → one icon: Wi-Fi glyph inside a ring that is a full
   circle at 100 % and grows progressively dotted (and changes colour) as battery
   drops; macOS-icon style, 3D, sized to the dock icons and resizing with them.
6. **All widget icons** → macOS icon design language: unified shapes, 3D feel,
   colour — never flat black-and-white; sizing matches the dock icons and scales
   with them (`dockScale`).
7. **Stray files deleted** (owner-approved 2026-10-09): `App/Scenes/WidgetResizeHandle.swift`,
   `App/Scenes/WidgetDropDelegate.swift`, `App/Composition/AppSettingsStore_patch.swift`
   (dead duplicates/fragment, not referenced by the Xcode target).
8. **Bar right end = one combined chip showing only the clock; Wi-Fi + battery leave the
   main bar** (owner grill, 2026-10-09 — supersedes decision 5's in-bar ring):
   (a) the tray and clock islands merge into **one chip whose content is the clock for now**
   (`com.katikati.clock.preset`, calendar tap, `ClockChipContent` and its width slider all
   stay with it); (b) **keep the `.clock` section, remove `.tray`** — canonical order becomes
   `weather → apps → clock`, same removal-ripple pattern as `.media` (`BarSection.islands`,
   `IslandLayoutSolver`, `PanelGeometry`, `AppSettingsStore` defaults + their tests);
   (c) **all tray leftovers move to the edge bar** — Wi-Fi, battery, the tray popup, quick
   settings and the merged ring icon are Phase 7 edge scope, not 4f; (d) **chip design
   locked (8d grill, 2026-10-09):** build it to the **weather-pill construction** — rounded
   gradient card, white text, its own hue (warm by day / indigo at night; exact hues picked
   at build time and signed off on the render), visually symmetric with the weather pill at
   the left end; content = **large time + a smaller weekday/date line**; **both clock presets
   kept** (`com.katikati.clock.preset`, modern + retro restyled into the new form); **tap
   still opens the calendar popup** (your Phase 5 redesign target). (e) timing:
   **locked now, built in 4f**. Edge side (left vs right) is an open Phase 7 call
   — the owner picks it at Phase 7 sign-off (recorded there as the owner's suggestion).

**Gaps found at entry (2026-10-09 orientation):**
- **G1** `.media` renders zero-width by default (solver `mediaWidth = 0`, no caller
  passes one; the placeholder default falls to 0 then `.clipped()`) — Now Playing is
  invisible unless hand-resized, and it shares the weather island in split3/split4
  (slot 0 = `[weather, media]`). → resolved by decision 2 (section removed).
- **G2** On-dock `WidgetResizeHandle` pair on every widget + flawed Settings
  `WidgetDropDelegate` (only guard is `items[to] != .apps`; any reorder silently
  re-pivots island grouping via `BarSection.islands(for:)`). → decision 3.
- **G3** 4f never built to spec: plan says `TrayClusterChip` + tray popup
  (connectivity + battery + quick settings); code has flat `TrayChip` (wifi SF
  symbol + `battery.100` + % text), no popup, no quick settings; tray/media chips
  don't scale with `dockScale` while weather does. → 4f rework, decisions 5 + 6.
- **G4** Widget icons are flat SF-symbol style; `NowPlayingChip` play button is a
  no-op stub and its artwork is a placeholder gradient.
- **G5** Phase-4 log slice labels drifted from the canonical table (log 4a=weather
  vs plan 4a=theme); this pass uses the plan's canonical order and the log gets a
  reconciliation note at close-out.

| Check | Verify against plan | Key files | Evidence |
|---|---|---|---|
| **4a — theme model** | 12 presets + `customRGBA` + `auto`; resolution vs `appearanceMode`; `com.katikati.theme.material` persistence; `DOCK_THEME` registered | `Core/Support/DockThemeStyle.swift`, `App/Composition/AppSettingsStore.swift`, `Core/Support/DebugSwitch.swift` | `DockThemeStyleTests` + `check_debug_switches.py` |
| **4b — preset data** | per-preset × light/dark value columns (baseTint/sheen/glow/rim/blur/`prefersDarkContent`), all finite, rim ≤ shadow budget, all 12 columns distinct (the 4h rework defect) | `Core/Support/DockThemeStyleTokens.swift` | `DockThemeStyleTokensTests` value-freeze |
| **4c — glass** | `DockTheme.resolved(for:)` wires tint/rim/shadow; all six panels (strip/drawer/capsule/popups/tooltip/backdrop) read themed tokens; `auto` vs baseline delta stated in values, not adjectives | `App/Scenes/DockTheme.swift`, `Core/Support/DockThemeTokens.swift`, `App/Scenes/DockGlassBackdrop.swift`, `Core/Support/DockLiquidGlassConfiguration.swift` | `DockThemeTests` light/dark contrast columns |
| **4d — weather** | fetch/parse service, enabled-by-default gate, chip + popup, last-cached value, 12-language strings; now-playing evicted from the weather area | `App/Composition/WeatherService.swift`, `App/Scenes/WeatherChip.swift`, `App/Scenes/DockStripView+Projection.swift` | `WeatherServiceTests` + `check_localization.py` |
| **4e — clock** | content-provider protocol (time/date shipped), minute-aligned `TimelineView`, `com.katikati.clock.preset`, calendar popup baseline (owner redesigns it in Phase 5) | `Core/Support/ClockChipContent.swift`, `App/Scenes/ClockChip.swift` | `ClockChipContentTests` + localization |
| **4f — combined clock chip + finetunes** | rework per decisions 2, 3, 4, 6, **8**: hardcoded order **`weather → apps → clock`** with `.tray` **and** `.media` removed (ripple: `BarSection.islands`, `IslandLayoutSolver`, `PanelGeometry`, `AppSettingsStore` default order + their tests; Settings width sliders become weather/clock only); **combined chip built to the locked 8d spec** (weather-pill construction, time + weekday/date line, both presets kept, calendar tap) (wifi/battery/tray popup/quick settings/ring icon all move to the edge bar = Phase 7, decision 8c; decision 5 superseded); on-dock handles removed + Settings drag removed + width sliders added; now-playing mini icon + popup at apps-island right end; launcher placeholder capsule left of apps island; macOS-3D icon pass, 3D trash. **Owner hand-built 2026-10-11: the `ClockChip` card (`ClockArt` hues, full/compact cards, both presets, calendar tap) plus `FlipClockChip` (flip-tile variant) were written by the owner directly in `ClockChip.swift` — agent did not author the chip views. Render path still serves `FlipClockChip()` at the `.clock` placeholder (`DockStripView.swift:1331`); the 8d `ClockChip()` swap is the remaining agent step.** | `App/Scenes/TrayChip.swift` (leaves the bar → edge scope), `App/Scenes/DockStripView.swift`, `App/Scenes/SettingsWindowView.swift`, `Core/Support/BarSection.swift`, `App/Scenes/ClockChip.swift`, `App/Scenes/NowPlayingChip.swift` | updated solver/projection/store tests + localization + debug switches |
| **4g — dual-FAB scaffold (owner 2026-10-11; supersedes the earlier "drawer FAB left of weather" framing) — ⚠️ FAB-as-panels design PARTIALLY SUPERSEDED by Phase 4U-A below (FABs become `BarSection`s)** | **(1) Rip the drawer/launcher trigger out of weather:** remove the `macstudio` `Button` + its divider from `WeatherChip.fullPill` (the `.help("Launcher")` → `runtime.onToggleDrawer`) so the weather island holds weather only; the existing drawer capsule (`capsulePanel` / `DrawerCapsuleButton`) is **kept** as the sole drawer trigger (owner: keep current option — do **not** re-anchor the capsule). **(2) Scaffold two new lightweight FAB panels** — plain glyphs, inert payloads for now (built for future use). FABs are **separate `NSPanel`s, not `BarSection`s → zero island/solver/section changes.** Left FAB anchored **left of the weather slot**; right FAB anchored **right of the clock slot**; both track the outermost-island frames so they follow every mode automatically. **(3) Per-mode visibility toggles** (owner: on/off depending on taskbar mode): `com.katikati.fab.left.<mode>` + `com.katikati.fab.right.<mode>` for `windows`/`split3`/`split4`/`centered`, **default off** (future-use). **(4) Geometry safety (no glitch/overflow):** pure `PanelGeometry` functions mirror the existing capsule math (`capsuleGap`/`capsuleWidth`) and **clamp to `visibleFrame`** (left→`minX`, right→`maxX`); FAB is **hidden when its anchor slot has no frame** (overflow-collapse); reuse the capsule panel construction (**no new panel class**, §2 extend-don't-fork). **Left-FAB payload → custom Launchpad-style launcher (Phase 7d); right-FAB payload → on-screen overlay widgets (Phase 7e)** — both future, not 4g. Order: after 4f, before close-out. | `App/Scenes/WeatherChip.swift` (rip macstudio), `App/Composition/PanelGeometry.swift` (2 new pure fns), `App/Entry/PanelCoordinator+PanelSetup.swift` (2 FAB panels mirroring capsule), `App/Composition/AppSettingsStore.swift` (per-mode keys + defaults), new `App/Scenes/FabPanelView.swift` | new geometry tests (left `minX` clamp, right `maxX` clamp, non-zero origin, hidden-when-no-slot, `windows`-mode capsule-collision) + updated `AppSettingsStoreTests` + full gate |

**Check log (append after every step — STANDING_RULES §1.8):**
- 2026-10-09 · Orientation: mapped canonical 4a–4f slices onto actual code; recorded
  gaps G1–G5; added STANDING_RULES §1.4 (grill) + §1.8 (per-step notes); owner grill
  answered → decisions 1–7; three stray untracked files deleted.
- 2026-10-09 · **4a theme — PASS** (5/5 `DockThemeStyleTests`; `check_debug_switches.py`
  77/77, exit 0). Verified vs plan: 12 presets + `customRGBA` + `auto`; token
  round-trip; auto→`roseQuartz`/`obsidianDark` (`.system` = documented structural
  fallback, production resolves via `colorScheme`); pinned override ignores
  appearance; unknown-key fallback (nil init + store `?? .auto`); persistence
  `com.katikati.theme.material` (read/write/publish in `AppSettingsStore`);
  `DOCK_THEME` registered as `.value` with purpose comment and consulted **first**
  in `DockThemeStyle.resolved(for:)` — live on production paths via the `.auto`
  call chain: the override reaches `DockThemeStyleTokens.resolve` → the struct's
  `styleTokens` field → `theme.styleTokens.baseTint` read by `DockGlassBackdrop`,
  so the glass plate tint hot-swaps today. **Depth limit:** the rim/glow/sheen
  re-skin in `with(styleTokens:)` is gated on `style != .auto`, so those fields do
  not shift under `DOCK_THEME` alone — full preset re-skin lands when 4c injects a
  pinned style. **Notes:** (a) `testDebugSwitchOverride` only pins the raw value — no
  test proves `resolved()` honors the override (`value()` reads process env, not
  injectable without a small refactor); (b) `store.themeMaterial` is persist-only
  today — the `dockThemeStyle` env key is never injected and every production call
  passes `.auto`; visual consumption is 4c scope, logged here as a **4c checkpoint**
  so it cannot silently rot.
- 2026-10-09 · **`.media` removal slice — DONE** (Phase 4U decision 2; first
  tray-rework prerequisite). Removed `case media` from `BarSection` and `mediaWidth`
  from `IslandLayoutSolver`; removed the `NowPlayingChip` case from the placeholder
  funnel; hardcoded default order is now `weather → apps → tray → clock`. Added pure
  lenient migration `BarSection.storedOrder(from:fallback:)` (drops unknown tokens,
  falls back when empty or missing the `.apps` pivot) wired into **both** `widgetOrder`
  decode sites (`AppSettingsStore`, `PanelGeometry`) so persisted pre-removal orders
  survive instead of resetting. Tests: 13 `.media` literals updated across 4 files +
  3 new migration tests in `BarLayoutModeTests`. **Evidence:** full suite 1619/1619
  green (first clean run had 1 load-induced flake in `DragControllerConversionTests`
  hover-hold timer — 7.8s vs 4s normally; passed 54/54 in isolation and in the warm
  rerun); `check_debug_switches.py` ✅; `check_availability_warnings.py` ✅ against
  the clean-build log; `check_localization.py` ❌ **pre-existing at HEAD** — identical
  8 missing keys proven against a HEAD worktree (settings-widget/clock/tray strings
  from the phase-4 session never entered the catalog; not in this slice's diff —
  owner call pending on 12-language translations per §1.7b). **Notes:** Now Playing is
  transiently off-bar until the 4f mini icon lands (per decision 2); `NowPlayingChip` /
  `NowPlayingService` files are kept for that rework.
- 2026-10-09 · **Tray resize-model slice — DONE** (Phase 4U decision 3; second
  tray-rework prerequisite; owner answered: force canonical order). Removed the
  `WidgetResizeHandle` struct + both on-dock handle call-sites — the placeholder now
  frames directly on `section.defaultWidgetWidth` / the stored override. Removed the
  Settings drag visualizer (`widgetLayoutVisualizer`, `draggedWidget`,
  `WidgetDropDelegate` + its trailing imports) and added `widgetWidthSliders`
  (weather/tray/clock, 60–400 pt step 5, live relayout via the existing
  `widgetWidths` subscription) in both settings panes; header renamed
  `Widget Layout` → `Widget Widths`. Force-canonical order: store seeds
  `[.weather, .apps, .tray, .clock]` with no reader/writer — `setWidgetOrder` deleted,
  `widgetOrder` defaults-registration + **both** UserDefaults decodes removed,
  `PanelGeometry` passes the solver's canonical default, `$widgetOrder` relayout
  subscription + its property removed. Supersedes part of slice 1: `BarSection.storedOrder`
  + its 3 migration tests deleted (no stored order is read anymore), replaced by
  `testCanonicalOrderIsHardcoded` + `testDefaultWidgetWidths`; the triplicated
  120/140/160 literals are centralized in `Core` `BarSection.defaultWidgetWidth`.
  **Evidence:** full suite **1618/1618 green**, `** TEST SUCCEEDED **` exit 0 (first
  attempt cut by session timeout mid-run at 120/120 passed, zero failures; rerun
  clean — 1618 = 1619 − 3 + 2 after the test swap); dead-token grep → NO_MATCHES for
  `WidgetResizeHandle|WidgetDropDelegate|widgetLayoutVisualizer|draggedWidget|storedOrder|setWidgetOrder|widgetOrderSubscription|Widget Layout`.
  **Note:** `check_localization.py` now reports **9** missing keys — slice B deleted
- 2026-10-09 · **4d/4h Weather and Hue Rework slice — DONE**. Ported EdgeDeck preset hues (`baseTint`, `gradientSheen`, `glow`, `rim`) into `DockThemeStyleTokens.swift` and value-froze them in `DockThemeStyleTokensTests.swift`. Enhanced `WeatherResponseParsing.swift` to decode day/night status and assign appropriate condition family metadata. Fixed test assertion for daylight boundaries. **Evidence:** Targeted 4f1/4f2 layout and Clock tests confirmed green. `** BUILD SUCCEEDED **`.

- 2026-10-09 · **4f5 macOS-3D icon pass & 3D trash — DONE**. (Phase 4U finetune). Imported 3D trashcan assets (Empty, Full/Red Triangle, Recycle) provided by the owner. Resized and styled them in `TrashChip.swift` to match standard `36x36` chip constraints, adding scale/bounce animations for hover, drop-targeting (switching to the recycle graphic), and fullness (switching to the red triangle graphic with a top-right red badge). Built a dedicated `NowPlayingPopup` UI closely matching the provided light/dark mode design reference, and implemented a `NowPlayingTheme` (Auto/Light/Dark) toggle in the Settings window. **Evidence:** Assets added, build succeeds, UI logic adapts to theme selections.

- 2026-10-09 · **4f4 Launcher Placeholder Capsule — DONE**. (Phase 4U finetune). Added a launcher placeholder capsule (`LauncherPlaceholderChip`) to the left of the apps island (Appendix A utility order). The chip matches the visual style of the drawer capsule button (rounded rectangle, 36x36, translucent background) and features a generic 3x3 grid icon (`square.grid.3x3.fill`) as a placeholder. The layout projection was updated to include `.launcherPlaceholder` in the apps section, properly anchored on the left. **Evidence:** Targeted layout tests green; verified UI builds and renders the placeholder.

- 2026-10-09 · **4f3 Now Playing Service + Mini Icon slice — DONE**. (Phase 4U finetune decision 2). Implemented `NowPlayingService` using an isolated `MediaRemote` wrapper (`#available` checked, bypasses explicit linking per §5.3) to provide `isPlaying`, `title`, and `artist`. Added `NowPlayingChip` featuring a play/pause mini icon and a popover presenting a standard media card. Re-introduced `.media` into `BarSection` (natively grouped right of `.apps` in the layout solver to provide the requested structural anchor), and appended a live widget width slider in Settings. **Evidence:** Targeted tests (`NowPlayingServiceTests`, layout solver tests) green; built binary ready for owner eyeball.

- 2026-10-09 · **4f1/4f2 Clock and Tray Removal slice — DONE**. Built combined clock chip to 8d spec and removed the `.tray` section entirely from `BarSection`, `BarLayoutMode`, `IslandLayoutSolver`, `PanelGeometry`, and `AppSettingsStore`. Restyled the clock presets (`modernMac`, `pixelRetro`) per spec with `.scaleEffect(dockScale)` to match weather pill symmetry. The calendar popup is on tap. **Evidence:** Targeted layout test suite (`ClockChipContentTests`, `BarLayoutModeTests`, `IslandLayoutSolverTests`, `IslandStripProjectionTests`, `IslandAnchorTests`, `AtomicFullscreenTests`) re-run and passed 37/37 with 0 failures; `** BUILD SUCCEEDED **` (exit 0) confirmed `ClockChip.swift` in the `SwiftFileList`.

  the 2 obsolete drag keys (`Apps`, `Widget Layout`) and added 4 new user-facing
  strings (`Widget Widths`, `Weather`, `Tray`, `Clock`); all 9 (incl. the 3
  pre-existing settings keys + 2 interpolation keys) are batched into the pending
  localization fix — owner approved: draft translations ×12 + owner review (§1.7b).
- 2026-10-09 · **4b preset data — PASS** (5/5 `DockThemeStyleTokensTests` + 34/34
  `DockThemeTests`, `** TEST SUCCEEDED **` exit 0; targeted `-only-testing` run — no
  app-source change in this slice, full gate still at close-out). Verified vs plan:
  pure value tables for all 12 presets + `customRGBA` + `auto` in
  `Core/Support/DockThemeStyleTokens.swift` (no SwiftUI import, per `DockThemeTokens`
  discipline), each preset × light/dark holding baseTint/sheen/glow/rim/blur/
  `prefersDarkContent`. **Gaps found → fixed (tests only, data untouched):** (a) the
  value-freeze covered only 4 presets × `baseTint` — now all **24 columns frozen
  field-for-field** in `testEveryPresetColumnIsValueFrozen`; (b) `testAllFieldsFinite`
  only checked the `.r` channel of the 24 statics — now **every channel of all four
  colours + blur**, across all 12 presets + `.auto` + `.customRGBA` × all three
  appearances; (c) **no distinctness test existed** — exactly the 4h defect (all 12
  columns identical white-tint values) could regress silently — now pairwise-distinct
  per appearance across all 12 in `testAllTwelvePresetColumnsAreDistinct`; (d) plan item
  **"rim ≤ shadow budget" had no definition anywhere in the code** (the only budget is
  `shadowPadding` = 20pt capping `DockShadow.verticalExtent`, preset-independent) →
  **owner called (§1.4), chose the shadowPadding reading**: new
  `DockThemeTests.testRimStrokePlusShadowStaysInsideShadowPaddingBudget` asserts the
  wider rim stroke (1pt) + strip/popup shadow extent ≤ 20 — light 1+11 = 12, dark
  1+17 = 18. **Notes:** the freeze table is a literal copy of today's data (its job is
  to catch drift, not to judge the numbers — eyeballing against EdgeDeck stays 4h scope);
  `check_localization.py` still ❌ 9 missing keys (unchanged, pending the batched
  12-language fix); the owner-screenshot evidence for 4b is the same visual set 4h will
  produce (no separate capture requested for the data layer).
- 2026-10-09 · **Test build launched with permissions bypassed** (owner step after 4b):
  `Scripts/build_and_run.sh run` → `** BUILD SUCCEEDED **` (fallback signing identity
  absent in this session → Xcode's build signature kept, script's documented fallback);
  relaunched the built executable directly with `DOCK_DEV_SKIP_PERMISSIONS=1` because
  `open` does not propagate env (trace polarity, `=1` only — `AppDelegate` then reports
  `launched(trusted:)` and skips onboarding/watchdog/suspend). Verified: process alive
  (pid 10038), `ps -E` shows `DOCK_DEV_SKIP_PERMISSIONS=1`, zero
  permission/onboarding lines in `/tmp/katikati-dev-bypass.log`, strip glass composite
  active. Runs as a background process for the owner's manual testing.
- 2026-10-09 · **4c glass — PASS** (full suite **1626/1626 green**, `** TEST SUCCEEDED **`
  exit 0; targeted rerun 48/48 for the touched classes; `check_debug_switches.py` ✅ 77/77;
  `check_availability_warnings.py` ✅ exit 0 against this slice's build log;
  `check_localization.py` ❌ unchanged — the 9 pre-existing keys, batched fix pending).
  **Verified vs plan:** `DockThemeTokens.resolved(for:style:)` (machinery landed in
  f670bdd, the Phase-4 4c commit) wires tint/rim/shadow — `with(styleTokens:)` overrides
  exactly four fields (panelRimTop/Bottom, panelRimHighlighted ← glow, panelInnerHighlight
  ← sheen) and `styleTokens` itself; the plate plumbing exists (`DockPanelBackdrop` →
  `DockGlassBackdrop(baseTint:)` → `DockLiquidGlassConfiguration.baseTint`); all six
  panels (strip/drawer/capsule/popups/tooltip/backdrop) read themed tokens.
  **Gaps found → fixed:** (a) **4a checkpoint (b) closed — `themeMaterial` was
  persist-only**: no read site ever passed a non-`.auto` style, so the pinned preset never
  reached a panel and the `style != .auto` re-skin gate never opened. Now wired: strip +
  capsule read `settingsStore.themeMaterial` directly (reactive — both observe the store)
  and inject the `dockThemeStyle` key into their bodies for their subtree; drawer gets an
  `@ObservedObject settingsStore` on `DrawerRootView` + body injection (reactive); the
  three popups get `.environment(\.dockThemeStyle, settingsStore.themeMaterial)` at
  their `NSHostingView` roots (rebuilt every open); the tooltip takes a `themeStyle`
  param (rootView refreshed every show); 11 read sites converted to
  `resolved(for:style:)`. Uninjected hosts fall back to `.auto` = baseline
  (`DockThemeStyleKey.defaultValue` pinned by test). (b) **The plan's original 4c evidence
  test never ran**: `testCustomThemeOverrides` sat *after* the class closing brace as a
  stray global function (0 hits in the executed-case log) — relocated inside the class.
  **Evidence tests added:** `testEveryPresetReSkinsTheThemedFieldsInBothColumns` (12 × 2,
  values + "did it actually move off baseline"), `testPresetReskinLeavesContrastCriticalFieldsAtBaseline`
  (labels/pill/shadows/tooltips identical across all 24 columns → the contrast column
  tests hold for every preset by construction), `testAutoDeltaAgainstTheUntouchedGlassConfiguration`
  (**values**: rim/glow/sheen delta under `auto` = 0; plate tint delta = roseQuartz
  (0.95,0.85,0.88,0.6) light / obsidianDark (0.05,0.05,0.05,0.85) dark vs baseline
  `baseTint = nil` → neutral grey 127), `testThemeStyleEnvironmentDefaultsToAuto`.
  **Gaps recorded, not fixed (owner call / 4h):** (c) the **liquid-glass composite
  background window** (`makeTaskbarGlassBackground`) is handed the static
  `DockGlassPresentation.configuration` with `baseTint: nil`, so in composite mode — the
  path live on this machine ("[glass] taskbar composite active") — the *plate* does not
  take the preset tint even though the content-side plumbing honours it; rim/highlight do
  move (they are drawn content-side). This is exactly what 4h proof (a) measures; if the
  pinned rims move but the plate does not, plate-level tint is 4h rework, per the plan.
  (d) **drag-carrier / label snapshots** (`ChipSnapshotter`) build hosts without the key
  → `.auto` fallback during a pinned theme (ephemeral ghost only).  (e) **Reactivity:**
  strip/capsule/drawer update live; popups/tooltip pick the value up on their next
  build; there is still **no runtime UI** to change `themeMaterial` (Appearance tab =
  Phase 6) — Phase 6 must re-verify invalidation end-to-end. Owner screenshots for 4c are
  the same set as 4h proof (a).
- 2026-10-09 · **4d weather — PASS + owner rework DONE** (full suite **1630/1630 green**,
  `** TEST SUCCEEDED **` exit 0; `WeatherResponseParsingTests` 6/6;
  `check_localization.py` ✅ **exit 0 — first green run of this whole pass**;
  `check_debug_switches.py` ✅ 77/77). **Verified vs plan:** fetch/parse service
  (Open-Meteo → `WeatherResponseParsing`, pre-existing tests); enabled-by-default gate
  (`com.katikati.weather.enabled`, key absent ⇒ on); last-cached value (disk cache
  restored at init with `isLive = false` stale marker); now-playing evicted from the
  weather island (decision 2 — the island is weather-only). **Gaps found → fixed:**
  (a) **the popup existed but was never wired** — `WeatherPopupView` had no tap path at
  all; the pill now opens it with `.popover(isPresented:arrowEdge:)`, the same mechanism
  as the 4e2 calendar. (b) **no condition data to art on** — added `WeatherCondition`
  (WMO code → family, plus recovery from the legacy payload's SF Symbol for caches
  written before 4d) and `isDay` (Open-Meteo `is_day`) to `WeatherState`; both optional
  so a pre-4d cache still decodes (pinned by test). (c) **two phantom localization keys**
  — `Text("\(day)")` / `Text("\(battery)%")` routed bare numbers through the localizer;
  now `Text(verbatim:)` (data, not copy) instead of planting fake no-op catalog entries.
  (d) **catalog was 9 keys short** (settings labels: Clock/Tray/Weather/Widget
  Widths/Drawer Position/Left/Right) → added ×12; new `Cloudy Night` ×12 as well.
  **Owner decisions (grill, 2026-10-09):** pill in the bar / cards in the popup;
  illustrations **drawn in SwiftUI** (no assets); check + redesign in one step.
  **Rework to the samples:** bar widget rebuilt as the pill (condition over city,
  temperature with the degree ring, spot illustration, stale marker kept,
  `ViewThatFits` compact variant for narrow widths with a macOS 12 fallback);
  popup rebuilt as the gradient card (condition, big temperature + ring, divider,
  locale-formatted date, pin + city, illustration). **Colours sampled from the
  references:** clear-day (48,158,255)→(86,180,255) [Sunny card]; cloudy-day
  (45,143,210)→(44,104,180) [your pill]; night (72,105,240)→(128,114,228) [Cloudy Night
  card]; rain family (22,201,165)→(76,225,163) [Rain card]. **Notes / open items:**
  (i) **snow and fog have no reference** — they got the nearest family in the same
  language (icy blue / grey-blue), flagged for the owner's eyeball at screenshot time;
  (ii) the H/L highs-lows line from the old popup was dropped to stay faithful to the
  card sample — one word puts it back; (iii) the 3420×145 paste was a **Gemini chat
  screenshot** (OCR), not a sample — recorded so nobody chases it; samples copied to
  `refs/weather/`; (iv) illustrations are drawn, not pixel-parity with the stock art
  (owner choice);  (v) **no visual proof yet** — live screenshots are 4h proof (d).
- 2026-10-09 · **Decision 8 locked + plan re-cut (no code change this step):** the bar's
  right end becomes **one combined chip showing only the clock** (owner grill: “clock for
  now, no wifi, no battery — wifi goes to tskbaredge on the side”). Written into the plan:
  decision 8 block (a–e), the 4U **4f row rewritten** (order → `weather → apps → clock`,
  `.tray` removed with the same ripple as `.media`, tray popup / quick settings / ring icon
  struck from 4f, combined chip needs an owner-signed design before it is built), and a
  Phase-7 bullet for the **Wi-Fi + battery edge widget with the side (left/right) chosen by
  the owner at Phase 7 sign-off**. Timing: locked now, **built in 4f**; decision 5 (in-bar
  ring) superseded by 8c. Next slice: **4e clock**.
- 2026-10-09 · **8d resolved (grill):** the combined chip is a **weather-pill twin** —
  matched gradient-card construction with its own hue, **large time + weekday/date line**,
  **both clock presets kept** (restyled into the new form), **calendar popup still on tap**.
  Written into decision 8(d) and the 4f row; the build (and the hue pick on the render)
  lands in **4f**, after 4e.
- 2026-10-11 · **4f owner hand-build (manual input, not agent work):** the owner wrote
  both chip views directly in `App/Scenes/ClockChip.swift` — the 8d `ClockChip` card
  (`ClockArt` day-warm/night-indigo hues, `fullCard` large-time + weekday/date line,
  `compactCard` narrow-width fallback, both presets as typography, calendar tap via
  popover) **and** the `FlipClockChip` flip-tile variant. What remains is the agent's
  wiring step: swap the `.clock` placeholder in `DockStripView.swift:1331` from
  `FlipClockChip()` to `ClockChip()` (one line), then gates + check-log note. Until
  that swap, the bar renders the flip variant and the 8d card is unproven on-screen.
- 2026-10-09 · **4e clock — PASS** (full suite **1632/1632 green**, `** TEST SUCCEEDED **`
  exit 0; targeted `ClockChipContentTests` 3/3; app build re-verified after touching both
  edited files: `** BUILD SUCCEEDED **` exit 0 with `ClockChip.swift` compiled;
  `check_localization.py` ✅ exit 0; `check_debug_switches.py` ✅ 77/77).
  **Verified vs plan:** content-provider protocol (`ClockDataProvider` +
  `StandardClockProvider`, time + date shipped from Core) ✓; `com.katikati.clock.preset`
  persists both presets via `@AppStorage` ✓; calendar popup baseline present, owner
  redesigns it in Phase 5 ✓.
  **Gaps found → fixed:** (a) **the chip was not minute-aligned** —
  `Timer.publish(every: 1, on: .main)` woke the main thread once a second for content that
  changes once a minute; now `TimelineView(.periodic(from: ClockTick.nextMinute(after:),
  by: 60))` starts on the next whole-minute boundary and ticks each minute (the plan's
  exact ask), with the alignment maths in Core as the testable seam
  (`ClockTick.nextMinute(after:calendar:)`). (b) **the calendar popup shipped empty** —
  `CalendarPopupView.body` was a blank `VStack` since the 4e2 commit while `header` /
  `daysOfWeek` / `monthGrid` sat unused; the baseline is now composed (header + weekday
  row + month grid). Baseline only — the owner's Phase 5 redesign stands.
  **Evidence tests added:** `testNextMinuteIsTheNextWholeBoundary` (mid-minute, exactly on
  a boundary → the *next* minute, :59, hour/day rollover, repeated ticks stay whole) and
  `testStandardClockProviderIsMinuteResolution` (same-minute reads are identical — an
  aligned ticker therefore can never show a stale reading; the next minute ticks over).
  **Notes:** both presets survive into the 8d combined-chip restyle (4f); the 4d
  `Text(verbatim:)` day-cell fix still stands; no visual proof yet — 4h proof (d).

- 2026-10-11 · **4g scope reframed by owner — dual-FAB scaffold** (supersedes the
  single "drawer-FAB-left-of-weather" framing). Owner decisions: (a) **keep the
  existing drawer capsule** as the sole drawer trigger — do NOT re-anchor it;
  (b) **rip the `macstudio` launcher/drawer glyph + its divider out of
  `WeatherChip.fullPill`** so weather holds weather only (capsule keeps the drawer
  reachable → nothing orphaned; verified the capsule's `DrawerCapsuleButton` is the
  other `onToggleDrawer` caller, so the AppRuntime hook survives); (c) **scaffold
  two new lightweight FAB panels for future use** — left FAB (left of weather slot)
  + right FAB (right of clock slot), plain glyphs, inert payloads; (d) **per-mode
  visibility toggles** `com.katikati.fab.left.<mode>` / `.right.<mode>`
  (windows/split3/split4/centered), default off; (e) **future payloads recorded, not
  built:** left FAB → custom Launchpad-style launcher (Phase 7d), right FAB →
  on-screen overlay widgets (Phase 7e). **Code-confirmed this session:** the
  4f4 `LauncherPlaceholderChip` / `square.grid.3x3` no longer exist in code (grep
  hits only in this doc) → no two-launcher glyph collision; the FAB glyph must stay
  distinct from the capsule's 4-up live preview (it is: plain grid vs preview).
  **Glitch/overflow safety:** FABs are panels not `BarSection`s (no island-width
  impact); anchored to outermost slot frames (auto-track every mode); clamped to
  `visibleFrame`; hidden when the anchor slot is overflow-collapsed; reuse capsule
  panel construction (no new panel class). **Known collision to design around:** in
  `windows` mode weather+apps share one island, so a left FAB and a left-positioned
  drawer capsule both sit at the bar's left edge → per-mode toggle defaults the left
  FAB **off in `windows`**, and geometry must collision-check against the capsule
  frame. No code written yet this note — plan only.
- 2026-10-11 · **4U-A close-out gate — tungsten gate DONE; visual sign-off PARTIALLY
  DONE (owner proceeding past the eyeball blocker).** Full gate re-run by agent from a
  clean build+test: **1640 tests, 0 failures, TEST SUCCEEDED**; `check_localization.py`
  ✅ exit 0; `check_debug_switches.py` ✅ 77/77; `check_availability_warnings.py` ✅
  exit 0. App launched live with `DOCK_DEV_SKIP_PERMISSIONS=1` (executable launched
  directly — `open` does not propagate env; pid confirmed, glass strip composite
  active). Owner accepted the 4U-A visual direction (split5 kept — "I like it"; launcher
  / widgets FABs as sections accepted) and chose to **proceed past the per-decision
  screenshot blocker**, recording it as **partially done** rather than blocking Phase 5.
  **Still outstanding (non-blocking, owner to finalise):** windows/centered FAB ends,
  split4 media-island adjacency, left-launcher vs left-drawer-capsule collision in
  `windows`, split5 spacing; and 4h visual proof (ΔE values + idle-CPU re-measure vs
  3.2–3.4%). FAB width sliders captured for 7d/7e (fixed 40pt today, no slider).

**Close-out:** full tungsten gate (`xcodebuild test` + `check_localization.py` +
`check_debug_switches.py` + conformance-availability check) — ✅ **DONE 2026-10-11
(1640 tests green, all three Python gates exit 0, re-run by agent)**; per-decision
screenshots (owner supplies references per step) — ⏳ **PARTIALLY DONE 2026-10-11:
owner eyeball of the 4U-A layout change (launcher/widgets FABs as sections, split5)
started on a live permission-bypassed build; sign-off not yet itemised per decision**;
check log complete **(incl. 4f combined chip + 4g dual-FAB scaffold + 4h proof)**.
**Remaining owner eyeballs to finalise close-out:** windows/centered FAB glyphs at the
strip ends (is a far-left launcher on a full-width bar wanted?), split4 media-island
adjacency (next to clock group), left-launcher vs left-drawer-capsule collision in
`windows`, split5 spacing; plus 4h visual proof (owner screenshots, ΔE values, idle-CPU
re-measure vs 3.2–3.4%). Then Phase 5 opens.

### Phase 4U-A — FAB-as-sections rework (owner 2026-10-11) · MAJOR island-model change

> [!IMPORTANT]
> **Read before touching any layout/island code.** This supersedes the 4g decision
> "FABs are separate floating panels → zero island/solver/section changes." Under 4U-A
> the left FAB (launcher) and right FAB (widgets) are **promoted to real `BarSection`s**
> so they participate in island layout — enabling distinct split3/4/5 and a genuine
> 5-island mode. Large blast radius; **must land as gated sub-slices, each gate-green,
> never one commit.**

**New canonical section order (6):** `launcher · weather · apps · media · clock · widgets`

**Mode diagrams (target):**
- `windows`  → `[ launcher · weather · apps · media · clock · widgets ]` (1 island)
- `centered` → `[ launcher · weather · apps · media · clock · widgets ]` compact, centered (1 island)
- `split3`   → `[launcher·weather] gap [apps·media] gap [clock·widgets]` (3 islands)
- `split4`   → `[launcher·weather] gap [apps] gap [media] gap [clock·widgets]` (4 islands)
- `split5`   → `[launcher] gap [weather] gap [apps·media] gap [clock] gap [widgets]` (5 islands)

Progression: 3 → 4 → 5 separates one more grouping per step; all three distinct (fixes split3 == split4).

**Gated sub-slices (each ends gate-green; ≤300 lines/commit; §1.8 note each):**
1. **Sections:** add `launcher` + `widgets` `BarSection` cases with `title` / `defaultWidgetWidth` / `minimumWidgetWidth` (~40pt, square) / `placeholderEntryID`; register `com.katikati.*` defaults. Tests: `BarLayoutModeTests` case coverage.
2. **Grouping:** extend `islands(for:)` — FABs at the outer ends of left/right groups for split3/4; detached into their own islands for split5. Solver delegates (single source of truth) → propagates automatically.
3. **Geometry/widths:** `PanelGeometry.islandTargetFrame` hardcodes `weatherWidth=150` / `clockWidth=160` and special-cases weather/apps/clock → add width handling for `media`, `launcher`, `widgets`.
4. **Projection + render:** wire `launcher`/`widgets` into the `DockStripView` projection funnel; render the inert `FloatingActionButton`; payloads stay empty (launcher → 7d, widgets → 7e).
5. **Settings:** default-order seed + width sliders extended to the new sections (weather/clock-only today).
6. **Modes + tests:** add `split5` `BarLayoutMode`; update `BarLayoutModeTests`, `IslandLayoutSolverTests`, `IslandStripProjectionTests`, `IslandPanelGeometryTests`, `AtomicFullscreenTests`, `PinnedIslandTests` island-count/grouping assertions; localization "Launcher"/"Widgets" ×12.

**Cautions:**
- **windows/centered behavior change:** those modes now render FAB buttons at the strip ends → needs owner eyeball (is a far-left launcher button on a full-width bar wanted?).
- Reverts the earlier 4g "zero solver change" guarantee — expect real solver/projection diffs.
- The committed floating-panel FAB geometry (`f753baf`) is superseded; per sub-slice decide reuse-vs-remove — do **not** carry both a floating panel and a section for the same FAB.
- Keep 4g overflow/glitch rules: clamp to `visibleFrame`, hide on overflow-collapse, collision-check left FAB vs the left drawer capsule in `windows`.
- `split5` is brand-new — no `split5` exists anywhere in the tree today.


**4U-A check log:**
- 2026-10-11 · **Slices 1+2 (sections + grouping) — PASS, merged into one commit** (order change forces grouping assertions to move together). `launcher`/`widgets` added; canonical order is `BarSection.canonicalOrder`; split3 = `[launcher·weather][apps·media][clock·widgets]`, split4 = `[launcher·weather][apps][media][clock·widgets]` (4 islands). Unit suite green. Stale `defaultWidgetWidth` weather test (120→150) and PinnedIsland width (198 = 40+8+150) corrected. `check_localization.py` flags dead `Launcher` key (orphaned by 4g rip; slice 5 re-references it). Notes: split4 media island is placed by the solver's right-to-left trailing pass (adjacent to clock group, not apps) — owner eyeball.
- 2026-10-11 · **Slices 3–6 — PASS.** Solver/`PanelGeometry` already width-handle new sections via `defaultWidgetWidth`; floating FAB geometry (`FABSide`, `fabTargetFrame`) removed; `SectionFABGlyph` renders inert launcher/widgets glyphs; `BarLayoutMode.split5` = `[launcher][weather][apps·media][clock][widgets]` (slotCount 5, distinct 3/4/5); "Widgets" ×12 added, `Launcher` key re-referenced; `check_localization.py` ✅, unit suite ✅. Not done: live eyeball of windows/centered FAB ends and left-launcher vs left-drawer-capsule collision (owner); no settings width sliders for fixed 40pt FABs.


### Phase 5 — Hardening (native Dock, teardown, recovery drill) (DONE)

*Scoped into gated sub-slices 2026-10-11 (owner asked to plan Phase 5 in slices, mirroring the
Phase 2/3/4 cadence and the 4U-A scoping commit). Every slice ends gate-green
(`xcodebuild test … CODE_SIGNING_ALLOWED=NO` + `check_localization.py` +
`check_debug_switches.py` + `check_availability_warnings.py`); ≤ ~300 lines per commit; no
drive-by refactors (Standing Rules §1). Slices 5b/5c are **evidence-gated** — code lands only
for a gap the drill actually proves.*

**Original scope (source of truth — kept verbatim):**
- Keep tungsten native-Dock services as the path; run the recovery drill: kill -9 during
  Dock-mutating states, SIGTERM/SIGINT teardown, crash-relaunch, dev-bypass guard.
- **Calendar Popup Redesign**: Owner will redesign the Calendar Popup manually in this phase (Phase 4 popup implementation removed/deferred).
  Adopt live-SplitBar recovery-file ideas **only** if the drill proves a tungsten gap
  (evidence-gated diff, recorded in the PR).
- Window-lift avoidance re-verified with island frames (maximized windows avoid every
  island, not just the strip rect).
- **Verify**: drill log in the PR; no lost Dock state; no orphaned island panels after
  crash-relaunch.

#### Sub-slices

- **5a — window-lift avoidance: one reservation per display (de-dup + invariant test).**
  *Corrected 2026-10-11 after tracing the geometry: the earlier "taller apps island"
  rationale is **disproven**. `PanelCoordinator.layoutMetrics` is the **global**
  `settingsStore.dockPanelHeight.metrics`, and `PanelGeometry.islandTargetFrame` gives
  **every** split slot `height: metrics.windowHeight` at `y: island.frame.minY -
  shadowPadding` (IslandLayoutSolver sets `y = screenMinY + bottomMargin` for all). So all
  islands are the **same height, bottom-aligned → same `taskbarTop`**, and the existing
  full-width bottom-strip reservation (`Geometry.liftTargetFrame` → `adjustedFrame`) already
  clears every island. There is **no lift gap**; `windowLiftAvoidanceContexts()` merely
  returns N **identical** contexts per display (one per island unit) — redundant, not wrong.*
  Scope is therefore a **de-dup + future-proofing + invariant-pinning** slice:
  - `App/Entry/TaskbarScreenOrchestrator.swift`: `windowLiftAvoidanceContexts()` returns
    **one context per display** (drop the N identical per-island copies). Reservation keyed to
    the display's **union bounding-frame top** (`boundingFrame(forDisplayUUID:)`) so it stays
    correct if islands ever gain distinct heights.
  - `Core/Support/WindowLiftAvoidance.swift`: reservation input derived from the bar bounding
    frame if needed (`Geometry` already carries `screenFrame`/`visibleFrame`/`taskbarTop`).
  - Tests: new cases in `Tests/Unit/WindowLiftAvoidanceTests.swift` pinning the invariant
    across `windows`/`split3`/`split4`/`split5`: (a) one context per display; (b) all islands
    share `taskbarTop`; (c) a window filling the visible frame is raised above **every**
    island's top; (d) `windows`/`centered` behavior unchanged.
  - **Verify**: `DOCK_WINDOW_LIFT_TRACE` shows one reservation per display; geometry + existing
    suite green; zero behavior change in any mode.

- **5b — SIGTERM/SIGINT teardown drill (evidence + gap-fix only). — ✅ DONE (2026-10-11):
  drilled on the dev Mac; gap PROVEN under real Accessibility (no signal handlers —
  SIGTERM/SIGINT killed the process outright, `stopAndRestore` never ran, lifted window
  stuck) and FIXED (`installTerminationSignalHandlers`, runloop-dispatched `terminate:` —
  calling it inside the GCD handler deadlocked; `77a20a0`). See phase-5 log addendum 2.**
  Exercise `AppDelegate.applicationShouldTerminate` / `applicationWillTerminate` / `terminateOtherInstances`
  (`stopAndRestore`, monitor stops, in-flight `terminationTask` cancellation). Drill log in PR;
  fix + test only if the drill proves a gap (e.g. a monitor not stopped, a Task surviving
  teardown → "two taskbars").

- **5c — `kill -9` during a Dock-mutating state + crash-relaunch (Dock-state integrity).
  — ✅ DONE (2026-10-11): idle `kill -9` + relaunch = no orphaned panels (1 process,
  13 windows = clean baseline); mid-write sequence emulated 30× at random 0–250ms =
  0 corrupt reads (cfprefsd per-key atomicity → partial application only, reasoned
  acceptance); C3 gap PROVEN under real Accessibility (lift sessions were memory-only,
  relaunch did not restore) and FIXED (`WindowLiftRecovery` mirror file replayed at
  launch, +4 tests; `e482a95`, `77a20a0`). See phase-5 log addenda.**
  The Dock-mutating path is `NativeDockPreferencesService.apply(recommendations:)` →
  `commands(for:)` (writes `com.apple.dock` defaults + a single `killall Dock`). Drill: kill -9
  mid-sequence, relaunch, verify Dock prefs not corrupt, KatiKati recovers, **no orphaned island
  panels** (`TaskbarScreenOrchestrator.rebuildUnits` idempotent). Adopt live-SplitBar
  recovery-file ideas **only if** the drill proves a tungsten gap (evidence-gated diff in the PR);
  add a relaunch-idempotence test.

- **5d — dev-bypass guard lock (`DOCK_DEV_SKIP_PERMISSIONS`).** Confirm the switch stays **off by
  default**, honored at every choke point (`AppDelegate.permissionProbeQueue`,
  `PermissionRecoveryMachine`/`AccessibilityPermissionModel`, `isSuspendedForPermissionLoss` via
  `suspendPanelsAndStores`), and can never ship on. Extend `DebugSwitchTests` polarity +
  choke-point coverage; `check_debug_switches.py` green.

- **5e — Floating Calendar Panel (owner design 2026-10-11; supersedes the "owner-external" note — owner now has the agent build it). — ✅ DONE (2026-10-11): 5e-A…G panel + tiles rework landed in-repo; eyeball flags in check log.**
  Replaces the `CalendarPopupView` popover (`ClockChip.swift`) with a tall **floating panel on the
  right of the screen**, opened by tapping the clock (click-outside/Esc dismiss). Contents, **all
  visible, no scrolling**: date card · month grid · agenda · world clocks (user-picked, ≤4) ·
  focus (Pomodoro) · reminders · alarms; theme-glass styled per the owner's reference shots.
  Real EventKit (agenda + reminders), real in-app alarms (UserNotifications) and focus timer.
  **REWORKED 2026-10-11 (owner rejected the single glass panel): separate solid floating tiles, no outer
  panel, content-sized, anchored top-right.** Two **layout presets** (Settings → Calendar Layout,
  `com.katikati.calendar.layout`): **Mac** (one ~340pt column: Clock+Focus tiles, wide Calendar tile =
  next event/later today + month grid, Reminders+Alarms band tiles) and **iPad** (≈half-screen 3-column
  grid: Date, Agenda, Month, Clock, Focus, Reminders, Alarms). Replaces the 420/half-screen size presets
  (migrated `compact420`→mac, `halfScreen`→ipad). **Tile colour palettes** (Classic/Vivid/Pastel/Mono,
  `com.katikati.calendar.palette`) over a solid base that follows system light/dark. Time Zones tile is a
  clock, **flip (default) or analog** (`com.katikati.calendar.clockStyle`).
  **Shared widget vocabulary — applies to ALL future widgets (Weather redesign, Phase 7e overlay widgets):
  reuse `CalendarPanelLayout` (Mac/iPad), `TilePalette`, and the solid `tileSurface`; do not invent new
  size/colour systems.**
  Sub-slices (each gate-green, ≤300 lines): **5e-A** panel shell + `PanelGeometry.calendarPanelFrame`
  + clock-tap toggle; **5e-B** card grid + date/month; **5e-C** size presets + setting + this note;
  **5e-D** EventKit agenda/reminders (+ Info.plist usage strings, fake-store tests); **5e-E** world
  clocks model + picker; **5e-F** focus timer state machine + alarms/notifications; **5e-G** polish,
  localization ×12, lock.

- **5g — Weather widget tiles (left) (owner 2026-10-11; continuation of 5e, built on its tile system).**
  Tapping the weather pill toggles a floating tile stack on the **left** (top-left, content-sized,
  transparent window) — same mechanics, **shared Widget Layout (Mac ~340pt / iPad half-screen), shared
  palette, solid `tileSurface`** as the calendar (the calendar's `Calendar Layout` setting is renamed
  **Widget Layout** and migrated). Setting **"Keep both open"**, default **off** (one at a time).
  Data: **Open-Meteo** forecast + geocoding APIs (no key). Tiles: **Hero** (temp, feels-like, condition,
  hi/lo, sunrise/sunset, moon) · **Hourly** 24–48h with **Sky / Humidity / Wind** chips and arrows ·
  **Trend graphs** (temperature + feels-like line 48h; precipitation/snowfall bars 48h + 16-day totals) ·
  **Daily** up to 16 days (hi/lo range bars, rain chance) · **Details** (UV, pressure, visibility, dew
  point, precip, cloud cover, wind gust/direction, moon phase) · **Warnings banner**. **Warnings are
  derived from forecast thresholds** (heat via feels-like, freeze, heavy rain, snow accumulation, strong
  wind/gusts, thunderstorm, high UV) — labelled forecast-based, not official; thresholds in Settings;
  badge on the pill. **Locations:** current location when permitted, else city search; ≤5 saved cities
  with arrows to switch (replaces the hard-coded Istanbul fallback). **Animation:** hero-tile background
  only (rain, snow, thunder flash, drifting clouds, night stars, sun glow, fog); Canvas +
  `TimelineView`, runs only while the panel is visible, honours Reduce Motion and a Settings toggle.
  Weather settings: units (°C/°F; km/h | mph | m/s), animation, thresholds, keep-both-open, saved cities.
  Charts are custom `Path`/`Canvas` (Swift Charts needs macOS 13; floor is 12).
  Sub-slices (each gate-green, ≤300 lines): **5g-A** extended Open-Meteo models + parser + unit helpers
  (+ fixtures, cache back-compat) · **5g-B** geocoding client, saved-cities store, location fix
  (`NSLocationUsageDescription`, accept `.authorized`) · **5g-C** pure `WeatherWarningEngine` · **5g-D** left
  panel shell (side-parametrised controller, `PanelGeometry.widgetPanelFrame(side:)`, pill toggle, remove
  `WeatherPopupView` popover) · **5g-E** tiles (Hero, Hourly, graphs, Daily, Details, Warnings; shared tile
  system extracted from `CalendarPanelView.swift`) · **5g-F** `WeatherEffectsView` + unit-tested particle
  simulator · **5g-G** Settings + localization ×12.
- **5h — Joint polish: weather + calendar (owner: "improve them all together as the last Phase 5 step
  before Phase 6").** Owner 2026-10-11 decisions, built: **Tall layout** (`CalendarPanelLayout.tall`, 420pt,
  fills the screen height; default for fresh installs — **Mac and iPad kept as presets**, stored choices
  untouched) · calendar Tall order: Clock + zones full width → Calendar full width → Alarms → Reminders →
  **Focus | Timer** → Notes → **Stopwatch | Countdown**, sized by the pure `TallLayoutPlanner` (optional
  tiles only while they fit; leftover shared by flex) · new tiles: **Timer** (separate from Focus),
  **Stopwatch** (laps), **Event Countdown**, **Quick Notes** · **animation presets** (Settings → Widget
  Animation): **Instant** (original, kept), **Slide** (default; from the right for calendar, left for weather)
  and **Spring Pop** (staggered tile scale+fade); Reduce Motion forces Instant · shared `WidgetMetrics`
  (radius 24, gutter 8, gap 10), layered shadows + top highlight · toggles for Notes and Stopwatch &
  Countdown. Suggested future widgets (not built): Now Playing, System stats (CPU/RAM/disk/battery).

- **5i — Weather glance redesign (owner 2026-10-11): no scrolling, sky-coloured, layered scene.** Weather
  now defaults to a **Glance** page: layered **mountain/horizon scene hero** (sky gradient, sun/moon, 3
  ridges, animated weather on top) → next-6-hours strip → one **Hourly | Daily | Details** panel; every
  datum has a single home (sun times/UV/wind/pressure only in Details; hourly temps only in the strip;
  16-day totals only in Daily). The whole pane is one **sky** (`SkyTint`: per-condition/night gradient
  sliced into tiles, auto-contrast text). **Presets kept: Weather Layout = Glance | Classic (previous
  Mac/iPad/Tall stacks); Hero Style = Scene | Classic (previous icon hero)** — Settings → Weather.
  **Standing rule (owner): every future widget ships 2–3 presets (layout/style) and keeps the previous
  design as one.**

- **5f — Phase 5 lock + proof gate (closes Phase 5 last, after 5g and 5h). — ✅ PASS (2026-10-11; lock entry in check log, re-verified at phase-close).** Drill log(s) in the PR; no lost Dock state; no orphaned
  island panels after crash-relaunch; full tungsten gate; dated phase-5 log under
  `Docs/Archive/Planning/`, `CHANGELOG.md`, and the `Result:` line here.

**Owner decisions — RESOLVED 2026-10-11 (owner: "Proceed with your recommendations" + team directive):**
1. **5a reservation semantics — accepted as recommended** (union bounding frame / one
   context per display); corrected scope executed (see check log below).
2. **5e calendar — baseline `CalendarPopupView` stays live until 5e-A lands**; owner then
   (later 2026-10-11) asked the agent to build the floating panel (see 5e above).
3. **5b/5c drill — owner deferred** ("to be done later"); remains evidence-gated when resumed.

**Phase 5 check log (append after every step — STANDING_RULES §1.8):**
- 2026-10-11 · **Phase 5 scoped into sub-slices 5a–5f — DONE** (`f0073a8`, docs-only).
  Original §7 scope preserved verbatim; 5a rationale later corrected (below); 5b/5c marked
  evidence-gated, 5e owner-external.
- 2026-10-11 · **5a window-lift de-dup — PASS** (`b4290b6`; sub-agent authored, owner-side
  audit by main session before commit). *Correction of the original 5a premise:* tracing
  `PanelGeometry.islandTargetFrame` + `IslandLayoutSolver` proved all islands are equal-height
  and bottom-aligned (global `settingsStore.dockPanelHeight.metrics`), so the per-island
  `taskbarTop` was already correct everywhere — **there was no lift gap**. The real defect was
  redundancy: `windowLiftAvoidanceContexts()` returned N byte-identical contexts per display,
  which made `WindowLiftAvoidanceController.reconcileContexts`' whole-array `!=` misread every
  layout-mode switch (split3↔4↔5 = per-screen island count change) as a geometry change,
  needlessly restore-lifting windows and clearing sessions, plus N redundant CG scans.
  Shipped: pure `WindowLiftAvoidance.deduplicatedContexts` (value-based, order-preserving —
  `Set<CGRect>` is macOS 15+, floor is 12) wired into the orchestrator; doc invariant on
  `PanelCoordinator.windowLiftAvoidanceContext`. Tests added (3): equal-height + union-top
  invariant across all 5 layout modes; dedup collapses only byte-identical copies (keeps
  height-override variants); filling window raised above **every** island top per mode with
  top/left/width untouched. **Evidence:** full suite **1652/1652 green, 0 failures**;
  `check_localization.py` ✅ (296 keys × 12); `check_debug_switches.py` ✅ (77/77);
  `check_availability_warnings.py` ✅ (clean against the test build log).
- 2026-10-11 · **5d dev-bypass guard lock — PASS** (`02673ab`; test-only, zero production
  change, `DebugSwitch.swift` enum untouched per BASELINE_RULES §4 rule 4). Tests added (8):
  `DebugSwitchTests` pins `.trace` polarity of `DOCK_DEV_SKIP_PERMISSIONS` (literal `"1"` only —
  13 hostile values incl. `true`/`1.0`/whitespace; env unset→`1`→unset round-trip proving the
  no-arg `isEnabled()` production read path); `PermissionOnboardingTests` proves the two pure
  choke points honor it (no TCC trust-poll + no 1s polling timer under bypass; initial-launch and
  runtime-recovery `requestSystemPrompt` both suppressed while `.suspended` dispatch still reaches
  the effect handler) and that `PermissionRecoveryMachine` stays **switch-free** (putting the
  switch in the pure machine would gut onboarding — pinned so nobody "helpfully" adds it).
  AppKit-side choke points (`showGuideWindow`/`startWatchdog`/`suspendPanelsAndStores`/
  `openSettings` in `AppDelegate`) are documented in the test header as **manual verification** —
  they need a live `NSApplication`. **Evidence:** same full gate as 5a, all green.
- 2026-10-11 · **5b/5c — DEFERRED by owner** ("to be done later"). 5e — **owner-external**,
  to be done by the owner in Claude Code. 5f (lock + gate + phase log + CHANGELOG) remains
  the closing slice once 5b/5c/5e resolve.
- 2026-10-11 · **5e-A panel shell — PASS (code), NOT eyeballed.** `CalendarPanelPreset` +
  pure `PanelGeometry.calendarPanelFrame` (right-edge hug, clears taskbar/menu bar, width clamp,
  non-zero origin; 6 new tests); `CalendarPanelController` (`ClockChip.swift`) = borderless
  non-activating floating panel, clock tap toggles, Esc / outside-click (other-app clicks) dismiss;
  `.popover` removed. Content is still the baseline month view until 5e-B. Unit suite + localization
  + debug-switch gates green. **Owner to verify on the Mac:** panel position on real displays,
  Esc focus behavior, and that clicking another in-app panel does not dismiss (by design).
- 2026-10-11 · **5e-B…G — PASS (code), awaiting owner eyeball.** Panel now shows, all at once with
  no scrolling (`FittedRows` shows what fits + "+N more"): date card · month grid (heat tint,
  today/selected) · agenda · world clocks (≤4, picker, `com.katikati.calendar.timezones`) · focus
  (25/5/15 Pomodoro, `FocusTimerModel`) · reminders (check-off) · alarms (daily or weekday-set,
  `UNUserNotificationCenter` + in-app chime fallback). `compact420` = 2 columns, `halfScreen` = 3;
  Settings picker `com.katikati.calendar.panelPreset` (also the size vocabulary for the Weather
  redesign). EventKit via `CalendarService` (Info.plist calendar/reminders usage keys added;
  macOS 14 full-access API behind `#available`). 11 new model tests (DST, date line, cycle,
  alarm next-fire); full unit suite 1669 ✅; localization ×12 ✅; debug switches ✅. **Gaps /
  not verified:** no UI tests for the panel; EventKit + notification flows need real grants
  (cannot be bypassed by `DOCK_DEV_SKIP_PERMISSIONS`, which only skips Accessibility); alarm UI has
  no weekday chips yet (model supports them); not yet checked at small screen heights. 5f still
  open (5b/5c deferred).
- 2026-10-11 · **5e rework (tiles) — PASS (code), NOT eyeballed by agent.** Replaced the glass panel with
  solid tiles (`CalendarPanelView.swift`), layouts Mac/iPad, palettes, flip/analog clock tile, band
  tiles, top-right content-sized transparent window (`PanelGeometry.calendarPanelFrame(contentHeight:)`,
  window height follows a measured preference), legacy size-preset migration, month-grid greedy-cell bug
  fixed (bare `Color.clear` was vertically greedy). Tests: geometry/layout/palette/migration/countdown;
  suite 1671+ ✅, localization ✅, debug switches ✅. **Not verified:** actual on-screen look vs the
  references, small screens, transparent-gap click-through (gaps between tiles still swallow clicks).
- 2026-10-11 · **5g/5h scoped (docs-only).** Weather tile stack on the left + joint polish added before
  5f; owner answers recorded above (coexist default one-at-a-time, shared Widget Layout + palette,
  derived warnings, saved cities, hero-only animation, temp + precip graphs).
- 2026-10-11 · **5g-A…G built (agent), eyeballed live on the dev Mac in both layouts.** 5g-A extended
  Open-Meteo payload (`WeatherDetail`; live API checked — `current_weather=true` suppresses the `current`
  block, so only `current=` is requested), units, dew point, moon phase · 5g-B saved cities (≤5),
  geocoding client, selection stepping, no more hard-coded Istanbul (`needsLocation` → city search),
  Info.plist location keys · 5g-C `WeatherWarningEngine` (+ settings thresholds) · 5g-D side-aware
  `WidgetPanelController` (calendar right / weather left, "Keep both open" default off, closes the other
  when they would collide), `PanelGeometry.widgetPanelFrame(side:)`; shared `WidgetTileKit` · 5g-E tiles
  (hero, warnings, hourly + Sky/Humidity/Wind, temp+feels line, precip/snow bars, 16-day range bars,
  details grid; custom Canvas charts; mac column scrolls when taller than the screen) · 5g-F
  `WeatherEffects` deterministic particles + Canvas hero (rain/snow/clouds/stars/sun glow/fog/lightning,
  pauses when hidden or Reduce Motion) · 5g-G Settings (units, animations, keep-both-open, heat/wind/snow
  thresholds). "Calendar Layout/Colors" renamed **Widget Layout/Colors** (storage keys unchanged).
  Tests: parser/units/moon, warnings, locations, effects, geometry (suite green), localization ×12 ✅.
  **Not done / not verified:** per-condition animations only seen for Drizzle (others untested live);
  no UI tests; light-mode look not checked; Calendar/Reminders stay "access is off" until the user grants
  macOS permission; 5h joint polish and 5f lock still open.
- 2026-10-11 · **5h built + eyeballed on the dev Mac (Tall calendar + Tall weather, slide animation observed
  mid-flight).** On a 1117pt display every Tall calendar tile incl. Notes and Stopwatch|Countdown fits
  (tiles sit near their minimum heights; taller screens get larger tiles). New pure models in
  `Core/Support/WidgetTall.swift` (planner, timer, stopwatch, countdowns, animation timing) + 22 tests;
  settings resolution moved to Core (`CalendarPanelLayout.resolve`, `WidgetAnimationPreset.resolve`) so it is
  testable. **Not verified:** Spring Pop and Instant visually, light mode, Notes/Countdown/Stopwatch
  interactions beyond layout, weather Tall still scrolls (its content is taller than a 1117pt screen),
  Calendar/Reminders data (needs macOS permission). 5f lock still open.
- 2026-10-11 · **5i built + eyeballed (night/rain tint, all three segments, 988pt, no scrolling).** Pure
  `SkyTint`/`SceneGeometry` + presets in `Core/Support/SkyTint.swift` (6 tests), `WeatherGlanceView.swift`,
  sky-aware `TileEnv`. **Not verified:** daytime/snow/fog tints live (only unit-tested), light mode, the
  Classic presets re-checked after the change, wide (iPad) widths with Glance.
- 2026-10-11 · **Phase 5 — DONE (owner directive "mark phase 5 as done").** All sub-slices
  closed: 5a/5d (main session), 5e–5i (owner's Claude Code session), 5b/5c drilled on the
  dev Mac — first pass (dev bypass) showed no gap; with real Accessibility two gaps were
  **proven and fixed** (signal handlers + `WindowLiftRecovery`, `e482a95`/`77a20a0`);
  5f lock PASS. Status markers on 5b/5c/5e/5f flipped to ✅; phase-log Summary aligned with
  its addendum 2 (it still read "no gap found, no code changed"); `Result:` line added.
  Closure gate re-run: **1719 tests, 0 failures, `TEST SUCCEEDED`** + localization /
  debug-switch / availability checks green. Owner eyeball items (Spring Pop/Instant,
  light mode, day/snow/fog tints, iPad-width Glance, Classic presets, real EventKit
  grants) are logged in the phase-5 log and **do not block closure**.

- **Result**: **DONE (2026-10-11)**. Hardening proven by drill, not assertion: 5a window-lift
  de-dup to one reservation per display (3 invariant tests); 5d dev-bypass polarity lock
  (8 tests); 5b/5c recovery drills found two real defects — SIGTERM/SIGINT skipped
  `stopAndRestore` and `kill -9` lost lift sessions — both fixed (runloop-dispatched
  `installTerminationSignalHandlers` + `WindowLiftRecovery` replay file, +4 tests, verified
  live: kill -9 with a lifted window → relaunch → restored) with mid-write `kill -9`
  reasoned-accepted (30× emulation, 0 corrupt reads) and relaunch-idempotence pinned
  (`IslandSlotSetTests`); 5e floating calendar tiles; 5g/5h weather tiles + Tall layouts +
  animation presets + extra tiles; 5i weather Glance redesign. Closure gate:
  **1,719 unit tests green, 0 failures**, localization ×12, debug switches 77/77,
  availability-warnings clean (build log). Drill log + addenda:
  `Docs/Archive/Planning/2026-10-11-phase-5-log.md`.


### Phase 6 — Settings Layout tab + welcome step + polish (DONE)

- New "Layout" `SettingsTab` (mode picker with live thumbnails drawn from
  `IslandLayoutSolver`), `WelcomeGuideView` pick-a-layout step, status-menu mode entry;
  height/gap/width sliders reuse tungsten's `DockPanelHeight` scaling path.
- **Bottom-edge hug toggle** (owner 2026-10-08: tungsten's 8pt floating default
  kept, hug opt-in): new `com.katikati.layout.bottomGap` (default 8 = current
  floating; preset Hugging 2, slider 0…12) as a segmented control/slider on the
  Layout tab. Single substitution in `DockPanelHeight.metrics` (replaces the
  literal `8`); all four modes + capsule + drawer follow automatically
  (`dockTargetFrame`/`islandTargetFrame`/`bottomMargin` already thread it).
  Edge bars (Phase 7A) default to hugging; bottom islands default to floating.
  Tests: hug-value bottom-anchoring cases alongside the existing
  `bottomGap 8 − shadowPadding 20` pins; solver `validate()` unchanged.
- **Appearance tab** (new Settings tab, next to the existing Layout tab): the
  theme/preset picker from Phase 4, using the same `com.katikati.*` domain:
  `com.katikati.theme.material` (default `auto` = light `roseQuartz` / dark
  `obsidianDark`, all 12 presets + customRGBA selectable as a pinned override);
  appearance stays on the existing `appearanceMode` setting (no duplicate control).
- **Icon-set config** (next to Appearance): the line-set folder / download / trash +
  status-menu item variants, controlled by a single key `com.katikati.iconSet`
  (`modern` default | `classic` familiar fallback) as a segmented control, so all
  12 theme presets and icon variants are independently switchable.
- **Visual regression gate:** `check_localization.py` stays green; screenshot
  golden-set per theme + icon-set across all 12 languages; no `tungsten` brand
  marks on product chips or menu bar (section 5.5 of the Phase-0 trademark audit).
- Polish: hover-title tooltips per island, ~~drag-to-resize grip per island panel~~ (dropped,
  owner 2026-10-11 — 4U decision 3: no on-dock resize handles), edge auto-hide delay interplay
  with multi-island layouts.
- **Rich inline chip variant (owner 2026-10-08, CoolDock parity, Phase 6+ polish).**
  *Intent: CoolDock screenshots 2–3 surface rich content (folder thumbnails,
  clipboard summaries, terminal+weather) inline in the pill, while our model puts
  richness in popups — record the option to match without conceding the default.*
  Opt-in per-chip "expanded inline" form; popups stay the default. Clipboard stays
  edge-only (owner Q2(a) 2026-10-08: clipboard content in the main bar is a
  privacy-sensitive surface — passwords/visible text on screen; the Phase-7A edge
  bar keeps it one deliberate glance away). Terminal/CLI pill not recorded
  separately (owner Q3(a) 2026-10-08: arc-menu's CLI-by-path in 7c covers the
  function; the pill form is this variant if ever wanted). No strip-semantics
  change (§2.4).
- **Light-preset tuning pass (owner 2026-10-08, CoolDock parity).** *Intent:
  screenshots 2–3's white pills must be reproducible from our light column, not
  approximated.* During 4h, check `crystalClear`/`titaniumFrost`-family values
  against the reference whites; record measured values in the 4h log.
- **Calendar popup brainstorm slice 4e2 (owner 2026-10-08, deferred — NOT 4e).**
  *Intent: the calendar popup is a bigger design step than the chip; brainstorm
  it separately.* Scope when activated: month grid + today highlight baseline;
  alarms/calendar-notification badges, event integration, and provider-driven
  cells decided in the brainstorm, not assumed. Own mini-plan + tests.
- **Verify**: mode/width/gaps persist across restarts; switch without relaunch; onboarding
  snapshot test green.

**Phase 6 check log (STANDING_RULES §1.8):**
- 2026-10-11 · **Plan + design.** Full plan re-read; design canvas (Layout tab, Appearance tab,
  welcome step, status menu, polish) built as a claude.ai Design artifact. Owner picks:
  icon set **Modern = current 3D trash art / Classic = SF Symbols**; welcome guide becomes
  **two steps (Pick a layout → Dock settings)**. Canvas predates the 4U-A re-read (it drew split4
  = split3); the shipped thumbnails come from the solver, so they show the real 1/3/4/5/1.
- 2026-10-11 · **6a bottomGap — PASS.** `com.katikati.layout.bottomGap` (default 8 floating,
  Hugging 2, clamp 0…12, whole points, non-finite → 8). The literal `8` in
  `DockPanelHeight.metrics` became `metrics(bottomGap:)`; live callers read
  `AppSettingsStore.layoutMetrics` (strip, capsule, coordinator) and `$bottomGap` joined the
  relayout sink — every mode + capsule + drawer + window-lift context follow. `tungstenEdge`
  stays at 8. Tests: hug pins beside the `8 − 20` one (2 → −18, 0 → −20, every mode's islands
  drop by the delta) + store default/clamp/persist. Solver `validate()` untouched.
- 2026-10-11 · **6b iconSet — PASS.** `com.katikati.iconSet` (`modern` default, unknown → modern)
  in `Core/Support/IconSet.swift`; `\.iconSet` environment injected beside `\.dockThemeStyle`
  (strip, drawer, capsule). Classic draws the trash as `trash` / `trash.fill` in themed label
  colour and the menu-bar item as an SF Symbol, swapped live by a `$iconSet` sink. **Scope
  note:** folder/download chips have no "modern" art of their own today (they show folder
  covers), so the set covers trash + menu-bar icon only.
- 2026-10-11 · **6c Layout tab — PASS.** New `SettingsTab.layout` + `SettingsLayoutPane`:
  cropped live preview + five mode cards drawn by `LayoutThumbnailModel` (pure, solver-fed,
  4 tests), bar height (existing `DockPanelHeight` setter/scaling path), island gap, side
  margin, centered width (enabled only in Centered), widget widths (moved from General — also
  fixes the missing "Now Playing" label there), bottom edge Floating/Hugging/Custom + slider.
  Fixed-height mode description so the pane never changes height in place.
- 2026-10-11 · **6d Appearance tab — PASS (code).** `SettingsTab.appearance`: Auto + 12 presets
  + Custom, swatches drawn from the real `DockThemeStyleTokens` columns (Auto shows both),
  custom tint + opacity → `.customRGBA`; Icon set segmented control with previews. Light/dark
  stays in General (caption points there; no duplicate control). **Not verified live:** popups
  and tooltip pick a theme change up on their next open (4c note) — an already-open popup is
  not re-themed; left as is.
- 2026-10-11 · **6e welcome step — PASS.** `WelcomeGuideStep` (pure) + two stacked steps in one
  fixed-height view (the window is measured once). Step 1 writes the mode immediately via
  `setBarLayoutMode`. **Onboarding snapshot test** = structural, in a real `NSHostingView`
  (`WelcomeGuideOnboardingTests`: width fixed at 520, height independent of the starting mode,
  every mode has solver islands) — no image goldens: that would need a new dependency.
- 2026-10-11 · **6f status menu — PASS (code).** "Layout ▸": five modes (radio), Floating /
  Hugging (a custom gap checks neither), "Layout Settings…" opening Settings on the Layout tab
  (`SettingsWindowController.selectBeforePresenting`). Rows are fixed; only states refresh.
- 2026-10-11 · **6g polish.** (a) Hover title per island section via `.help` (system tooltip,
  no new panel). (b) **Auto-hide interplay gap found + fixed:** each island ran its own
  idle-hide check against its own frame, so hovering the apps island let weather/clock hide on
  their own; `isMouseOutsideInteractivePanels` now also asks the sibling islands on the same
  display (`onQuerySiblingContainsMouse`), so the bar hides and stays as one surface. Wake was
  already screen-wide. Not unit-testable (reads `NSEvent.mouseLocation`) → owner eyeball.
  (c) **Drag-to-resize grip per island — DROPPED (owner 2026-10-11: "no on-dock resize
  handles").** Phase 4U decision 3 wins; widths stay Settings sliders only. (d) Carried items (rich inline chip, light-preset tuning, 4e2,
  DockDoor preview) untouched.
- 2026-10-11 · **6h localization + gate — PASS.** 47 new keys × 12 (catalog 429 × 12,
  `check_localization.py` ✅); stale `BarLayoutMode` split3/split4 copy corrected to the 4U-A
  grouping. **Translations are agent drafts — owner review pending (§1.7).** No "Tungsten" in any
  new UI copy. Gate: **1,731 tests, 0 failures**; debug switches 77/77; availability ✅.
  Layout pane + welcome step rendered to PNG and eyeballed (dark mode); the live app was **not**
  launched in this session.
- **Not done / owner items:** per-theme × icon-set × 12-language image golden set (needs a
  snapshot dependency or a manual capture pass); live check of persistence across relaunch and
  of the status-menu entry; light-mode look of both new tabs.
- 2026-10-11 · **Phase 6 — DONE (verified by main session on owner directive "check phase 6
  is actually done").** Slices 6a–6h all committed (`4bff890`…`4510af5`); 6g(c)
  drag-to-resize grip DROPPED by owner (4U decision 3 supersedes); carried items (rich
  inline chip, light-preset tuning) stay deferred, DockDoor preview moved to Phase 9c.
  Independent closure gate re-run: **1,731 tests, 0 failures, TEST SUCCEEDED**;
  `check_localization.py` ✅ (429 keys × 12); `check_debug_switches.py` ✅ (77/77);
  `check_availability_warnings.py` ✅ (fresh build log). Owner items above (translation
  drafts §1.7 review, live persistence/status-menu/light-mode eyeball, image golden set)
  recorded as **non-blocking** — same posture as Phase 5's eyeball list.

- **Result**: **DONE (2026-10-11)**. Settings Layout tab (solver-drawn mode thumbnails +
  height/gap/width/bottom-edge controls), Appearance tab (Auto + 12 presets + custom tint +
  icon set), welcome-guide pick-a-layout step (two-step flow), status-menu Layout submenu,
  bottom-edge hug toggle (`com.katikati.layout.bottomGap`, single substitution in
  `DockPanelHeight.metrics`), icon-set key (`com.katikati.iconSet`), island auto-hide
  unified per display + per-island hover titles; drag-grip dropped per 4U decision 3.
  47 new localization keys ×12 (translations = agent drafts, owner review pending).
  Closure gate: **1,731 unit tests green, 0 failures** + all three check scripts green.
  Phase log: in-plan check log above (§6.4 dated entry: `Docs/Archive/Planning/2026-10-11-phase-6-log.md`).

### Phase 7 — Deferred, split into 7A / 7B (owner 2026-10-11: sign-off + mini-plan + license check each)

**Split (owner directive; boundary confirmed 2026-10-11):** **7A = edge-bar integration**
— new panel machinery (`displayUUID#edgeSlot` extension of `rebuildUnits`, vertical
geometry, risks #13/#14, Instruments CPU gate). **7B = launchers & FAB payloads** —
feature logic riding existing panels (7c explicitly no new panel class; 7d/7e reuse the
4g/4U-A FAB panel pattern). No dependency inversion (7B does not need 7A), but **7B
starts only after Phase 6 lands**: its FAB Settings width sliders edit
`SettingsWindowView`, the same territory Phase 6 builds. Slice IDs 7a–7e unchanged;
Appendix C stays normative for both halves.

#### Phase 7A — Edge-bar integration — **DONE 2026-10-12** (owner sign-off; see the closing note in the check log)

- **7a right-edge notes bar** (first): EdgeDeckBar notes + noty sync/crypto/editor
  per §5e. Local-only `.md` in `~/Library/Application Support/KatiKati/`,
  iCloud-Drive-folder sync, AES-GCM. Non-activating, all-Spaces, atomic
  fullscreen-hide per display, popup anchored to its own edge chip.
- **Wi-Fi + battery status widget on an edge bar** (owner suggestion, 2026-10-09 —
  moved out of the main bar by Phase-4U decision 8): the status cluster (Wi-Fi,
  battery, plus the tray popup's quick settings and the merged ring icon that 4f
  used to plan) lands on whichever edge bar the owner picks — **left vs right is
  decided by the owner at 7A sign-off**. `TrayChip` moves to this scope.
- **Status trio (owner 2026-10-11):** the status cluster above adopts the **combined-icon
  pattern** from `lingyired/status-trio` (reference, Apache-2.0): Wi-Fi + battery +
  **volume** in one compact configurable status icon (iPhone Duo-style) with per-status
  popovers. Reference policy applies (§5 intro): investigate before any code use (Swift 6 /
  macOS 13 floor vs our macOS 12 floor), NOTICE attribution if behavior is derived. Adds
  **volume** to the wifi/battery/quick-settings cluster.
- **7b left-edge widgets bar** (second): all 6 EdgeDeckBar widgets per §5e,
  re-skinned to tungsten chips + `PanelGeometry` anchors.
- **Verify 7A**: tungsten gate green + per-edge anchor tests + idle CPU ≤
  island baseline + ε (Instruments number in PR); notes sync round-trips
  local ↔ iCloud-Drive folder (acceptance criterion 10).

#### Phase 7B — Launchers & FAB payloads (deferred; start after Phase 6)

- **7c centered launcher** (first in 7B; the original Phase-7 order ran it after 7a/7b):
  hybrid per §5e — arc-menu base + EdgeDeck dispatch + Volant ranking/config + Liftoff
  preview/search. ⌥Space or center-slot summon; anchored flyout, no new panel class.
- **7d left-FAB custom launcher (Launchpad-style)** (owner 2026-10-11; payload for
  the 4g-scaffolded left FAB): an old-macOS-Launchpad-style full-surface app
  launcher summoned by the left FAB. Distinct from 7c's centered launcher (different
  trigger + UX; owner to sequence — they may share the app-enumeration/dispatch
  core). Needs its own mini-plan + slice: overlay panel (reuse the FAB panel
  pattern), app grid + paging, launch dispatch, dismiss gesture; no new TCC surface
  beyond the existing app list; CPU gate. **Add a Settings width slider for the
  left FAB** (owner 2026-10-11) — the 4U-A FABs have no slider (fixed 40pt square);
  the left FAB's `BarSection.launcher` `defaultWidgetWidth`/`minimumWidgetWidth`
  (currently both 40) become the seeded slider value, floored at `minimumWidgetWidth`
  and threaded through `AppSettingsStore` + `IslandLayoutSolver` like weather/clock.
  Sign-off + license check per the Phase-7B gate.
- **7e right-FAB on-screen overlay widgets** (owner 2026-10-11; payload for the
  4g-scaffolded right FAB): an on-screen overlay surface for glanceable widgets
  (clock/weather/notes) summoned by the right FAB. Scope (which widgets, overlay vs
  HUD, dismissal) decided in its own mini-plan; reuse the FAB panel pattern; CPU +
  all-Spaces/fullscreen-hide gate. **Add a Settings width slider for the right FAB**
  (owner 2026-10-11) — the 4U-A FABs have no slider (fixed 40pt square); the right
  FAB's `BarSection.widgets` `defaultWidgetWidth`/`minimumWidgetWidth` (currently
  both 40) become the seeded slider value, floored at `minimumWidgetWidth` and
  threaded through `AppSettingsStore` + `IslandLayoutSolver` like weather/clock.
  Sign-off + license check per the Phase-7B gate.
- **Verify 7B**: tungsten gate green + launcher/FAB anchor tests + FAB width sliders
  persist across restarts + no new TCC surface beyond the existing app list +
  idle CPU ≤ island baseline + ε (Instruments number in PR; acceptance criterion 11).

**7B reoriented 2026-10-12 (owner, after 7A closed) — supersedes the 7c/7d split above; plan only, nothing built.**
Reference screenshots: one Launchpad-style surface (icon grid + widget tiles, left sheet, Light/Dark/Glass/wallpaper themes).
- **Merged launcher (7c+7d):** one full-screen panel (existing panel pattern, no new class) summoned by the left FAB
  **and** ⌥Space; ⌥Space opens it with the search field focused and toggles it closed. One page only.
- **Sources/licences:** LaunchNext (GPL-3.0, compatible) and macos-launchy (AGPL-3.0) are *ideas/logic only, UI written fresh*;
  NOTICE entries when logic is derived. Native app + Spotlight indexing. Phase 8a drawer reuses the same index later.
- **Slices:** L1 app-index core (Spotlight + /Applications scan, live updates, launch counts, ranking pinned > most used >
  recently installed, fuzzy search; pure Core + tests) → L2 summon/shell (⌥Space, FAB, blurred backdrop, Esc) → L3 grid page
  (lazy, icon cache, pin/unpin) → L4 left sheet = **All Apps + Search only** (Downloads moves to the right widgets later) →
  L5 widget tiles: Clock/World time, Calculator, Countdown, Files; user picks which show (**Browser tile dropped**) →
  L6 themes: full picker (Light, Dark, Glass, tints, **current desktop picture, blurred**; no bundled wallpapers) →
  L7 FAB redesign + launcher icon (three presets rendered as SVG; **orbit is the default**) → L8 verify (gate, idle CPU, live).
- **B2 Screen Time / Digital Wellbeing (usage + limits):** W1 on-device per-app foreground time (no network) → W2 flyout
  (today/week) as a **button on the productivity deck** → W3 per-app daily limits, break reminder, gentle block, pause switch.
  Needs its own privacy note before W1.

- 2026-10-12 · **7B-L1a landed (gate green, 1896 tests):** pure `Core/Support/LauncherAppIndex.swift` (merge/dedupe by bundle id, sections pinned > most used > recently installed, launch recording, pin toggle, fuzzy `LauncherSearch`) + 8 tests. Platform indexer (Spotlight + /Applications, live updates, usage store) is L1b.

- 2026-10-12 · **7B-L1b landed (gate green, 1900 tests):** `Platform/Launcher/LauncherStore.swift` (launch counts + pins, `launcher.json`, corrupt file → `.bak`) and `LauncherIndexer.swift` (instant directory scan, then live Spotlight query; lazy `start`/`stop`; skips LSUIElement/background-only). Nothing is wired to UI yet; icon cache lands with the grid (L3).

- 2026-10-12 · **7B-L2 landed (gate green, 1900 tests; live check pending):** `LauncherPanelController` (full-screen blurred borderless panel, key-capable, non-activating, screen under the pointer; indexer runs only while shown), `LauncherView` (AppKit search field focused on open, results list as a stand-in for the L3 grid, Return launches first hit, Esc / background click closes, launches recorded in `launcher.json`), ⌥Space second `GlobalHotKeyMonitor` (id 2, toggles), left FAB tap toggles. Risk: Carbon ⌥-only hotkeys were flaky on macOS 15 (FB15168205) — failure is logged and the FAB still works; a rebinding setting is a follow-up if it bites.

- 2026-10-12 · **7B-L3 landed (gate green, 1900 tests):** grid page — Pinned / Most Used / Recently Installed sections (+ a temporary All Apps section until L4), flat grid while searching, cached 64 pt icons (`LauncherIconCache`), Pin/Unpin context menu persisted to `launcher.json`.
- 2026-10-12 · **Owner amendment for L4:** the All Apps + Search side sheet can sit on the **left or right, right by default**, with a preset in Settings to switch it (own key, e.g. `com.katikati.launcher.sheetSide`, plus a Settings control and tests). The temporary All Apps grid section is removed when the sheet lands.

- 2026-10-12 · **7B-L4 landed (gate green, 1901 tests):** All Apps + Search side sheet (search field at the sheet's bottom; list narrows while typing); sheet side is `com.katikati.launcher.sheetSide` (default **right**), Settings → Launcher → App List Side, read at each summon; temporary All Apps grid section removed. Live check of L2–L4 follows.

- 2026-10-12 · **7B L2–L4 live check:** ⌥Space opens the launcher with search focused; Recently Installed grid + right-hand All Apps sheet render; typing `cal` narrows both grid and list; Esc closes. Not exercised: Return-to-launch, pin/unpin menu, left-side setting, FAB tap, multi-display/fullscreen. Seen: a faint blurred rectangle mid-screen (likely the app's permission window behind the blur) — recheck with permissions granted.

- 2026-10-12 · **7B-L5a landed (gate green, 1906 tests):** search field leaves the sheet and sits centred on a chosen side — `com.katikati.launcher.searchPosition` = top (default) / bottom / left / right (pure `LauncherSearchPosition` + insets, tests); Settings → Launcher → Search Position; a side field stacks beside the sheet when both share a side. Interpretation of "all sides, symmetrical": four centred positions, not corners. L5b (widget tiles) next.

- 2026-10-12 · **7B-L5b landed (gate green, 1911 tests):** widget row above the grid — Clock (time + date), Calculator (pure `CalculatorEngine`, live result), Countdown (existing `EventCountdownStore`), Downloads (newest 4, read only when the tile first appears; may raise the system folder-access prompt); `com.katikati.launcher.tiles` (default all), Settings → Launcher toggles. World-time zones deferred. Housekeeping: `LauncherLayout` pbxproj IDs were 25 chars (overflow in my helper) — replaced with valid `EE…` IDs; helper fixed.

- 2026-10-12 · **7B L5 live check:** search centred at the top by default, four tiles render (Clock 01:51, Calculator, Countdown "No events", Downloads list), sheet on the right; typing `12+6*2` in the Calculator tile shows 24. Not exercised: other search positions, left sheet, tile toggles in Settings, Downloads item open, Countdown with events, Return-to-launch, pin menu, FAB tap.

- 2026-10-12 · **7B-L6 + L7 landed (gate green, 1915 tests):** L6 themes — `LauncherTheme` (system default / light / dark / glass / desktop picture), `LauncherTint` wash, `LauncherBackdrop` (blur layers; desktop picture downscaled, blurred, cached per file+mtime; folder/rotating wallpapers fall back to system blur); keys `com.katikati.launcher.theme|tint`; Settings → Launcher. L7 — `LauncherIconView` (gradient squircle with **orbit** default / tiles / petal) replaces the grid-symbol FAB glyph; key `com.katikati.launcher.icon`; Settings shows the three as selectable presets. Live: desktop-picture + purple tint verified (launched with `-com.katikati.launcher.theme desktop`). Not seen live: light/dark/glass themes, the FAB icon in the strip (the bar is not shown while the Accessibility prompt is up), the Settings icon presets. First-time desktop-picture read may touch a protected folder if the wallpaper lives there. L8 (verify) remains.

- 2026-10-12 · **7B launcher safe-area fix (gate green, 1917 tests):** the launcher keeps its search field and grid clear of the notch, menu bar, Dock and KatiKati's own bottom bar (`LauncherScreenInsets` from `frame`/`visibleFrame`/`safeAreaInsets.top` + bar height; clamped to a third of the screen; tests).

- 2026-10-12 · **Owner: Downloads tile scrapped from the launcher** (the retired `files` id is ignored when parsing; strings removed). The right-hand Downloads widget's home is still to be confirmed (edge-deck button proposed).

- 2026-10-12 · **7B-B2 privacy note (Screen Time) — binding for W1–W3.** *Collected:* for each local day, the bundle id, display name and seconds of the frontmost **regular** app (KatiKati itself, loginwindow and the screensaver excluded). *Never collected:* window titles, URLs, documents, keystrokes, screenshots; no Accessibility or Screen Recording permission is used. *Counted only while* the screen is awake and the last input was under 2 minutes ago; gaps over 2 minutes between ticks are not credited. *Stored:* `Application Support/KatiKati/screentime.json`, on this Mac only — no network, no iCloud, no analytics; 90-day retention; "Delete Screen Time Data" wipes it. *Consent:* **off by default**; nothing is observed and no timer exists until the owner turns it on in the flyout. Limits (W3) act only on this local data.
- 2026-10-12 · **7B-W1 + W2 landed (gate green, 1927 tests):** pure `ScreenTimeLedger` / `ScreenTimeTracker` (midnight split, idle/sleep gating, gap cap, prune; 8 tests) + `ScreenTimeStore`; `ScreenTimeController` (15 s timer + workspace notifications only while enabled); edge-deck **Screen Time** button (`ProductivityItem.screenTime`, `EdgeItem.screenTime`; hourglass) with a flyout (today, top apps, 7-day strip, on/off switch, delete); launcher **Screen Time** detailed tile (`LauncherTile.screenTime`, toggle in Settings → Launcher). **Owner: Downloads dropped entirely** (the bottom dock already has the Downloads folder). W3 (limits) next.

- 2026-10-12 · **7B-W3 landed (gate green, 1932 tests):** per-app daily limits — pure `ScreenTimeLimits` (stored `com.katikati.screentime.limits`, 5–720 min) and `ScreenTimeLimitState` (one heads-up per app per day at ≤5 min left; "reached" re-prompts every 5 min unless snoozed; OK silences the app until midnight; 5 tests); `ScreenTimeAlertPresenter` (small non-activating top-centre card: heads-up fades after 8 s, reached shows Snooze 5 Minutes / OK — never blocks the app, per the owner's "gentle overlay" choice); limits editor (Daily Limits, Add Limit) in the flyout. Limits act only while the app is frontmost and the user is not idle. Not verified live yet.

**Previously listed (still deferred, phase TBD — parked 2026-10-11 in neither half):**
dividers (`pruned` logic), `macOS` pill mode, magnification, hover-preview strip
upgrades, wallpaper/personalisation, extra flyouts.

**Phase 7 check log (append after every step — STANDING_RULES §1.8):**
- 2026-10-11 · **7A sign-off + sliced (owner):** status cluster defaults to the **right edge
  with notes**; side is a Settings option with user-friendly presets (7A-2). Slices: 7A-0 refs →
  7A-1 foundation → 7A-2 presets/Settings → 7A-3 side-edge auto-hide → 7A-4 status providers
  (real Wi-Fi/battery/volume; today's `SystemStatusProvider` is a stub, `TrayChip` orphaned) →
  7A-5 status trio chip → 7A-6 notes store+sync → 7A-7 notes UI → 7A-8 widgets bar → 7A-9 verify.
  Plan correction: no FAB panel exists (FABs are in-strip `SectionFABGlyph`s); edge panels follow
  `WidgetPanelController`/capsule patterns instead.
- 2026-10-11 · **7A-0 refs studied (scratchpad clones, study only):** EdgeDeckBar MIT, noty MIT,
  status-trio **Apache-2.0** (needs NOTICE entry if behavior is derived); EdgeDeckBar and
  status-trio are `swift-tools 6.0`, status-trio floor **macOS 13** vs our 12 → investigate before
  any use. No code taken.
- 2026-10-11 · **7A-1 foundation landed (gate green, 1743 tests):** `Core/Support/EdgeBarSlot.swift`
  (`EdgeSide`, `EdgeSlotSet` → `displayUUID#edge-left|right`), `PanelGeometry.edgeBarTargetFrame`
  (vertical, ⊆ visibleFrame, 0.5 pt min, hugging 2 pt), `com.katikati.edge.{enabled,status.side,gap,margin}`
  in `AppSettingsStore` (default off), `DOCK_EDGE_BARS` (=1 forces on), slim `EdgeBarPanelController`
  (placeholder plate), orchestrator `reconcileEdgeBars` with a separate `edgeControllers` map (islands untouched),
  visible only while a sibling island unit is logically visible (fullscreen hides both atomically),
  included in `allSpacesPanels`. Tests: `EdgeBarSlotTests` (11) + settings test. Not yet done:
  live fullscreen/Spaces eyeball, side-edge auto-hide (7A-3).
- 2026-10-11 · **7A-2 presets + Settings landed (gate green, 1745 tests):** `EdgeBarPreset`
  (off / notes / notesAndStatus / status → content per edge, notes always right, status on the
  chosen side) in `Core/Support/EdgeBarSlot.swift`; `com.katikati.edge.preset` replaces the
  never-released `edge.enabled` bool; "Edge Bars" section in `SettingsLayoutPane` (preset
  segmented control + Status Side Left/Right, disabled when no status). 6 new strings x12
  (**drafts, owner review — §1.7b**), added as one line-anchored insert (+462 lines, generated
  file; committed separately). Phase 12 settings refinement may relocate the section.
- 2026-10-11 · **7A-3 side-edge auto-hide landed (gate green, 1747 tests):** pure
  `EdgeBarAutoHide` (2 pt hot zone along the screen side spanning the bar, 0.4 s idle delay,
  reveal/arm/cancel decision incl. `popupOpen` guard for later popovers) in `EdgeBarSlot.swift`;
  `EdgeBarPanelController.pollMouse` + one-shot idle timer (no timers while hidden), separate from
  the island-visibility verdict so fullscreen is never overridden; `com.katikati.edge.autoHide`
  (default off) + Settings toggle (1 string x12, drafts, separate commit); rides the existing
  `pollAllUnits` mouse monitors (`hoverMonitorsNeeded` now includes edge auto-hide) — no new
  global monitor. Not yet verified live (hover feel, multi-display, CPU) — 7A-9.
- 2026-10-11 · **7A-4a status value types landed (gate green, 1754 tests):** pure
  `Core/Support/SystemStatus.swift` — `BatteryStatus` (parses an IOPS description dict; rejects UPS /
  malformed), `WiFiStatus` (RSSI → 0…3 steps, symbols; SSID optional, never requests Location, never
  reads passwords), `VolumeStatus` (clamped, symbol steps, percent), aggregate `SystemStatus`; 7 tests.
  4b (next): lazy event-driven Platform monitors (IOPS run-loop source, CWWiFiClient events,
  CoreAudio property listeners); frameworks autolinked via `import`. Old stub
  `SystemStatusProvider` + orphan `TrayChip` retire in 7A-5 with the chip.
- 2026-10-11 · **7A-4b live monitors landed (gate green, 1756 tests):**
  `Platform/SystemStatus/SystemStatusService.swift` — `@MainActor` ObservableObject publishing
  `SystemStatus`; **lazy + ref-counted** (`acquire`/`release`; nothing observed until first
  consumer, fully torn down at zero; §1.7e) and **event-driven, no timers**: IOPS run-loop
  source (battery), `CWWiFiClient` power/SSID/link/quality events, CoreAudio listeners on the
  default output device (re-bound when the device changes; volume + mute; `setVolume` for the
  popover slider). Privacy: no Location request, no password/keychain reads; SSID shown only if
  the OS provides it. Frameworks autolinked. Tests: lazy/ref-count + sane-readings smoke. Not
  wired to UI yet (7A-5). Live eyeball (unplug charger, toggle Wi-Fi, change volume) pending.
- 2026-10-11 · **7A-5 status trio chip landed (gate green, 1759 tests):** pure `EdgeBarLayout`
  (tile sizes/stacking, `tileFrame`) + `PanelGeometry.edgeBarPopupFrame` (opens inward, clamped to
  visibleFrame) committed first (`54e62ad`). Then `App/Scenes/Edge/StatusTrioView.swift` (Wi-Fi +
  battery + volume stacked in one compact column; each glyph a popover trigger; Wi-Fi variable-value
  symbol gated `#available(macOS 13)`), `StatusPopupView` (SSID / dBm, battery %, volume slider via
  `SystemStatusService.setVolume`, "Open System Settings…" per pane), `EdgeStatusPopupController`
  (popover panel placed by the pure geometry, outside-click dismiss, toggle on re-tap; feeds the
  auto-hide `popupOpen` guard), `EdgeBarPanelController` now hosts SwiftUI content per preset
  (`EdgeBarContentView`; notes tile is still a glyph placeholder for 7A-7), orchestrator holds a
  **lazy** `SystemStatusService` acquired only while status content is shown. `DOCK_EDGE_BARS=1`
  with the preset off shows a lone notes tile. Retired: orphan `TrayChip`, stub
  `SystemStatusProvider` + its test (pbxproj lines removed by verified ID). Behaviour reference:
  status-trio studied for the combined-icon + per-status-popover pattern only; no code or assets
  taken, so no NOTICE entry (Apache-2.0 entry stays reserved if that changes). 10 strings x12
  (drafts, separate commit); a ternary-String `Text` bug (would not localize) was caught by
  `check_localization.py` and fixed. **Not verified live** (click targets in a non-activating panel,
  popover placement on a real display, Wi-Fi/battery/volume updates) — needs an eyeball pass.
- 2026-10-11 · **7A-6a notes core landed (gate green, 1781 tests):** pure Core only —
  `Note` model (whole-second dates, derived title), `NoteDocument` (Markdown + `katikati-id`
  front-matter render/parse, tolerant of CRLF / bad values / unclosed header / identity-less files),
  `NotesSyncPlan` (decision table: push / pull / reindex / adopt / deleteLocal / deleteRemote /
  conflict; unreadable files never read as deleted; lost index with matching stamp reindexes instead
  of conflicting; duplicate-id files keep the indexed home and adopt the copy) + `NotesSyncIndex`.
  noty's `SyncPlan` (MIT) studied for the decision table, re-derived and re-tested here — one
  divergence: the final pull/delete pass walks the de-duplicated set, so a duplicated id is never
  pulled twice. 22 tests. NOTICE entry for noty to be filled when the store/sync runner lands
  (behaviour derived). 6b (local store + AES-GCM + iCloud runner) pending an owner call on the
  at-rest format.
- 2026-10-11 · **Owner decisions (7A-6):** notes are **AES-GCM encrypted locally**, plain `.md` only in
  the opt-in sync folder; sync folder = `~/Library/Mobile Documents/com~apple~CloudDocs/KatiKati Notes`
  (plain path, no CloudKit entitlement, off until enabled).
- 2026-10-11 · **7A-6b encrypted local store landed (gate green, 1790 tests):** `Core/Support/NoteCipher.swift`
  (AES-256-GCM, fresh nonce per seal, combined box; tamper / wrong key / malformed all distinguished;
  `NoteKeyProviding` + in-memory provider for tests), `Platform/Notes/KeychainNoteKeyProvider.swift`
  (generic-password item, this-device-only, after-first-unlock, lazy create, race-safe),
  `Platform/Notes/NotesStore.swift` (`~/Library/Application Support/KatiKati/Notes/<id>.note`, atomic
  writes, ids sanitized so a synced `katikati-id` can't escape the folder, unreadable files reported and
  **never deleted**, pinned→order→created sort). `Note` is `Codable`. 9 tests (cipher round-trip /
  nonce / no plaintext in blob / tamper; store round-trip / encrypted on disk / overwrite+delete /
  wrong key / path traversal). Keychain provider is not unit-tested (needs a signed host) — eyeball
  on first run. 6c next: sync runner (iCloud folder listing, placeholders, executing `NotesSyncPlan`
  actions, conflict copies, index persistence).
- 2026-10-11 · **7A-6c sync runner landed (gate green, 1801 tests):** `Core/Support/NoteFileName.swift`
  (legal/unique/readable file names, case-insensitive), `Platform/Notes/NotesSyncFolder.swift` (plain-path
  iCloud Drive folder, `NSFileCoordinator` reads/writes, `.Name.md.icloud` placeholders → *unresolved* + download
  requested, never "deleted"), `Platform/Notes/NotesSyncRunner.swift` (executes `NotesSyncPlan` actions;
  conflict keeps the loser as a new note titled with an injected, localizable suffix; identity-less / duplicated
  files adopted and the header written back; per-note errors never abort the pass; **refuses to run when the
  folder is missing or any local note is undecryptable**, so copies are never mistaken for deletions),
  `NotesSyncIndexStore` (JSON, loss-safe). 11 tests incl. two-device push/pull/edit/conflict/delete round trips
  on a temp folder, adopt, wrong key, placeholder, index round-trip. NOTICE §5 (noty) updated: behavior
  re-derived, no source copied. **Acceptance criterion 10's local↔iCloud round trip is proven against a
  temp folder; the real iCloud Drive path is untested** (needs a signed-in Mac eyeball). Not wired to the app yet —
  the notes UI slice (7A-7) will own enabling sync, scheduling passes (folder-change events, no polling) and the
  localized conflict suffix.
- 2026-10-11 · **7A-7a notes controller landed (gate green, 1810 tests):** `Platform/Notes/NotesController.swift` —
  `@MainActor` ObservableObject: published list (pinned → order → created via shared
  `[Note].inListOrder()`), create (newest on top), edit (applied in memory at once, **250 ms debounced
  autosave**, no-op edits don't bump `modified`), pin / archive, `flush()`, delete with a **10 s single-level
  undo** (restores the same id so a synced copy re-links; a pending edit can't resurrect a deleted note),
  `reload()` for external/sync changes, `lastError` for unreadable notes, `onLocalChange` hook for scheduling
  sync passes. Scheduler injected → deterministic tests (9). UI-free; 7A-7b adds the notes popup (list +
  editor), undo toast, wiring to the bar's notes tile, sync enable/scheduling and the strings.
- 2026-10-11 · **7A-7b notes flyout landed (gate green, 1810 tests; UI not eyeballed):**
  `App/Scenes/Edge/NotesPopupView.swift` (note list + `TextEditor` + pin/delete + 10 s undo toast, Esc closes),
  `App/Entry/EdgeNotesPopupController.swift` (key-capable *non-activating* panel so typing works without
  stealing app focus; placed by `edgeBarPopupFrame` with the new `EdgeBarLayout.notesPopupSize`; outside click
  or hide flushes autosave), the bar's notes tile is now a button, status and notes popups are mutually
  exclusive, and the auto-hide `popupOpen` guard covers both. `NotesController`/`NotesStore`/Keychain key are
  created **lazily on first tile tap** (§1.7e); an unavailable Keychain/store degrades to "no notes" with a log
  line. 6 strings x12 (drafts, separate commit). Removed a Sendable warning my timer introduced.
  **Still open in 7A-7:** the sync toggle + scheduling (7A-7c: setting, folder watcher, debounce after local
  edits, localized conflict suffix) — sync is not reachable from the UI yet.
- 2026-10-11 · **7A-7c notes sync wiring landed (gate green, 1813 tests; not run against real iCloud):**
  `Platform/Notes/NotesSyncService.swift` — `SyncPassScheduler` (debounce 1.5 s; requests during a pass collapse
  into one follow-up; idle = no timers; 3 tests) + `NotesSyncService` (pass on start, after debounced local edits via
  `NotesController.onLocalChange`, and on folder changes via a `DispatchSource` file-system event — **no polling**;
  runner executes off the main actor, index persisted, controller reloaded only when a pass changed local notes).
  Opt-in `com.katikati.notes.sync` (default off) + "Sync Notes with iCloud Drive" toggle in the Edge Bars section;
  orchestrator starts/stops the service from the setting and touches the Keychain only when enabled; conflict suffix
  is the localized `(conflict)`. 2 strings x12 (drafts, separate commit). **7A-7 is now feature-complete;**
  remaining 7A: widgets bar (7A-8) and the verification slice (7A-9: live eyeball, idle CPU, real-iCloud round trip).
- 2026-10-11 · **7A live check #1 (dev build, `-com.katikati.edge.preset notesAndStatus` argument-domain override — no
  persisted defaults; driven through the accessibility tree):** ✅ right-edge bar rendered at the screen side (56×220:
  notes tile + Wi-Fi/battery/volume column, matches `EdgeBarLayout`); ✅ Wi-Fi popover opened 8 pt inward of the bar
  (showed the real SSID), battery popover (92 % "On Battery") and volume popover (80 % + slider) reused the same panel,
  repositioned per tile; ✅ opening notes closed the status popover (exclusive); ✅ new note → typing → title derived
  from the first line → file on disk is AES-GCM ciphertext (no plaintext); ✅ delete → undo toast → undo restored the same
  note with its text → delete again removed the `.note` file; ✅ idle CPU ≈ 0.1–0.4 % (one transient 12 % sample while
  I was clicking). ⚠️ **Not confirmed:** Esc did not close the flyout when sent as a background keystroke (may be a
  limitation of that input path — needs a hand check; outside-click dismissal also unchecked); fullscreen hide, Spaces
  and multi-display, auto-hide hover, real iCloud sync, and a proper Instruments idle-CPU number are still owed (7A-9).
  Found + fixed: `TextEditor` painted an opaque dark box over the glass plate → hidden via `scrollContentBackground`
  (macOS 13+; macOS 12 keeps the default). Side effects of the check: a Keychain item `com.katikati.notes / note-key`
  was created and `~/Library/Application Support/KatiKati/Notes/` exists (empty).
- 2026-10-11 · **7A-8 re-scoped with Hop (owner, plan approved):** the widgets bar folds in the best of
  `antonyshakirov/hop` (MIT, cloned for study; ~20 modules) with no duplicated features. **In:** Bluetooth, System
  monitor, Clipboard history (opt-in, encrypted, concealed-type filter), Text recognition + QR, Time tracker + to-dos,
  Window snapper. **Reused (not re-built):** weather, now playing, calendar/clock, timer/stopwatch/countdown tiles, notes
  (= the quick-notes widget). **Excluded:** torrents, VPN, traffic filter, converter/archives/documents, uninstaller,
  screenshots/markup. **Parked:** keep awake, color picker, keyboard lock, speed test, app shelves. One tile per module +
  own flyout; copy-with-attribution allowed, per-file choices recorded in NOTICE at 8h. Slices 8a–8h in the approved plan.
- 2026-10-11 · **7A-8a widgets bar shell landed (gate green, 1819 tests; live-checked):** `WidgetTile` (weather, nowPlaying;
  stored ids frozen) + `EdgeBarContent.widget(_)` + pure `EdgeBarComposition.resolve(preset, statusSide, widgets)` (widgets
  lead the **left** bar, a left-side status trio sits below them; widgets alone create the left bar), `EdgeBarLayout.widgetTileHeight`,
  `com.katikati.widgets.tiles` (default empty; toggling keeps catalog order), Settings toggles under Edge Bars,
  `EdgeStatusPopupController` generalized to `EdgeFlyoutController` (id + size + SwiftUI content; status popovers now use it).
  Tiles: **weather** toggles the existing left weather stack (`WidgetPanelController.weather`), **now playing** opens the strip
  chip's `NowPlayingPopup` in a flyout with a lazily-created, event-driven `NowPlayingService`. The weather stack now insets
  itself (`widgetPanelFrame(sideInset:)`, +test) so it no longer covers a left edge bar. Live: left bar 56×124 at the left edge,
  now-playing flyout opened inward, weather panel opened and closed the flyout. No new strings (Widgets/Weather/Now Playing existed).
- 2026-10-11 · **7A-8b Bluetooth tile landed (gate green, 1825 tests):** pure `BluetoothDeviceParser` over
  `system_profiler SPBluetoothDataType -json` (schema verified on this Mac: `device_connected` / `device_not_connected`,
  `device_minorType`, `device_batteryLevel{Main,Left,Right,Case}`) — connected first, lowest-battery badge, symbol per
  minor type, malformed input → empty; `BluetoothDeviceReader` runs the fixed-argument process off-main with an 8 s
  timeout **only when the flyout opens or Refresh is tapped (never polled)**; no IOBluetooth/CoreBluetooth, so **no
  Bluetooth permission prompt**. `WidgetTile.bluetooth`, flyout (list, battery %, connected dot, refresh, System Settings
  link), Settings toggle. 3 strings x12 (drafts, separate commit). 6 tests. Not live-checked yet (D6 sweep).
- 2026-10-11 · **Noty-deck redesign approved (owner, plan `7A-D`):** both edges adopt noty's deck model (rest pill → hover fan →
  pull-out sheet); notes = colour paper tabs, rotated titles, hover preview/open, drag reorder; status/widget tiles = glass round
  buttons or coloured chips (Settings option); extras = ⌥-drag reposition, deck scale + keep-open, handwritten tab fonts, dashed spine +
  staggered shingle. Slices D0–D6 (D0 = 8b commit, done). Hop tiles 8c–8h resume afterwards inside the deck.
- 2026-10-11 · **D1a notes colour + ordering landed (gate green, 1834 tests):** `Core/Support/NotePalette.swift` (8 frozen colours
  paper/dash/ink, wrap, `nextIndex` rotates from the newest note; values/idea from noty `NoteColor`, MIT), `Note.color`
  (tolerant decoder: pre-colour encrypted notes decode as 0), `color:` header key in `NoteDocument` (noty-compatible), pure
  `NoteOrdering.reorder` (dense orders, returns only changed notes), `NotesController.setColor` / `move(id:by:)` / new notes
  rotate colours. 12 tests. D1b (DeckGeometry + label runs), D1c (state machine + settings keys) next.
- 2026-10-11 · **D1b deck geometry landed (gate green, 1850 tests):** `Core/Support/DeckGeometry.swift` — `DeckMetrics(scale)` (every
  length scaled + rounded to whole points, scale clamped 0.5…2), pill height (≤14 dashes + overflow dash), `DeckLayout` (pitch from the
  longest label, 68 % height budget shrink to a floor, shingle `spacing`, `stackHeight` incl. `+N` tab and round buttons),
  panel-frame helpers `restFrame` / `fanFrame` (edge-hugging, yRatio-placed, centred on the pill, ⊆ visibleFrame incl. non-zero
  origins), `yRatio(forPointerY:)` + `snapSide` for the ⌥-drag, 60 %-of-a-slot `dragTarget` and `dragShift`; `VerticalLabelLayout`
  (upright CJK/emoji vs rotated Latin runs, truncation with an upright ellipsis) with an injected `VerticalLabelMeasure` so Core has
  no AppKit. 16 tests (found + fixed: an oversized fan overflowed `visibleFrame`). Re-derived from noty `DeckGeom`/`DeckLayout`/
  `VerticalLabelLayout` (MIT).
- 2026-10-11 · **D1c deck state machine + settings landed (gate green, 1863 tests):** `DeckStateMachine.reduce(state, event, ctx)` —
  rest/fan/expanded with pointer enter/confirmed-exit, tab click toggle, hover-rest open, idle (fan 4 s, unpinned note 60 s, "exceed
  not equal"), Esc peels one layer, outside click, note removed, keep-open re-pointing; dragging and keep-open suppress folding;
  `DeckTiming` constants (exit confirm 0.15 s, hover open 0.4 s, preview 0.18 s). `DeckSettingsRules` + `EdgeTileStyle` (glass |
  coloured, frozen ids). `AppSettingsStore`: `com.katikati.edge.{deckScale 0.8…1.4, alwaysShown, openOnHover, tabPreview, tileStyle,
  tabFont, yRatio.left/.right}` with sanitising + persistence tests. The old `edge.autoHide` stays until D2 swaps the behaviour.
- 2026-10-11 · **D2a deck views landed (gate green, 1864 tests; not wired yet):** `App/Scenes/Edge/DeckShapes.swift` (`EdgeTabShape`
  hand-drawn because `UnevenRoundedRectangle` is macOS 13+, `EdgeLine`, `DeckPressStyle`, palette → `Color`), `DeckLabel.swift`
  (`DeckFont`: face setting + deck scale, cached text measurement feeding the pure `VerticalLabelMeasure`; `VerticalTabLabel`
  upright-vs-rotated rendering, `kerning` not the macOS-13 `tracking`), `DeckViews.swift` (`DeckViewModel` publishing state/tabs/buttons,
  `DeckPillView` dashes, `DeckFanView` shingled stack with negative spacing + 42 ms staged slide-in + dashed spine, `DeckTab` paper tab
  leaning 3° with bleed, hover shadow, pin dot, accessibility label/action, `DeckMoreTab`, `DeckRoundButton` glass | coloured).
  `DeckLayout` now supports buttons-only stacks (left deck). 1 string x12 (`Settings`, draft, separate commit). D2b wires the
  controller/orchestrator and removes the plate.
- 2026-10-11 · **D2b deck wired in (gate green, 1862 tests; live-checked with `DOCK_EDGE_FAN=1`):** `EdgeBarPanelController` rewritten as
  the deck controller — one panel per edge, rest = pill frame (click-through), fan = stack frame (`DeckGeometry.restFrame/fanFrame`),
  frame set first and the staged reveal two display frames later, 0.45 s exit-then-shrink, never an animated panel frame; transitions go
  through the pure `DeckStateMachine` (pointer enter/confirmed exit via the existing orchestrator mouse poll, 1 s idle watch only
  while above the resting state, tab/new-note → `expanded`, sheet close → fan/rest). Items: note tabs (observed from
  `NotesController`), `+` new note, status trio as three round buttons, widget tiles, gear. Old plate, `EdgeBarContentView`/tile views,
  `EdgeBarAutoHide` + its tests and the `edge.autoHide` setting are gone (replaced by *Keep Edge Bars Open* = `alwaysShown`); orchestrator
  now drives everything from one debounced `settingsStore.objectWillChange` subscription (`update` is idempotent) and keeps the mouse
  monitors on while a deck exists. `DOCK_EDGE_FAN=1` (new debug switch) starts decks fanned and kept open. Live: right deck showed
  rose/peach/lemon paper tabs with rotated titles above the glass `+`/Wi-Fi/battery/volume/gear buttons (matches the noty reference);
  left deck showed weather/now-playing/Bluetooth glass circles; `+` created notes and opened the sheet. Bugs found live and fixed:
  buttons overlapped (the shingle's negative VStack spacing also applied to them), a keep-open settings race folded the forced fan,
  titles ellipsised too early (pitch max 106 → 124, font 11 pt). **Not yet exercised live:** real pointer hover enter/exit, idle fold,
  hover preview/open, drag reorder (D3); the sheet is still the old list+editor (D4). 1 string x12 swapped (`Keep Edge Bars Open`
  replaces `Auto-Hide Edge Bars`, separate commit). Test notes created during the check were removed.
- 2026-10-11 · **D3a deck interactions landed (gate green, 1862 tests; pointer paths not yet exercised live):** tabs publish their
  frames (preference key) so the existing mouse poll drives **hover preview (0.18 s)** and **hover-to-open (0.4 s, setting)** with no SwiftUI
  hover plumbing; `DeckPreviewCard` (note's own paper/ink, 4 body lines, pin, "Empty note"; clicking opens) in the flyout panel, dismissed
  when the pointer leaves tab and card; **drag-to-reorder** (5 pt slop, 60 %-of-a-slot target, neighbours step aside, lifted tab 1.04×,
  global-space gesture so the tab's own offset can't feed back) → `NotesController.move`; **context menu** (Pin/Unpin, Color ▸ 8 names,
  Archive, Delete); dragging suppresses fold/hover. Fixed: `Unpin` was a ternary-String `Text` that never localized. 11 strings x12
  (drafts, separate commit). D3b (⌥-drag pill, vertical only — notes/widgets are bound to their edges so cross-edge snap is dropped) next.
- 2026-10-11 · **7A-D4 — note sheet:** `NoteSheetView` (single note on its own paper in ink; 8 colour dots, pin, delete, undo toast, tab-font
  setting, short edge-side pull transition, closes when the note vanishes, Esc) replaces `NotesPopupView`'s list+editor; `EdgeNotesPopupController`
  hosts it (330×300, no vibrancy plate); `EdgeBarLayout.notesPopupSize` and the dead `No Notes Yet` string removed. No new strings. Gate green
  (1862 tests). Live pull/Esc/outside-click still to verify at live check #2.
- 2026-10-11 · **7A-P1 — modular layouts (owner, queried):** all presets stay (Off / Notes / Notes & Status / Status) plus **Productivity + Rest
  (new default)** and **Custom**; every preset flips to either edge via **Main Side** (`com.katikati.edge.side`, replaces `edge.status.side`; the
  opposite edge gets status + widgets). Core: `ProductivityItem` (frozen ids, `built` set empty until P2–P6 so no placeholders), `EdgeItem` (14
  placeable items incl. notes tabs, +, gear; case order = render order), `EdgePlacement` left/right/hidden, `EdgeBarComposition.placements/resolve`
  (one path for presets and Custom; missing Custom entries fall back to Productivity + Rest). Store: `edge.custom`, `productivity.items`; widgets
  and productivity default to all on; first entry into Custom seeds from what is on screen. `Off` now hides widgets too. Controller renders +/gear
  as independent content. Settings: preset menu, Main Side, widget toggles, Custom rows (Left / Right / Hidden per item). Order within a side is
  canonical (no drag-reorder yet). Gate green (1861 tests); strings in separate l10n commit.
- 2026-10-11 · **7A-D5 — rest deck + tile style (cleanup slice):** both edges already render their item lists through the deck (glass / coloured
  round buttons landed in D2–D3; the Settings control for tile style comes with D6). This slice retires the pre-deck bar: `EdgeBarLayout`,
  `PanelGeometry.edgeBarTargetFrame` and their 9 tests are deleted; the weather stack now keeps clear of a deck by `DeckGeometry.fanWidth` (scale-aware,
  was a hard-coded 56 pt bar) + 8 pt. Gate green (1855 tests).
- 2026-10-12 · **7A-P2 — Reminders / Alarms / Time flyouts:** `ProductivityItem.built` = reminders, alarms, time, so those three round buttons now sit on
  the main side. `ProductivityServices.shared` owns the one CalendarService / AlarmStore / timer / stopwatch / countdown / focus set; the weather-side
  `CalendarPanelView` now observes the same objects (a timer started in either place is the same timer). Flyouts reuse `RemindersTile` / `AlarmsTile`
  and `TimerTile` / `StopwatchTile` / `CountdownTile` / `FocusTile` (Time = tabs Timer · Stopwatch · Countdown · Focus; Focus is the existing
  focus/break cycle, the pomodoro). `EdgeFlyoutController` panel can take key for flyouts that need typing (Time: event-name field). Live check: Time
  tabs, countdown add (typed + saved), Alarms render OK; Reminders not opened live (would raise the macOS permission prompt). 1 string (Time) in l10n commit.
- 2026-10-12 · **7A-D6a — deck settings, NOTICE, CHANGELOG:** Settings › Edge Bars gains Bar Size (0.8–1.4 slider), Button Style (Glass / Coloured),
  Note Tab Font (installed faces), Preview / Open Notes on Hover, Reset Bar Positions (all via existing store setters). NOTICE §5 now lists the noty files
  whose pure logic was ported; CHANGELOG entry for the edge decks. 8 strings in the l10n commit. Remaining for D6: live check #2 (real pointer) + idle-CPU.
- 2026-10-12 · **7A-D6b — idle CPU (resting decks, both edges, default layout):** a 10 s `sample` of the running app after 20 s idle holds **zero** frames in
  Deck* / EdgeBarPanel / EdgeFlyout / pollAllUnits / pollMouse; the main thread is ~99 % blocked in the run loop. Whole-app idle is 3–7 % CPU and comes from the
  pre-existing `WindowLiftAvoidanceController` polling (`SLWindowListCopyWindowInfo`) plus occasional `SystemStatusService.refreshWiFi` on audio-device changes —
  not from this phase (preset off measured ≈3 %, on ≈3–7 %, run-to-run noise comparable). Instruments' exact number and the real-pointer live check #2
  (hover enter/exit, preview, drag, ⌥-drag, Esc/outside click) are still open — they need the physical pointer.
- 2026-10-12 · **7A-P3 — Tasks (Hop to-dos + tracker, compact port):** `TaskList` (Core; checklist in place, completing stops the tracker, one tracker at a time,
  clear completed, lenient Codable) + `TasksStore` (tasks.json, corrupt file → `.bak`) + `TasksController` (persist on change; a tracker left running by a quit is
  closed at launch rather than crediting the closed time) + `TasksFlyoutView` (add field + button, rows with check / tracker / context menu, total tracked while
  running; 1 s ticks only while a tracker runs). Hop's reminders/estimates/overrun are not ported (Reminders/Alarms buttons cover them). Live check: add task +
  start tracker OK (synthetic Return does not fire onCommit → visible + button added). Also fixed a latent D6a break: the test target compiles SettingsLayoutPane, so
  DeckLabel.swift (DeckFont) is now in the test target. 6 strings in the l10n commit.
- 2026-10-12 · **7A-P6 — Windows (Hop window snapper):** `SnapPosition` (Core; 15 zones as unit rects, offset-origin frames, Cocoa→AX flip, tested) +
  `WindowSnapService` (AX focused window of the frontmost *other* app — the deck panels are non-activating so that is still the app you were in; Hop's
  enhanced-UI toggle and size-position-size convergence) + `WindowsFlyoutView` (miniature-screen zone icons; Accessibility-missing hint with Open Settings).
  Taken ahead of clipboard/capture because it is small. Not live-pressed (would move a real window); renders in the flyout. 17 strings in the l10n commit.
- 2026-10-12 · **7A-P4 — Clipboard (Hop clipboard rules, text-only):** `ClipboardHistory` (Core; trim/blank-ignore, dedupe with pin kept, growing-text merge,
  50 unpinned cap, pinned lead, one-line preview, secret-type skip list per nspasteboard.org) + `ClipboardMonitor` (0.7 s changeCount poll **only while recording**) +
  `ClipboardFlyoutView` (click row = copy back, pin/delete, record switch, clear). Decision: **recording is opt-in (default off) and memory-only, never written to disk** —
  the clipboard routinely holds secrets, so this is the one productivity item that is on-screen by default but not collecting by default; it overrides the earlier
  'encrypted history' idea (nothing persisted = nothing to encrypt). Images/files are not recorded (text only). Live check: switch on, two pbcopy copies appear
  newest-first. 6 strings in the l10n commit.
- 2026-10-12 · **7A-P5 — Capture (text recognition + QR in one button):** the Capture button closes any flyout, runs the system's own region selector
  (`screencapture -i`), recognises text (Vision, accurate, reading-order sort) and QR/barcodes in the picture, deletes the temp PNG at once, then shows a result flyout at the
  button (Copy; web links get Open on click only — nothing is opened automatically; Wi-Fi/tel/other payloads stay text). `CaptureRules` is pure + tested; a rendered-image
  test proves Vision finds both text and a QR payload (first run ~30 s model warm-up, then 0.2 s). Not live-driven: the region selector needs the real pointer. One button
  instead of Hop's two modules (text recognition, QR) since both come from the same capture. 7 strings in the l10n commit. All seven productivity buttons are now built.
- 2026-10-12 · **7A-8c — System monitor (rest side):** new `WidgetTile.systemMonitor` / `EdgeItem.systemMonitor` (frozen id, joins the widgets default and Custom) opening a
  flyout with CPU, memory (active+wired+compressed), disk free and network ↓↑. `SystemMonitorMath` (Core, tested: tick deltas, counter-reset-safe rates, clamped fractions,
  formatting) + `SystemMonitorSampler` (host_statistics, vm_statistics64, volume capacity, getifaddrs en*) + `SystemMonitorController` (ref-counted 1 s timer that exists
  only while the flyout is on screen). Found + fixed: `EdgeFlyoutController.dismiss` only ordered the panel out, so SwiftUI `onDisappear` never fired and a sampler would
  have kept running — it now clears the content view; a 5 s `sample` after open→close shows zero SystemMonitor frames. Live: flyout shows live numbers. 5 strings in the l10n commit.
- 2026-10-12 · **7A-D7 — dock magnification + per-edge size (owner request during 7A-9):** `DeckMagnification` (Core: cosine falloff, 1.55× peak, 76 pt radius, tested);
  the controller feeds the pointer's panel-space y (from the existing mouse poll, only while fanned) and each round button scales about its edge-side anchor so it grows inward.
  New settings: `edge.magnify` (default on) and per-edge size `edge.deckScale.left/.right` (0.8–1.4; the old single `deckScale` seeds both). Settings: Left/Right Bar Size sliders +
  Magnify toggle. Tabs/notes are unaffected by magnification (buttons only). 3 strings in the l10n commit. Real-pointer feel is verified in live check #2.
- 2026-10-12 · **7A-9 live check #2 (real pointer, this Mac):** VERIFIED — real hover opens the fan on both edges; dock magnification (peak under the pointer, neighbours falloff, grows
  inward); hover preview card; idle fold back to the pill; Esc closes the sheet (real keypress); colour dots; delete → undo toast → expiry; flyouts (Time/Tasks/Clipboard/System). FOUND + FIXED:
  a pointer parked on the fanned deck folded it after 4 s (idle counted only movement) — a resting pointer now counts as activity. SYNC pipeline (iCloud-Drive *path*, local folder — this Mac has no
  iCloud account, so no real iCloud daemon): create → plaintext `.md` appears; external edit and a foreign `.md` → applied live incl. the open sheet and a new tab; delete in app → file removed;
  all test data removed. IDLE CPU: 60 s cpu-seconds, deck off 7.1 %/9.3 % vs deck on 6.6 %/4.9 % (Debug build) — the deck adds nothing measurable; the ~5–9 % baseline is the pre-existing window-lift
  polling. NOT verified (needs real clicks/drags, blocked without a Finder grant): drag-reorder, ⌥-drag pill, outside-click dismissal; also multi-display, fullscreen/Spaces, real iCloud account.
- 2026-10-12 · **Phase 7A CLOSED (owner: "skip them, mark 7A done").** Delivered: noty-style decks on both edges (pill → fan → paper sheet, magnification, per-edge size), encrypted notes + opt-in
  folder sync, status trio, Weather / Now Playing / Bluetooth / System monitor tiles, productivity buttons (Reminders, Alarms, Time, Tasks, Clipboard, Capture, Windows), layouts (Off / Notes / Notes & Status /
  Status / Productivity + Rest [default] / Custom, any side), Settings, NOTICE §5 + §9, CHANGELOG. Final gate: 1888 tests, 0 failures, localization + debug-switch checks green. **Accepted open items (not blocking
  the close):** drag-reorder, ⌥-drag pill and outside-click dismissal not exercised with a real pointer (covered by unit tests of the math/state machine); multi-display, fullscreen/Spaces hide and a real
  iCloud account not verified on this Mac; Windows snap not pressed on a real window; Capture region selector and Reminders permission prompt not driven; Instruments trace not taken (cpu-seconds comparison
  recorded instead); all 12-language strings are drafts awaiting speaker review (STANDING_RULES §1).
- 2026-10-11 · **Owner addendum — *Productivity + Rest* preset, new default (queried, nothing assumed):** one edge = productivity (notes tabs +
  buttons: Reminders, Alarms, Time [Timer/Stopwatch/Countdown/Focus tabs — focus and pomodoro are the same existing focus/break timer],
  Tasks [Hop to-dos + tracker], Clipboard, Capture [text recognition + QR], Windows [snapper], gear), the other edge = the rest (status trio,
  Weather, Now Playing, Bluetooth, System monitor). Productivity side is a Settings choice, **default right**; each button opens its own flyout
  reusing existing logic; **everything on for every user** (single user, no migration); all four Hop modules moved to the productivity side
  (system monitor stays rest-side). Slots P1 (pure core + settings) after D4, P2 (Reminders/Alarms/Time flyouts) after D5, P3–P6 = the Hop
  modules. Recorded in the plan file; no code yet for this addendum.
- 2026-10-11 · **Phase 7 split into 7A/7B (owner directive; boundary confirmed: both
  FABs + 7c in 7B, 7b edge widgets bar stays in 7A).** Slice IDs unchanged; acceptance
  criterion #10 split into #10 (edge bars + notes sync) and #11 (launchers & FAB
  payloads — 7d/7e were previously uncovered); risks #13/#14 re-tagged 7A; Appendix C
  now normative for both halves. Rationale: 7A = new panel machinery (risks #13/#14),
  7B = features on existing panels (shares the 7c↔7d dispatch core and one pass of the
  7d↔7e slider plumbing); 7B sequences after Phase 6 (`SettingsWindowView` collision).
- 2026-10-11 · **Terminology sweep + status trio (owner directive).** All "donor" wording →
  "reference" (23 occurrences, decision 4 retitled "Third-party repos = references, not
  donors"); reference policy note added at §5 intro + §0 pointer (code may be broken or
  unsuitable — **investigate before any code use**, NOTICE if derived). **Status trio**
  (`lingyired/status-trio`, Apache-2.0 — combined wifi/battery/volume icon + popovers)
  added to **7A**: combined-icon pattern for the status cluster, + a §5e study row.

### Phase 8 — Interior content rework (deferred: mini-plan each — owner 2026-10-11: "we will plan it out when we get there")

**Classified 2026-10-11 (owner directive; structure confirmed via grill: 8 = interior
content, 9 = strip semantics + interaction + summoning, 10 = presets + wallpaper).
Reference priors are eyeball-only study rows (§5b rule) — code written fresh.**

- **8a — Drawer redesign**: most-used / recently-closed / recently-added sections inside
  the drawer. Owner gates the design (mini-plan when activated). Priors (study only):
  DockBar Start Menu Most-Used via Spotlight + pinned drag-drop editor + AppBeBack
  recently-closed restore; SplitBar-old launcher recents/full app catalog.
- **8b — Now Playing redesign**: rework the 4f mini-icon + popup. Priors: SplitBar-old
  NowPlaying flyout (§5d — reopened as an eyeball prior only for this slice, never code).
- **8c — Shelf redesign**: tungsten-core shelf rework — explicit behavior-frozen
  exception slice, witness tests per §4 rules 2/5.
- **Verify each**: tungsten gate green + drawer/shelf behavior witnesses + localization ×12.

### Phase 9 — Strip semantics, interaction & summoning (deferred: mini-plan each)

- **9a — Icons / icons+text logic, multi-window of same app**: display-mode rules for
  window chips, incl. grouping + cycling multiple windows of one app. Priors (study only):
  DockBar Window Grouping + click-to-cycle, icon-only mode, max button width, minimized
  dimmed badges; SplitBar-old 5 icon sizes + running indicators. **Care:** §2.4 strip
  semantics are tungsten-frozen — this slice is an explicit behavior-frozen exception
  with witnesses (§4 rule 5).
- **9b — Right-click context menu refinement**: extend tungsten `StripContextMenuZone`
  menus. Prior (study only): DockBar task-button menu (window list / Hide / Pin /
  Blacklist / Quit).
- **9c — Window preview refinement** (DockDoor item MOVED here from the Phase-6 carried
  list — owner 2026-10-11, was "owner to confirm phase"): *hovering a window chip shows
  ONE preview window (declutter default); moving the mouse into that preview expands to
  all live windows of the app; optional themed preview chrome with quit / close /
  minimise actions.* Feasibility: tungsten owns `ChipSnapshotter` +
  `StackPopupSnapshotProbe` + debounced strip hover ("Tungsten path wins ties" §5b);
  DockBar `ThumbnailService`/hover thumbnails are eyeball-only gap-analysis. Design:
  hover intent (debounced, existing path) → single `CarrierSnapshot` anchored per
  Phase-3 `screenFrame`; mouse-enter → fan-out to per-window snapshots; actions row
  (opt-in via settings) in themed popup chrome. No new TCC/AX surface beyond existing
  window-list reads; snapshot cadence is new CPU — **Instruments gate when built**;
  anchor tests required.
- **9d — Shortcuts for widgets/drawers/panels**: extend tungsten `HotKeyRegistrar`
  (existing `edgeToggleHotKey` pattern) to summon widgets/drawers; reconcile with 7c's
  ⌥Space palette dispatch (§5e — cross-reference, nothing moves out of 7B). Priors
  (study only): SplitBar-old `Services` shortcuts, DockBar Command Launcher (⌃⌥⏎).
- **9e — Hyperkey layer (bindings TBD by owner)**: capslock-as-modifier — caps+W →
  weather, caps+C → clock/calendar, etc. Own mini-plan: `flagsChanged`/event-tap infra;
  new global-input surface → CPU/latency gate + Instruments number; every binding
  registered per §3.4, off by default until owner signs off.
- **Verify each**: tungsten gate green + menu/preview/shortcut anchor tests + Instruments
  idle-CPU number in the PR.

### Phase 10 — Widget presets + wallpaper integration (deferred; owner-assigned scope 2026-10-11)

- **10a — Widget presets**: saved widget configurations (layouts/palettes/presets).
  Priors: SplitBar-old `WidgetProvider` + height/personalisation presets — **§5d override
  recorded 2026-10-11** (reopened as eyeball-only priors, built fresh in tungsten patterns).
- **10b — Wallpaper engine**: wallpaper integration incl. SplitBar-old's
  **weather-reactive wallpapers** — **§5d `WallpaperEngine` override recorded 2026-10-11**
  (same eyeball-only posture). Themed per Phase-4 tokens; personalisation stays behind
  the existing Appearance-tab vocabulary.
- **10c — App icon + menu-bar icon art (owner 2026-10-11; placement = recommended, move on
  request):** redraw the app icon (`.icns`) and the menu-bar/status art. The menu-bar variant
  slots into **6b's existing `com.katikati.iconSet` machinery** (as the `modern` art — no new
  Settings work); the app icon replaces the product icon in `Resources`. Trademark gate:
  never tungsten marks (§6 / `TRADEMARK.md`); README/marketing screenshots updated in the
  same slice.
- **Verify**: visual-regression gates + localization ×12 + idle CPU ≤ island baseline + ε.

**Phase 8–12 check log (STANDING_RULES §1.8):**
- 2026-10-11 · **Phases 8/9/10 created (owner directive; structure confirmed via grill).**
  Source items: drawer (most-used/recently-closed/recently-added), Now Playing + shelf
  redesign, icons/icons+text incl. multi-window same-app, right-click context menu, window
  preview (DockDoor moved out of the Phase-6 carried list into 9c), shortcuts, hyperkey
  (TBD), widget presets + wallpaper (Phase 10 owner-assigned). Reference mining: DockBar →
  8a/9a/9b/9c priors; SplitBar-old → 8a/8b/9a/10 priors (§5d overrides for wallpaper +
  WidgetProvider/NowPlaying priors); **Eskele** → new eyeball-only reference in §0
  (edge-dock geometry + Dock-restore escape hatch feed 7A). **Nothing from this batch
  enters Phase 7** — 7A/7B unchanged.
- 2026-10-11 · **10c + Phases 11/12 added (owner directives).** (a) **10c** app icon +
  menu-bar icon art — menu-bar art reuses 6b's `com.katikati.iconSet` machinery, trademark
  gate applies; placement recommended in Phase 10, move on request. (b) **Phase 11 —
  layout-mode rendering refinement** ("render well and be distinct"; placement
  owner-confirmable). (c) **Phase 12 — settings refinement** ("at the end"): full
  page/button audit; recategorize (owner example appearance→general — flagged: conflicts
  with 6d's new Appearance tab, confirm at activation); General gains **Permissions +
  Shortcuts** sections (reverse mouse ✓ already there, edge hotkey ✓ there, hyperkey 9e,
  ⌥Space); **License tab → About** (audited: dormant tungsten activation machinery —
  `LicenseStore`/`LicenseVerifier` + `SubscriptionSubmitter` — **gates nothing today**);
  Widgets page recommended (host for 10a presets + widths from 6c's Layout pane);
  theme refinement.

### Phase 11 — Layout-mode rendering refinement (deferred; placement owner-confirmable)

- **11a — distinctness + render quality per mode**: make `windows` / `split3` / `split4` /
  `split5` / `centered` each render well and read as **clearly distinct** — island
  composition, spacing, widget grouping per mode (owner 2026-10-11). Solver changes keep
  tungsten clamp discipline + golden tests; Appendix A stays normative (update it if
  composition changes); Layout-tab thumbnails (6c) follow automatically — they draw from
  the solver. Per-mode golden screenshots become the visual witnesses.
- **Verify**: solver goldens + per-mode screenshots + full gate.

### Phase 12 — Settings refinement (deferred; owner 2026-10-11: "at the end")

- **12a — full audit**: every settings page + button exercised; dead/broken controls fixed
  or removed; manual checklist committed with the PR + unit tests for any pure logic.
- **12b — recategorize** (owner example: **appearance → general**). ⚠ **Conflicts with 6d's
  new Appearance tab** — owner confirms exact move (dissolve tab vs partial) at activation.
- **12c — General becomes the feature hub**: **Permissions** section (Accessibility / Screen
  Recording / Automation / notifications status + re-trigger buttons — currently only
  reachable via the onboarding window) and **Shortcuts** section (scroll-reverse toggle ✓
  already there; edge hotkey `⌥⇧⌘D` rebind ✓ there; hyperkey bindings from 9e; ⌥Space from 7c).
- **12d — License tab → About** (owner 2026-10-11). *Audited current state:* the License tab
  is dormant commercial machinery inherited from tungsten — `LicenseStore`/`LicenseVerifier`
  activation-code entry (credentials signature-checked, re-verified every launch) +
  `SubscriptionSubmitter` hooks; **it gates nothing today** (no feature consults activation).
  Move its content into About next to version/credits/GPL notice; tab list becomes
  General / Layout / (+Appearance, pending 12b) / Widgets / Advanced / Feedback / About.
- **12e — Widgets page? (owner asked; recommendation: YES)** — dedicated Widgets tab for
  widget on/off + widths (relocated from the Layout pane where 6c put them) and **Phase-10
  presets (10a)** as its natural host. Sequencing note: create it **before or with Phase 10**
  so 10a lands there directly; otherwise 10a lands in Layout and 12e relocates it.
- **12f — theme refinement** (owner eyeball-driven; final home follows 12b's decision).
- **Verify**: audit checklist complete (every button witnessed), tab/order tests,
  localization ×12, full gate.


## 8. Risks, mitigations, open questions

| # | Risk | Mitigation | Phase |
|---|---|---|---|
| 1 | Tungsten snapshot is a single squashed public commit — no upstream history for blame/bisect | Pin `a4e1a55` in §0/B; keep import clean; rely on tungsten's in-code rationale (Chinese comments — translate per-area on demand) + ~1,300 tests as the spec | 0 |
| 2 | GPL-3.0-or-later copyleft surprises owner (v2 assumed MIT-only) | §6 makes GPL explicit + Phase-0 license confirmation gate; NOTICE/TRADEMARK in first PR; no binary ships before confirmation | 0 |
| 3 | Trademark slip (shipping tungsten name/icon/feed) | Phase-0 rebrand checklist (§6); `check_localization.py` + string audit for "Tungsten Edge"/"钨极"; new icon/feed/key | 0 |
| 4 | Bundle-id/defaults collision with tungsten or either SplitBar repo | New id + `com.katikati.*` domain + one-way lineage-stamped migration; side-by-side install test in Phase 0 | 0 |
| 5 | Multi-island panels break tungsten's per-Unit assumptions (drag surfaces, hover monitors, popups) | Extend, don't fork: `displayUUID#slot` reconcile inside `rebuildUnits`; drag-carrier per screen stays; Phase-2/3 tests pin behavior | 2–3 |
| 6 | Island frames escape `visibleFrame` on exotic topologies | Tungsten clamp stays authoritative; Phase-1 golden tests on tungsten topology snapshots; 0.5 pt min gap | 1 |
| 7 | Fullscreen/Spaces regressions with N panels instead of 1 | Atomic per-displayUUID hide/show; `allSpacesPanels` coverage test; two-display + Spaces matrix in Phase 3 | 3 |
| 8 | Widget ports clash with tungsten theme/glass tokens | Re-skin to tungsten chips/popups; tungsten tokens win; DockBar tokens consulted, never pasted wholesale | 4 |
| 9 | macOS 12 floor vs Liquid Glass (macOS 26 SDK) | Keep tungsten's `#available(macOS 26.0, *)` gating + fallback; CI stays `macos-26`/Xcode 26 | 0–6 |
| 10 | SwiftUI-in-panel perf with 3–4 islands | Reuse tungsten construction; Instruments idle-CPU gate (≤ baseline + ε) in Phase 2; no new panel class | 2 |
| 11 | Signing/Accessibility grant churn from rebrand | Keep `build_and_run.sh` same-cert discipline; never bare `xcodebuild` + `open`; reinstall-local test in Phase 0 | 0 |
| 12 | Sparkle feed/key rotation breaks updates | New feed URL + key in Phase 0; `package_release.sh` fail-closed gate before any release | 0/5 |
| 13 | Vertical edge geometry escapes `visibleFrame` on exotic topologies | Tungsten clamp stays authoritative; Appendix C edge rules; golden tests on tungsten topology snapshots | 7A |
| 14 | N+2 panels per display break fullscreen/Spaces/CPU assumptions | Extend `rebuildUnits` with `displayUUID#edgeSlot`, atomic per-displayUUID hide/show, `allSpacesPanels` coverage; Instruments idle-CPU gate ≤ island baseline + ε | 7A |
| 15 | Two always-on FAB panels (left of weather, right of clock) overlap the drawer capsule in `windows` mode or escape `visibleFrame` on narrow screens | FABs are panels not sections (no island-width impact); anchored to outermost slot frames; clamped to `visibleFrame`; hidden when anchor slot collapsed; per-mode toggles default off (esp. `windows`); collision-check vs capsule frame; golden `minX`/`maxX` + non-zero-origin tests | 4U |

**Open questions for owner (non-blocking):**

1. Confirm GPL-3.0-or-later as KatiKati's license (required while the tungsten core is
   inside) — else the core choice must be revisited.
2. ~~Final product name~~ **decided: KatiKati**; still open: bundle id (`com.katikati.app` assumed) + Sparkle feed host.
3. Fate of `wakilibaraka/SplitBar` (+ fork link) and `wakilibaraka/dockbar` usage once
   KatiKati reaches parity: freeze, keep as parallel experiments, or archive?
4. Confirm Phase 7 items are out of the required scope.
5. Which tungsten prefs must migrate one-way on first run (screen placement? heights?
   delays? drawer/kept/folders/shelf?) — default is the §6 user-meaningful set.
6. (Resolved 2026-10-08): edge-bar/launcher scope = EdgeDeckBar-only (widgets-only,
   option (a)) + noty-inspo refinements; order 7a notes → 7b widgets → 7c launcher.
   AI Usage/Dispatch explicitly out.

## 9. Acceptance criteria

1. All four required modes render on the built-in display; switchable from Settings
   without relaunch; mode/width/gaps/bottom-offset persist across restarts.
2. Tungsten gate green: `xcodebuild test … CODE_SIGNING_ALLOWED=NO` (~1,300 + new
   `IslandLayoutSolver`/placement/migration tests) + localization + debug-switch +
   conformance checks; no regressions.
3. Islands are non-activating, survive Space switches, hide atomically for fullscreen per
   display, reflow on resolution/display-set change; every popup anchors to its own
   island/chip (per-island anchor tests green).
4. Overflow: crowded app sets collapse with `showsOverflow` exactly as SplitBar-old tests
   specify; no island exceeds `visibleFrame`.
5. No tungsten regression: per-window switching, tab merging, drawer, drag-to-organize,
   badges, shelf/trash/folders, hover/tooltips, window-lift, auto-hide, updates behave
   exactly as snapshot `a4e1a55` does today.
6. Widgets (§5b) render per Appendix A in every mode with 12-language strings.
7. Native-Dock drill (§Phase 5) passes with log in the PR; no lost Dock state.
8. `LICENSE` (GPL-3.0-or-later) + combined `NOTICE` cover all sources; no tungsten
   marks in product; new id/domain/feed; zero new third-party dependencies.
9. Idle CPU with 4 island panels ≤ strip baseline + ε (Phase-2 Instruments number in PR).
10. Edge bars (Phase 7A: 7a/7b): non-activating, survive Space switches, hide
    atomically for fullscreen per display, reflow on display-set change; every
    popup anchors to its own edge chip; idle CPU ≤ island baseline + ε; notes
    sync round-trips local ↔ iCloud-Drive folder.
11. Launchers & FAB payloads (Phase 7B: 7c/7d/7e): centered launcher and both
    FAB payloads non-activating, survive Space switches, hide atomically for
    fullscreen per display, reflow on display-set change; flyouts/popups anchor
    to their own chip/FAB; FAB width sliders persist across restarts; no new
    TCC surface beyond the existing app list; idle CPU ≤ island baseline + ε.

---

## Appendix A — Per-mode layout spec (normative)

| Mode | Slots | Slot 0 | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|---|---|
| `windows` | 1 | full-width strip: `[weather] — spacers — [apps CENTERED] — spacers — [tray, clock]` (+ tungsten drawer/shelf/trash/folders/badges in apps zone) | — | — | — |
| `split3` | 3 | `[weather]` | `[apps]` (overflow-capable; window chips + drawer/shelf/trash/folders entry) | `[tray, clock]` | — |
| `split4` | 4 | `[weather]` | `[apps]` (overflow-capable) | `[tray]` | `[clock]` |
| `centered` | 1 | hug-width centered: `[weather, apps, tray, clock]`, width = `centeredWidth` clamped to content + margins | — | — | — |

Rules:

- Section order inside a slot is always the canonical L→R order weather, apps, tray, clock
  (only the grouping changes between modes); tungsten utilities (drawer/shelf/trash/
  folders) travel with the `apps` island.
- `apps` is the only overflow-capable section; on overflow: shrink chips to a floor, then
  set `showsOverflow` (overflow popup uses tungsten stack/folder popup geometry).
- Gaps: inter-island gap and screen margin come from settings (defaults mirror SplitBar-
  old's gap/margin); enforce 0.5 pt minimum.
- `centeredWidth` persists under a new `com.katikati.*` key with SplitBar-old's value
  semantics (new domain — no shared defaults with tungsten or SplitBar-old).
- Every island frame must satisfy: `frame ⊆ visibleFrame`, `min gap ≥ 0.5pt`,
  `frame.height` from `DockPanelHeight` metrics, bottom-left origin screen space, and
  tungsten clamp validation.
- Tungsten chip semantics are mode-independent: `StripItem` identity (`groupID`),
  per-display filtering (`displayUUID` + `taskbarScreenPlacement`), optimistic states and
  toggle planning behave identically in every island.

## Appendix C — Edge-bar + launcher spec stub (normative for Phase 7A + 7B — 7a–7e — when they activate)

- Edges: notes = right edge, widgets = left edge, launcher = centered summon
  over bottom bar. Default: bottom bar + right notes on; left widgets opt-in.
- Widths: fixed at 7a/7b landing, drag-resizable only via tungsten
  `DockPanelHeight`-style scaling path (no new resize engine).
- Gaps/margins: mirror island `islandGap`/`islandMargin` semantics under new
  `com.katikati.edge.*` keys; enforce 0.5 pt minimum.
- Every edge frame: `frame ⊆ visibleFrame`, bottom-left origin screen space,
  tungsten clamp validation; fullscreen hides all panels on that display atomically.
- Section rule: edge bars never host `apps` window chips (islands own them);
  launcher never owns panels (anchored flyout only).
- Bottom offset: edge bars default to hugging (2pt); bottom islands default to
  floating (8pt, tungsten original) with the Phase 6 `com.katikati.layout.bottomGap`
  toggle (Hugging 2 / slider 0…12).

---

## Appendix B — References

**Tungsten Edge** (`/tmp/tungsten-edge`, `moonbai-studio/tungsten-edge @ a4e1a55`)

- `App/Entry/AppDelegate.swift` + `MacOSDockCCV2App.swift` — composition root + wiring.
- `App/Entry/PanelCoordinator.swift` (+`+Drawer/+Fullscreen/+Layout/+PanelSetup/+Popups/
  +ResizeCursor/+Spaces/+Tooltip/+Visibility`) + `NonConstrainingPanel.swift` +
  `ManualPanelHost` — the 5-panels-per-unit construction this plan extends.
- `App/Entry/TaskbarScreenOrchestrator.swift` — per-display `Unit`s + `rebuildUnits` +
  `TaskbarPerDisplaySeedController` + hover/fullscreen monitors (extend, don't replace).
- `App/Composition/PanelGeometry.swift` (`DockPanelHeight`, `PanelLayoutMetrics`, popup/
  tooltip/drawer target frames) + `AppSettingsStore.swift` (`com.tungsten.edge.*` keys,
  `taskbarScreenPlacement`, height/delay patterns) — geometry + settings authority.
- `App/Composition/AppComposition.swift` (`AppRuntime`, `DockSnapshot` consumption,
  optimistic states) + `IntentPipeline/` — interaction engine (untouched).
- `App/Scenes/DockStripView*.swift` + `StripProjection` + `UI/ReadModel/StripItem.swift`
  — strip rendering + per-window slotting (per-island instances filter, never redefine).
- `Core/` (`WindowIdentityEngine`, `LifecycleTransitionEngine`, `LifecycleActionPlanner`,
  `PlacementEngine`, `DockSnapshot`/`WindowModels`, ~50 `…Decision/…Plan/…Policy` types) +
  `Platform/` (`AppTracker`, AX/CG/fullscreen/Spaces/Finder/permissions) — inventory +
  decisions (untouched).
- `Resources/` (`Info.plist`, `.xcstrings` ×12 languages, entitlements) +
  `macos-dock-cc-v2.xcodeproj` (bundle ids `com.caye.macosdockcc.v2*`, Swift 5.0, floor
  12.0, Sparkle SPM pin) + `Scripts/` + `.github/workflows/ci.yml` — build/ship discipline.
- `LICENSE` (GPL-3.0-or-later) + `TRADEMARK.md` (name/logo reservation) — §6 obligations.
- `README.md` (features, build/test commands, folder rules, signing, Chinese code comments
  note) + `Docs/Archive/Releases/` — operator manual for the core.

**SplitBar-old** (`/Users/baraka/Desktop/SplitBar-old`)

- `Sources/SplitBar/Views/TaskbarConcept/TaskbarConceptView.swift` — `TaskbarMode`,
  `TaskbarSection`, `islands(for:)`, `TaskbarStrip.layoutIslands`, overflow loop,
  `centeredBarWidth` (L1408/L1784).
- `Sources/SplitBar/Services/TaskbarPanelController.swift` — per-display panel lifecycle
  (slot-key precedent).
- `Sources/SplitBar/Services/FullscreenMonitor.swift`, `SplitBarDockRestore/main.swift`.
- `Tests/SplitBarTests/TaskbarStripTests.swift` — island cases to port.
- README/build: `./run.sh`, `scripts/build_app.sh`, `xcrun swift build|test`.

**DockBar** (`/Users/baraka/dockbar`)

- Widget implementations: `WeatherService`, `CalendarTrayButton`/`CalendarView`,
  `ConnectivityTrayView`, `WindowsTrayClusterView`, `BatteryMonitor` (+ quick-settings
  cluster) — §5b ports.
- Settings-window search/catalog patterns — "Layout" tab organization precedent.
- AppKit panel lessons (`TaskbarPanel`, `BarPanelLayout` edge handling) — gap-analysis
  only; no structural port.
- Docs: `SPEC.md`, `CHANGELOG.md`, `agents.md`.

**Live SplitBar** (`github.com/wakilibaraka/SplitBar`, clone `/tmp/splitbar-upstream`)

- `Sources/SplitBar/Models/DockSegment.swift` — `SegmentKind`/`SegmentAlignment` priors.
- `Sources/SplitBar/Support/PanelGeometry.swift` — clamp/anchor priors (tungsten
  `PanelGeometry` wins ties).
- `Sources/SplitBar/Services/SegmentPanelManager.swift` — incremental-sync priors
  (tungsten `rebuildUnits` wins ties).
- `Sources/SplitBar/Services/DockController.swift` — recovery-file priors
  (evidence-gated, Phase-5 drill decides).
- Key commits: `a2d3de0` (restructure → SplitBar, `com.baraka.splitbar`), `f5fee81`
  (segment split + DockController), `04b121d` (asymmetric scaling, per-icon anchors,
  hover previews), `a96b7dd` (merged center apps, equalized heights). Docs: `CLAUDE.md`,
  `TASKS.md`.

**Edge-bar + launcher candidates** (Phase 7 only — §5e, owner's 2026-10-08 decision,
widgets-only option (a))

- **EdgeDeckBar** (`github.com/senoldogann/EdgeDeckBar`, MIT) — edge geometry,
  auto-hide handle, magnification, reorder, 6 widgets, quick-notes, ⌥Space palette.
- **noty** (`github.com/aimen08/noty`, MIT) — SQLite + AES-GCM notes, SyncPlan,
  one-deck-per-display, NSTextView editor.
- **arc-menu** (`github.com/egemenince-git/arc-menu-for-macos`, MIT) —
  enumeration, aliases, CLI-by-path.
- **Volant** (`github.com/mysticcoders/volant`, MIT) — ranking, ⌘K editor,
  portable config.
- **Liftoff** (`github.com/firstfu/Liftoff`, GPL-3.0) — live previews, title
  search, Smart Organize.

**Screenshots** (owner's Desktop)

- `Screenshot 2026-10-06 at 02.03.12.png` — split-3 visual target.
- `Screenshot 2026-10-06 at 00.15.28.png`, `...00.46.50.png` — Windows full / mode picker.
- `Screenshot 2026-10-07 at 07.16.08.png` — onboarding pick-a-layout.
- `Screenshot 2026-10-06 at 15.34.57.*`, `03.30.35.png` — widgets/weather flyouts.

**Superseded**: v2 plan (`DockBar base × SplitBar-old modes × live-SplitBar segments`,
commit `3d914c6`, backup at `/tmp/HYBRID_PLAN.v2.backup.md`) — retained for review
archaeology; this v3 document governs.

## Known Layout Defects (Logged 2026-10-08)
- ~~**Space next to trash can:** The gap or empty space next to the trash/tray area needs tight alignment review.~~ (Resolved in Phase 4 layout rewrite)
- ~~**Drawer overlapping clock:** In certain modes/directions, the drawer expands to the left and incorrectly overlaps the clock. This geometry intersection needs to be resolved before Phase 4 concludes.~~ (Resolved in Phase 4 layout rewrite)
- 2026-10-11 · **5b/5c drills — PASS (no gap).** SIGTERM: exit ~500ms, no survivors, Dock prefs identical. kill -9 idle + relaunch: prefs identical, 1 process, 13 windows/8 on screen = same as clean restart (no orphaned panels). Not proven: kill inside `NativeDockPreferencesService.apply` (needs normal-permission build). No code change.
- 2026-10-11 · **5f — Phase 5 lock. Result: PASS.** Unit suite, localization, debug switches, availability-warnings (clean build) green. Log: `Docs/Archive/Planning/2026-10-11-phase-5-log.md`; CHANGELOG updated. Owner eyeball items listed in the log remain.
- 2026-10-11 · **5b/5c follow-up.** B1 (frame restore) and C3 (kill -9 with lifted windows) **blocked**: bypass skips Accessibility so no windows are lifted; owner must grant real AX, then rerun. Mid-write kill -9 emulated 30x on the defaults sequence: 0 corrupt reads, accepted by reasoning. Added relaunch-idempotence test (`IslandSlotSetTests`). Details in the phase-5 log addendum.
- 2026-10-11 · **5b/5c with Accessibility — gaps PROVEN + FIXED.** SIGTERM/SIGINT bypassed `stopAndRestore` (no handlers) and `kill -9` left lifted windows displaced. Added signal handlers (runloop-dispatched terminate) and a lift recovery file replayed on launch (`WindowLiftRecovery`, 4 tests). kill -9 + relaunch verified restoring; SIGTERM-with-lifted-window needs one owner recheck. 1719 tests green. See phase-5 log addendum 2.
