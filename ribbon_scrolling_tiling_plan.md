# Ribbon (Scrolling Strip) — audit + slice plan

Status: **shipped.** RT-0…RT-8 are in `main` (`b8ed2d25`, `786a0be1`, `f2c7e028`, `1f7c469e`,
`85611113`, plus the close-out commits at the end of this file's log); the ⌥-scroll half of RT-6 is
deliberately deferred (see *Deferred* below), and so is the peek row as a *control* — macOS owns that
number. No checklist item is open.

Scope: a scrollable strip of columns as a *tiling preset* (`.ribbon`), reusing the existing
`TilingTree`, `TilingEngine`, `TilingGaps`, `WindowSnapService.place`, the Carbon hotkey registry
and the Shortcuts page. No new top-level subsystem, no new Settings page — one more preset plus
its own rows.

## What already exists

- `TilingLayoutPreset` (8 presets) + `TilingLayout.resolve` + `TilingGaps` + `TilingPolicy`;
  `LayoutCatalog` (9 pictures, slot-capped).
- `TilingTree`: ordered window list, insert-left-of-focus, remove-closes-gap, swap, focus nav.
- `TilingEngine`: per-display trees keyed by EDID UUID, preset/layout overrides, AX apply,
  in-memory `preTilingFrames`, restore on disable.
- `WindowSnapService.place` already does size → position → size (the standard anti-drift dance).
- `workArea(of:)` already subtracts the Dock and a solid dock reserve.
- 55 Carbon hotkey IDs used (next free 56); `ShortcutAction` + `SettingsLayoutPane.shortcutActionName`
  + `isTilingAction` already route tiling keys into Settings.
- `GestureDispatcher` already classifies 3-finger swipes via MultitouchSupport; `GestureActionTarget`
  is a small enum.

## What was genuinely missing

No viewport/scroll state, no per-column widths, no stacks/tabs, no off-screen parking, no restore
on quit.

## Three findings that shaped the design

1. **`applyFrames` currently undoes parking.** It calls `WindowFit.shifted(actual, into: workArea)`,
   which pushes any edge-clamped window back inside. Parked columns must be written with
   `within: nil`, and the existing `<` 2 pt skip then re-fires every snapshot against the
   WindowServer clamp — so a *requested-frame* cache is needed, and clamped windows are written
   once.
2. **macOS will not park a window fully off-screen.** Published measurements (PaperWM, Paneru,
   scrollwm, SlideScroll, nehir, Snug): ~1 pt is allowed at the left/right edge, asking for more
   snaps to ~40 pt; never above the menu bar. So the spec's "6–12 pt peek" is not achievable as
   stated — the solver parks at the OS clamp (`StripParking.peek = 1`) and reads back the actual
   frame. Multi-display adjacency also leaks onto the neighbour; those columns park at the bottom
   edge instead.
3. **The overflow guard would evict ribbon windows.** `WindowFit.allUsable` (≥ 360 × 240) removes
   newcomers; a ¼ column on a 1280 pt display is 320 pt → windows vanish. The ribbon path bypasses
   it: a strip never shrinks a column to fit, it scrolls.

## Decisions

- **Width cycling is ⌃⌥⇧R**, not ⌃⌥R (that is the radial dial's default, keyCode 15 + ⌃⌥).
- **Eight pictures on ⌘⌃1–8**, visual order, 1 = Chain. The old five keys did not cover the eight.
- **Settings ≤ 1074 pt is a retired rule** (`FEATURE_ROADMAP` 2026-10-20: "do not cite 1074 pt as a
  reason for any design"). The ribbon rows are compact, but nothing is gated on that number.
- **Restore on quit is ribbon-only.** No preset restores on quit today; applying it to every preset
  is a behaviour delta nobody asked for.
- **⌥+2-finger scroll is opt-in and non-consuming.** A passive `NSEvent` monitor cannot consume the
  event, so the app under the pointer scrolls too. Consuming it would need a HID tap, which the
  single-tap rule forbids; the setting is default-off and says so.
- **Vertically stacked displays** are the documented caveat: columns that would park onto a
  vertically adjacent display park at the bottom edge instead.

## Slices

- **RT-0 doc** — this file. No code.
- **RT-1 pure strip state** — `ColumnWidthPreset`, `StripColumn`, `ScrollingStripState` in
  `Core/Support/TilingLayout.swift`: insert right of focus, close-gap, cycle width, stack-left,
  tabs, focus/swap, order preserved per display.
- **RT-2 camera + parking** — `StripCamera` and `StripParking` in `Core/Support/TilingGaps.swift`.
- **RT-3 eight pictures** — `RibbonQuickLayout` is a table over existing presets, in
  `Core/Support/LayoutCatalog.swift`, not new geometry.
- **RT-4 engine wiring** — `.ribbon` case, per-display `ScrollingStripState`, ribbon frame path
  before the catalog path, parking-aware `applyFrames` with a requested-frame cache, overflow
  bypass, widths preserved across picture switches, ribbon-only restore on quit.
- **RT-5 shortcuts** — 9 strip actions + 8 picture actions, IDs 56–72, `shortcutActionName`,
  `AppDelegate` dispatch. Width cycle defaults to ⌃⌥⇧R; pictures to ⌘⌃1–8; the rest `.off`.
- **RT-6 gestures** — `.stripNext` / `.stripPrevious` targets + dispatch, optional ⌥-scroll monitor
  behind a default-off key.
- **RT-7 UI** — eight-picture grid in `SettingsTilingPane` and the Windows flyout (the flyout draws
  Chain itself and the other seven as the catalog pictures), preset note, a Column Width row, and a
  parking-peek note.
- **RT-8 localization** — the new keys, hand-anchored in `Localizable.xcstrings` for all 15 locales
  (catalog-only commit; no whole-file rewrite).

## Verification per slice

`xcodebuild test -only-testing:KatiKatiTests/TilingLayoutTests` for the pure slices, then the full
suite + `Scripts/check_localization.py` + `Scripts/check_debug_switches.py`. Live: enable the
ribbon, verify new windows join right, widths survive a new open, the parking peek, focusing a
column from its shortcut, and disable/quit restore. Idle CPU measured with `top -l 5 -pid`, not
asserted.

The first draft of this line said "⌃⌥N handoff" as if a strip focus key shipped bound. It does not:
every strip focus/move/tab action is `.off` by default (only ⌃⌥⇧R and ⌘⌃1–8 have defaults), so the
shortcut path is reachable only after the owner assigns a key in Settings › Shortcuts. The focus
path it drives is the same one app activation and a click on a sliver drive, and that is what the
live checks below exercise.

## What shipped

- **Strip model** — `ColumnWidthPreset` (¼…Full, `next` wraps), `StripColumn` (tabs share one
  column, active index), `ScrollingStripState` (insert right of focus, close-gap removal, width
  cycling that only touches the focused column, stack-left, tab toggling/splitting, tab focus,
  `sync(with:)` that adopts newcomers without reordering, focus-aware removal).
- **Camera + parking** — `StripCamera.offset` moves only as far as the focused column needs and
  clamps at both ends; `StripParking` requests the 1 pt sliver macOS actually grants, parks at the
  bottom edge when a display sits to the side, and the engine converts the Quartz work area before
  fitting.
- **Geometry** — `TilingLayout.resolveRibbon` returns frames, camera and the parked set; every
  window of a tabbed column shares its column's frame. `TilingLayoutPreset.ribbon` falls back to
  equal columns when called without strip state.
- **Eight pictures** — `RibbonQuickLayout` (Chain, Halves, 2 + 1, 1 + 2, Thirds, Quarters, Five,
  Six) is a table over the catalog; `LayoutCatalog` gained the slot-capped `fiveUp`/`sixUp`
  pictures so 5 and 6 reuse the grid instead of squeezing windows.
- **Engine** — per-display `strips`/`stripOffsets`, ribbon branch before the catalog branch, the
  usable-size guard skipped on this path, parking written with `within: nil`, a requested-frame
  cache so the WindowServer's clamp does not re-fire AX, width persisted
  (`com.katikati.tiling.stripWidth`), `applyQuickLayout`, and ribbon-only restore on quit — wired
  into `applicationWillTerminate` at close-out, because the call used to live in
  `suspendPanelsAndStores()`, which nothing calls, so a quit left the parked columns parked.
- **Shortcuts** — ids 56–64 for the strip, 65–72 for the pictures; ⌃⌥⇧R cycles width and ⌘⌃1–8 set
  the pictures; all strip actions are `.off` by default so nothing new grabs a key.
- **Gestures** — `GestureActionTarget.stripNext`/`.stripPrevious` step along the strip.
- **UI** — eight-picture grid in Settings › Tiling, a Chain button plus the catalog pictures in the
  Windows flyout (so all eight are reachable there; Five and Six appear through the catalog), preset
  note, a Column Width picker bound to the focused column (`TilingEngine.setStripColumnWidth`, same
  effect as ⌃⌥⇧R), a note that the parking peek is the OS clamp, and all 18 new labels in 15 locales.

## Live check (2026-11-20, single 1710 pt display)

Staged through stored preferences only (`tiling.enabled = true`, `tiling.preset = ribbon`) on the
rebuilt app, then the owner's defaults were restored (`defaults import` merges, so the two staged
keys were deleted afterwards; they were absent from the snapshot).

- **Two windows:** drawn as two half-width, full-height columns side by side — the strip path runs,
  the usable-size guard does not evict, and the camera sits at offset 0 because both columns fit.
- **Third window (TextEdit):** the strip parked it at the right edge. The solver asked for the 1 pt
  peek and the WindowServer granted `x = 1665` with `width = 825` on a 1710 pt screen — a ~45 pt
  sliver. That reproduces finding 2 (macOS keeps far more than the requested 1 pt) and confirms the
  parked column is written without the work-area clamp, since a clamped write would have pulled it
  back to `x = 877`.
- **Reveal on focus (the gap from the first pass, now closed).** The camera does scroll when a
  parked column's window becomes focused, by app activation, a click on its sliver, ⌘-Tab or a strip
  shortcut. Recorded on the rebuilt app (single 1710 pt display, same staged prefs, restored after):

  | Event | Strip focus | Camera | Window frame (AS `{x, y, w, h}`) |
  | --- | --- | --- | --- |
  | TextEdit parked at the right edge | `strip = 32` | `25832` | `1664, 46, 825, 1010` (parked) |
  | TextEdit activated | `strip = 32` | `25832` | `832, 46, 825, 1010` (fully on screen) |
  | Safari parked at the left edge | `strip = 17` | `13688` | `-824, 46, 847, 1010` (parked) |
  | Safari activated | `strip = 17` | `13688` | `832, 46, 847, 1010` (fully on screen) |
  | click on the right-edge sliver at x = 1709 | `strip = 19` (YouTube Music) | `15003` | `832, 46, 825, 1010` |
  | click on a window that is already visible | `strip = 19` (unchanged) | `15003` (unchanged) | unchanged |

  Three defects had to fall out for that to work, and each was confirmed live rather than only in
  tests:

  1. **Nothing polled for focus.** The snapshot stream does not publish on every focus change,
     `NSWorkspace`'s `didActivateApplication` notification never reaches this agent app (a standalone
     listener receives it), the AX observer fired once at start, and `NSWorkspace.frontmostApplication`
     reports a stale app here. The engine now reads the WindowServer's front-to-back window list
     (`CGWindowListCopyWindowInfo`, first layer-0 window the strip manages) on a 500 ms main-queue
     timer, only while the ribbon is on, and maps that CGWindowID onto a `WindowRecord` — the
     window's granted frame is never used as the focus signal.
  2. **The reveal laid out the wrong thing.** `reapplyLayout()` resolved catalogue frames on every
     preset, so a focus grant scrolled the camera but wrote column frames the strip never asked for.
     It now resolves `ribbonFrames` when the preset is the strip, including the parked set.
  3. **The AX repeat guard swallowed the reveal.** `applyFrames` skipped a write whenever the last
     request equalled the new target, so a column that had once been asked on screen and then parked
     was never re-asked and stayed in its band. Parked targets still trust the repeat (the
     WindowServer clamps them, so re-firing AX every snapshot would be pointless); on-screen targets
     must actually be there first.

  Clicking a visible column leaves the offset untouched, and the revealed column stays put across
  later snapshots — the engine does not re-park the window it just revealed, and a partial drag is
  adopted as focus (`tree.focus`, not a release) instead of being snapped back mid-drag.

### Close-out (2026-11-20, after the audit against `85611113`)

The plan was re-read item by item against the code, not against earlier summaries. Two RT-7 items and
one RT-4 item were still open and are closed here; the measurements below are from the rebuilt app on
the same staged prefs, restored afterwards.

- **New windows join right.** A new TextEdit document grew the strip by one column —
  `content 28314 → 29917`, camera `10838 → 11123` — written at the strip's current width.
  `ScrollingStripState.insert` places it right of focus and `sync(with:)` does not reorder the
  existing columns.
- **Widths survive a new open.** ⌃⌥⇧R on the focused column widened Freebuff `847 → 1129`
  (½ → ⅔, camera `11123 → 11405`, frame `573, 46, 1129, 1010`). Opening another TextEdit document
  afterwards left that column at `1129` and gave the new column the same width (`content 30199 →
  31336`); cycling also stores the value as the width new columns start at, by design.
- **Quit restore.** Before the wiring fix a quit with the ribbon on left YouTube Music at
  `1664, 46, 1099, 1010` instead of its pre-launch `1709, 46, 847, 1010`. After moving the call into
  `applicationWillTerminate`, the same quit returned it from a tiled `1709, 46, 1129, 1010` to
  `1664, 46, 1099, 1010` — its pre-launch frame.
- **Idle CPU.** `top -l 5 -pid` on the running app: ribbon on `4.0–4.8 %`, tiling off `2.7–5.2 %`.
  The strip adds nothing measurable; the plan's "expect ~0.0–0.3 %" was a guess about the whole
  process, and neither state matches it.
- **Disable restore**, driven live this pass: switching Enable Auto-Tiling off put the strip's
  windows back and collapsed the panel to the enable / focus-follow / snap-zone rows. (Measured on
  the same window as the width change below, which went from `855, 46, 847, 1010` to
  `8, 46, 1694, 1010` and back to its pre-session frame.)
- **Column Width row, seen on screen** (Settings › Tiling, 1080 × 700 window): it renders under the
  picture grid with the current width as a glyph (`½` first) and the parking-peek note directly
  below. Choosing `1` from the picker widened the focused column from `855, 46, 847, 1010` to
  `8, 46, 1694, 1010` — a measured 847 → 1694 pt. A TextEdit document created afterwards started as
  a full-width column at `8, 46, 1694, 1010`, so the chosen width is the new-column default. With
  Enable Auto-Tiling off the row and its note disappear while the enable, focus-follow and snap-zone
  rows stay — the ribbon-only gating works.
- **Full suite with the display unlocked:** 3423 tests, 2 skipped, 4 failures, all in the two
  pre-existing classes (`DesktopRevealPolicyTests`, `SideDeckLogicTests`). `KeyGuardSharedTests`
  passes; its failures in the earlier run came from the locked session and appear only while
  `CGSSessionScreenIsLocked` is 1.

### Three-window re-check (2026-11-20, after the audit)

Three TextEdit documents placed at `100, 160` (620 × 480), `240, 700` (560 × 420) and
`780, 260` (700 × 520), ribbon on, columns at ½.

- **Narrow columns + sliver.** The focused column sat at `8`, the next at `863`, and the rest
  parked at `1709` on a 1710 pt display — `CGWindowList` reports `cg=33735` at
  `1709, 46, 847 × 1010`, the 1 pt sliver macOS allows (finding 2).
- **Reveal on activation.** Raising a parked column scrolled the camera `1718 → 26513` and wrote
  that column at `855`, fully on screen.
- **Reveal from a Settings-assigned shortcut.** With `⌃⌥→` bound to *Focus Next Column* in
  Settings › Shortcuts, the next parked column was revealed (`camera 27368`, window at `855`);
  `⌃⌥←` stepped back `31 → 30 → 29 → 28` (camera `25658 → 24999 → 24795 → 23940`), one trace line
  per press, and a parked TextEdit column arrived at `863`.
- **Disable restore.** Toggling tiling off returned all three windows to exactly the frames above.
- **Quit restore.** Enabling again and quitting returned the same three frames.

Two defects came out of the check and are fixed here:

1. **The pre-tiling frame could be a column frame.** Capture read `record.bounds` from the snapshot,
   which can still carry the parked column a previous pass wrote; the restore then had nothing to
   put back and that window stayed parked on *every* cycle (reproduced three times on the third
   window before the fix, `cg=33735` captured at `1709, 46, 847 × 1010` instead of `100, 160`). The
   live AX frame is now captured first, with the snapshot as the fallback; the same cycle then
   restored all three windows exactly.
2. **`⌃⌥←` / `⌃⌥→` could not be assigned at all.** `ShortcutKeyNames` had no arrow key codes, so
   `.key` failed validation and the binding silently fell back to `.off` — the recorder could not
   accept the brief's own focus keys. Key codes 123–126 (`←→↓↑`) are in the table now.

## Deferred

- **⌥+2-finger scroll on the strip.** A passive global monitor cannot consume the event, so the
  app under the pointer scrolls too. (This entry first said consuming it "needs a HID tap, which the
  single-tap rule forbids" — both halves were wrong: there is no single-tap rule, the tree runs four
  `CGEventTap`s, and `ScrollReverserMonitor` is already an active `.scrollWheel` tap that can swallow
  events. Consuming is possible by widening that one existing tap into a shared scroll hub; the real
  cost is semantic — it takes ⌥+scroll away from every app under a tiled window — so the gesture is
  still unbuilt, now for a reason that holds.)
- **Live rebuild of a multi-display ribbon.** This machine has one display; the neighbour-display
  parking path is unit-tested (`StripParking.side(forEdge:neighbourOnEdge:)`) but has no on-screen
  witness here. This is the only item above that was not demonstrated on screen.
- **A peek control.** `StripParking` asks for the 1 pt sliver and the WindowServer grants ~45 pt, so
  the peek belongs to macOS and the Settings row is a note rather than a slider: there is no number
  of ours to tune (finding 2).
- **A default ⌃⌥N strip key.** Every strip focus/move/tab action ships `.off`; the plan's earlier
  "⌃⌥N handoff" note described an idea, not a binding, and adding a default would grab a key nobody
  asked for.
