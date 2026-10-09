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
4. **Two donors, one reference** (see §0/§5):
   - **Donor A — SplitBar-old** (`~/Desktop/SplitBar-old`, `wakilibaraka/SplitBar-old`):
     the 4 required layout modes, section/island model, pure island geometry, mode
     picker/onboarding, island tests.
   - **Donor B — DockBar** (`~/dockbar`, `wakilibaraka/dockbar`, fork of
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
- §7 Phases 0–7 (each shippable + testable)
- §8 Risks, mitigations, open questions
- §9 Acceptance criteria
- Appendix A — per-mode layout spec (islands, overflow, migration)
- Appendix B — references (files, commits, screenshots)
- Appendix C — edge-bar + launcher spec stub (Phase 7 only)

---

## 0. Sources at a glance

| | **Tungsten Edge** (core) | **SplitBar-old** (donor A) | **DockBar** (donor B) | **Live SplitBar** (reference) |
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
- No new third-party dependencies beyond tungsten's single Sparkle SPM pin — all donor
  ports must be dependency-free.
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
| Fullscreen hide per screen | ✅ intent monitor + per-coordinator path | ✅ `FullscreenMonitor` | ✅ | ❌ | Tungsten path; donor-A ideas only if a gap is found |
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
- **SplitBar-old is donor A** because it is the only source of the *4 required modes* as
  semantics: `TaskbarSection.islands(for:)` (which sections group into which island), the
  overflow-collapse loop, and `TaskbarStripTests` proving them. Its structure (7.5k-line
  SwiftUI monolith) is deliberately not ported — only model + math + tests.
- **DockBar is donor B** because it owns the missing widget set (weather, clock, tray
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
v2 renamed DockBar concepts, this plan keeps tungsten names and maps donors onto them:

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

### 5a. From SplitBar-old (donor A) — port model + math + tests

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

### 5b. From DockBar (donor B) — eyeball-only reference (owner 2026-10-08)

**Eyeball-only rule:** DockBar code is a *specimen, never a source*. Study how it
fetches, decides and renders — then write fresh code in tungsten patterns (pure
decisions in `Core/Support` + unit tests, thin services in `App/Composition`, tungsten
chip/popup chrome, Phase-4 theme tokens). **Nothing is pasted or mechanically
translated**; pin DockBar's commit hash for reference. No donor regression can enter
because no donor line enters. The table below is a *study list* — the Target column is
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

### 5e. Edge-bar + launcher candidates (Phase 7 only — owner's 2026-10-08 decision)

Single edge donor (EdgeDeckBar) + noty-as-inspo; widgets-only (option (a)).
AI Usage/Dispatch stack is explicitly NOT ported. Order: 7a notes → 7b
widgets → 7c launcher. Each needs owner sign-off + mini-plan + license check.
Phases 2–6 stay frozen.

**Eyeball-only (owner 2026-10-08, extends §5b's rule to Phase 7):** donor repos
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
     AppleSiliconDDC MIT lines where donor-A code ports) — carried verbatim.
  4. DockBar/DeskBar MIT (rajeshgoli/deskbar → wakilibaraka/dockbar) — carried verbatim
     when donor-B code ports.
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
- Adopt `LICENSE` (GPL-3.0-or-later, Moonbai Studio) + `NOTICE` (§6 entries; donor
  entries land with their code, placeholder now) + `TRADEMARK.md` reservation note.
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
donor reference = **eyeball-only** (§5b rule: DockBar studied, never copied); no new
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
| **4f — combined clock chip + finetunes** | rework per decisions 2, 3, 4, 6, **8**: hardcoded order **`weather → apps → clock`** with `.tray` **and** `.media` removed (ripple: `BarSection.islands`, `IslandLayoutSolver`, `PanelGeometry`, `AppSettingsStore` default order + their tests; Settings width sliders become weather/clock only); **combined chip built to the locked 8d spec** (weather-pill construction, time + weekday/date line, both presets kept, calendar tap) (wifi/battery/tray popup/quick settings/ring icon all move to the edge bar = Phase 7, decision 8c; decision 5 superseded); on-dock handles removed + Settings drag removed + width sliders added; now-playing mini icon + popup at apps-island right end; launcher placeholder capsule left of apps island; macOS-3D icon pass, 3D trash | `App/Scenes/TrayChip.swift` (leaves the bar → edge scope), `App/Scenes/DockStripView.swift`, `App/Scenes/SettingsWindowView.swift`, `Core/Support/BarSection.swift`, `App/Scenes/ClockChip.swift`, `App/Scenes/NowPlayingChip.swift` | updated solver/projection/store tests + localization + debug switches |

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

**Close-out:** full tungsten gate (`xcodebuild test` + `check_localization.py` +
`check_debug_switches.py` + conformance-availability check), per-decision screenshots
(owner supplies references per step), check log complete, then Phase 5 opens.

### Phase 5 — Hardening (native Dock, teardown, recovery drill)


- Keep tungsten native-Dock services as the path; run the recovery drill: kill -9 during
  Dock-mutating states, SIGTERM/SIGINT teardown, crash-relaunch, dev-bypass guard.
- **Calendar Popup Redesign**: Owner will redesign the Calendar Popup manually in this phase (Phase 4 popup implementation removed/deferred).

  Adopt live-SplitBar recovery-file ideas **only** if the drill proves a tungsten gap
  (evidence-gated diff, recorded in the PR).
- Window-lift avoidance re-verified with island frames (maximized windows avoid every
  island, not just the strip rect).
- **Verify**: drill log in the PR; no lost Dock state; no orphaned island panels after
  crash-relaunch.
- **Calendar Popup Redesign**: Owner will redesign the Calendar Popup manually in this phase (Phase 4 popup implementation removed/deferred).


### Phase 6 — Settings Layout tab + welcome step + polish

- New "Layout" `SettingsTab` (mode picker with live thumbnails drawn from
  `IslandLayoutSolver`), `WelcomeGuideView` pick-a-layout step, status-menu mode entry;
  height/gap/width sliders reuse tungsten's `DockPanelHeight` scaling path.
- **Bottom-edge hug toggle** (owner 2026-10-08: tungsten's 8pt floating default
  kept, hug opt-in): new `com.katikati.layout.bottomGap` (default 8 = current
  floating; preset Hugging 2, slider 0…12) as a segmented control/slider on the
  Layout tab. Single substitution in `DockPanelHeight.metrics` (replaces the
  literal `8`); all four modes + capsule + drawer follow automatically
  (`dockTargetFrame`/`islandTargetFrame`/`bottomMargin` already thread it).
  Edge bars (Phase 7) default to hugging; bottom islands default to floating.
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
- Polish: hover-title tooltips per island, drag-to-resize grip per island panel,
  edge auto-hide delay interplay with multi-island layouts.
- **Rich inline chip variant (owner 2026-10-08, CoolDock parity, Phase 6+ polish).**
  *Intent: CoolDock screenshots 2–3 surface rich content (folder thumbnails,
  clipboard summaries, terminal+weather) inline in the pill, while our model puts
  richness in popups — record the option to match without conceding the default.*
  Opt-in per-chip "expanded inline" form; popups stay the default. Clipboard stays
  edge-only (owner Q2(a) 2026-10-08: clipboard content in the main bar is a
  privacy-sensitive surface — passwords/visible text on screen; the Phase-7 edge
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
- **DockDoor-style hover preview, single-then-expand (owner 2026-10-08, future
  phase — NOT Phase 4).** *Intent: hovering a window chip shows ONE preview
  window (declutter default); moving the mouse into that preview expands to all
  live windows of the app; optional thematic (themed-tokens) preview chrome with
  quit / close / minimise actions.* Feasibility: yes — tungsten owns
  `ChipSnapshotter` (snapshot-backed popups) + `StackPopupSnapshotProbe` +
  debounced strip hover (plan §5b/§2-matrix rows: "Tungsten path wins ties");
  DockBar `ThumbnailService` is eyeball-only gap-analysis. Design: hover intent
  (debounced, existing path) → single `CarrierSnapshot` preview anchored per
  Phase-3 `screenFrame`; mouse-enter on preview → fan-out to per-window
  snapshots; actions row (quit/close/minimise, opt-in via settings) rendered in
  themed popup chrome. New TCC/AX surface: none beyond existing window-list
  reads, but snapshot cadence is new CPU — Instruments gate when built. Needs
  its own slice + anchor tests + CPU number; place in Phase 6+ polish or Phase 7
  edge scope when scheduled (owner to confirm phase).
- **Verify**: mode/width/gaps persist across restarts; switch without relaunch; onboarding
  snapshot test green.

### Phase 7 — Deferred (owner sign-off + mini-plan + license check each)

- **7a right-edge notes bar** (first): EdgeDeckBar notes + noty sync/crypto/editor
  per §5e. Local-only `.md` in `~/Library/Application Support/KatiKati/`,
  iCloud-Drive-folder sync, AES-GCM. Non-activating, all-Spaces, atomic
  fullscreen-hide per display, popup anchored to its own edge chip.
- **Wi-Fi + battery status widget on an edge bar** (owner suggestion, 2026-10-09 —
  moved out of the main bar by Phase-4U decision 8): the status cluster (Wi-Fi,
  battery, plus the tray popup's quick settings and the merged ring icon that 4f
  used to plan) lands on whichever edge bar the owner picks — **left vs right is
  decided by the owner at Phase 7 sign-off**. `TrayChip` moves to this scope.
- **7b left-edge widgets bar** (second): all 6 EdgeDeckBar widgets per §5e,
  re-skinned to tungsten chips + `PanelGeometry` anchors.
- **7c centered launcher** (last): hybrid per §5e — arc-menu base + EdgeDeck
  dispatch + Volant ranking/config + Liftoff preview/search. ⌥Space or
  center-slot summon; anchored flyout, no new panel class.
- Previously listed (still deferred, unchanged): dividers (`pruned` logic),
  `macOS` pill mode, magnification, hover-preview strip upgrades,
  wallpaper/personalisation, extra flyouts.
- **Verify each**: tungsten gate green + per-edge anchor tests + idle CPU ≤
  island baseline + ε (Instruments number in PR).

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
| 13 | Vertical edge geometry escapes `visibleFrame` on exotic topologies | Tungsten clamp stays authoritative; Appendix C edge rules; golden tests on tungsten topology snapshots | 7 |
| 14 | N+2 panels per display break fullscreen/Spaces/CPU assumptions | Extend `rebuildUnits` with `displayUUID#edgeSlot`, atomic per-displayUUID hide/show, `allSpacesPanels` coverage; Instruments idle-CPU gate ≤ island baseline + ε | 7 |

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
10. Edge bars (7a/7b) + launcher (7c): non-activating, survive Space switches,
    hide atomically for fullscreen per display, reflow on display-set change;
    every popup anchors to its own edge/launcher chip; idle CPU ≤ island
    baseline + ε; notes sync round-trips local ↔ iCloud-Drive folder.

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

## Appendix C — Edge-bar + launcher spec stub (normative when 7a–7c activate)

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
