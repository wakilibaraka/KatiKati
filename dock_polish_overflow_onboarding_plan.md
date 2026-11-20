# Dock Polish: duplicates, spacing, overflow, presets & onboarding

Read-only audit first (no code, no `project.pbxproj`, no commit). Evidence comes from `graphify query`, the files named below, and the running app after a preference reset (fresh-install state, `com.katikati.app` domain deleted at 13:39). Line numbers are HEAD (`2cfca645` + the pushed slot-row fix `0f5e2b64`).

---

## 1. Root-cause audit

### 1.1 `Aa` and `>_` render twice — one slot, two renderers

**Symptom.** `Dictionary` and `Terminal` appear inside the utilities cluster *and* again as standalone chips before the clock (screenshots 1–3).

**Cause: two independent render paths both draw them.**

| Path | File | Line |
| --- | --- | --- |
| Utilities island iterates every visible utility slot, dictionary/terminal included | `App/Scenes/DockStripView.swift` | `2388` (`dockSlotLayout.visibleItems.compactMap(\.utilityKind)`), drawn by `utilityView(for:)` at `2400` |
| Slot layout also maps `.dictionary` → `BarSection.dictionary`, `.terminal` → `BarSection.terminal` | `Core/Support/BarSection.swift` | `508`–`520` |
| Legacy migration seeds the utilities cluster with **all seven** kinds (`drawer…trash`), dictionary and terminal among them | `Core/Support/BarSection.swift` | `833`–`842` (`slots(for: .utilities)`), `592`–`598` |
| `renderOrder` collapses repeats **per section**, so seven rows collapse to one `.utilities` row — but `.dictionary`/`.terminal` are *different* sections and survive separately | `Core/Support/BarSection.swift` | `770`–`788` |
| Standalone sections then render their own chip | `App/Scenes/DockStripView.swift` | `2045`, `2051` |
| Projection emits both as entries | `App/Scenes/DockStripView+Projection.swift` | `finalEntries` loop over `hostedSections`, ~`330`–`360` |

DI-1 (`DockToolDeduplication`) only suppresses the *app-level icon* for those apps (`DockStripView+Projection.swift:81`). It never deduplicates the two **module** renderers, which is why the duplicate survived that slice.

**Invariant that makes it impossible.** A `DockSlotItem` may be rendered by exactly one renderer:

- `utilityKind` slots whose `section != .utilities` (`dictionary`, `terminal`) are **not** island members — they render only through their `BarSection`.
- `DockUtilitiesClusterView` therefore takes `visibleItems.filter { $0.utilityKind != nil && $0.section == .utilities }`.
- `DockSlotLayout.utilitiesRailLength` counts the same subset, so the rail does not reserve two tiles that the island no longer draws.
- A pure test asserts, for every preset and every utility-toggling combination: `Set(renderedModuleSections).count == renderedModuleSections.count` and `island-owned ∩ section-owned == ∅`.

### 1.2 Dead gaps in Wide

**Cause.** Wide (`.windows`) is the only mode with a fixed content width (`DockStripView.swift:1864`). It stretches two dividers with bare `Spacer(minLength: 9)` — the ids are `layout-divider-pre-apps` and the divider after `.apps` (`DockStripView.swift:1600`, set built at `1998`). Everything else packs at natural width.

With few windows the entire spare width lands in those two gaps, so the leading widgets pin left, the tail pins right, and two large voids appear wherever the apps island is short. That is exactly the `Add City → apps` and `Trash → Aa` voids in the screenshots. Nothing is "reserved" or stale: the space is elastic by design, with no cap and no distribution rule.

**Fix shape (pure, testable).** Replace the two `Spacer`s with a computed gap plan: `WideGapPlan.gaps(spare:leadingCount:trailingCount:cap:)` that distributes spare width as equal small gaps (`≤ cap`, e.g. 24 pt) across the section boundaries, leaving the remainder as symmetric end padding. Result: no single void, no clipped widgets, and a test pins `max(gap) ≤ cap` and `sum(gaps)+content == plateWidth`.

### 1.3 AI pill on by default

**Cause: legacy defaults, faithfully migrated.**

- `BarSection.ai.startsHidden == false` (`Core/Support/BarSection.swift:49`–`54`), comment says "On by default".
- A fresh install has no stored slot layout, so `AppSettingsStore` migrates from the legacy widget layout (`App/Composition/AppSettingsStore.swift:833`–`846`), and `DockSlotLayout.migrating` sets `aiTracking` hidden only when the legacy `.ai` section was hidden (`BarSection.swift:905`; `isHidden` at `895`–`903`). Legacy `.ai` is *visible*, so the slot comes out visible.
- `DockSlotLayout.defaultHidden` already contains `.aiTracking` (`BarSection.swift:597`), but that constant is only used by `DockSlotLayout.default`, which the migration path never reaches. Verified on the reset install: `com.katikati.dock.slotLayout.v1` contains `{"item":"aiTracking","isHidden":false}`.

**Fix shape.** Three coordinated changes:
1. `BarSection.ai.startsHidden = true` and `WidgetLayout.default` follows automatically (`WidgetLayoutModel.swift:91`).
2. A one-time migration key (e.g. `com.katikati.dock.aiTrackingDefaultedOff.v1`): hide the `aiTracking` slot **unless** an explicit-user-choice marker exists. `setDockSlotItem` writes that marker whenever a user toggles AI, so an opt-in is never overridden on a later launch.
3. Fresh-install path writes `DockSlotLayout.default` (AI hidden) instead of migrating the legacy order.

Tests: fresh install hidden; migrated legacy-visible install hidden once; user toggled on → stays on across relaunch; user toggled off → stays off.

### 1.4 Sections preset: clipping and a detached Background Apps block

**Clipping beside `Add City`.** In split modes the solver shrinks fixed islands when the span runs out: `fixedWidths = fixedWidths.map { $0 * shrink }` (`Core/Support/IslandLayoutSolver.swift:168`–`179`). The frames shrink; the content does not. The strip's content row is laid out at intrinsic size inside a `ScrollView` clipped to the island (`DockStripView.swift:271`–`290`), so the last chip of a shrunk island is cut mid-icon — the white sliver at the left island's right edge.

The shrink budget is also wrong in one respect: it is computed against `minApps = appsWidth(1)` (one 42 pt tile) while the apps island actually renders up to its own content; and widget widths entering the solver are `BarSection.defaultWidgetWidth` floors, not the width the chip really needs (`WeatherChip` with a city name is wider than `weatherWidth: 150` at small bar heights).

**Background Apps floats between islands.** `backgroundApps` has no `BarSection` (`BarSection.swift:520` returns `nil`), so it is invisible to `derivedSections`/`renderOrder`. Its panel block is placed from the capsule/secondary rectangle in `PanelCoordinator+Layout` (`App/Entry/PanelCoordinator+Layout.swift:377`), which is solved from the whole bar, not from the island that should host it. In three-island mode that lands it in the gap between the middle and right islands.

**Fix shape.**
- Solver returns, per island, `contentWidth` and `frame`; if `contentWidth > frame.width`, the island's content scrolls inside its frame instead of being clipped (explicit `ScrollView` per island or a documented clip-with-fade), and the solver never shrinks below a floor derived from real chip widths.
- Feed the solver the **rendered** widget widths (`fittedWidgetLayout`), not defaults, at the current bar height.
- Give `backgroundApps` a host: place it relative to the trailing island's frame (or the capsule when the trailing island is empty), never to a bar-wide anchor. Pure `BackgroundAppsAnchor.resolve(...)` with cases for single/split/rail.

### 1.5 Minimal and Side Rail: parity with the native vertical Dock

**Rail thickness.** The rail's panel is one `metrics.panelHeight` wide (`DockStripView.swift:280`), i.e. **54 pt** at the medium size, while every tile inside is `BarSection.railTileSize = 40` (`Core/Support/StripPlacement.swift:134`) with `railChipSpacing = 2` (`IslandLayoutSolver.swift:328`). Native macOS vertical Dock on the owner's machine is ~42–46 pt wide with a tight icon pitch; KatiKati spends 14 pt of horizontal slack and a fixed 42 pt pitch regardless of item count.

**Fix shape (formula, pure).**
- Rail thickness `T = tile + 2·railInset`, with `railInset = 3…4` → **46–48 pt** at native scale, scaling with bar height and clamped ≤ 48.
- Icon pitch becomes adaptive: `pitch = min(tile + gap, (usable − 2·railInset) / (count + 0.5))`, floored at a legibility minimum (e.g. 26 pt); when the floor is hit, app tiles collapse into a scroll/overflow affordance instead of clipping.
- Widget tiles on a rail shrink with `pitch`, not with `barHeight`.
- Tests: 18 items fit inside a 900 pt rail with `pitch ≥ floor`; 30 items trigger overflow rather than clipping; thickness matches the native range.

**Minimal.** Minimal is `.centered` + `.small` + `.compact` (`Core/Support/DockStyle.swift:100`). It does not hide wide widgets — it inherits whatever the user has visible, so `Weather`/`Keep Awake`/`Now Playing`/`Clock` can overflow a centered island whose width is `min(centeredWidth, content)`. The auto-degrade ladder exists (`BarSection.startsHidden`, `fittedWidgetLayout`, `DockStyleFit.resolve`) but is not applied to the centered island. Fix: run the same L→M→S widget degrade before the centered width is clamped, and let Minimal's card write a widget set (apps + clock + utilities) unless the user has customised.

### 1.6 Wings under constrained widths

`PanelGeometry.wingPanelFrames` already degrades (`DockWingLayoutPlanner.resolveSizes`/`resolveVerticalSizes`, `App/Composition/PanelGeometry.swift:1053` onward) and drops a wing below a 40 pt floor on the bottom bar, but:

- the budget is `leftAvailable + rightAvailable` pooled, so one wing can consume the other's room;
- there is no third step between "full size" and "gone" on the horizontal bar (vertical has a height clamp) — the wing simply vanishes at ≤ 40 pt;
- the main dock never learns it lost its wing, so the strip does not reclaim the gap until the next layout pass.

Fix shape: per-side budgets (never pooled), an explicit ladder `L → M → S → icon-pillar → hidden`, and the resolved plan published back so the strip's available width accounts for hidden wings. Pure tests for 14"/15" widths with 12+ windows.

---

## 2. Presets: naming and the new default

Current: `BarLayoutMode` has `windows / centered / split3 / split4 / split5` (`Core/Support/BarLayoutMode.swift:11`–`17`); `DockStyle` wraps them as cards (`Core/Support/DockStyle.swift:83`–`105`).

| Card today | id | mode | proposed |
| --- | --- | --- | --- |
| Sections (fresh-install look) | `style.islands` | `.split3` | **Sections** (unchanged) |
| Classic | `style.classic` | `.centered` | **Floating** (title only, id kept for persistence) |
| Wide | `style.wide` | `.windows` | **Wide — new default** |
| Minimal | `style.minimal` | `.centered` small | **Minimal** |
| Side Rail | `style.sideRail` | `.split3` on left edge | **Side Rail** |

**Default change.** `AppSettingsStore` defaults to `.centered` (`App/Composition/AppSettingsStore.swift:586`), and the welcome guide pre-selects the Sections card. To make Wide the out-of-the-box look: default mode `.windows`, default style `DockStyle.wide`, welcome guide pre-selects `style.wide`. **Existing installs keep their stored mode** — no forced migration of layout, only new installs change.

Card order becomes `[wide, floating, sections, minimal, sideRail]`.

---

## 3. Onboarding revamp

Current `WelcomeGuideView` has five steps (`App/Scenes/WelcomeGuideView.swift:112`, steps enumerated at `~160`): Pick a Layout (style cards + theme swatches), Dock Items (section grid + wings), Dynamic Notch, Permissions, Dock Settings. Theme gets a row inside step 1; AI sits in the widget grid with no opt-in signal; the weather city is never asked for, which is why a fresh bar shows `Add City`.

Proposed **3 steps**, all live-applying:

1. **Layout & edge** — four cards (`Wide` preselected, `Sections`, `Minimal`, `Side Rail`) + a `Bottom / Left / Right` edge segmented control. Live preview strip already exists (`DockLivePreviewStrip`), reuse it. Theme stays in Settings.
2. **Widgets & wings** — wings `CPU / RAM / Off` per side, a Weather city picker (search field, no empty pill), and AI Tracking as an explicit **off-by-default** toggle with a one-line cost explanation.
3. **Permissions & triggers** — Accessibility status, double-tap `⌘` launcher toggle, notch copy/paste toast toggle. Reuse `PermissionRow` and the existing grant polling.

Dropping a step is a product decision; the plan keeps the Dynamic Notch toggle as a row inside step 2 rather than its own page.

---

## 4. Slice plan (each ≤ ~300 diff lines, no `project.pbxproj`, pure Core first)

> Gate for every slice: `xcodebuild test … -only-testing:KatiKatiTests/<class>` green, `python3 Scripts/check_localization.py`, `python3 Scripts/check_debug_switches.py`, `git diff --check`, 12-locale `Resources/Localizable.xcstrings` entries for any new string.

| Slice | Scope | Files | Tests |
| --- | --- | --- | --- |
| **DP-1** Duplicate-proof modules | Add `DockSlotItem.islandUtility` (utilityKind + `section == .utilities`); island reads it; `utilitiesRailLength` counts it. | `BarSection.swift`, `DockStripView.swift` (~1 line each) | `ModularDockCoreTests`: no slot renders twice across presets; island-owned set excludes dictionary/terminal; rail length matches island count |
| **DP-2** AI off by default | `ai.startsHidden = true`; fresh path writes `DockSlotLayout.default`; one-time hide + user-choice marker in `setDockSlotItem`. | `BarSection.swift`, `WidgetLayoutModel.swift`, `AppSettingsStore.swift` | fresh hidden; migrated hidden once; opt-in survives relaunch; opt-out survives relaunch |
| **DP-3** Wide gap plan | Pure `WideGapPlan`; strip renders capped gaps instead of two `Spacer`s. | new Core file or `IslandLayoutSolver.swift`, `DockStripView.swift` | gaps ≤ cap; sum + content == plate; one-window case has no void |
| **DP-4** Sections overflow + Background Apps anchor | Solver returns per-island content width and never shrinks below real content; island scrolls instead of clipping; `BackgroundAppsAnchor` pure resolver. | `IslandLayoutSolver.swift`, `PanelCoordinator+Layout.swift`, `DockStripView.swift` | shrunk-island content still reachable; anchor lands on the trailing island in split3/4/5; rail case |
| **DP-5** Rail parity + adaptive pitch | Rail thickness formula, adaptive pitch with overflow, widget tiles follow pitch, Minimal widget degrade. | `IslandLayoutSolver.swift`, `DockStripView.swift`, `DockStyle.swift` | 18-item parity vs native range; 30-item overflow; Minimal drops wide widgets before clipping |
| **DP-6** Wings ladder | Per-side budgets, `L→M→S→pillar→hidden`, publish back to the strip. | `PanelGeometry.swift`, `DockWingModels.swift`, `DockStripView.swift` | 14"/15" with 12+ windows: no overlap, no vanishing without a step |
| **DP-7** Presets | `Classic` → `Floating` title; card order; Wide default for fresh installs; welcome guide pre-select. | `DockStyle.swift`, `AppSettingsStore.swift`, `WelcomeGuideView.swift`, xcstrings | `DockStyle.matching` for each card; fresh default == wide; stored mode untouched on upgrade |
| **DP-8** Onboarding 3 steps | Rework `WelcomeGuideView` steps, add city picker + AI opt-in + triggers, keep permissions. | `WelcomeGuideView.swift`, xcstrings | Existing `WelcomeGuideDecisionTests` unchanged; new pure test for step→settings mapping |
| **DP-9** Docs + live check | Plan log entry, live AX verification of each defect (duplicate gone, AI hidden, no void, rail parity), graphify rebuild. | `HYBRID_PLAN.md` | — |

**Ordering notes.** DP-1 and DP-2 are independent and can ship first. DP-3 before DP-4 (both touch gap/width math). DP-5 depends on DP-4's per-island content width. DP-7 must land before DP-8 (onboarding offers the new default). DP-6 is last in the geometry chain because it consumes the final budgets.

---

## 5. Verification for the fix phase

- Unit: `ModularDockCoreTests`, `AppSettingsStoreTests`, `IslandLayoutSolverTests`, `RailGeometryTests`, `DockWingModelsTests`, `LayoutThumbnailModelTests` (currently 3 pre-existing centered-mode failures — fix or explicitly re-baseline in DP-4).
- Live (AX tree, no synthetic gestures): strip exposes exactly one `Dictionary` and one `Terminal`; AI chip absent on reset install; Wide shows no gap wider than the cap; Sections shows no clipped icon; rail thickness/pitch measured from frames.
- Fresh-install check after DP-2/DP-7: reset `com.katikati.app`, relaunch, confirm `slotLayout.aiTracking.isHidden == true` and mode `windows`.

---

## 6. Decisions needed before code

1. **Sections layout after the duplicate fix** — is dictionary/terminal *inside* the utilities cluster (then their `BarSection` rows must disappear from the section renderer) or *outside* it (island excludes them)? Recommendation: **outside** (keeps DI-1's "one module, one glyph" and lets Settings order them independently).
2. **Wide default** — new installs only, or also migrate existing installs that never touched layout? Recommendation: **new installs only**.
3. **Minimal card** — allowed to write a widget set (destructive to a customised bar) or merely warn when wide widgets are visible? Recommendation: write a set only when the user has never edited widgets.
4. **Onboarding step count** — 3 steps as proposed, or keep 4 by folding the notch under Widgets? Recommendation: **3**.
