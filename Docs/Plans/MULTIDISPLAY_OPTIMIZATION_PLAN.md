# Multi-Display Optimization Plan — `MD-1` audit → `MD-2`…`MD-6`

> MD-1 was a **strictly read-only** audit: no Swift file, no `KatiKati.xcodeproj/project.pbxproj`
> and none of the five behaviour-frozen files (`WindowLiftAvoidanceController`, `AppTracker`,
> `DragController`, `AccessibilitySource`, `FullscreenIntentMonitor`) were touched. The only file
> written is this plan. The app under test was the installed `/Applications/KatiKati.app`
> **0.18.0 (build 54)**, launched for the live pass and left running.
> Audited on `main`, 2026-11-26, macOS 27.2.1, Apple M3, two physical displays.

---

## 1. Live dual-display hardware snapshot

Read with `NSScreen` + `CGGetActiveDisplayList` (Cocoa frames are bottom-left origin; Quartz frames
top-left origin anchored at the menu-bar display's top).

### 1.1 Geometry

| | Built-in Retina Display | LG HDR 4K |
|---|---|---|
| `CGDirectDisplayID` | `1` | `2` |
| EDID UUID | `37D8832A-2D66-02CA-B9F7-8F30A301B230` | `402CE39A-032C-4ABE-A1DE-98681D3D3786` |
| `NSScreen.frame` (Cocoa) | `(0, 0, 1710, 1112)` | `(-164, 1112, 1920, 1080)` |
| `NSScreen.visibleFrame` | `(56, 0, 1654, 1074)` | `(-164, 1112, 1920, 1080)` — **identical to `frame`** |
| CG bounds (Quartz) | `(0, 0, 1710, 1112)` | `(-164, -1080, 1920, 1080)` — **negative origin** |
| Backing scale | `2.0` | `2.0` (1920×1080 pt → 3840×2160 px) |
| `safeAreaInsets.top` | `37.5` → physical notch | `0.0` → notchless |
| Menu-bar height | `38.0` | `0.0` (no menu bar on the secondary) |
| Role | **Main display** (`NSScreen.main`, menu bar, Spacess owner) | secondary, independent Space |

Layout read off those numbers:

- The external sits **above** the built-in, not beside it. The shared seam is the horizontal line at
  Cocoa `y = 1112` / Quartz `y = 0`.
- Horizontal overlap is `x 0…1710`; the external overhangs `164 pt` to the left (`x −164…0`) and
  `46 pt` to the right (`x 1710…1756`). Those two bands are **dead walls**: pointer travel there has
  no display on the built-in's side.
- The built-in's `visibleFrame` is inset `56 pt` on the left (system Dock visible at the left edge).
  The external keeps the full frame, so any code that treats "visible origin" as "screen origin"
  agrees on one display and disagrees on the other.
- Mixed geometry is real: `1710×1112` vs `1920×1080`, both at 2×, so this is a height/width mismatch
  without a DPI mismatch. A 1× or 1.5× external reproduces the DPI half of the bugs.

### 1.2 Live runtime (31 KatiKati windows, one process)

| Surface | Live evidence | Verdict |
|---|---|---|
| Taskbar / Dock | one bar plate per display: built-in `(294,1064 1028×46)`, external `(287,−48 923×46)` in Quartz | per-display mode works |
| Bar mode | `com.katikati.taskbarScreen.mode = allScreensPerDisplay`, `perDisplaySeedPending = 0` | auto-seeded on first multi-display connect (§3.9) |
| Right Edge Bar | `14×256` at `x 1696` (built-in) **and** `x 1742` (external) | **rendered on both displays' own right edges** (§3.1) |
| Left Side Deck | no left-edge window; `EdgeBarComposition` forces every item to `.right` | left edge free for the drawer by design |
| Live Island | built-in `340×38` at `(685, 0)`; external `640×24` at `(476, −1080)` | external correctly gets `wideBar` (no fake notch) |
| Notch design store | no `com.katikati.notch.displayDesigns` entry → `NotchDesign.resolve` falls back to `hasHardwareNotch ? .notch : .wideBar` | correct default |
| Desktop widgets | `300×224` panels on both displays (`(1386,864)` built-in, `(1432,−248)` external) | keyed by display UUID |
| Wallpaper overlay | two windows (`1710×1112`, `1920×1080`) parked at `(−100000, 100000)` | offscreen when inactive — see §3.5 |
| Settings window | `(536, −1066 520×1026)` on the external | opens on the external and fits |
| Status/menu-bar panels | four `1710×38` strips at `y 0`, `onscreen = no` | closed notch stages, click-through |

### 1.3 Gates actually run

| Check | Result |
|---|---|
| `python3 Scripts/check_input_hygiene.py` | **pass** (`all rules passed`) |
| `python3 Scripts/live_check_input_hygiene.py` | **crashes on system Python 3.9** (`int \| None` at import). Under `/opt/homebrew/bin/python3.14`: LR2 pass (0 `.defaultTap`), **LR1/LR3 skipped — PyObjC not installed** (§3.10) |
| `Scripts/bench_katikati.sh --idle-only` (30 s settle + 30 s) | **17.85 % CPU**, 181 MB RSS, 8 threads — measured immediately after a cold launch |
| Steady state, same process, ~5 min later (`top -l 1 ×3`, 5 s apart) | **0.0 % CPU**, 182 MB |
| 3 s `sample` of the process | main thread + 6 workers parked in `mach_msg`/`__workq_kernreturn`; no spin |
| `log show --predicate 'subsystem == "com.katikati.app"'` | no entries in the last 2 h (no hot-plug was performed, see §5) |

**CPU conclusion (measured, not inferred):** there is **no idle CPU doubling** at steady state with
two displays. The 17.9 % is a cold-start transient (first window scan + wallpaper/terrain work +
SwiftUI first layout), and it lasts longer than the 30 s bench window. Memory is `182 MB`, single
digit thread count. Treat this as the baseline MD-6 must not regress, and re-measure cold start
separately from idle.

---

## 2. Ranked defects

### Must fix

| # | Defect | Evidence | Impact on a real desk |
|---|---|---|---|
| M1 | **Outer-edge surfaces are per-display, not topology-outer.** `DeckGeometry.restFrame` anchors to `visible.minX` / `visible.maxX` of *each* screen, and `EdgeSlotSet.desiredSlots` crosses every display with the enabled sides. | `Core/Support/DeckGeometry.swift` L80–89; `Core/Support/EdgeBarSlot.swift` L25–38; live windows at `x 1696` **and** `x 1742` | With side-by-side displays, both decks sit on the shared seam. Harmless only because this desk stacks vertically. |
| M2 | **No inner-seam immunity in drag-to-snap.** `edgeZone` is purely "within 12 pt of this area's edge"; `evaluateZone` picks the screen containing the mouse. Nothing knows the edge is adjacent to another display. | `Core/Support/WindowSnap.swift` L159–210; `Platform/Windows/WindowSnapService.swift` L339–360 | Dragging a window between displays grazes the seam → `topHalf`/`bottomHalf` preview fires and snaps the window back. Exactly the reported trap. |
| M3 | **The external's bar sits on the seam.** Bars anchor to each display's bottom; on this desk the external's bottom edge *is* the seam to the built-in. | external bar `y −48…−2` vs built-in top `y 0` | Bottom-edge hover/auto-hide dwell can wake the wrong display's bar when crossing between displays. |
| M4 | **Several surfaces still pick the main display instead of the cursor's.** `WallpaperOverlay` and `MusicDesktopWidgetController` resolve `NSScreen.main ?? screens.first`. | `App/Composition/WallpaperEngine.swift` L484; `App/Entry/DesktopWidgetPanelController.swift` L778 | On a notchless secondary those defaults are wrong as soon as the main display is the laptop panel. Popup controllers must be audited one by one (MD-3). |
| M5 | **Per-display wallpaper identity uses `CGDirectDisplayID`, not EDID UUID.** | `WallpaperEngine.screenKey` L540–542 (`NSScreenNumber.stringValue`) | `CGDirectDisplayID` is not stable across reconnect/port change, unlike `DisplayIdentity.uuidString` used everywhere else → per-display wallpaper resets when the monitor comes back on another port. |

### Should fix

| # | Defect | Evidence | Note |
|---|---|---|---|
| S6 | Island has 3 per-display *designs* but no topology-level *mode*, and no clamshell handover: `reconcile` builds a controller per display whose design ≠ `.off`, keyed by `CGDirectDisplayID`; a vanished display's controller is torn down. | `App/Entry/NotchPanelController.swift` L736–819; `Core/Support/NotchBehavior.swift` L41–70 | Lid close leaves the external with whatever design it already had; no deliberate handover, and no "built-in only" / "follow pointer" choice. |
| S7 | Layout restore keys **absolute point frames** by UUID-set. | `Core/Support/WindowLayoutMemory.swift` L31–58; `WindowLayoutRestoreController.fitToWorkArea` L161+ | Clamping (`fitToWorkArea`) keeps windows on-screen but does not preserve relative proportions on a different-sized external. |
| S8 | Screen-identify badges number by `NSScreen.screens` index while Settings lists displays by UUID. | `App/Entry/ScreenIdentifyOverlayController.swift` L14–46 | Badge "2" can name a different display than the row above it. |
| S9 | First multi-display connect silently switches to `allScreensPerDisplay`. | `Core/Support/TaskbarPerDisplaySeed.swift` L10–18; live defaults `mode = allScreensPerDisplay`, `seedPending = 0` | Intended and tested, but the user is never told the bar mode changed; relevant for the "first external monitor" story. |
| S10 | The live hygiene gate passes while checking nothing. | LR1/LR3 skipped without PyObjC; script crashes on Python 3.9 | A gate that degrades silently is worse than no gate. Also inspects the process globally, never per display. |

### Nice to have

| # | Item |
|---|---|
| N11 | DDC/CI hardware brightness + volume per external display with software-dim fallback (MD-5, explicitly in scope). |
| N12 | "Jump cursor to next display" and proportional crossing over mismatched vertical edges. |
| N13 | "Throw window to next display" preserving relative size across resolutions. |
| N14 | Active-display cue on a per-display dock (`StripDisplayFilter` itself is pure and already correct). |

---

## 3. Designs for `MD-2` … `MD-6`

Every slice: **≤ 300 diff lines**, no frozen-file edits, generated files appended by hand only,
pure `Core/Support` logic first with `-only-testing:` unit tests, then the wiring, then the
localization/gate run. New Swift files need a hand-appended `project.pbxproj` entry (integrator);
where a file already exists, extend it instead.

### `MD-2` — Coordinate hygiene, outer-edge anchoring, inner-seam safety

**New pure type `ScreenEdgeTopology`** (`Core/Support/ScreenEdgeTopology.swift`):

```swift
enum ScreenEdge { case left, right, top, bottom }
struct ScreenEdgeTopology {
    // Per display UUID: edges with no other display sharing that boundary.
    let outer: [String: Set<ScreenEdge>]
    let seam:  [String: Set<ScreenEdge>]
    static func resolve(displays: [TopologyDisplay], tolerance: CGFloat = 2) -> Self
}
```

Adjacency = two displays whose frames touch on that axis (within `tolerance`) **and** overlap on the
other axis by more than 0 pt. For this desk that yields: external `.bottom` = seam, built-in `.top` =
seam, and `.left`/`.right` mostly outer (the 164 pt / 46 pt overhangs leave `.right` of the external
outer, `.left` of the built-in outer).

- **Edge anchoring.** Keep `DeckGeometry` untouched as the geometry authority. Add
  `EdgeBarPlacement.resolve(side:topology:connectedKeys:)` returning which display hosts each deck
  and whether it renders `.outerOnly` (new key `com.katikati.edge.outerOnly.v1`, default on for the
  right deck, off for a single display). `EdgeSlotSet.desiredSlots` gains an `outerOnly` input so the
  orchestrator simply creates one fewer controller. Window placement stays `DeckGeometry.restFrame`.
- **Inner-seam snap immunity.** `WindowSnap.edgeZone(at:in:edgeMargin:suppressed:)` takes
  `Set<ScreenEdge>`; `WindowSnapService.evaluateZone` computes it from
  `DisplayIdentity.topologySnapshot()` + `ScreenEdgeTopology`. A seam edge only resolves when the
  user has held the pointer still for `SnapGaps.seamDwell` (≈ 450 ms) **or** holds `⌥`. No new event
  tap; the existing poll already runs per drag.
- **Bar on the seam (M3).** When a display's `.bottom` is a seam, the bar keeps its current
  placement but suppresses bottom-edge auto-hide wake for that display (the other display owns wake),
  and `TaskbarScreenOrchestrator.hoverMonitorsNeeded` keeps the monitor because the other display
  still needs it.
- **Wallpaper identity.** `WallpaperEngine.screenKey` → `DisplayIdentity.uuidString(for:)`, with a
  one-time migration of the stored `lastApplied` dictionary keyed by the old numeric string.
- Tests: `Tests/Unit/ScreenEdgeTopologyTests.swift` (stacked, side-by-side, offset, single display,
  tolerance), extension of `WindowSnapTests` for suppressed edges, and a `DeckGeometry` test that
  `restFrame` is unchanged for a given visible frame.

### `MD-3` — Cursor-screen popups, 4-mode island, per-display polish

**Topology-level island mode** (extend `Core/Support/Island/IslandDisplayTopology.swift`):

```swift
enum IslandPlacementMode: String, CaseIterable, Codable, Sendable {
    case builtInOnly          // notch screen only
    case followActiveDisplay  // one island, on the screen with the pointer / frontmost window
    case externalFloatingPill // notchless screens get a floating pill, built-in keeps its notch
    case allDisplays          // today's behaviour (default)
}
struct IslandPlacement { static func resolve(mode:displays:builtIn:active:) -> [String: IslandRole] }
enum IslandRole { case notch, wideBar, floatingPill, hidden }
```

- `NotchPanelCoordinator.reconcile` consumes `IslandPlacement.resolve` instead of the per-display
  loop; `NotchDesign` stays as the per-display override and still wins.
- **Clamshell handover.** On `didChangeScreenParametersNotification`, if the built-in disappears and
  the mode is `.builtInOnly` / `.follow…`, reassign the island role to the resolved active external
  and keep that controller alive (no teardown + rebuild) so the open state and page survive the lid
  closing. On lid open, hand it back. Pure decision in `IslandPlacement.handover(...)`, tested.
- **Popups on the cursor screen.** One helper in `App/Composition/PanelGeometry.swift`:
  `CursorPopoverGeometry.frame(cursor:size:screens:insets:)` already clamps to a `visibleFrame`; add
  the screen choice (`screen containing NSEvent.mouseLocation`, else main) and route Launcher,
  Command Bar, Control Center and Menu Bar Hub through it. Replace the `NSScreen.main` defaults in M4
  with the cursor screen, keeping the main display only as a last resort.
- **Identify badges.** Number by the attributed display list (`DisplayIdentity.attributionTable`
  order, UUID-keyed) so numbers agree with the Settings rows.
- **Strip polish.** `StripDisplayFilter` is already correct and tested; add the active-display cue
  (existing accent token, no new string).
- New user-facing strings for the 4 modes: English + 11 locales, hand-appended, gate
  `check_localization.py`.

### `MD-4` — Topology-bound layout recovery + window throw

- `WindowLayoutMemory` v2: store, per window, both the absolute frame (today) **and**
  `relativeFrame` = origin/size as fractions of that display's `visibleFrame`, keyed by display UUID.
  Decode v1 unchanged (version field), write v2. Pure:
  `static func plan(topology:current:displays:) -> [Move]` picks relative restore when the display
  sizes differ beyond `tolerance`, absolute otherwise.
- `WindowLayoutRestoreController`: pass the per-display visible frames; keep the 3 s settle; add a
  `hotPlugDebounce` of 1 s so a rapid unplug/replug does not race the wake path. `fitToWorkArea`
  stays as the final clamp.
- **Throw window to next display.** `WindowSnapService.moveToNextDisplay` already exists
  (`Platform/Windows/WindowSnapService.swift` L66); add the pure mapping
  `WindowThrow.relativeFrame(from:to:)` (preserve width/height fractions, clamp into the target
  `visibleFrame`) and wire `⌃⌥⌘←` / `⌃⌥⌘→` in `Core/Support/Shortcuts.swift` +
  `ShortcutService`. No new input tap.
- Tests: `WindowLayoutMemoryTests` (same topology, resized external, one display missing),
  `WindowThrowTests`.

### `MD-5` — DDC/CI external brightness + volume, and cursor assist

Explicitly in scope per the owner. Clean-room, MIT-compatible implementation (the algorithm and
VCP constants are public MCCS/DDC-CI; no MonitorControl source is copied — attribution row added to
`NOTICE` only if code is derived).

- **Backend** (`Platform/Display/DDCService.swift`, private API isolated in this one file):
  - Apple Silicon: `IOServiceGetMatchingServices` for `DCPAVServiceProxy`, keep nodes whose
    `Location == External`, then `IOAVServiceCreateWithService` +
    `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` (`IOAVServiceWriteI2C(service, 0x37, 0x51, …)`).
    No entitlement, no root, no TCC prompt; exported-but-unheadered symbols, stable since macOS 11.
  - VCP codes: `0x10` brightness, `0x62` volume, `0x6F` (read) for capability discovery;
    map display → `CGDirectDisplayID` → EDID UUID with `DisplayIdentity`.
  - Intel fallback (optional, gated): `IOFramebuffer` `kIOI2CDDCciReplyTransactionType`; otherwise
    software dimming only.
- **Coalescing** (pure Core, `Core/Support/DDCWriteCoalescer.swift`): last-value-wins per
  `(displayUUID, vcp)`, minimum interval 50 ms, dropped writes never queue up. Testable without I/O.
  All I/O on a dedicated serial `DispatchQueue` — never the main thread, never during a slider drag.
- **Software fallback**: `GammaDim` panel per display (`CGSetDisplayTransferByFormula`-based,
  restored on quit and on disable), clamped to `0.15…1.0`; used automatically when a DDC read fails
  and offered explicitly for TVs/virtual displays. Never applied to the built-in panel (native
  brightness).
- **UI**: per-display brightness (and volume where `0x62` responds) sliders in Control Center and
  Menu Bar Hub; optional "brightness keys follow the pointer" routing F1/F2 to the display under the
  cursor via the existing shortcut path. Feature-gated behind `com.katikati.display.ddc.v1` and
  lazily initialised (Standing Rules §1.7e).
- **Cursor assist**: pure `CursorCrossingPlan` (proportional y mapping across mismatched vertical
  edges) plus a "Jump cursor to next display" hotkey using `CGWarpMouseCursorPosition` — no Input
  Monitoring, 0 % idle cost.
- Tests: coalescer (order, throttle, drop), crossing plan (mismatched heights, dead walls),
  capability fallback decision. DDC I/O itself is hardware-only and listed as a manual check.

### `MD-6` — Stress test, 12-locale gate, regression guard

- **`live_check_input_hygiene.py`**, per display:
  - require Python ≥ 3.10 (fix the `int | None` crash) *or* run under a compatible interpreter;
  - **fail loudly** when PyObjC/Quartz is missing instead of skipping LR1/LR3;
  - map every `CGWindowListCopyWindowInfo` bounds rect to a display via
    `CGDisplayBounds` + area-overlap (same rule as `WindowDisplayAttribution`);
  - assert per display: onscreen windows at layer ≥ 0 either ignore mouse events or fall inside that
    display's resting footprint; no window straddles a seam while eating events; parked windows are
    at the documented off-screen origin.
- Full gate: `xcodebuild test -only-testing:` for the new Core tests, full `xcodebuild test`,
  `check_localization.py` (12 locales), `check_debug_switches.py`,
  `Scripts/build_and_run.sh --check-signing`, `bench_katikati.sh --idle-only` on two displays.
- Manual checklist (cannot be automated): plug/unplug while dragging a window; lid close (clamshell)
  and open; sleep/wake with both displays; change the external's resolution; DDC read/write on the
  real panel; confirm no bar wake on the seam.

---

## 4. Slice table

| Slice | Focus | Files (primary) | Tests | Est. diff |
|---|---|---|---|---|
| `MD-2` | Edge topology, outer-edge decks, seam-immune snap, wallpaper UUID | `Core/Support/ScreenEdgeTopology.swift` (new), `WindowSnap.swift`, `WindowSnapService.swift`, `EdgeBarSlot.swift`, `TaskbarScreenOrchestrator.swift`, `WallpaperEngine.swift` | `ScreenEdgeTopologyTests`, `WindowSnapTests`, `DeckGeometry` regression | ~280 |
| `MD-3` | 4-mode island + clamshell, cursor-screen popups, identify order | `IslandDisplayTopology.swift`, `NotchPanelController.swift`, `PanelGeometry.swift`, 4 popup controllers, `ScreenIdentifyOverlayController.swift`, `Localizable.xcstrings` | `IslandPlacementTests`, `CursorPopoverGeometryTests` | ~300 |
| `MD-4` | Relative layout memory + throw hotkey | `WindowLayoutMemory.swift`, `WindowLayoutRestoreController.swift`, `WindowSnapService.swift`, `Shortcuts.swift` | `WindowLayoutMemoryTests`, `WindowThrowTests` | ~260 |
| `MD-5` | DDC/CI brightness/volume + cursor assist | `Platform/Display/DDCService.swift` (new), `Core/Support/DDCWriteCoalescer.swift` (new), `CursorCrossingPlan.swift` (new), Control Center + Hub panes | `DDCWriteCoalescerTests`, `CursorCrossingPlanTests` | ~300 |
| `MD-6` | Per-display gate + stress + locales | `Scripts/live_check_input_hygiene.py`, `Localizable.xcstrings`, `CHANGELOG.md` | manual checklist | ~200 |

Hot-file touches (integrator applies): `KatiKati.xcodeproj/project.pbxproj` (three new files in
MD-2/MD-5, hand-appended), `Resources/Localizable.xcstrings` (MD-3, MD-5), `CHANGELOG.md`,
`HYBRID_PLAN.md` slice notes.

---

## 5. What this audit did **not** verify

- **No physical hot-plug** (unplug/replug), **no clamshell** (lid close), **no sleep/wake** was
  performed — all of those need the operator at the desk. The code paths exist
  (`TaskbarScreenOrchestrator.screenParametersChanged`, `NotchPanelCoordinator.reconcile`,
  `WallpaperOverlay.update`, `WindowLayoutRestoreController.scheduleRestore`), but their *runtime*
  behaviour on this dual-display desk is unverified.
- **No click-through assertion per display**: `live_check_input_hygiene.py` LR1/LR3 could not run
  without PyObjC, and none was installed (that would change the user's Python environment).
- **No DDC capability probe** was attempted; whether this LG panel answers VCP `0x10`/`0x62` on the
  active port is unknown until MD-5 exists.
- **No interaction testing** of the live surfaces (no clicks, drags or window throws were
  performed); the window list is a static capture, not a behavioural trace.
- The 17.85 % CPU figure is a **cold-start window**, not steady state; steady state measured 0.0 %.

---

## 6. Implementation status (2026-11-26)

`MD-2` … `MD-6` are implemented (see `HYBRID_PLAN.md` § Multi-Display Optimization for the file-by-file
account). Every pure rule is in `Core/Support` and covered by tests; the wiring is in the orchestrator,
the snap monitor, the notch coordinator, the restore controller and the display-control facade. All six
slices have been checked against two live displays, including the LG panel's DDC/CI; the only items left
need a human at the desk (§5).

| Slice | State | Checks |
|---|---|---|
| `MD-2` | Implemented — `ScreenEdgeTopology`, `EdgeBarPlacement` (`com.katikati.edge.outerOnly.v1`), seam-suppressed `edgeZone` with `SnapGaps.seamDwell`, UUID wallpaper key | 6 + 4 + 3 tests, build green |
| `MD-3` | Implemented — `IslandPlacementMode` + `IslandPlacement.handover`, controller re-target, cursor-screen popover resolver, attribution-ordered badges, 5 keys × 12 locales | 8 tests, localization gate green |
| `MD-4` | Implemented — relative layout memory (v1 files still decode), 1 s hot-plug debounce, `WindowThrow` shared with `moveToDisplay` | 4 + 4 tests |
| `MD-5` | Implemented and live-verified on the LG — DDC/CI transport + coalescer + gamma fallback + `DisplayBrightness` facade behind four existing sliders; external volume (VCP `0x62`) with cached readback in the Control Center card and the Menu Bar Hub; `cursorNextDisplay` binding | 5 + 4 + 4 + 17 tests; live read/write on hardware |
| `MD-6` | Implemented — Python 3.9, hard failure without PyObjC, per-display LR1/LR3, LR4 (seam straddle, shadow-margin aware) and LR5 (stray park), active-dock rim cue | two-display run exit 0; without PyObjC exit 2; 3 cue tests |

### Closed in this pass (previously listed here as gaps)

- **Cursor-jump hot key.** `ShortcutAction.cursorNextDisplay` — Carbon id 77, `.off` by default (a
  pointer-moving key is never bound without the user asking), band `.windowAndSnap`, so it appears in
  the existing shortcut list with no new surface. Dispatches to `DisplayBrightness.jumpCursor(step: 1)`,
  which plans the landing with `CursorCrossingPlan` and warps the pointer. Localized title
  "Jump to Next Display" × 12 locales. The coordinate conversion was measured against the live window
  server: planned landing vs. read-back ≤ 1 pt, and the pointer was restored afterwards.
- **External volume.** `DisplayBrightness.volume(for:)` / `setVolume(_:for:)` read VCP `0x62` once per
  display (cached per UUID, cleared in `restoreAll`), and writes ride the same 50 ms last-value-wins
  `DDCWriteCoalescer` as brightness. Nil on the built-in panel and on any panel that does not answer
  `0x62`; the row is then hidden — the same graceful degradation as the brightness slider, with the
  one honest difference that there is no software stand-in, because gamma can dim a panel but cannot
  make its speaker quieter. Rendered as "Display Volume" in the Control Center card and in the Menu
  Bar Hub's display card, both reading through `DisplayTargetRule` so they act on the pointer's
  display.
- **Display targeting rule.** `DisplayTargetRule` (pointer's display → main → first; a pointer in a
  dead wall falls back instead of picking a neighbour) is now one pure rule shared by brightness,
  volume and the cursor jump, so the three can never disagree about which display they act on.
- **Active-display cue.** `ActiveDockCue` + the rim in `DockStripView`: on a desk with two or more
  displays the dock on the focused display wears the theme's existing highlighted rim token; on a
  single display the pixels are unchanged. Updated from `didActivateApplicationNotification` and
  `didChangeScreenParametersNotification` only — no pointer polling, no idle cost.

### Checked on the attached LG HDR 4K (2026-11-26, two displays)

The desk reported the geometry from §1.1 exactly (built-in `1710×1112` at Quartz `(0,0)`, LG
`1920×1080` at `(-164,-1080)`), and the live pass closed the two hardware items that were open:

- **DDC/CI works, once the packets are right.** The first probe of the shipped transport got no answer
  on any VCP. Three defects were proven with a byte-level probe and fixed: the chip address was sent
  shifted (`0x6E` instead of `0x37`, which reads back as one repeated garbage byte), the read request
  checksum omitted the folded host/opcode bytes, and the Set VCP checksum omitted the same. A fourth,
  from the previous pass, double-scaled every value: a 100 % slider wrote 39 % on a panel whose
  maximum is 100. With `DDCCommand`'s frames the LG answered `6E 88 02 00 10 00 00 64 00 64 A4`
  (max 100, current 100) and accepted writes. The panel also drops the first request after idle and
  returns an empty reply about half the time, so each request is written twice and a read retries up
  to three times.
- **Live end-to-end through the shipped transport:** brightness `100/100`, volume `30/100`; set
  brightness 80 % → read-back `80/100`; restore → `100/100`; volume 30 → 50 → 30. `probeIfNeeded` now
  only latches on a display that answered, and a silent panel is asked at most twice, so a flaky bus
  does not leave DDC off for the session.
- **Cursor jump across the seam:** planned `(988.30, 1110.0)`, read-back `(988.0, 1110.0)` — 0.30 pt
  off, inside the target display, pointer restored afterwards.
- **Hygiene gate, two displays:** `live_check_input_hygiene.py` under Python 3.14 + PyObjC reported 13
  windows on the built-in and 8 on the LG, 0 event taps, and exit 0. Two gate defects it exposed were
  fixed: LR1 failed the app's own dock plate/rail (now a bar/rail shape is legitimate), and LR4 flagged
  the plate's 18 pt shadow margin crossing onto the neighbouring display's menu-bar band (window level
  25 sits above the plate's 20), now a note rather than a failure.
- **Not captured on screen:** the "Display Volume" row in the Control Center card. AX does not expose
  the card's SwiftUI labels and the status-item click toggled the hub closed; its visibility rests on
  the transport returning `30/100` for the pointer's display through `DisplayTargetRule`, not on a
  screenshot.

### Still open — operator at the desk only

- The §5 manual checklist (hot-plug mid-drag, clamshell, sleep/wake, resolution change, seam wake)
  still needs the operator at the desk; the geometric checks above do not exercise it.
- `Scripts/live_check_input_hygiene.py` needs `pyobjc-framework-Quartz` in the operator's Python;
  without it the script exits 2 by design rather than pretending to pass. On this machine it runs via
  `uv run --python 3.14 --with pyobjc-framework-Quartz python Scripts/live_check_input_hygiene.py`.
- `DDCServiceOrder` still assumes registry order matches display order; on this desk one external
  service paired with one external display, so the assumption held. A two-external desk should confirm
  it or set `com.katikati.display.ddcMap`.
