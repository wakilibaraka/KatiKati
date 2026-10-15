# Slices 6 + 7, two rows to a line, and Advanced last — live evidence (2026-10-15)

Ten screenshots of the running app (`Scripts/build_and_run.sh --verify`) after the last source edit
of the slice, each with the accessibility dump of the same run. Nothing below is read off the source;
the numbers are the accessibility tree's own frames on the built app.

The owner's three asks, in their words: *execute slices 6 and 7* of the 10-page plan; *make the page
Advanced the last page, not Tools*; *window management, edge bar etc to use two lines* — every page
whose rows are narrow.

| Page | Shot | Extent before | Extent after |
|---|---|---|---|
| General | `General.png` | 790 pt | **708 pt** |
| Appearance | `Appearance.png` | 1479 | **1400** |
| Widgets | `Widgets.png` | 1440 | **1114** |
| Notch | `Notch.png` | 948 | 948 *(untouched on purpose — see below)* |
| Edge Bars | `Edge-Bars.png` | 955 | **914** |
| Window Management | `Window-Management.png` | 1357 | **1317** |
| Launcher | `Launcher.png` | 1291 | **1132** |
| Shortcuts | `Shortcuts.png` | 1940 | 1940 *(the pair was tried and put back — see below)* |
| Tools | `Tools.png` | 822 | **741** |
| Advanced | `Advanced.png` | 521 | **482** |

"Extent" is the y of the bottom-most element in that page's dump: where the content ends and the
scroll begins. The window is 1074 pt tall, so a page under that does not scroll.

The before-set was measured on a build of the previous commit's tree in the same session, with the
same probe (`/tmp/kktabs.swift dump`) and the same window width (900 pt).

## Slice 6 — the Shortcuts pane, and Layout emptied: verified, no work needed

The slice landed earlier as the A4 commit. Re-verified on this tree, live:

- the strip has **ten** tabs and no `Layout`: `swift /tmp/kktabs.swift tabs`;
- `press Layout` answers `ERR no tab Layout` — the page is gone rather than hidden;
- the Layout page's content reads on General (preview, mode, size), Appearance (the same geometry
  card) and the pages the plan assigned it to.

## Slice 7 — the Advanced/About tidy

`Advanced-ax.txt` is the dump; the page now reads:

- **Behaviour** — the full-screen prediction row first (it was a headerless card of one row above the
  page, which the page owed a title nothing could name), then Hold Control to Show Memory, Show
  System Helpers, **Reset Ignored Apps**, Show CPU and Memory in the Menu Bar;
- **Notifications** — `Move Notification Banners` as a shared row with its explanation behind the
  row's ⓘ, and the Position picker under it when the switch is on.

Two things the dump pins that were defects before: **Reset Ignored Apps** is disabled and now says
why on its own row (`No background app is ignored right now.`), and the notification banner's
three-line paragraph is no longer in the card — it is the row's ⓘ. The Appearance page's
**Restore Wallpaper** got the same treatment (`Turn Dynamic Wallpaper on to restore it.`). The
hand-rolled `Toggle`-beside-a-paragraph was the last row in Settings not built from the shared set.

The stale comment in `SettingsWindowController` (“我们的五个标签恒可点”) said five tabs; it says ten.

## Advanced is the last tab

The live strip, in order: **General · Appearance · Widgets · Notch · Edge Bars · Window Management ·
Launcher · Shortcuts · Tools · Advanced**. `SettingsTabTests` pins `.advanced` last and `.tools` one
before it, so dropping or reordering a case fails the suite rather than silently moving a page.

## Two rows to a line

A pair's halves are exactly `SettingsMetrics.halfRowWidth` each (408 pt at this window width). Every
page that still ran narrow rows one per line was paired: menus, segmented pickers, switches and lone
buttons share a line; sliders, text editors and rows carrying two controls stay full width. The
shots show it: General (Drawer Position | Reverse mouse scroll direction, Check for updates
automatically | Diagnostic Info), Appearance (Position | Bar Height, Dynamic Wallpaper | Mode),
Widgets (Widget Layout | Widget Colors, Clock Tile Style | Glass, Show Notes Widget | Show Stopwatch
& Countdown, the four preset menus), Edge Bars (six pairs below its sliders), Launcher (Side | Size,
Anchor | Animation, Script Commands | Show Command Hints), Tools (Copy Sounds | Copy Notifications,
Shake to Shelf | Auto-Expire), Window Management (Show All Running Apps | Hover Preview, Preview
Delay | Preview Size, the two window behaviours).

Two measurements changed the design rather than being assumed:

1. **A pair's halves have to be computed, not flexible.** An `HStack` with two `maxWidth: .infinity`
   children — and a two-column grid — both size a column by its own content, so the half holding the
   wider control took the width from the other: measured live, the right half's Record button was
   **20 pt wide, reading “…”**, against 67 pt in the left half. A pair now lays its halves out at
   `SettingsMetrics.halfRowWidth`, derived from `SettingsMetrics.windowWidth` (which
   `SettingsWindowView.contentWidth` reads), and `SettingsMetricsTests` pins that two halves make one
   card.
2. **A row with two controls does not pair.** With equal halves, the 26 Shortcuts assignments and the
   6 tiling assignments still did not fit — a name, a 154 pt menu and a Record button — and the
   Record button was squeezed to 20 pt in *both* halves. They are back to one per line: that is rule
   5's own exception, and the Shortcuts page's find field is its answer to the height.

**Notch is the one page left unpaired on purpose.** It fits the window at 990 pt, and
`Docs/SETTINGS.md` §4 freezes that page's rows until the owner's Compact-notch decision (the
decision states what the Compact skin shows, and that is this page's content). Pairing would not
move a row, but the freeze is the owner's call to lift, so the page is untouched here.

## Still owed (not claimed)

- **Five pages still exceed the window**: Appearance 1400, Widgets 1114, Window Management 1317,
  Launcher 1132, Shortcuts 1940. Their height is now section count and tall controls — the theme and
  sky grids, the five layout-mode thumbnails, Window Management's six sections against rule 5's
  three, and 26 shortcut rows behind a find field — not single-column narrow rows.
- The Launcher page's Spotlight steps are still five notes in the card (rule 4).
- macOS 12 is not tested: there is no macOS 12 machine in this session. The tree compiles for it and
  the pair uses no `#available` branch.

## Reproducing the numbers

```
swift /tmp/kktabs.swift tabs | press <page> | dump      # the strip, a tab, the page's AX tree
swift /tmp/kkwidths.swift                              # each control's width, for a squeezed one
swift /tmp/kkaxprobe.swift                             # each checkbox's VoiceOver name
```

Scratch tools live in `/tmp` by repo rule (`STANDING_RULES.md` §6).
