# Splitbar — Hybrid Merge Plan

**DockBar base × SplitBar-old 4 modes × wakilibaraka/SplitBar segment engine**

Status: **PLANNED** · Plan v2 (three-repo reorientation) · Date: 2026-10-07  
New repo: `/Users/baraka/Desktop/Splitbar` (branch `main`)

---

## Decisions locked with the owner

1. **New repo from scratch** — not a branch or fork of any of the three source repos.
2. **Pure AppKit** core: `NSPanel` + `NSStackView` zones exactly like DockBar. No SwiftUI
   in the bar, islands or flyouts. SwiftUI only inside settings/onboarding windows if
   convenient (the bar path stays AppKit).
3. **One base, two donors** (owner-confirmed 2026-10-07):
   - **Base — DockBar** (`~/dockbar`, `wakilibaraka/dockbar`, fork of rajeshgoli/deskbar):
     architecture, window management, widgets, settings, tests.
   - **Donor A — SplitBar-old** (`~/Desktop/SplitBar-old`): the 4 required layout modes,
     section/island model, pure island geometry, mode picker/onboarding, island tests.
   - **Donor B — live SplitBar** (`github.com/wakilibaraka/SplitBar`, fork of
     `senoldogann/EdgeDeckBar`): generalized config-driven segment engine, one-panel-per-
     segment manager, real-Dock hardening, per-icon flyout anchors, hover previews, glass
     tokens. **Algorithms and hardening only — its SwiftUI shell is not ported.**
4. Open (non-blocking): final bundle id; working assumption `com.splitbar.app` (§6).

## Table of contents

- §0 Sources at a glance
- §1 Goal (the four modes, in detail) + non-goals
- §2 Why this split of work (capability matrix)
- §3 Naming (three vocabularies → one canonical set)
- §4 Target architecture (components + mechanics)
- §5 Port allow-list, file-level (and explicitly-not-ported)
- §6 Build, identity, licensing
- §7 Phases 0–7 (each shippable + testable)
- §8 Risks, mitigations, open questions
- §9 Acceptance criteria
- Appendix A — per-mode layout spec (islands, overflow, migration)
- Appendix B — references (files, commits, screenshots)

---

## 0. Sources at a glance

| | **DockBar** (base) | **SplitBar-old** (donor A) | **Live SplitBar** (donor B) |
|---|---|---|---|
| Path / URL | `~/dockbar` → `wakilibaraka/dockbar` | `~/Desktop/SplitBar-old`, branch `integrate-taskbar-prototype` (clean vs origin) | `github.com/wakilibaraka/SplitBar`, single `main`, clone at `/tmp/splitbar-upstream` |
| Upstream | fork of rajeshgoli/deskbar | local prototype, MIT © 2026 senoldogann lineage | fork of senoldogann/EdgeDeckBar (restructured in `a2d3de0`) |
| Stack | **Pure AppKit**, SwiftPM, Swift 6 (lang mode v5), macOS 14 floor | SwiftUI hosted in `NSPanel`s, SwiftPM, macOS 15 | SwiftUI in `NSHostingView`/`NSPanel`, swift-tools 6.0, macOS 15 |
| Identity | `com.dockbar.app` (dir/test names still `DeskBar`) | local `SplitBar.app` builds | `com.baraka.splitbar`, CI `build.yml` |
| Scale | ~250 src files: Views ×70, QuickSettings ×30, Services ×30, Utilities ×30 | monolith `TaskbarConceptView.swift` = **7,567 lines** + services | ~9.7k lines (App/Services/Stores/Models) |
| Tests | **~40 files** in `DeskBarTests` | `TaskbarStripTests` only | **none** (no Tests target) |
| Splitter | none — one strip panel per display | 4 fixed modes, `displayID#index` panels | generalized `DockSegment`s, 1 panel/segment, config-persisted, auto-migration |
| Multi-display | ✅ per-display | ✅ per-display (`TaskbarScreenMode`) | ❌ primary display only (CLAUDE.md phase-1 rule) |
| Dock hide/restore | `DockManager` (independent/autoHide/hidden) | `hideMacDock` + `SplitBarDockRestore` helper + login item | `DockController`: save-before-mutate, crash-recovery file, SIGTERM/SIGINT, dev bypass |
| Role in merge | **architecture + engine + test culture** | **mode semantics + island math + island tests** | **segment priors + hardening + glass tokens** |

---

## 1. Goal

**Splitbar** is a macOS taskbar replacement: an LSUIElement background agent (menu-bar item
only, no Dock icon of its own) whose bar renders in four required layouts:

| Mode | Visual | Islands | Sections (left → right) |
|---|---|---|---|
| `windows` | **Windows full** — full-width strip | 1 | `[weather] … [apps centered] … [tray, clock]` |
| `split3` | Floating islands ×3 | 3 | `[weather]` `[apps]` `[tray, clock]` |
| `split4` | Floating islands ×4 | 4 | `[weather]` `[apps]` `[tray]` `[clock]` |
| `centered` | Narrow, width-adjustable centered bar | 1 (hug) | `[weather, apps, tray, clock]` |

Optional later (present in SplitBar-old, not required by the brief): `macOS` pill mode —
DockBar's existing `mac` / `floatingCenter` styles cover most of it (Phase 7).

**Invariants that hold in every mode**

- Island panels are non-activating (`canBecomeKey = false`), `.statusBar` level,
  `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` — they persist
  across Spaces and stay out of Mission Control.
- Flyouts open anchored to the island/icon that summoned them (weather from island 1,
  calendar from island 4, per-icon window previews above the exact icon).
- All islands on a screen hide together when a fullscreen window covers that screen, and
  reflow when the screen set or resolution changes.
- The active mode, centered width and gaps persist across relaunch and switch from
  Settings **without relaunching**.

### Non-goals

- No SwiftUI on the bar path (decision 2); no TCA-style reducer store — DockBar's
  settings + `AppDelegate` wiring governs state.
- No wallpaper/personalisation engine, AI-usage, clipboard, quick-notes, secrets or
  `ProcessRunner` features from SplitBar-old in scope (see §5 not-ported; Phase 7 max).
- Zero third-party dependencies — all three source repos are dependency-free; preserved.

---

## 2. Why this split of work

### Capability matrix (verified against the three repos)

| Capability | DockBar | SplitBar-old | Live SplitBar | Verdict |
|---|---|---|---|---|
| Fixed 4 taskbar modes + picker | ❌ | ✅ | ❌ (no mode concept) | Port SplitBar-old |
| Generalized segments (any edge/alignment, config-persisted) | ❌ | ❌ (fixed 4 only) | ✅ `DockSegment` + migration | Port as persistence/geometry *model* |
| Island/segment geometry (pure) | `BarPanelLayout` (strip-level) | `layoutIslands` + overflow loop | `segmentPanelFrame` (clamped) | Compose: DockBar strip frame + SplitBar-old island split |
| Multi-panel management | ❌ (1/display) | ✅ `TaskbarPanelController` | ✅ `SegmentPanelManager` | Port SplitBar-old keys, live-repo sync hygiene |
| AX window mgmt + per-window task buttons | ✅ mature | ❌ prototype | ❌ basic | DockBar only |
| Launcher / quick settings / tray cluster | ✅ mature | partial | partial pills | DockBar only |
| Multi-display | ✅ | ✅ | ❌ | DockBar |
| Fullscreen hide per screen | ✅ + `FullscreenMonitor` (donor A) | ✅ | ❌ | Merge both |
| Flyout anchoring | ✅ `relativeTo:of:` | per-panel | ✅ per-icon `screenFrame` | DockBar + live per-icon composition |
| Dock hide/restore hardening | `DockManager` | `hideMacDock` + restore helper | ✅ strongest (`DockController`) | Merge: `DockManager` + live recovery file/signals |
| Hover window previews (ScreenCaptureKit) | `ThumbnailService` (click) | ❌ | ✅ debounced strip | Port live `WindowPreviewStripController` ideas (Phase 7 or 6) |
| Glass/material tokens | `DesignSystem` | `ThemeToken`/`GlassProvider` | `LiquidGlass`, `DockMaterialStyle` | Reconcile into DockBar `DesignSystem` |
| Tests | ✅ ~40 files | ✅ `TaskbarStripTests` | ❌ none | DockBar culture + port island tests |
| Settings window with search | ✅ | ❌ | SwiftUI `SettingsView` | DockBar + add "Layout" page |
| Update service | ✅ | ❌ | ❌ | DockBar |
| Auto-hide handle/activation zone | ✅ | ❌ | ✅ `edgeHandleFrame`/`edgeActivationFrame` | Keep DockBar; adopt live formulas if needed |

### Rationale

- **DockBar is the base** because it is the only repo with a tested, AppKit, multi-display,
  data-driven architecture (`TaskbarStyleSpec` × `TaskbarLayoutStrategy` × `BarEdge`), a
  real settings catalog, and ~40 passing test files — the new repo inherits a green suite
  on day one.
- **SplitBar-old is donor A** because it is the only source of the *4 required modes* as
  semantics: `TaskbarSection.islands(for:)` (which sections group into which island), the
  overflow-collapse loop, and `TaskbarStripTests` proving them. Its structure (7.5k-line
  SwiftUI monolith) is deliberately not ported — only model + math + tests.
- **Live SplitBar is donor B** because it already battle-tested the *panel-per-chunk*
  approach in production: per-segment `NSPanel`s with incremental sync and a 0.5 pt
  minimum gap, clamped cross-edge frame math, config migration detectors for legacy
  layouts, per-icon flyout anchors that survive multiple panels, and real-Dock
  save-before-mutate/crash-recovery hardening. It has no tests and no fixed-mode
  concept, so it contributes **priors and hardening code**, not architecture.
- Precedence rule when donors disagree: **SplitBar-old wins on mode semantics** (it owns
  the 4 modes), **live SplitBar wins on multi-panel mechanics** (it ships them), **DockBar
  wins on everything else** (it is the base).

## 3. Naming (three vocabularies → one canonical set)

All three repos collide (`TaskbarMode` alone means two different things). Canonical names
in the new repo:

| Concept | DockBar | SplitBar-old | Live SplitBar | **New repo (canonical)** |
|---|---|---|---|---|
| Style preset | `TaskbarMode` (custom/windows/mac/classic/eskele/hybrid) | — | `DockMaterialStyle` | **`TaskbarMode`** (keep DockBar's meaning) |
| Bar layout, the 4 required | — | `TaskbarMode` (windows/split3/split4/centered) | — | **`BarLayoutMode`**: `windows|split3|split4|centered` (+`macOS` later) |
| Horizontal chunk | zones in one strip | `TaskbarSection` (weather/apps/tray/clock) | `DockSegment` (kind × edge × alignment, UUID id) | **`BarSection`**: `weather|apps|tray|clock` |
| Island math | `BarPanelLayout` (strip frame) | `TaskbarStrip.layoutIslands` | `segmentPanelFrame` (alignment+offset+clamp) | **`IslandLayoutSolver.layout(...)`** over DockBar `BarPanelLayout` |
| Panel manager | `AppDelegate` panels dict | `TaskbarPanelController` (`displayID#index`) | `SegmentPanelManager` (per-segment) | **`BarLayoutController`** (`displayID#slot`) |
| Mode picker UI | — | `OnboardingView` + thumbnails | — | **Settings „Layout" page** + onboarding step |

Conceptual model: **style × layout mode × edge** are three independent axes.
`TaskbarStyleSpec` gains a `layoutMode` override field, reusing the exact pattern of its
existing `layoutMode` / `edge` / `dockPosition` overrides (incl. equality + resolution
helper + tests, mirroring `TaskbarStyleSpecTests`).

## 4. Target architecture

```
Splitbar (LSUIElement agent)
 ├─ AppDelegate
 │   ├─ BarLayoutController              NEW — port of SplitBar-old TaskbarPanelController
 │   │    ├─ panels: [displayID: [IslandSlot: TaskbarPanel]]
 │   │    │    slot 0  → the single "strip" panel (windows / centered modes)
 │   │    │    slot 0..n → one panel per island (split3 / split4)
 │   │    ├─ IslandLayoutSolver          NEW — pure, unit-tested geometry
 │   │    │    (port of TaskbarStrip.layoutIslands + live segmentPanelFrame clamping)
 │   │    ├─ reconcile(old:new) — incremental sync like SegmentPanelManager:
 │   │    │    reuse panels when key survives, orderOut strays, 0.5 pt min gap
 │   │    └─ boundingFrame() — union of island frames → whole-bar flyout anchor
 │   ├─ TaskbarContentView (refactored → per-slot section view)
 │   │    ├─ WeatherZoneView  ← WeatherWidgetView      (forced .dock placement)
 │   │    ├─ AppsZoneView     ← LauncherZoneView + WindowsTrayClusterView + task zone
 │   │    ├─ TrayZoneView     ← ConnectivityTrayView + battery + quick settings
 │   │    └─ ClockZoneView    ← CalendarTrayButton
 │   └─ everything else unchanged: WindowManager, AX, tray, Launchpick,
 │        QuickSettings, FlyoutPanel, SettingsWindowController, UpdateService,
 │        DockManager (hardened, see below), WeatherService, Calendar, thumbnails
 └─ shared: DesignSystem (absorbs glass tokens from both donors)
```

### Key mechanics

1. **Panel keys**: `"<displayID>#<slot>"` (SplitBar-old's `displayID#index` convention).
   Mode switch = *reconcile* the panel set — what `TaskbarPanelController.show(_:)` does,
   but incremental (live repo's `SegmentPanelManager.sync`: keep a panel if its key and
   size still match, only touch frames that changed, `orderOut` only when leaving).
2. **Island chrome**: each island is DockBar's `TaskbarPanel` with its existing
   `isFloating` path — rounded corners, shadow, gap to screen edge; per-slot corner radius
   and material come from `DesignSystem` tokens.
3. **Geometry** (the Phase-1 contract):
   - DockBar computes the strip frame via `BarPanelLayout` (bottom-left origin, edge-
     aware, float/hug variants) — this stays authoritative for *outer* frames.
   - `IslandLayoutSolver` takes the StripBar-old `layoutIslands` signature
     `(screenWidth, tileStride, appCount, weatherWidth, trayWidth, clockWidth, clusterWidth,
     gap, margin, barHeight, bottomMargin)` → produces island frames in the same
     bottom-left screen space (both donors' AppKit math is bottom-left; SplitBar-old's
     SwiftUI y-from-bottom maps 1:1 — *prove with the Phase-1 golden test*).
   - Live `segmentPanelFrame`'s clamp discipline (never off `visibleFrame`, alignment
     origin + offset) is re-applied per island as a safety net.
4. **Horizontal distribution**: DockBar's `leftTaskZoneStackView /
   neutralTaskZoneStackView / rightTaskZoneStackView` + flexible spacers already encode
   weather-left / apps-center / tray-right — the refactor promotes these to per-slot zone
   hosts; each island gets exactly its slot's sections in fixed L→R order (Appendix A).
5. **Overflow**: port SplitBar-old's loop verbatim — shrink visible app tiles until the
   island fits, set `showsOverflow`, rest lives behind the overflow flyout
   (DockBar's existing group/flyout views render it).
6. **Flyouts**: DockBar `FlyoutPanel.show(contentViewController:relativeTo:of:)` unchanged;
   add live SplitBar's per-icon composition: `screenFrame = islandFrame + localFrame` —
   note the y-flip the live repo does (`maxY - logical.maxY`) exists *only* because
   SwiftUI locals are top-down; in AppKit locals are already bottom-left, so composition
   is a plain addition + the flip constant is dropped. Test both (Phase 3).
7. **Fullscreen**: merge SplitBar-old `FullscreenMonitor` logic with DockBar's existing
   fullscreen handling; hide/show applies to **all slots of that displayID atomically**.
8. **Widget placement rule**: in all four layout modes, weather/tray/clock are forced into
   the bar regardless of `WidgetPlacement`'s menu-bar default; the menu-bar placement wins
   only in plain single-strip styles (migration stamp in `WidgetPlacement.resolve`,
   mirroring its existing v0.6 precedent — no silent flips for existing installs).
9. **Real-Dock hardening**: DockBar `DockManager` + live `DockController`'s pieces:
   save-before-mutate state file, restore-on-launch crash recovery, SIGTERM/SIGINT
   restore, dev bypass flag (`killall Dock` guard).

---

## 5. Port allow-list (file-level)

The §-tables are normative: **if a file/feature is not listed, it is not ported.**

### 5a. From SplitBar-old (donor A) — port model + math + tests

| Source | Target in new repo | Notes |
|---|---|---|
| `TaskbarConceptView.swift` → `enum TaskbarMode` | `Models/BarLayoutMode.swift` | 4 cases only; drop `macOS` to Phase 7 |
| `TaskbarSection` + `islands(for:)` | `Models/BarSection.swift` (section + island grouping) | Keep exact groupings (Appendix A) |
| `TaskbarStrip.layoutIslands(...)` | `Utilities/IslandLayoutSolver.swift` | Pure function; no views, no timers |
| `TaskbarStrip.pruned` (divider logic) | *deferred* | Only if dividers are wanted (Phase 7) |
| `TaskbarStrip` overflow-collapse loop | inside `IslandLayoutSolver` | Returns per-island `showsOverflow` |
| `Services/TaskbarPanelController.swift` | `Services/BarLayoutController.swift` | `displayID#slot` keys, mode-switch reconcile |
| `Services/FullscreenMonitor.swift` | merge into DockBar fullscreen path | Applies to all slots per display |
| `centeredBarWidth` defaults key (`taskbar.centeredWidth`) | `TaskbarSettings.centeredWidth` | Same migration pattern DockBar uses |
| `TaskbarPanelController` per-display re-layout | `TaskbarScreenMode`-equivalent in DockBar | DockBar already re-styles on screen change |
| `Tests/SplitBarTests/TaskbarStripTests.swift` | `Tests/SplitbarTests/IslandLayoutSolverTests.swift` | All cases: islands-per-mode, section coverage, bounds, overflow |
| `OnboardingView` pick-a-layout step | AppKit redraw in `Views/Onboarding/` | Reference screenshots, Appendix B |
| Mode thumbnails | extend `TaskbarStylePreviewView` | Drawn **from `IslandLayoutSolver`** → preview = real geometry |

### 5b. From live SplitBar (donor B) — port priors + hardening only

| Source (commit) | Target in new repo | Notes |
|---|---|---|
| `Support/PanelGeometry.swift` → `segmentPanelFrame` clamping discipline | validation layer inside `IslandLayoutSolver` | alignment origin + offset + clamp-to-visibleFrame; unit tests copied in spirit |
| `SegmentPanelManager` incremental sync (`f5fee81`) | `BarLayoutController.reconcile` | reuse-on-key-match, 0.5 pt min gap, touch only changed frames, `sizingOptions = []` lesson for hosting views |
| `SegmentPanelManager.boundingFrame()/frame(for:)/screenFrame(forItem:inSegment:)` (`04b121d`) | `BarLayoutController` same methods | Drop the SwiftUI y-flip (AppKit locals already bottom-left); per-icon flyout anchors |
| `Services/DockController.swift` (`f5fee81`) | hardening diff on DockBar's `DockManager` | save-before-mutate file, restore-on-launch, SIGTERM/SIGINT, dev bypass |
| `Models/DockSegment` migration detectors (`f5fee81`, `a96b7dd`) | `WidgetPlacement.resolve` migration-stamp pattern | *Pattern* port: auto-generated configs migrate, hand-edited untouched |
| `Views/Common/LiquidGlass.swift`, `ThemedGlassBackground.swift`, `DockMaterialStyle` | tokens in `Utilities/DesignSystem.swift` | AppKit `NSVisualEffectView` rendering; `NSGlassEffectView` feature-detected (macOS 26) |
| `edgeActivationFrame`/`edgeHandleFrame` | only if auto-hide handle is adopted | Otherwise DockBar's autohide already covers it |
| `WindowPreviewStripController` (SCK hover previews, `04b121d`) | **Phase 7** candidate | DockBar `ThumbnailService` covers click previews today |

### 5c. From DockBar (base) — kept as-is

Everything under `Sources/DeskBar` is inherited wholesale in Phase 0, notably:
`WindowManager`/`AXObserverManager`/`AccessibilityService`, `TaskbarStyleSpec` +
`TaskbarLayoutStrategy` + `TaskbarSettings`, `TaskbarPanel` + `BarPanelLayout`,
`TaskbarContentView` (then refactored), `FlyoutPanel`/`BorderlessFlyout`/`FlyoutLayout`,
`QuickSettings*`, `Launchpick/*`, `WeatherService`, `CalendarTrayButton`/`CalendarView`,
`ConnectivityTrayView`, `WindowsTrayClusterView`, `BatteryMonitor`, `DockManager`,
`ThumbnailService`, `WindowSwitcherService`, `UpdateService`, `SettingsWindowController` +
`Settings/` + `SettingsCatalog`, `Onboarding/`, `DesignSystem`, `MigrationManager`,
`PermissionsManager`, `SingleInstanceLock`, all `Utilities/*`, all ~40 test files,
`scripts/build.sh|package.sh|release.sh`, `.swiftformat`, CI.

### 5d. Explicitly NOT ported

- SplitBar-old: `WallpaperEngine`, `ThemeToken`/`GlassProvider` (superseded by DesignSystem
  reconciliation), personalisation flyouts, `WidgetProvider`, `splitbar.html`,
  `SplitBarDockRestore` (DockBar has a login-item story; live `DockController` has the
  recovery), `ProcessRunner`, `SecretsStore`/`SecurityKeychain`, AI-usage stack
  (`AIUsage*`, `ProviderUsageScanner`, `ClaudeStatusLineBridge`, `AIAccountStore`),
  clipboard stack (`Clipboard*`), quick notes, command palette, window tiling, Bluetooth/
  NowPlaying/SystemMonitor flyouts (DockBar has its own equivalents where in scope).
- Live SplitBar: `SegmentContainerView`, `EdgeDockView`, `SegmentPills`, all
  `Stores/*` reducers, `AppRuntimeController`, SwiftUI `SettingsView`, `DockMagnificationLayout`.
  (Magnification itself is a DockBar decision, not a donor feature.)
- DockBar: nothing is removed in Phase 0; de-scoping only happens with owner sign-off.

## 6. Build, identity, licensing

- **Repo**: `/Users/baraka/Desktop/Splitbar`, branch `main`, SwiftPM package (no
  `.xcodeproj`), swift-tools 6.0 / language mode v5, **platforms macOS 14+** (DockBar's
  floor; raise only if a Phase-6 API demands 15+ — live SplitBar's `NSGlassEffectView`
  path must feature-detect anyway).
- **Targets**: `Splitbar` (app executable), `SplitbarTests`. Phase 0 renames DockBar's
  `Sources/DeskBar` → `Sources/SplitBar`, `DeskBarTests` → `SplitbarTests`.
- **Identity**: product `Splitbar.app`, **provisional bundle id `com.splitbar.app`**.
  ⚠️ Deliberately *not* `com.baraka.splitbar` (live SplitBar's id): both apps must be
  installable side-by-side during migration, so their ids, app-support directories and
  defaults domains must differ. If the owner later retires the live repo, an id swap is a
  one-line `Info.plist` change — flagged as the open question in §8.
- **Scripts**: reuse `scripts/build.sh`, `scripts/package.sh` (stamps version from tag),
  `scripts/release.sh`, `Info.plist.template` → `Splitbar.app`; CI runs
  `swift build && swift test`.
- **Zero third-party dependencies** — all three sources are dependency-free; preserved.
- **Licensing (must-do, combined `NOTICE`)**:
  1. DockBar/DeskBar MIT — rajeshgoli/deskbar lineage, wakilibaraka/dockbar.
  2. SplitBar-old MIT © 2026 senoldogann + its Status Trio (Apache-2.0 inspired) and
     AppleSiliconDDC MIT attribution lines — carried verbatim when donor-A code ports.
  3. Live SplitBar NOTICE (EdgeDeckBar→SplitBar lineage, senoldogann) — for donor-B code.
  4. Inherited DockBar rules stay: exelban/Stats MIT = OK with attribution; SketchyBar &
     yabai = **study only, never paste**; anything in `Reference/` is read-only.
  5. No GPL anywhere; private API (SkyLight/SLS, IOBluetooth, NSGlassEffectView) isolated
     behind protocols + feature-detected + flagged in PRs (notarization risk).

---

## 7. Phases (each = shippable, testable slice)

Every phase ends with `swift build && swift test` green plus a named verification step.

### Phase 0 — Bootstrap (in this repo)

- Import DockBar `main` (clean, in sync with origin) as the baseline tree.
- Rename: target `DockBar`→`Splitbar`, `Sources/DeskBar`→`Sources/SplitBar`,
  `DeskBarTests`→`SplitbarTests`, bundle id `com.dockbar.app`→`com.splitbar.app`,
  uninstall strings, README/agents.md, `Info.plist.template`, package.sh/package.sh
  output name → `Splitbar.app`. Keep `SettingsCatalog` and internal type names unless a
  name collides with §3.
- Adopt `NOTICE` (§6, three entries — donor entries land with their code, placeholder now).
- **Verify**: `swift build && swift test` green; app launches, bar appears, settings open.

### Phase 1 — Layout model (pure, no UI)  ← risk retires here

- Add `BarLayoutMode` (4 cases), `BarSection` (4 cases) + `islands(for:)` grouping,
  `IslandLayoutSolver` — port `layoutIslands` + overflow loop + live clamp discipline.
- Golden test vs DockBar: for a synthetic 1728×1117 screen (and the multi-display set
  DockBar's `ScreenGeometryTests` uses), assert island frames ⊆ `BarPanelLayout` strip
  frame, all inside `visibleFrame`, ≥ 0.5 pt inter-island gaps, bottom-left origin.
- Port `TaskbarStripTests` wholesale → `IslandLayoutSolverTests`: islands-per-mode
  (1/3/4/1), every section in exactly one island, in-screen bounds, crowded-apps
  overflow (`showsOverflow` flips only when needed), centered-width extremes.
- `TaskbarStyleSpec.layoutMode` field + resolution helper + equality + tests (mirror
  `TaskbarStyleSpecTests`, `TaskbarModeMigrationTests` patterns).
- **Verify**: new + existing tests green; zero UI diff (nothing wired yet).

### Phase 2 — Sectioned content view (still one panel)

- Refactor `TaskbarContentView` to render an explicit `BarSection` set; extract host
  views: `WeatherZoneView`, `AppsZoneView`, `TrayZoneView`, `ClockZoneView` around the
  existing widget/task views. Order within a section fixed (Appendix A).
- Implement the widget-placement rule (§4.8) in `WidgetPlacement.resolve` + migration
  stamp + tests (extend `WidgetPlacementTests`).
- Visuals unchanged: one strip panel, same as DockBar today.
- **Verify**: `TaskbarContentViewResponsiveTests`, `TaskZoneOrderingTests` updated + green;
  screenshot diff of the bar before/after refactor ≈ identical.

### Phase 3 — Multi-panel islands

- `BarLayoutController`: `displayID#slot` panel dictionary; mode switch = reconcile
  (reuse/adjust/orderOut — SegmentPanelManager discipline). `AppDelegate`'s flat panels
  dict shrinks to flyout/settings panels.
- Wire `IslandLayoutSolver` output → per-slot frames; zone hosts move into their slot's
  panel; island chrome (rounded corners, gap, shadow) via `TaskbarPanel.isFloating` path.
- Fullscreen hide/show across all slots atomically; screen-change re-layout (DockBar's
  existing path calls into `BarLayoutController`);
- Per-icon flyout anchor composition (`islandFrame + localFrame`, no y-flip) — unit test
  with a fake island + known local frame; `boundingFrame()` for bar-level anchors.
- Hidden defaults key `barLayoutMode` for dogfooding the 4 modes.
- **Verify**: island tests green; manual script — each mode on built-in display, Space
  switch, fullscreen app, resolution change; flyouts open from correct islands; CPU idle
  check with 4 panels (Instruments) ≤ strip baseline + ε.

### Phase 4 — Mode picker & settings

- Settings page **"Layout"**: 4 mode cards with live mini-previews drawn from
  `IslandLayoutSolver` (extend `TaskbarStylePreviewView` — preview = real geometry),
  `centeredWidth` slider, gap/inset knobs, per-mode reset.
- Onboarding: port SplitBar-old's "Pick a layout" step in AppKit (reference screenshots
  Appendix B); honors `SettingsCatalog` search.
- Persistence tests: mode/width/gap roundtrip across defaults.
- **Verify**: switch all modes from Settings without relaunch; relaunch restores;
  `SettingsCatalogTests` green.

### Phase 5 — Visual parity with the reference

- Reconcile glass tokens: DockBar `DesignSystem` absorbs donor tokens (corner radii,
  vibrancy/material per mode, icon-size presets, pill vs capsule thickness — live repo's
  asymmetric pill/capsule lesson from `04b121d`/`a96b7dd`).
- Match `Screenshot 2026-10-06 at 02.03.12.png` (split-3: weather pill left, centered app
  icons, tray+clock pill right); running-indicator styles per mode; hover/press states.
- Dock-harden: `DockManager` + `DockController` recovery file/signals/dev-bypass;
  menu-bar-only agent; Dock hide opt-in.
- **Verify**: side-by-side screenshot review vs reference set; crash-recovery drill
  (kill -9 during hidden-Dock session → relaunch restores).

### Phase 6 — Hardening

- Per-screen fullscreen matrix (2 displays, one fullscreen); display connect/disconnect
  mid-session; 5-min idle CPU budget; slow-App-launch overflow stress; relaunch under
  login-item conditions.
- Private-API audit (§6.5); notarization dry-run (`codesign --verify`, hardened runtime).
- **Verify**: adversarial checklist passes; no new warnings; coverage floor held.

### Phase 7 (optional, owner-gated)

- `macOS` pill mode; SplitBar-style dividers (`pruned` orphan logic); hover preview strip
  (live `WindowPreviewStripController`); widgets board/personalisation; magnification.

---

## 8. Risks & open questions

| # | Risk | Impact | Mitigation |
|---|---|---|---|
| 1 | Coordinate-space mismatch porting `layoutIslands` (donor A is SwiftUI; island `y` measured from screen bottom) | Wrong island positions | Phase-1 golden tests vs `BarPanelLayout` on synthetic + DockBar test screens **before any UI wiring**; AppKit locals are bottom-left → donor A's `bottomMargin` maps directly; live repo's clamp is the safety net |
| 2 | `TaskbarContentView` refactor regressions (~2,400 lines of ordering/grouping logic) | Bar renders wrong for existing users | Phase 2 keeps single-strip rendering; screenshot diff before Phase 3; DockBar's `TaskbarContentViewResponsiveTests`/`TaskZoneOrderingTests` must stay green |
| 3 | Widget placement flips menu-bar → bar for existing DockBar installs | User surprise | Explicit rule + migration stamp in `WidgetPlacement.resolve` (§4.8), mirroring the file's own v0.6 precedent; tests in `WidgetPlacementTests` |
| 4 | 4 panels/idle CPU cost, duplicated timers | Battery drain | Max 4 panels/display; all panels share services (one `SharedTimer`); Phase 3 Instruments check vs strip baseline |
| 5 | Scope creep from two 10k-line donors | Never ships | §5 tables are normative; "if not listed, not ported"; one capability per PR (donor-B CLAUDE.md rule adopted) |
| 6 | License mixing across three MIT lineages | Distribution violation | Combined `NOTICE` (§6); donor attribution carried verbatim with each ported file; no GPL (SketchyBar/yabai study-only) |
| 7 | Bundle-id / app-support collision with live SplitBar | Both apps fight over defaults/locks | Fresh `com.splitbar.app` + own defaults domain + own app-support dir + `SingleInstanceLock` scoped to new id (§6) |
| 8 | Renaming DeskBar→Splitbar breaks DockBar scripts/CI conventions | Build drift | Phase 0 is a pure rename with `swift build && swift test` as exit gate; scripts adapted in same PR |
| 9 | Donor-A fullscreen logic vs DockBar's existing fullscreen path disagree | Flashes/stranded islands | Phase 3 merges into one path; atomic per-display hide; test with two displays |
| 10 | macOS 14 floor vs donor-B macOS-15/26 APIs (`NSGlassEffectView`) | Build errors on 14 | Feature-detect + fallback to `NSVisualEffectView` (donor B's own rule); CI matrix includes 14 |

**Open questions for owner (non-blocking):**

1. Final bundle id: `com.splitbar.app` (assumed) vs keeping `com.baraka.splitbar` (would
   tie the new app to the live repo's identity — only safe once the live repo is retired).
2. Fate of the live `wakilibaraka/SplitBar` after Phase 5: freeze, keep as parallel
   experimental branch, or archive once Splitbar reaches parity?
3. Confirm Phase 7 items are out of the required scope (dividers, `macOS` mode, hover
   previews, magnification).

## 9. Acceptance criteria

1. All four required modes render on the built-in display; switchable from Settings
   without relaunch; mode/width/gaps persist across restarts.
2. `swift build` && `swift test` green: full DockBar suite + ported `IslandLayoutSolver`
   tests + new placement/migration tests; no warnings-as-errors regressions.
3. Islands are non-activating, survive Space switches, hide atomically for fullscreen per
   display, reflow on resolution/display-set change; every flyout anchors to its own
   island/icon (per-icon anchor test green).
4. Overflow: crowded app sets collapse with `showsOverflow` exactly as SplitBar-old tests
   specify; no island exceeds `visibleFrame`.
5. No DockBar regression: window switching, launcher, quick settings, tray, calendar,
   weather, thumbnails, update flow behave exactly as `~/dockbar` does today.
6. Dock hide/restore: save-before-mutate + crash recovery + SIGTERM/SIGINT restore proven
   by the Phase-5 drill.
7. Combined `NOTICE` covers all three codebases; no GPL; private API isolated + flagged;
   zero third-party dependencies.
8. Idle CPU with 4 island panels ≤ strip baseline + ε (Phase-3 Instruments number recorded
   in the PR).

---

## Appendix A — Per-mode layout spec (normative)

| Mode | Slots | Slot 0 | Slot 1 | Slot 2 | Slot 3 |
|---|---|---|---|---|---|
| `windows` | 1 | full-width strip: `[weather] — spacers — [apps CENTERED] — spacers — [tray, clock]` | — | — | — |
| `split3` | 3 | `[weather]` | `[apps]` (overflow-capable) | `[tray, clock]` | — |
| `split4` | 4 | `[weather]` | `[apps]` (overflow-capable) | `[tray]` | `[clock]` |
| `centered` | 1 | hug-width centered: `[weather, apps, tray, clock]`, width = `centeredWidth` clamped to content + margins | — | — | — |

Rules:
- Section order inside a slot is always the canonical L→R order weather, apps, tray, clock
  (only the grouping changes between modes).
- `apps` is the only overflow-capable section; on overflow: shrink tiles to a floor, then
  set `showsOverflow` (split-out flyout from DockBar's group/flyout views).
- Gaps: inter-island gap and screen margin come from settings (defaults mirror SplitBar-
  old's gap/margin); enforce donor-B's 0.5 pt minimum.
- `centeredWidth` persists under the same defaults key SplitBar-old used
  (`taskbar.centeredWidth`) so migrating users keep their width.
- Every island frame must satisfy: `frame ⊆ visibleFrame`, `min gap ≥ 0.5pt`,
  `frame.height == barHeight(mode)`, bottom-left origin screen space.

## Appendix B — References

**SplitBar-old** (`/Users/baraka/Desktop/SplitBar-old`)
- `Sources/SplitBar/Views/TaskbarConcept/TaskbarConceptView.swift` — `TaskbarMode`,
  `TaskbarSection`, `islands(for:)`, `TaskbarStrip.layoutIslands`, overflow loop,
  `centeredBarWidth` (L1408/L1784).
- `Sources/SplitBar/Services/TaskbarPanelController.swift` — per-display panel lifecycle.
- `Sources/SplitBar/Services/FullscreenMonitor.swift`, `SplitBarDockRestore/main.swift`.
- `Tests/SplitBarTests/TaskbarStripTests.swift` — island cases to port.
- README/build: `./run.sh`, `scripts/build_app.sh`, `xcrun swift build|test`.

**DockBar** (`/Users/baraka/dockbar`)
- `Sources/DeskBar/Models/{TaskbarStyleSpec,TaskbarLayoutStrategy,TaskbarSettings,BarEdge,WidgetPlacement,SettingsCatalog}.swift`
- `Sources/DeskBar/Utilities/{BarPanelLayout,BarGeometry,BarContentAxis,BarLengthSolver,ScreenGeometry,TaskbarWidthPlanner,DesignSystem}.swift`
- `Sources/DeskBar/Views/{TaskbarPanel,TaskbarContentView,FlyoutPanel,TaskbarStylePreviewView,SettingsWindowController}.swift`
- `Sources/DeskBar/App/{AppDelegate,MigrationManager,PermissionsManager,SingleInstanceLock}.swift`
- `Sources/DeskBar/Services/{WindowManager,DockManager,ThumbnailService,UpdateService,WorkspaceMonitor}.swift`
- Tests: `Tests/DeskBarTests/*.swift` (~40, incl. `TaskbarStyleSpecTests`,
  `WidgetPlacementTests`, `TaskbarContentViewResponsiveTests`, `TaskZoneOrderingTests`,
  `ScreenGeometryTests`). Docs: `SPEC.md`, `CHANGELOG.md`, `agents.md`.

**Live SplitBar** (`github.com/wakilibaraka/SplitBar`, clone `/tmp/splitbar-upstream`)
- `Sources/SplitBar/Models/DockSegment.swift` — `SegmentKind`/`SegmentAlignment`, config
  decode, legacy-layout migration detectors (`matchesB1Layout`,
  `matchesLegacyFiveSegmentLayout`).
- `Sources/SplitBar/Support/PanelGeometry.swift` — `segmentPanelFrame` (alignment+offset+
  clamp), `flyoutPanelFrame` (segment & per-item), `edgeActivationFrame`,
  `edgeHandleFrame`, `edgePanelCollectionBehavior()`.
- `Sources/SplitBar/Services/SegmentPanelManager.swift` — one panel per segment,
  incremental sync, `boundingFrame()`, `screenFrame(forItem:inSegment:)` (y-flip lesson).
- `Sources/SplitBar/Services/DockController.swift` — save-before-mutate + crash recovery.
- `Sources/SplitBar/Views/Common/{LiquidGlass,ThemedGlassBackground}.swift`,
  `Models/DockMaterialStyle.swift` — glass tokens.
- Key commits: `a2d3de0` (restructure → SplitBar, `com.baraka.splitbar`), `f5fee81`
  (segment split + DockController), `04b121d` (asymmetric scaling, per-icon anchors, hover
  previews), `a96b7dd` (merged center apps, equalized heights). Docs: `CLAUDE.md`, `TASKS.md`.

**Screenshots** (`/tmp/shots`, owner's Desktop)
- `Screenshot 2026-10-06 at 02.03.12.png` — split-3 visual target.
- `Screenshot 2026-10-06 at 00.15.28.png`, `...00.46.50.png` — Windows full / mode picker.
- `Screenshot 2026-10-07 at 07.16.08.png` — onboarding pick-a-layout.
- `Screenshot 2026-10-06 at 15.34.57.*`, `03.30.35.png` — widgets/weather flyouts.
