# The density pass + the Edge Bars page — live evidence (2026-10-15, plan step A5)

Six screenshots of three pages, before and after, each with the accessibility tree of the same run.
The window is 900 × 1074 pt in every one of them.

| Page | Before | After |
|---|---|---|
| Edge Bars | `before-Edge-Bars.png` | `after-Edge-Bars.png` |
| Launcher | `before-Launcher.png` | `after-Launcher.png` |
| Window Management | `before-Window-Management.png` | `after-Window-Management.png` |

The `*-ax.txt` files next to each are the dumps (`/tmp/kktabs.swift dump`).

## How the two sides were produced

The **after** side is the working tree after the last edit of the slice, built with
`Scripts/build_and_run.sh --verify`. The **before** side is a scratch worktree of the previous commit
(`git worktree add /tmp/kk-before HEAD`, then the same script) — not an older screenshot, so the only
difference between the two sides is this slice.

"Content extent" below is the y of the bottom-most element in the accessibility tree of the page,
which for a page taller than the window is where the content ends and the scroll begins. The window
height is 1074, so a page whose extent is under that does not scroll.

## Measured, before → after

| Page | Content extent | What the change is |
|---|---|---|
| **Edge Bars** | **1033 → 955 pt** | Three sections (Edge Bars / Widgets / Size & Behaviour) where one card held ~28 controls; the tile checklist is two columns; the six sliders keep the card's width and the nine narrow rows pair up two per line; the page's paragraph is the first card's note |
| **Launcher** | **1451 → 1291 pt** | The Control Center's four widget checkboxes are two rows and its eighteen quick settings are nine rows, in two columns |
| **Window Management** | **1415 → 1328 pt** | The app-override list is on `SettingsRow`, and every row is 8 pt tighter as the window's shared rhythm |

Facts read off the dumps, not inferred:

- **The two columns exist and line up.** The left column's labels start at x = 42 with their
  checkboxes at 396; the right column starts at x = 450 — half the card's content width, which is
  where `SettingsRowPair`'s right half starts too, so a grid and a pair in the same card agree —
  with its checkboxes at 804. The Control Center's quick settings read the same two columns
  (Dark Mode | Keep Awake, Hide Desktop | Hidden Files, … Relaunch Finder | Screen Mirroring), in
  reading order.
- **The checklist kept its control.** A cell is a checkbox (`SettingsCheckboxRow`) at
  `SettingsMetrics.gridRowVerticalPadding` (4) — 26 pt rows, against 40 for a settings row. That is
  what makes the grid a height win: the old single columns were 17–22 pt rows, so a two-column grid
  of 40 pt switch rows would have been *taller* than before. Measured on the Launcher page: the
  eighteen quick settings were 306 pt in one column and are 235 pt in the grid.
- **The edge bars page is one grid.** `Edge Bars` (preset, dock-side policy, main side, keep open,
  then the page's one-line note), `Widgets` (the tile checklist, or the custom item list on rows),
  `Size & Behaviour` (sliders full width, then the pairs). Nothing was dropped: the dump still shows
  all 28 controls.
- **No setting moved.** `defaults export com.katikati.app` taken before and after the runs differs
  only in the app's own rewritten blobs (`wallpaper.original.v1`) and in window tab-group state, plus
  two clipboard switches (`Copy Sounds`, `Copy Notifications`) that something set to `true` between
  the two snapshots and that were written back to `false` and re-checked across a relaunch.

## The label audit this slice owed, and its result (rule 9)

`Docs/SETTINGS.md` §3 recorded ~18 `labelsHidden()` toggles with no VoiceOver label. That record was
wrong: it had been read off `AXTitle`, which a SwiftUI toggle leaves empty while it puts the name on
`AXDescription`. Every `AXCheckBox` on all ten pages was probed for `AXDescription` / `AXTitle` /
`AXHelp` against the running build (`/tmp/kkaxprobe.swift`), and **one** control was genuinely
unnamed — the Widgets page's **Glass** switch, at y = 259 among six named checkboxes. It now carries
its row's name (`WidgetLookSettingsBlock`), verified on the rebuilt app: `label-audit.txt` is the
probe's own output for the ten pages after that fix — **76 checkboxes, 0 with an empty name**. Read
`AXDescription` when auditing a toggle, not `AXTitle`.

## Still owed on these pages (not claimed here)

The Window Management and Advanced paragraphs that belong behind their rows' ⓘ (rule 4), and any
rendering on macOS 12.
