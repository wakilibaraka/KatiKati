# Page fit — the five pages past the 1074 pt clamp, brought inside it (2026-10-15)

What `Docs/SETTINGS.md` §3's **Close-out** row left open: the close-out pass
(`evidence/2026-10-15-close-out/README.md` §1) measured ten pages and found **five still taller than
the window** — Appearance, Widgets, Window Management, Launcher and Shortcuts were all clamped to
`visibleFrame − 80` = **1074 pt** and scrolled. This pass brings those five inside the clamp without
losing a section or a control.

Every number below is read off the running app, not the source. The subject is the Debug build of
`Scripts/build_and_run.sh` (the tree of this pass), Settings open at ⌘, each page selected from its
tab.

| Artifact | What it is |
|---|---|
| `Appearance.png` … `Shortcuts.png` | the Settings window, one shot per page in its **default** state (`screencapture -x -R<window rect>`) |
| `*-ax.txt` | that page's accessibility dump of the same run (`/tmp/kktabs.swift dump`): role, x, y and text |
| `*-rows.txt` | the same page, every role with its frame (`/tmp/kkrows.swift`) |
| `*-expanded-rows.txt` | the same page with **every disclosure group opened** (`/tmp/kkpage.swift`) — the dump that shows a collapsed default hides nothing |
| `README.md` | this file |

Scratch tools live in `/tmp` by repo rule (`STANDING_RULES.md` §6): `kkpages.sh` (the ten-page height
table), `kkdeep.swift` (a page's deepest element), `kktabs.swift` (select a page / dump),
`kkrows.swift` (all roles and frames), `kkpage.swift` (select, open every group, dump),
`kktoggle.swift` (press the lowest checkbox), `kkfit-capture.sh` (this directory).

## 1. Heights (rule 10)

The window sizes itself to the page and is clamped to 1074 pt, so a window shorter than the clamp
**is** the page's height. Readings below are the same `kkpages.sh` run, after the pass:

| Page | Window | Clamped before? | Now |
|---|---|---|---|
| General | 732 | no | — |
| **Appearance** | **1066** | **yes (1074)** | fits |
| **Widgets** | **1040** | **yes (1074)** | fits |
| Notch | 1013 | no | — |
| Edge Bars | 956 | no | — |
| **Window Management** | **883** | **yes (1074)** | fits |
| **Launcher** | **1067** | **yes (1074)** | fits |
| **Shortcuts** | **807** | **yes (1074)** | fits |
| Tools | 766 | no | — |
| Advanced | 523 | no | — |

Largest window is 1067 pt against the 1074 pt clamp, so **no page scrolls** any more. The pages that
were already inside the clamp are unchanged (their numbers match the close-out set).

**These numbers no longer need a hand probe.** The checked-in gate
`Scripts/check_settings_page_heights.py` launches the built app once (`DOCK_SETTINGS_PAGE_HEIGHT=1`)
and the app measures all ten pages through **the same probe it sizes its window with**
(`SettingsWindowController.naturalContentHeight`), so the gate reports *content* heights, 88 pt below
the window heights in the table above: launcher **979**, appearance **978**, widgets 952, notch 925,
edgeBars 868, tiling 795, shortcuts 719, tools 678, general 644, advanced 435 — the tightest page has
7 pt of the 986 pt the window allows. It exits 1 by page name when one outgrows the window (proved by
temporarily starting the Shortcuts run expanded: `shortcuts 1338.0 pt … ❌`) and 2 — never 0 — when
the app is not built.

## 2. What each page gave up — cards, not controls

| Page | Change |
|---|---|
| Shortcuts | the 26 assignments and the 4 snap-hotkey groups are two `DisclosureGroup`s, collapsed by default; the card's own header row went with them (the toolbar tab already says "Shortcuts"). A find query opens both groups, so search still reaches every row |
| Window Management | the 6 tiling assignments are one collapsed group; the merged Tiling card keeps every row it had |
| Appearance | Preview + Layout Mode + Size + Fine-tune are one card (three headers and their section gaps, 156 pt); the icon rows joined the Theme card (48 pt); the sky grid's swatches are 12 pt tall and its rows 2 pt apart; the two icon previews lost 4 pt of vertical padding each |
| Launcher | `Hidden Apps` (count + Show All Hidden Apps) and `Reset App Order` share one line (`SettingsRowPair`) |
| Widgets | `Keep Both Widgets Open` and `Weather Animations` share one line; `Widget Styles & Presets` is a sub-header with its ⓘ instead of a 41 pt row; the weather card's two thresholds share one line |

`Weather Animations` moved from the weather card to the widget-animation card (same `@AppStorage`
key, same switch): it was the only row on its line there.

## 3. Nothing was dropped (rule 5)

Two independent checks:

**a. Every label literal still exists.** `diff <(git show HEAD:<file> | grep -o 'Text("[^"]*")')` vs
the working tree, over the five files this pass touched:

| File | Literals removed | Literals added |
|---|---|---|
| `SettingsAppearancePane.swift` | none | none |
| `SettingsTilingPane.swift` | none | none |
| `SettingsLayoutPane.swift` | `Preview`, `Size` (card headers, merged into the Layout Mode card) | `Reset App Order` (was a `Button(…)`, same string) |
| `SettingsWindowView.swift` | `Weather Animations` | — |
| `WidgetLookSettingsBlock.swift` | — | `Weather Animations` |

Both `Preview` and `Size` were card headers whose rows are all still on the page (`Layout Mode` is
the merged card's header); nothing else lost a literal.

**b. The control counts, three states.** Whole-window dumps, `before` = the close-out/`/tmp` scratch
baseline of the same pages, `after` = this pass in the default state, `expanded` = this pass with
every group open. Counts are controls (buttons, checkboxes, popups, radios, sliders, fields, menus),
then the roles that moved:

| Page | before | after (default) | after (expanded) | the delta |
|---|---|---|---|---|
| Shortcuts | 85 controls, 29 popups | 32 controls, 3 popups | **84 controls, 29 popups** | the collapsed run hides 26 rows; opened, all 29 popups return. −1 button: the permission-gated `Open Input Monitoring Settings` (the permission is granted now), −1 static text: the card header that became the group's label |
| Appearance | 52 | 52 | **60** | unchanged in the default state (18 statics against 20: the two merged card headers). Opened, the Fine-tune group's 5 sliders / 5 value readouts / 3 radios / 1 group are there |
| Widgets | 64 | 64 | **64** | identical in every role, default and expanded |
| Window Management | 52 | 39, 1 popup | **51, 7 popups** | the collapsed run hides the 6 tiling assignments; opened, all 7 popups return. −1 button: the permission-gated `Allow Screen Recording`, −2 statics: the `Tiling Shortcuts` header (now the group's label) and that button's note |
| Launcher | 65 | 65 | **82** | unchanged in the default state; opened, the `Hide Rarely Used Apps` list shows its 15 app checkboxes and its two buttons |

Two probes are weaker than they look, and both are noted rather than papered over:

- **A toolbar tab must be pressed on its button.** The window also draws the page's name as a static
  text in the same toolbar, and pressing that one reports success without switching — an earlier run
  of this pass dumped one page's rows under another page's name. `kkpage.swift` now matches buttons
  only, and every `-expanded-rows.txt` is checked for the page it claims.
- **A page can be taller than the window only while it scrolls**, so a one-dump "control count" on a
  clamped page is a lower bound. The counts above are page-scoped dumps of pages that now fit.

## 4. One drift found and fixed (rule 1)

The Context Presets row (Widgets page, behind its toggle) first paired its two menus with
`HStack(spacing: SettingsMetrics.controlSpacing)` around two `halfRowWidth` children: 2 × 408 + 10 =
826 pt inside an 816 pt card, and the overflow pushed the row's label **5 pt left of the grid** (37
against the page's 42) and its right menu 5 pt past it. It goes through `SettingsRowPair` now — the
same two halves with no gap — measured live at x = 42 / 450 with both menus ending on 858.

## 5. How this was verified

```
python3 Scripts/check_settings_page_heights.py   # §1's heights, from the app itself (the gate)
swift /tmp/kkpage.swift <page>       # §3b's expanded dumps
screencapture -x -R<window rect>     # the shots in this directory
diff <(git show HEAD:…)              # §3a's literal audit
xcodebuild test … CODE_SIGNING_ALLOWED=NO
python3 Scripts/check_localization.py
python3 Scripts/check_debug_switches.py
python3 Scripts/check_availability_warnings.py <build log>
```

`/tmp/kkpages.sh` (with `kktabs.swift` / `kkdeep.swift`) is how §1 was measured by hand during this
pass; the gate above replaced it, and both agree once the 88 pt of chrome is subtracted.

The interaction checks were made with real input, not the accessibility set-value path: a typed
query in the Shortcuts find field (`System Events` keystroke) opens both groups — the AX set-value
path updates the field's text without reaching the SwiftUI binding, so it cannot be used to check
that binding.
