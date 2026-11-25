# Strip background right-click menu — live evidence

Date: 2026-11-25 · Build: Debug, `Scripts/build_and_run.sh` (local signing, Accessibility grant intact)

## What was missing

`DockStripView` already routed right-clicks on the strip's empty area to the shared
`StatusMenuController` menu (the overlay at `DockStripView.swift` ~line 377, gated by
`StripContextMenuZone.claims`: the two end insets plus divider-wide gaps). What that menu lacked was the
hub-style header the app-chip and folder menus got in `ce4985d3` — it opened straight into
"Open at Login" / "Taskbar Size".

## What changed

- `DockMenuChrome.stripHeader` (AppMenuFragments) builds the same 26 pt icon well, title, quiet pill and
  four wells: **Settings · Control Center · Auto-Hide · Position**. It reads only `AppSettingsStore`
  properties — no readers, timers, AX or disk work — so the menu still opens on the right-click event.
- `StatusMenuController` takes a `taskbarHeader` closure (injected from `AppDelegate`, since
  `AppMenuFragments` is app-target only and this file is compiled into the test target). The header is
  inserted at index 0 for that presentation and removed in `menuDidClose`, so the shared menu never
  accumulates headers and the pill is rebuilt from live settings on every open.
- Auto-Hide toggles the strip's own hide mode (`edgeAutoHideEnabled`); the pill shows
  "Bottom · Always Visible" / "Left · Auto-Hide" from the same values.
- `DockMenuModel.stripTiles()` + `stripPlacementToken()` keep the tiles in Core, matching the app/file
  tiles, with a unit assertion.

## Two defects found by the live pass, fixed

1. Tile captions clipped ("Control C…"). The header was 264 pt wide with ~56 pt wells; widened to
   288 pt and captions get `minimumScaleFactor(0.85)`.
2. App-chip menus were drawing the header as a stray **"NSMenuItem"** row: those menus open through the
   floating chip panel, whose bridge turns `NSMenuItem`s into text rows and has no way to host the
   SwiftUI view. Menus containing a custom-view item now open natively (`NSMenu.hasViewItem`), and the
   bridge skips view items defensively. Evidence `04` (before) vs `05` (after).

## What was actually seen

- `01/02` — right-click in the strip's left inset (screen 34,1085) opens one native menu: header
  "Taskbar" + pill "Bottom · Always Visible" + four wells, then the untouched rows (Open at Login,
  Taskbar Size slider, Layout ▸, Position ▸, Add Widget or Utility ▸, Customize Dock Layout…, Desktop
  Boxes ▸, Single/Multi-Display, Debug, Pick Color, Settings…, Quit). AX frames: header view 288×94,
  wells 62×44 at y=627.
- `03` — clicking the **Control Center** well closed the menu (no `AXMenu` left in the tree) and opened
  the standalone Control Centre panel (window `1338,50 360×994`, level 3). An earlier click of the
  **Settings** well likewise closed the menu and opened KatiKati Settings.
- `07` — opening, dismissing (Esc) and reopening the strip menu twice shows exactly one header each
  time (grep count 1/1): no duplicate rows, no stale pill.
- `05/09` — Finder app-chip menu: native menu with the same header (icon, "Finder", wells
  Hide · New Window · Unpin · Quit) above "Recent Folders" and the rest of the chip rows.
- `08` — close-up of the strip header at 2×.

## Second pass — chip-level menus (2026-11-25, same day)

### Why the trash chip was unreachable

The utilities island draws the trash chip, the pinned Downloads folder and the utility chips, and the
**section** wraps all of them in its own widget-menu overlay. That overlay sits above its children, so
a right-click on the trash chip opened the section's widget menu (Apply Preset … Hide) instead of the
trash menu. `StripContextMenuZone.sectionClaims` is the pure rule that fixes it: a section may claim
empty padding and its own reported frame, but steps aside for any other chip frame drawn inside it.
`floatingContextMenu` gained an optional `shouldClaim`, and the section host now uses it. The utility
chips (Screenshots / Clipboard / Dictionary / Terminal) were swallowed by the same overlay and are
fixed by the same rule.

### Headers on the item chips

`DockMenuChrome.dockHeader` is now the single header for every Dock surface (strip, app chip, pinned
folder, trash): icon well, title, placement/hide pill, and Settings / Control Center / Auto-Hide /
Position. `TrashChip` and `PinnedFolderChip` prepend it to their existing rows. Because the header is a
custom-view row, `NSMenu.hasViewItem` routes these menus to the native pop-up instead of the floating
chip panel, so the header is never flattened into an "NSMenuItem" row.

### What was seen

- `10` / close-up: right-click on the trash chip (screen 1396,1087) opens one native menu
  `1397,908 288×163`: trash icon + "Trash" + "Bottom · Always Visible" pill, the four 62×44 wells,
  then Open Trash and Empty Trash….
- `11`: clicking the **Settings** well closed the menu (AX tree had no menu left) and opened KatiKati
  Settings (`315,225 1080×700`).
- `12` / close-up: right-click on the pinned Downloads folder chip (screen 1362,1087) opens one native
  menu `1363,849 288×257`: folder icon + "Downloads" + the same pill and wells, then Preview Contents,
  Open in Finder, Sort by ▸, Add Folder…, Remove from Taskbar.
- `13`: clicking the **Control Center** well closed the menu and opened the Control Centre panel
  (`1338,50 360×994`, level 3).
- Reopening each menu counts exactly one header title (`Downloads` ×1, `Trash` ×1) and the menus
  open on the right-click event with no panel round-trip.

## Still open

- App-chip menus with a custom-view row now open as native menus; menus without one still use the
  floating chip panel (unchanged).
- The widget-section menu on genuinely empty padding of the utilities island is unchanged.
- The intermittent "Developer Tools Access" system dialog from the earlier pass was dismissed; the
  synthetic right-clicks and screenshots above ran without it.
