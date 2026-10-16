# Phase 12 Close-out — the ten pages measured, shot, and reviewed (2026-10-15)

What `Docs/SETTINGS.md` §3's **Close-out** row owes: after-shots of the ten pages against the
before-set, the measured margins and section gaps, and the Better Design review the plan asks for
(`Docs/Repository/settings-10-pages-plan.md`, slice 8).

Every number below is read off the running app, not the source. The subject is the installed
Release build — `/Applications/KatiKati.app`, 0.17.0 (51), the tree at `a1a60a0` — with the Settings
window open at ⌘, and each page selected from its tab.

| Artifact | What it is |
|---|---|
| `General.png` … `Advanced.png` | the Settings window, one shot per page (`screencapture -x -R<window rect>`, 20:15) |
| `*-ax.txt` | that page's accessibility dump of the same run (`/tmp/kktabs.swift dump`): role, x, y and text |
| `*-rows.txt` | the same page with **every** role and its size (`/tmp/kkrows.swift`) — the frames the geometry below is computed from |
| `label-audit.txt` | every `AXCheckBox` of the ten pages with its VoiceOver name (`/tmp/kkaxprobe.swift`), re-run on this build |
| `Widgets-after.png`, `Widgets-after-ax.txt`, `Widgets-after-rows.txt` | the Widgets page **after F1 was fixed** (23:31, the Debug build of the fix via `Scripts/build_and_run.sh`; same capture shape as the ten above) |
| `README.md` | this file |

Scratch tools live in `/tmp` by repo rule (`STANDING_RULES.md` §6):
`kkcloseout-capture.sh` (shots + dumps), `kkcloseout-rows.sh` (frames), `kktabs.swift`, `kkrows.swift`,
`kkcloseout-review.py` (heights, insets, bands), `kkcloseout-pixels.py` (the card bands, measured in
the shots' pixels), `kkattr.swift` (all four AX attributes of a control), `kkscrollbar.swift`.
The F1 re-shot used `kkf1-capture.sh` (same shape as the capture above), `kkf1-pixels.py` (the list's
well and its row ink, in the shots' pixels) and `kkdrag.swift` (a real mouse drag, for the reorder).

## 1. Heights (rule 10)

The Settings window sizes itself to the page and is clamped to `visibleFrame − 80`, which on this
machine is **1074 pt**. So a window shorter than the clamp **is** the page's height — and the pixel
check agrees: on those five pages the last card's bottom edge coincides with the window's bottom
edge (General 731/732, Notch 1012/1013, Edge Bars 955/956, Tools 765/766, Advanced 522/523). At the
clamp the page is taller than the window and scrolls; a single dump can only expose part of it, so
the "deepest element" column is a **lower bound** there, not a height.

| Page | Window (page height) | Deepest element in the dump | Content bottom edge | Scrolls? |
|---|---|---|---|---|
| General | 732 | 708 (`AXButton` Show Setup Guide Again) | 732 | no |
| Notch | 1013 | 971 (`AXStaticText` Teleprompter Notch Page) | 1013 | no |
| Edge Bars | 956 | 914 (`AXStaticText` Sync Notes with iCloud Drive) | 956 | no |
| Tools | 766 | 724 (`AXStaticText` System Dock) | 766 | no |
| Advanced | 523 | 482 (`AXButton` Move Notification Banners' switch) | 523 | no |
| Appearance | **1074** (clamped) | ≥1410 (`AXButton` Built-in Sky) | ≥1434 | **yes** |
| Widgets | **1074** (clamped) | ≥1114 (`AXCheckBox` Show) | ≥1130 | **yes** |
| Window Management | **1074** (clamped) | ≥1126 (`AXButton`) | ≥1150 | **yes** |
| Launcher | **1074** (clamped) | ≥1054 (`AXButton`) | ≥1074 | **yes** |
| Shortcuts | **1074** (clamped) | ≥1940 (`AXStaticText` Radial Dial note) | ≥1953 | **yes** |

The dumped extents here agree with the A5/A8 record on the two pages it could read exactly
(Widgets 1114, Shortcuts 1940) and run lower on the other three because a page past the clamp is
only partly exposed. **A page's height past the clamp is not measurable from one dump** — the
honest reading is "≥1074, and the page scrolls".

Five pages therefore still run past the window (Appearance, Widgets, Window Management, Launcher,
Shortcuts); five fit it. That is rule 5's own wall, not a row-spacing defect — the section count and
the tall controls (the theme grid, the five layout-mode thumbnails, Window Management's three
sections, 26 shortcut rows behind a find field).

## 2. Margins (rule 1)

**The card content starts at x = 42 pt on all ten pages** — one number, not ten — with the pane
margin at 28 and the cards' own left edge at 28. Two things sit left of 42, and neither is a grid
drift:

- **General's `Show Setup Guide Again` at x = 28**, the pane margin, outside every card. Deliberate
  (`SettingsWindowView.welcomeGuideButton`: the box holds settings, this is the entry point to
  another window) and the only element on the ten pages outside a card.
- **The two `DisclosureGroup`s report x = 19.5 in the accessibility tree** (Appearance's
  *Fine-tune*, Launcher's *Hide Rarely Used Apps*) — but they are **drawn at x = 43.5**, on the grid:
  measured in the shot, the ink on those rows runs 43.5–115 (Appearance) and 43.5–191.5 (Launcher)
  pt, and the luminance profile shows no ink at all between 14 and 28 pt. An AX frame artifact, not a
  visual defect. (See §5 F3.)

**Row rhythm.** A row's pitch is the control's own height plus 16 pt of padding plus the 1 pt
divider: 41 pt for a 24 pt control (a switch, a popup), 69 pt for the 52 pt `AppearanceModeCards`.
Verified on General, whose first four rows start at y 110 (the language popup), 151 (the three
appearance cards), 223 (the shortcut recorder's glyph) and 261 (the drawer-placement popup).

## 3. Section gaps (rule 1)

A `SettingsCard`'s background has no accessibility element, so the card-to-card gap is measured where
a reader sees it — in the shots, comparing a column inside the cards (x = 100 pt) with one on the
pane margin beside them (x = 6 pt), row by row, against the same row (the pane background carries a
slight vertical gradient).

**Every card-to-card gap is exactly 20.0 pt** = `SettingsMetrics.sectionSpacing`:

| Page | Card-to-card gaps (start–end, pt) |
|---|---|
| General | 20.0 (307–327), 20.0 (533–553), 20.0 (688–708) |
| Appearance | 20.0 (214–234), 20.0 (404–424), 20.0 (559–579), 20.0 (631–651), 19.0 (709–728), 20.0 (882–902), 20.0 (1025–1045) |
| Notch | 20.0 (580–600) |
| Edge Bars | 20.0 (287–307), 20.0 (410–430) |
| Window Management | 20.0 (668–688), 20.0 (1014–1034) |
| Launcher | 20.0 (434–454), 20.0 (898–918) |
| Tools | 20.0 (264–284), 20.0 (529–549) |
| Advanced | 20.0 (409–429) |
| Shortcuts | none visible — its first card runs past the window's bottom edge, so its boundaries are below the fold in this shot |
| Widgets | 20.0 (388–408), 20.0 (708–728) — **then the widget list's own well (§5 F1)**, whose runs measure 17.5, 13.5, 16.5, 18.5, 37.0, 16.5, 10.5, 37.0, 62.0 |

Cross-check from the AX frames: from the last element's bottom edge to the next card's header top
the gap is **56 pt** wherever the card ends in a one-line note (General ×2, Appearance ×4, Widgets,
Advanced) — 20 pt of `sectionSpacing` plus the two cards' padding and the header's own leading. The
48–62 pt spread elsewhere is the last element's own AX height (15 pt for a note, 24 for a control),
not a page inventing a margin.

The whole-page edge case the row also names: **`SettingsMetrics`' numbers are the only ones used** —
no page grew its own inset in this pass, and the one number that moved in the wrong direction is
F1's list.

## 4. The shots, and what they pair with

| Page | This set | Before-set |
|---|---|---|
| General, Appearance, Widgets, Notch, Edge Bars, Window Management, Launcher, Shortcuts, Tools, Advanced | `<page>.png` | `../2026-10-15-settings-pass/before-*.png` (08:51, the tree before the "form and function" pass) |
| Edge Bars, Launcher, Window Management | the same shot | `../2026-10-15-density-pass/before-*.png` (a scratch worktree of the previous commit) |
| all ten | the same shot | `../2026-10-15-advanced-pairs/*.png` (the A5 after-set) |

Captured after the last source edit of the phase, so each shot is the shipped layout. The three
earlier sets are unchanged and still the record for their own slices; this set is the one the
Close-out row names.

## 5. The Better Design review

The plan's slice 8 named the Better Design MCP tools (`get-review-rules`, `check-comprehension`,
`inspect-spacing`). **Those tools are not available in this session**, so this review was run by hand
against `Docs/SETTINGS.md`'s ten rules — the same checks on the same rendered evidence: the
accessibility frames, the pixels of the shots, and the strings actually drawn.

| Rule | Check on the running app | Result |
|---|---|---|
| 1 · One grid | left inset per page; card-to-card gap; row pitch | **42 pt on all ten**; **20.0 pt** gaps (§2, §3); pitch = control + 17 |
| 2 · One container | the pages' cards are `SettingsCard`; nothing else draws a box | pass — F1's list was painting its own background *inside* a card, **fixed** |
| 3 · One row type | every page's rows go through `SettingsRow` and its variants | pass — F1's list was the exception, **fixed** |
| 4 · Progressive disclosure | no card holds a paragraph; the long texts are their rows' ⓘ | pass |
| 5 · Grouping before adding | ≤3 sections a page; narrow rows paired; grids two-column | pass — the five pages past the window are section count, not single-column rows |
| 6 · One control per setting, one label per row | a label printed twice | pass — the two apparent duplicates on Tools are F3(a) |
| 7 · State is visible | a disabled control states why on its own row | pass (Reset Ignored Apps, the permission rows) |
| 8 · Empty states are designed | the editors' placeholders; the Notch demo caption | pass — placeholders are drawn and are the long hints (F3(a)) |
| 9 · Accessibility and i18n | `check_localization.py`; the label audit | pass — both re-run on this build: `check_localization.py` exits 0 (**880 keys × 12 languages**), and `label-audit.txt` in this directory is **76 checkboxes across the ten pages, 0 without a name** (read `AXDescription`, not `AXTitle`) |
| 10 · The window fits its content | the window height per page vs 1074 | **5 of 10 pages scroll** — the walls §1 names |

**Findings, ranked.** F1 was the one serious finding and is **fixed** (the owner asked to see the
findings first, then to implement it); F2–F4 are recorded, with no change proposed.

### F1 — serious · the Widgets page's widget list is a `List`, not the row system — **FIXED (2026-10-15)**
`App/Scenes/SettingsLayoutPane.swift:821–842` puts a plain-styled `List` (with `.onMove` for drag
reordering) inside a `SettingsCard`. Measured, on the running app (before):

- **it paints its own well in the window's background colour**: luminance 35 across x = 60…850 pt,
  y = 832…1018, against the card's 42 — a 816 × 186 pt hole in the card's surface. The same well is
  in the committed before-set (45 against 52), so it is not a regression from this phase, but it is
  the one place a card does not read as a card;
- **its row labels are drawn at 50.5–51 pt** against the page's 42 pt grid (ink start of each row:
  Launcher 50.5, Weather 51.0, Apps 50.5, Now Playing 50.5) — rule 1's "one number, not ten";
- **its rows are 38 pt apart** (`AXRow` y 838/876/914/952/990/1028) against the page's 41 pt rhythm;
- **its height is a literal**, `count * 38 + 24`, so it does not follow `SettingsMetrics` — the one
  control on the ten pages whose geometry is not derived from the grid.

**Fixed the same day, on the owner's word.** The `List` and its `.onMove` stay — drag reordering is a
feature, not to be cut — and it now sits on the card's grid. Measured on the fix
(`Widgets-after.png`, `Widgets-after-ax.txt`, `Widgets-after-rows.txt`; the row numbers below are
window-relative, the pixel numbers are read out of the shot at 2x):

| | before | after |
|---|---|---|
| the list's own well | 34.6 luminance (the window background) across the list's band | **gone**: 41.6 (the card's fill) from y 804 to 1068 at x = 300, against the pane's own 34.6 |
| row label | AX x = 50, ink at 50.5 | **42 pt** (ink at 43 — the same glyph side-bearing as the card's other rows) |
| row pitch | 38.0 pt | **41.0 pt** — rows at y 838 / 879 / 920 / 961 / 1002 / 1043, each 41 pt tall, the page's own rhythm |
| between rows | nothing | the `List`'s separator, spanning x = 42…865 — the card's grid, because the row's pitch now includes the 1 pt divider |
| list height | `count * 38 + 24`, a literal | `count *` the grid's row rhythm, derived from `SettingsMetrics` |
| drag to reorder | worked | **works** — a real mouse drag moved *Launcher* from first to last and back, checked in the AX frames after each drag |

Three platform facts the fix records in the code, all measured rather than assumed: `.listRowInsets`
does **not** reach the plain macOS `List`'s row chrome (a leading inset of 0 changed nothing — the
labels stayed at 50 pt; the rows live in an `NSOutlineView` that reserves the leading 8 pt), so the
list is pulled back by that measured inset; `.listRowSpacing` — the API that would zero row spacing —
is **unavailable on macOS** (checked in the SDK's `SwiftUI.swiftinterface`: `@available(macOS,
unavailable)`); and the row height is derived from `SettingsMetrics` (`24 + 2 × rowVerticalPadding +
1`), so it follows the grid if the padding ever moves rather than pinning a second rhythm.

### F2 — minor · recorded, no change proposed
General's `Show Setup Guide Again` sits at the pane margin (28), outside every card (§2). Deliberate
and documented; listed so the next review does not re-derive it.

### F3 — minor · two accessibility-tree traps this review had to disprove
Both are cases where the AX tree disagrees with what is drawn; a review that reads the tree alone
would report two defects that do not exist.

- **The `SettingsEditorRow` placeholder reports the row's name as its value.** On Tools, the tree
  shows `AXStaticText` "Custom Commands" twice (y 332 at x 42 — the row's label — and y 359 at x 47,
  the placeholder's position), so it looks like a label printed twice (rule 6). The pixels say
  otherwise: the ink on that line runs from x = 45 pt past 600 pt, which is the hint
  ("One command per line: ;name = /path/to/script"), not the 15-character label. Rule 8 holds.
- **A SwiftUI `DisclosureGroup` reports its header at x = 19.5 while drawing at 43.5** (§2).

### F4 — minor · the five pages past the window
Appearance, Widgets, Window Management, Launcher and Shortcuts scroll (§1). Rule 10 allows it; §3 of
`Docs/SETTINGS.md` names them as the walls each page's own grouping job. No row-spacing fix is
proposed here.

## 6. Not claimed

- **No visual read of the shots.** The app was driven and measured; the gradients, the notch tint,
  the two new plate sliders and the shortened pages were not eyeballed. The shots are for the owner's
  eye, and the review above is geometry, strings and pixels — not taste.
- **The Better Design MCP tools were unavailable** (§5), so their rule sets were applied by hand.
- **The Notch page is still frozen** by the owner's Compact-notch decision (`Docs/SETTINGS.md` §4);
  its rows were not touched and it is not signed off.
- **No macOS 12 parity check** — the floor is macOS 15 since 2026-10-15.
- **F1 is implemented; F2–F4 are not** (§5). F2 and F3 are records of things that are not defects,
  and F4 is the five pages that scroll — not a row-spacing fix.
- **The F1 after-shot is a Debug build** (`Scripts/build_and_run.sh`, the dev loop of §4.4) taken on
  the current tree, while the ten-page set above is the installed Release build of `a1a60a0`; the
  tree also carries other threads' in-flight work (phases 41/42), which is why the Widgets page has
  a `Widget Appearance` card the earlier shot does not. The widget-list region is what is compared,
  and layout does not vary by configuration — but the two shots are not from one build.
- **The reorder check is a real drag, not a unit test.** The list's geometry is a view property with
  no unit-test surface (the arithmetic is a `private static` on a dual-compiled view), so the witness
  is the live AX frame set and the two drags; `Tests/Unit/SettingsMetricsTests.swift` still pins the
  grid itself.
