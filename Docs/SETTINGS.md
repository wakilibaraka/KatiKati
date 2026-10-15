# Settings — the ten pages, and the rules that keep them one window

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
   `rowVerticalPadding` (11), a row's label → its note `rowNoteSpacing` (3), and the trailing
   control column is at least `rowMinimumLabelGap` (12) clear of its label. **No page invents an
   inset or a spacing.** *Check:* measure the left edge of the first control on each of the ten
   pages — one number, not ten; grep a page for a literal `.padding(` and find none outside a
   custom control.
2. **One container.** Every page renders its sections as `SettingsCard`, and the page's own stack
   is `SettingsPane` — applied **once, by `SettingsWindowContent`**, so a page body renders cards
   and nothing else. There is no second box implementation and no `#available` branch in the
   layout: macOS 12 and 13+ go through the same code. *Check:* grep `settingsGroup|groupRow|
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
   filter/affordance rather than a scroll. *Check:* count the cards on a page; count `SettingsRow`s
   inside a headerless card.
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
10. **The window fits its content.** The window is a fixed 900 pt wide
    (`SettingsWindowView.contentWidth`); pages must not demand more, and a page taller than the
    screen scrolls as a whole (no scrolling inside a card). *Check:* the height probe measures each
    page; switching pages never moves the left edge. Pages that still exceed the 1074 pt window are
    the walls §3 names.

## 2. The one system

| Piece | File | What it owns |
|---|---|---|
| `SettingsMetrics` | `Core/Support/SettingsMetrics.swift` | The numbers. Pure, no AppKit/SwiftUI, unit-tested (`Tests/Unit/SettingsMetricsTests.swift`) so a page cannot re-derive the grid. |
| `SettingsPane` | `App/Scenes/SettingsCard.swift` | A page's stack: one set of cards, the page margin. Applied by `SettingsWindowContent` for all ten pages. |
| `SettingsCard` | same | One section: optional header, rows, an optional one-line note, one background. |
| `SettingsRow` + variants | same | One row shape per control type, plus `SettingsInfoButton` (rule 4) and `SettingsNote`. |
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

The ten pages, in tab order, with the page that owns each remaining slice. This pass landed the
foundation (rules 1–3 on every page); each slice below is its own commit.

| Page | Owes | Rules it closes |
|---|---|---|
| **General** | Landed (2026-10-15): the About card — version + Check for Updates, auto-update, diagnostics — is this page's third section, so its budget under rule 5 is spent. Nothing owed. | — |
| **Appearance** | Theme cards get a caption (rule 8) while 12f contrast is open. *Not* a duplicate, checked live 2026-10-15: **Icon Set** and **Dock App Icon Shape** are two different settings (menu-bar icon set vs dock icon masking), and the two cards under the picker are previews, not a second control. | 8 |
| **Widgets** | Landed (2026-10-15): the weather rows are on the shared row system inside their own *Weather* card, the appearance rows and the style presets share one card, and the page is **three** sections. The clock tile's row is renamed **Clock Tile Style** so it stops duplicating the dock clock's *Clock Style* (both keys unchanged). Nothing owed. | — |
| **Notch** | Owns the demo preview's caption and, jointly with the tracker's **Compact-notch** item (§4), the skin decision before this page is signed off. | 8, §4 |
| **Edge Bars** | ~28 controls in one card: split into sections, header on each (rule 5). | 5 |
| **Window Management** | Window Chips' two-line note → the row's ⓘ (rule 4). | 4 |
| **Launcher** | Landed (2026-10-15): the page is the launcher, the Control Center and the launcher's own rows (`LauncherSettingsBlock`). Owes: the Spotlight steps' four hard-coded lines become that row's ⓘ. | 4 |
| **Tools** | Landed (2026-10-15): clipboard, commands, snippets and shelf, in the slot About left. Owes: placeholders + first-run hints on the two editors (rule 8), and it carries four sections against rule 5's three — merge the two editor cards or move Shelf. | 5, 8 |
| **Shortcuts** | ~35 rows into sections, plus a filter (rule 5) — the largest wall left. | 5 |
| **Advanced** | Notification banners' note runs to three lines, so it belongs on that row's ⓘ (rule 4). **Reset Ignored Apps** is disabled with no reason on its row — say why (rule 7). | 4, 7 |
| **About** | Gone as a page (2026-10-15); its four rows are the About card on General, and the tab it freed is Tools. | — |
| **All pages** | **Accessibility audit**: ~18 `labelsHidden()` toggles (Edge Bars tiles, Control Center widgets, several Chips switches) expose no label to VoiceOver, and the Appearance behaviour toggles likewise. Rule 9 is not satisfied until each row names its control. | 9 |
| **Layout-pane leftovers** | Two cards in `SettingsLayoutPane` still build rows by hand (`:442` window-chip app list, `:1267` quick-toggle list) — both belong on `SettingsRow` before Edge Bars and Window Management are signed off. | 3 |
| **Close-out** | After-shots of the ten pages against the before-set (`Docs/Repository/settings-sweep-2026-10.md` plus the 2026-10-15 capture), measured margins and section gaps, macOS 12 parity read-through (this tree compiles for 12; there is no macOS 12 machine in the session), and the Better Design review the plan asks for. | 1, 10 |

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
