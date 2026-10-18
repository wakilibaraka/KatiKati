# 2026-10-18 — live walk of the redesigned Settings window and the vertical dock rails

`Scripts/build_and_run.sh run` was used the normal way (own Debug build of the working tree, `open`ed so
TCC attributes it to KatiKati), then every page and every dock placement below was driven through the
UI a user would use. Two defects turned up in the walk and were fixed in this same working tree; the
captures that proved them are here, before and after.

## How it was driven

| step | mechanism |
| --- | --- |
| the build | `Scripts/build_and_run.sh run` (`** BUILD SUCCEEDED **`, then the app `open`ed from `build/DerivedData/Build/Products/Debug/KatiKati.app`) |
| opening Settings | `osascript` → the app menu's `Settings…` item |
| switching pages | the native toolbar item for each tab (`… to tell window "<current>" to tell toolbar 1 to click button "<tab>"`), the same route a click takes |
| reading what rendered | the app's own accessibility tree (`AXUIElementCopyAttributeValue` walker: role / title / value / frame) |
| reading what is on screen | `screencapture -x -o -l <window id>` (window id from `CGWindowListCopyWindowInfo`), then Vision OCR of the PNG |
| the dock controls | `AXPress` on the Appearance page's `Position` radio group (`Bottom` / `Left` / `Right`) and its `Layout Mode` buttons — the controls' own accessibility elements |
| the dock panels | the panel window itself, captured by window id from `CGWindowListCopyWindowInfo` (layer 3, largest KatiKati window) |

Every page capture was checked two ways: the OCR of the PNG has to contain a marker string that only
that page carries, and the accessibility tree has to agree. A capture whose page did not match its tab
would fail the marker check.

## The eleven pages (window 940 pt wide, as the window sizes itself)

> The sizes in this table are from **before** the fit pass below: they are the window as the old probe
> sized it (page only, no nav bar). The post-pass numbers are in §"The ten pages after the pass".

| # | page | window | marker that verified it |
| --- | --- | --- | --- |
| 01 | General | 940×737 | `Show/hide taskbar shortcut` |
| 02 | Appearance | 940×1074 | `Layout Mode` |
| 03 | Widgets | 940×1040 | `Widget Appearance` |
| 04 | Notch | 940×916 | `Live Island` |
| 05 | Edge Bars | 940×957 | `Main Side` |
| 06 | Window Management | 940×919 | `Enable Auto-Tiling` |
| 07 | Launcher | 940×608 | `Scroll Direction` |
| 08 | Control Center | 940×529 | `Control Center` |
| 09 | Shortcuts | 940×932 | `Search Shortcuts` |
| 10 | Tools | 940×1037 | `Clipboard` |
| 11 | Advanced | 940×524 | `Behaviour` |

`settings-wide-*.png` are the same pages at 1240 pt, where `SettingsBentoSplit` puts General, Launcher
(and the other bento pages) into two columns; Launcher at 1240 is 424 pt tall against 786 pt in the
pre-fix build, which is the point of the second fix below.

## Defect 1 — the page rendered one selection behind (fixed)

`SettingsWindowController.present()` had gained a Combine sink on `tabState.$selected`. `@Published`
publishes in **willSet**, so the sink ran while `tabState.selected` still held the page the user was
leaving — and it forced a synchronous `layoutSubtreeIfNeeded()` of a height-probe hosting view from
inside that publish. What the user saw: the title, the toolbar highlight and the window height all
followed the new tab, while the page body stayed on the previous one.

Captured before the fix (accessibility trees, window header first, then the page's own first rows):

| file | window title | what was on screen |
| --- | --- | --- |
| `tablag-before-ax-tree-control-center-title-with-widgets-page.txt` | Control Center | Widgets (`Widget Appearance`, `Widget Layout`, `Widget Colors`) |
| `tablag-before-ax-tree-advanced-title-with-tools-page.txt` | Advanced | Tools (`Clipboard`, `Clean Copied Links`, `Copy Sounds`) |
| `tablag-before-ax-tree-widgets-title-with-general-page.txt` | Widgets | General (`Language`, `Appearance`, `Show/hide taskbar shortcut`) |

The walk that produced those captures opened 11 tabs; 8 of them failed the marker check, and the three
that appeared to pass did so only because their marker string is also the tab's own toolbar label. Five
of the eleven were then checked one by one and each was showing another tab's page. (The pre-fix window
*images* are not in this folder: the walk overwrote them before the cause was understood, so only the
tree dumps above survive as the record of that state.)

Fix: the sink's window work moved out of the publish (`DispatchQueue.main.async` + a `guard
self.tabState.selected == tab` re-check), so the height probe reads the tab that was actually chosen.
After the fix the same walk is 11/11: every page's own first rows are in its capture, and the marker
check passes for all eleven (the table above is post-fix).

## Defect 2 — the bento split starved its leading column (fixed)

`SettingsBentoSplit` splits evenly (`HStack` of two `maxWidth: .infinity` columns), but the
`SettingsRowPair` inside a column still sized its halves from `SettingsMetrics.halfRowWidth(forWindowWidth:)`
— computed from the **window**, so inside a column it demanded the whole card width. The trailing column
took it, and the leading one was squeezed to a sliver.

Before / after, General page, OCR of the same region (`bento-before-1240-ocr.txt` /
`bento-after-1240-ocr.txt` and the PNGs):

| width | before | after |
| --- | --- | --- |
| 940 (bento off) | 3/3 permission rows legible, `About` under them | unchanged (3/3) |
| 1040 (bento on) | 0/3 rows legible — only one `Grant` at the left edge | `Permissions` and `About` side by side |
| 1240 | 0/3 | `Permissions` at x=0.03, `About` at x=0.52, each permission row's `Grant` at x=0.44 (the leading column's right edge) |
| 1320 | 0/3 | 50/50, `About` card ~0.5 of the window instead of ~0.9 |

Fix: the pair's halves are flexible (`maxWidth: .infinity`), so they divide whatever container they are
in — the same two equal halves at the default window width, and half a column inside a bento column.
`SettingsMetrics.halfRowWidth(forWindowWidth:)` is still defined and still pinned by
`SettingsMetricsTests`; nothing else reads it now.

## Verified after both fixes

- `python3 Scripts/check_settings_page_heights.py` — the same numbers as before this fix, unchanged page
  heights at 940 pt (`appearance` 1000 pt, `widgets` 952, `tools` 949, …), and red for `appearance`
  then. Both the red page and the limit's model are handled in the fit pass below.
- `xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS'` —
  `** TEST SUCCEEDED **`, 2517 tests, 0 failures (2 skipped).

## The dock in both vertical placements

The Appearance page's `Position` control was driven left → right → bottom and back; the panel window's
frame (points, top-left origin, screen 1710×1112) is the evidence that the rail is really on that edge:

| capture | placement | panel frame |
| --- | --- | --- |
| `dock-rail-left-fullwidth-panel.png` | Left, Full Width | `-18,24 87×1047` — 18 pt of shadow bleed off the left edge, rail hugging it |
| `dock-rail-left-split5-panel.png` | Left, Split 5 | `-18,198 87×682` — the split islands as one 682 pt block |
| `dock-rail-right-split5-panel.png` | Right, Split 5 | `1641,198 87×682` |
| `dock-rail-right-fullwidth-panel.png` | Right, Full Width | `1641,24 87×1047` |
| `dock-rail-right-restored-panel.png` | Right, Full Width (restored) | `1641,24 87×1047` — the same frame the walk started from, so the user's placement was put back (the two captures differ only in the live clock inside the rail) |
| `dock-bottom-fullwidth-panel.png` | Bottom, Full Width | `-14,1043 1683×87` — full-width bottom bar |
| `dock-bottom-split3-panel.png` | Bottom, Split 3 | `395,1043 865×87` — the centred island group |

`dock-rail-left-screen-strip.png` / `dock-rail-right-screen-strip.png` are the 140 pt × screen-height
columns at each edge with the desktop behind them (the panel windows themselves are mostly transparent,
so a bare panel capture shows the chips but not the edge). Both strips carry the weather chip's `16°`;
the left rail's own accessibility tree lists the chips in order — weather, 16°, app icons, Trash, clock,
Wi-Fi — stacked in one 1047 pt tall window, which is what makes it a rail rather than a bar.

## Open items — both fixed the same day (see the next section)

1. **Every page's tail was cut at the height the window fits itself to.** `naturalContentHeight` measured
   `SettingsWindowContent` only, but the floating nav bar sits inside the same window content area above
   the `ScrollView`. The window was therefore one nav bar (~54 pt) shorter than the page. Live: at the
   fitted 940×737 the General page's last row (`Show Setup Guide Again`) was not in the window, while at
   940×1000 it was. Both captures are the same page at the same width:
   `page-tail-940x737-fitted-row-below-fold.png` ends at `Diagnostic Info`,
   `page-tail-940x1000-same-page-row-visible.png` carries the row below it.
   A real wheel event over the page did not bring the row into view either, so it was not simply
   "scroll a bit".
2. **`check_settings_page_heights.py` was red for `appearance`** (1000 pt against the 986 pt limit).

## The fit pass (2026-10-18, later the same day)

Both items above are closed, and the heights were re-measured with the app's own probe (the same path
`SettingsWindowController.naturalContentHeight` sizes the window with) plus a fresh live walk.

### What changed

1. **The window measures the nav bar with the page.** The probe now hosts `SettingsFloatingNavBar` +
   `SettingsWindowContent` and injects `\.settingsLiveWindowWidth`, so the number the window is sized
   from is what the window actually has to hold. General went 737 → 818 pt, and its last row is on
   screen (capture 01 below).
2. **The three pages over the limit were compacted** per `Docs/SETTINGS.md` rule 5 — rows that are
   narrow pair on one line, a one-line caption stays one line, a long list folds behind a disclosure.
   No control, key or value was dropped except the two icon-set preview tiles on Appearance (their
   segmented control draws and names the same choice; they were 58 pt of a page that was 17 pt over
   in its custom-tint state).
3. **Three state-dependent overflows turned up while measuring, and are fixed too.** Each was a page
   that fit at its defaults and did not fit once a control was used:

| state | before | after | what it was |
| --- | --- | --- | --- |
| Appearance, custom tint pinned | 1003 pt | 956 pt | the two plate sliders now share one line (and the icon tiles are gone) |
| Widgets, *Context Presets* armed | 1018 pt | 975 pt | the switch + both windows + their fixed hours are one line; the widget list's rows are 37 pt, not 41 |
| Edge Bars, *Custom* preset | 1261 pt | 899 pt | the one-row-per-item list is folded behind a disclosure, collapsed by default (rule 5's own shape, as on Shortcuts) |

### The ten pages after the pass (window = content + the 88 pt title bar and toolbar)

| # | page | window | probe content | slack | marker that verified it | its own **last** row, on screen |
| --- | --- | --- | --- | --- | --- | --- |
| 01 | General | 940×818 | 730 | 256 | `Show/hide taskbar shortcut` | `Show Setup Guide Again` |
| 02 | Appearance | 940×987 | 899 | 87 | `Layout Mode` | `Tint Dock by Time of Day` / `Restore Wallpaper` |
| 03 | Widgets | 940×1039 | 951 | 35 | `Widget Appearance` | `Snow Warning` |
| 04 | Notch | 940×997 | 909 | 77 | `Live Island` | — |
| 05 | Edge Bars | 940×1038 | 950 | 36 | `Main Side` | `Open Notes on Hover` |
| 06 | Window Management | 940×1000 | 854 | 132 | `Enable Auto-Tiling` | — |
| 07 | Launcher | 940×689 | 601 | 385 | `Scroll Direction` | — |
| 08 | Control Center | 940×610 | 522 | 464 | `Control Center` | — |
| 09 | Shortcuts | 940×1013 | 884 | 102 | `Search Shortcuts` | — |
| 10 | Tools | 940×1036 | 948 | 38 | `Clipboard` | `Quiet Until` |
| 11 | Advanced | 940×605 | 517 | 469 | `Behaviour` | — |

`fit-01-…` … `fit-11-…` are those captures, each with the OCR text next to it (`…-ocr.txt`). The driver
was `/tmp/katshot/capture_fit.py`: it clicks each page's toolbar tab, raises the window, grabs it by
window id and OCRs it — a page whose marker was missing or whose tail row was off-screen fails loudly.
`python3 Scripts/check_settings_page_heights.py` is green for all ten (tightest: Widgets, 35 pt spare).

### The three states, captured live

Each was driven through the app's own defaults key, relaunched, and captured the same way:

| capture | state | window | what the capture shows |
| --- | --- | --- | --- |
| `state-appearance-tinted-940x-1020.png` | `com.katikati.theme.material = deepOcean` | 940×1020 (932 content) | `Vibrancy 55%` and `Contrast` read on one line, and the page's last row (`Restore Wallpaper`) is in the window |
| `state-widgets-context-presets-940x-1063.png` | `…widgets.contextPresets.enabled = YES` | 940×1063 (975 content) | `Context Presets`, `Work Hours`, `Evening` and `Mon-Fri 09:00-17:00 • 18:00-23:00` are one line, and it is the page's last line |
| `state-edge-bars-custom-940x-987.png` | `com.katikati.edge.preset = custom` | 940×987 (899 content) | the `Widgets` disclosure row with no item rows under it, and `Sync Notes with iCloud Drive` is the last row |

Every key was read before the capture and put back afterwards (`UNSET` → deleted), so the walk left the
app's settings as it found them.

### What the fit pass did not check

- Only the default state of the ten pages was captured live; the three states above are the ones that
  were driven, and the other state-dependent pages (a tiling app-override list, a second display's rail
  rows) were not exercised.
- The expanded Edge Bars item list is taller than the window when the user opens the disclosure — that
  is the disclosed content, and rule 5's disclosure case expects it. Nothing was checked at window
  widths other than 940 pt or in a language other than English.

### Re-run after the pass

- `xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS'
  CODE_SIGNING_ALLOWED=NO` — `** TEST SUCCEEDED **`, 2517 tests, 0 failures (2 skipped).
- `python3 Scripts/check_localization.py` — green (906 keys, 12 languages each). It caught two things:
  the Appearance note the pass deleted was still in the catalog, and twelve entries another session had
  added by hand were missing again after a bad `git checkout` of the catalog — both put right by hand.
- `python3 Scripts/check_debug_switches.py` — green (86 switches).
- `python3 Scripts/check_settings_page_heights.py` — green, tightest page Widgets at 951 of 986.

## What this walk did not check

- Nothing was checked in a language other than English, and nothing at window widths below 940 pt.
- The dock was read through its geometry and its accessibility tree, not by clicking a chip or dragging
  an island — hover, drag and drop behaviour in the vertical rails is unchecked.
- `left`/`right` placement was exercised on the main display only; per-display overrides are untouched.
