# Ribbon (Scrolling Strip) — audit + slice plan

Status: **implementing.** RT-0…RT-2 land first (doc, pure strip state, camera/parking); the
engine, shortcuts, gestures, UI and catalog follow as their own commits.

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
- **RT-7 UI** — eight-picture grid in `SettingsTilingPane` and the Windows flyout, preset note,
  width/peek rows.
- **RT-8 localization** — the new keys, hand-anchored in `Localizable.xcstrings` for all 12 locales
  (catalog-only commit; no whole-file rewrite).

## Verification per slice

`xcodebuild test -only-testing:KatiKatiTests/TilingLayoutTests` for the pure slices, then the full
suite + `Scripts/check_localization.py` + `Scripts/check_debug_switches.py`. Live: enable the
ribbon, verify new windows join right, widths survive a new open, parking peek, ⌃⌥N handoff,
disable/quit restore. Idle CPU measured with `top -l 5 -pid` (expect ~0.0–0.3 %), not asserted.
