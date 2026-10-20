# Settings — the pages, and the rules that keep them one window

> The rules the Settings window is built to. `App/Scenes/SettingsWindowView.swift` cites this file
> (it used to cite a `settings.md` that did not exist). Every rule has a way to check it, so a
> review is a checklist and not a matter of taste.
>
> **This file is committed on purpose (2026-10-15).** The code cites it by path, so it has to
> resolve in a fresh clone; it is the one top-level `Docs/*.md` whitelisted in `.gitignore`,
> next to the published `Docs/Archive/Planning/` log. Every other `Docs/*.md` stays a
> working-tree note.
>
> Landed 2026-10-15 with the Phase 12 "form and function" pass. Slices that still have work are
> named in §3, and each one names the page that owns it.

## 1. The rules

A rule is a defect if a page breaks it unaccountably. "Check" is how to see the violation.

1. **One grid.** The window edge → content inset is `SettingsMetrics.paneMargin` (28), card → card
   `sectionSpacing` (20), header → first row `cardHeaderSpacing` (10), a row's own padding
   `rowVerticalPadding` (8), and a `SettingsGrid` cell its own `gridRowVerticalPadding` (4), a row's label → its note `rowNoteSpacing` (3), and the trailing
   control column is at least `rowMinimumLabelGap` (12) clear of its label. The window's own width
   is `windowWidth` (900) — the one number `SettingsWindowView.contentWidth` reads — so a card's
   content box is `cardContentWidth` and a `SettingsRowPair` half is `halfRowWidth`, both arithmetic
   on it rather than a guess. **No page invents an
   inset or a spacing.** *Check:* measure the left edge of the first control on each of the ten
   pages — one number, not ten; grep a page for a literal `.padding(` and find none outside a
   custom control — **except** a negative inset that cancels a platform control's own chrome (the
   Widgets list's `List`, 2026-10-15: `.listRowInsets` does not reach its rows, so it is pulled back
   by the measured 8 pt it reserves). That is a platform compensation carrying its measurement in a
   comment, not a page inventing a margin. A `SettingsGrid`'s second column starts at exactly half
   the card's content width — a grid is still one grid, not a page's own arrangement.
2. **One container.** Every page renders its sections as `SettingsCard`, and the page's own stack
   is `SettingsPane` — applied **once, by `SettingsWindowContent`**, so a page body renders cards
   and nothing else. There is no second box implementation: the old macOS 12/13+ layout split was
   retired 2026-10-15, and the floor rose to macOS 15 the same day, so no version branch is left.
   *Check:* grep `settingsGroup|groupRow|
   settingsPane|settingRow|systemForm|formStyle` → only this file and the history comments.
3. **One row type.** A row is `SettingsRow` with a named variant: `SettingsToggleRow`,
   `SettingsPickerRow`, `SettingsSegmentedRow`, `SettingsSliderRow`, `SettingsButtonRow` (and
   `PermissionRow` for grants). Alignment follows the **variant**, never the page — pickers and
   segmented controls sit at the trailing edge sized to their content, sliders share
   `labelColumnWidth` so every track starts on the same x. *Check:* a page with a hand-rolled
   `HStack { Text(…); Spacer(); control }` is a violation unless the control is itself a row
   content view (`AppearanceModeCards`, the theme grid, a preview). Open ones are listed in §3.
4. **Progressive disclosure.** A section's note is at most one line of explanation
   (`SettingsNote`). Anything longer becomes an ⓘ on the row it explains — `SettingsRow(_:note:
   info:)` / `SettingsToggleRow(_:isOn:note:info:)`, which carries the long text in a popover and
   says the same text to VoiceOver. *Check:* no card holds a paragraph; the row that explains
   scroll reversal is the pattern, and the full-screen-prediction note now uses it.
5. **Grouping before adding.** A page has at most three top-level sections; a section gets a header
   (`SettingsCard(Text("…"))`) once it passes ~8 rows; a list longer than a screenful gets a
   filter/affordance rather than a scroll. A card whose rows are long and narrow — a checklist of
   switches, a run of menus, segmented pickers or switches — uses the window's width: a checklist
   is a `SettingsGrid` (two columns), and unlike rows are paired with `SettingsRowPair`. A single
   column of four to eighteen narrow rows leaves half the card dead and runs the page past the
   screen, which is the same defect as a scroll. A pair's two halves are exactly `halfRowWidth`
   each: an `HStack` and a grid both size a column by its own content, so the half holding the
   wider control takes the width and squeezes the other one's control (measured live 2026-10-15:
   a Record button at 20 pt reading “…” against 67 pt in the other half).
   A row whose control needs the width — a slider, a text field, a row carrying a menu *and* a
   button, a row with a paragraph of its own — never pairs; it is one per line and the page's
   height is handled another way: a run of them longer than the page can show is a
   `DisclosureGroup` collapsed by default, with the page's find field opening it
   (`SettingsLayoutPane.expandedWhileFiltering`, 2026-10-15).
   *Check:* count the cards on a page; count `SettingsRow`s inside a headerless card; measure a
   grid's column starts (42 pt and half the card) and a pair's control widths (the two halves match).
6. **One control per setting, one label per row.** Two controls for the same key, or a row that
   prints its label twice (a manual `Text` beside a `Picker` that draws its own label), is a defect
   and not a style choice. *Check:* `Text("Drawer Position")` appears once in the tree — inside
   `SettingsPickerRow`, whose picker is `labelsHidden()`.
7. **State is visible.** A control that can be granted, applied or refused says so where it is: the
   permission buttons read `Grant` → `Granted ✓`; a disabled button states why on the same row; a
   shortcut that failed to register says which combination and that the previous one still stands.
   *Check:* every `.disabled(` has its reason visible on its own row, not only in a tooltip.
8. **Empty states are designed.** A text area that starts empty gets a placeholder and a one-line
   first-run hint; a preview that would draw a plain slab gets a caption, and a demo preview draws
   placeholders rather than invented values (Phase 34 witness). *Check:* open the page with default
   settings.
9. **Accessibility and i18n.** Every control carries a VoiceOver label (a `labelsHidden()` control
   takes its label from its row); every user-facing string is a whole literal the localizer can
   see — never a bare `String` interpolated into `Text`, never a label assembled from fragments.
   *Check:* `Scripts/check_localization.py` green, plus the label audit named in §3.
10. **The window is fluid; there is no height gate.** The window resizes freely down to
    `SettingsMetrics.minWindowWidth × minWindowHeight` (640×440) and each page scrolls as a whole (no
    scrolling inside a card). The old page-height clamp and its script were retired on 2026-10-20
    (owner) and nothing replaces them. *Check:* by eye — open the page you changed at the minimum
    size; switching pages never moves the left edge.

## 2. The one system

| Piece | File | What it owns |
|---|---|---|
| `SettingsMetrics` | `Core/Support/SettingsMetrics.swift` | The numbers. Pure, no AppKit/SwiftUI, unit-tested (`Tests/Unit/SettingsMetricsTests.swift`) so a page cannot re-derive the grid. |
| `SettingsPane` | `App/Scenes/SettingsCard.swift` | A page's stack: one set of cards, the page margin. Applied by `SettingsWindowContent` for all ten pages. |
| `SettingsCard` | same | One section: optional header, rows, an optional one-line note, one background. |
| `SettingsRow` + variants | same | One row shape per control type, plus `SettingsInfoButton` (rule 4) and `SettingsNote`. |
| `SettingsGrid` | same | A card's checklist in two columns (rule 5) — cells are ordinary rows. |
| `SettingsRowPair` | same | Two unlike narrow rows on one line (rule 5) — each half is an ordinary row. |
| `SettingsDivider` | same | The row separator inside a card. |

`SettingsCard.swift` is dual-compiled (it ships in the test target as well as the app), so anything
it uses must be dual-compiled too — a block that is app-target-only must be composed by the page,
never from inside a shared card. (That trap broke `xcodebuild test` once; see the tracker.)

Retired in this pass, listed so they are not reinvented:
`SettingsLayoutPane.section(header:content:)`, `SettingsWindowView`'s `settingsGroup`/`groupRow`/
`settingRow`/`settingsPane`/`systemForm`, the `sliderRow`/`edgePrefRow`/`segmentedRow` row idioms,
the `#available(macOS 13.0, *)` split in the four panes that had two copies of one page, and the
four margins (`paneMargin` 28, `systemFormMargin` 20, `afterFormMargin` 8, the literal 28).

## 3. Slice ownership — who still owes what

The pages, in tab order, with the page that owns each remaining slice. This pass landed the
foundation (rules 1–3 on every page); each slice below is its own commit.

The strip reads General · Appearance · **Dock Items** · Widgets · **Weather** · Notch · Edge Bars ·
**Tiling** · Window Management · Launcher · **Command Bar** · **Control Center** · Shortcuts ·
**Tools · Advanced** (2026-10-20: the dock's list and the widget-look rows split into Dock Items /
Widgets, Weather got its own page, Window Management split into Tiling + Window Management, and
Command Bar split off Launcher): the one page a user visits once is last (owner, 2026-10-15), so
the tools used mid-session are not behind it, and Control Center is its own dedicated tab rather than nested inside Launcher.

| Page | Owes | Rules it closes |
|---|---|---|
| **General** | Landed (2026-10-15): the About card — version + Check for Updates, auto-update, diagnostics — is this page's third section, so its budget under rule 5 is spent. Nothing owed. | — |
| **Appearance** | Landed (2026-10-15, 12f with it): the theme grid carries a one-line caption saying the swatches are previews, and the card gained the two plate sliders — **Vibrancy** (0.1–1.0, 55 % = the pre-slider look) and **Contrast** (0.5–2.0×) — shown only for a pinned theme, because Auto and System tint nothing. The two cards under the icon-set picker are previews, not a second control. Landed 2026-10-16: **Dock App Icon Shape is gone** — Phase 32d packed it, so the dock icons' frame is fixed at launch by the `DOCK_ICON_FRAME` switch (unset = today's squircle) and there is nothing left to draw. Landed 2026-10-16 (Phase 32b): **Right FAB Style** moved here from the Widgets page — the dock's right button is a look, like the icon set beside it — into the row 32d freed, so the page is back to the height it had before 32d. | — |
| **Widgets** | Landed (2026-10-15): the weather rows are on the shared row system inside their own *Weather* card, the appearance rows and the style presets share one card, and the page is **three** sections. The clock tile's row is renamed **Clock Tile Style** so it stops duplicating the dock clock's *Clock Style* (both keys unchanged). Landed 2026-10-16 (Phase 32b): the row pair's right half is now **Dock Motion** (Fluid / Snappy / Instant — how the widgets' readings move when they change), and **Right FAB Style** left for Appearance. A swap on an existing pair, never a new row: the page is still 952 pt of the 986 pt cap. | — |
| **Notch** | Landed (2026-10-15): the shape preview carries its demo caption. Still owes, jointly with the tracker's **Compact-notch** item (§4), the skin decision before this page is signed off. | §4 |
| **Edge Bars** | Landed (2026-10-15): three sections — **Edge Bars** (preset, dock-side policy, main side, keep open), **Widgets** (the tile checklist as a grid, or the custom item list on rows) and **Size & Behaviour** — every control on the row system, and the page's paragraph a card note. Nothing owed. | — |
| **Window Management** | Landed (2026-10-15): the card's four paragraphs are their rows' notes/ⓘ and its three hand-rolled `Toggle`s are `SettingsToggleRow`s (rules 3 and 4), the preview and switch rows pair, the two window behaviours are one line, and the app-override list is on `SettingsRow`. Landed (2026-10-15): **three** sections — one **Tiling** card (Enable, Preset, the two gaps, Floating Applications and Tiling Shortcuts, the last two keeping their own labels inside the card), **Window Chips** and **Window Behaviour**. That was a regroup, not a row change: no row, key or value moved. The tiling assignments stay one per line: a name, a menu and a Record button do not fit half a card (measured). | — |
| **Launcher** | Landed (2026-10-15): the page is the launcher, the Control Center and the launcher's own rows (`LauncherSettingsBlock`), with the Control Center's widget and quick-setting checklists and the launcher's hidden-app list as two-column grids. Landed (2026-10-15): the hand-off's five steps are **Replace Spotlight**'s ⓘ (`SettingsButtonRow` gained the missing `info:` slot); each step stays a whole literal, joined with newlines rather than assembled. | — |
| **Tools** | Landed (2026-10-15): clipboard, commands, snippets and shelf, in the slot About left. Landed (2026-10-15): the two editors are one **Commands & Snippets** card (four sections → three) and both carry a placeholder while empty (new `SettingsEditorRow`; rule 8). The Clipboard card's doubled divider is gone. | — |
| **Shortcuts** | Landed (2026-10-15): the page is three sections — **Shortcuts** (a find field, the eleven feature actions, the fifteen snap zones under their captions), **Keyboard** (the input behaviours) and **Radial Dial** — with every row on the shared system, every long note behind its row's ⓘ, the pickers named for VoiceOver and the four snap captions translated. The 26 assignments were tried two per line and put back: three controls do not fit half a card (measured live 2026-10-15, the Record button squeezed to 20 pt in both halves), which is rule 5's own exception. The assignments and the four snap groups are therefore two `DisclosureGroup`s collapsed by default (2026-10-15), with the find field opening both — the page fits the window at 807 pt. | — |
| **Advanced** | Landed (2026-10-15): the notification banner paragraph is its row's ⓘ and the row is a `SettingsToggleRow` (rules 3 and 4), **Reset Ignored Apps** says why it is disabled on its own row (rule 7), and the headerless one-row card above the page was folded into **Behaviour** — one row is not a section, and the page owed a title it could not name. Two sections, each with a header; the page fits the window. | — |
| **About** | Gone as a page (2026-10-15); its four rows are the About card on General, and the tab it freed is Tools. | — |
| **All pages** | **Accessibility audit — done (2026-10-15), and the earlier note here was wrong.** It claimed ~18 `labelsHidden()` toggles exposed no label; it had been read off `AXTitle`, which a SwiftUI toggle leaves empty while it puts the name on `AXDescription`. Every checkbox on all ten pages was then probed for `AXDescription`/`AXTitle`/`AXHelp` on the running build: **one** control was genuinely unnamed, the Widgets page's **Glass** switch (`GlassTilesToggle`), and it now carries its row's name. Repro: press each tab and read `AXDescription` on every `AXCheckBox` — ten pages, zero empty. Read `AXDescription` when auditing a toggle, not `AXTitle`. | — |
| **Layout-pane leftovers** | Landed (2026-10-15): the two hand-rolled `HStack` row lists are gone — the window-chip app list (old `:442`) is on `SettingsRow`, the quick-setting list (old `:1267`) and the launcher's hidden-app list are `SettingsGrid`s. Standalone buttons and disclosures inside a card are controls, not rows (rule 3). | — |
| **Rows two per line** | Landed (2026-10-15, owner: "window management, edge bar etc to use two lines"): every page's narrow rows — menus, segmented pickers, switches, lone buttons — pair, with a pair's halves exactly `halfRowWidth` each; sliders, editors, rows with two controls and rows with a long note stay full width. Measured live against the previous build: Widgets 1440 → 1114 pt, Launcher 1291 → 1132, General 790 → 708, Appearance 1479 → 1400, Edge Bars 955 → 914, Tools 822 → 741, Advanced 521 → 482, Window Management 1357 → 1317. **Appearance (1400), Widgets (1114), Window Management (1317), Launcher (1132) and Shortcuts (1940) still run past the 1074 pt window** — their height is section count and tall controls, not single-column rows. | 5, 10 |
| **Close-out** | **Done (2026-10-15).** After-shots of the ten pages against the before-set (`Docs/Repository/settings-sweep-2026-10.md` plus the 2026-10-15 capture), measured margins and section gaps (the macOS 12 parity read-through is **retired**: the floor is macOS 15 since 2026-10-15, so there is no 12 path left to check), and the Better Design review the plan asks for — evidence and numbers in `Docs/Archive/Planning/evidence/2026-10-15-close-out/README.md`: card content at **42 pt on all ten pages**, every section gap **20.0 pt**, **5 of 10 pages taller than the window** (rule 10's own walls, §3 above), and its one serious finding — the Widgets page's reorderable `List` painting its own well and drawing its rows 8 pt off the grid — **fixed the same day** (`listRowInsets` does not reach a macOS `List`; the row height now derives from `SettingsMetrics` and drag reordering is unchanged, re-shot in the same directory). | 1, 10 |

## 4. Where the Compact-notch decision attaches

The tracker carries an owner note (2026-10-15, HYBRID_PLAN, "Owner note — the Compact notch needs
plan work"): **Compact** is the `classic` `LiveIslandSkin`, drawn from `NotchLayoutSpec`, and its
silhouette, sizing and content were never designed against the reference layout the `boring` skin
follows.

It attaches **here**: the **Notch page** owns it (§3), because that page carries the skin row and
the skin's demo preview (`LiveIslandSettingsBlock` → `NotchPreview`, `NotchGeometry.previewSize`).
Until the decision is recorded in the tracker:

- the Notch page is **not signed off**, and its demo preview stays labelled as a demo (rule 8);
- the Notch page's card list is **frozen** — no compaction slice may move rows off or onto it,
  because the decision will state what the Compact skin shows, and that is this page's content;
- the compaction work (rule 5's splits) may proceed on Edge Bars, Widgets, Shortcuts and Tools —
  those pages do not touch `NotchLayoutSpec`.

## 5. Verifying a change to a page

1. `xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS'
   CODE_SIGNING_ALLOWED=NO` — the whole suite, including `SettingsMetricsTests`.
2. `python3 Scripts/check_localization.py`, `python3 Scripts/check_debug_switches.py` and
   `python3 Scripts/check_availability_warnings.py <clean build log>` — rule 9's mechanical half.
3. Run the window and measure, don't assume. The 2026-10-15 before-set recorded the card-content
   left inset running 20 / 28 / 42 / 108 pt across the ten pages; after the migration it is 42 pt
   on all ten. A number you touch must move toward the grid, not away from it.
4. Screenshot the page before and after. A UI slice without its shots is unfinished
   (`STANDING_RULES.md` §6.5).
