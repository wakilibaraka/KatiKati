# SideDeck Replatform — Plan (`SD-1` → `SD-8`)

> The Left SideDeck becomes KatiKati's unified, full-height translucent glass workspace. It takes over
> **Downloader & Torrents** from the Notch and **Storage** from both the Notch and the Dock, and it gains
> EasyDict, a Notification Centre and code-reusing bento widgets.
>
> Status: plan approved 2026-11-25. Branch `feat/sidedeck-replatform` (worktree `../KatiKati-sidedeck`),
> built in parallel with Control Centre work on `main`. Merge-back items (§8) land on `main` once, at merge.

---

## 1. Ground truth (read from the code, not assumed)

| Surface | Fact | Anchor |
| --- | --- | --- |
| SideDeck tabs | Already pure Core: `SideDeckTab` (13 cases) with `title` / `symbol` / `searchPlaceholder` | `Core/Support/EdgeBarPrefs.swift:378-457` |
| Deck search/badges/selection | Pure helpers already tested | `EdgeBarPrefs.swift:441-520` (`SideDeckSearch`, `SideDeckBadges`, `SideDeckSelection`) |
| Deck shell | 400 pt wide panel, `area.height - 16` tall, `.regularMaterial` r18, rail hardcoded in the view, ⌃⌥W hotkey, opt-in edge hover (`com.katikati.drawer.edgeHover`, default **off**) polling `NSEvent.mouseLocation` every 0.15 s with a hard 0.4 s dwell. No side, order, visibility or width preference. | `App/Composition/WindowDrawerController.swift:16,46-104,208-221,310-500` |
| Notch pages | Downloads/Storage are **already retired** from `NotchPage`; raw values 0/1 are reserved so stored page orders cannot resurrect them | `Core/Support/NotchSectionPaging.swift:17-25` |
| Downloads leak | The deck's Downloads page is a wrapper over the Notch file and draws with `.notchCard()` + `NotchDesignSpec` | `App/Scenes/Edge/DeckViews.swift:868-873` → `App/Scenes/Notch/NotchDownloadsPageView.swift` (495 lines) |
| Storage leak | Two storage UIs: a hand-rolled deck view and the richer Notch page (row context menu, Review Caches, Scan App Leftovers) | `DeckViews.swift:876-996` vs `App/Scenes/Notch/NotchStoragePageView.swift` (215 lines) |
| Notch rest storage | `.storage` / `.storageLabel` ears, `dockChips` default pair, wide-bar `.storage` item at the 580 pt step, a 60 s `StorageScanService.freeBytes()` loop, two Settings choices | `Core/Support/NotchBehavior.swift:97-140`; `App/Scenes/Notch/NotchDockChips.swift:3-42,56-93`; `NotchWideBarView.swift:38`; `App/Scenes/LiveIslandSettingsBlock.swift:372-379` |
| Dock storage | `BarSection.drives` — picker row, canonical/default order, two render paths, Smart Stack signal, `WidgetLayout` normalisation | `Core/Support/BarSection.swift:33,44,47`; `DockStripView.swift:1925,2038-39,2130-31`; `SettingsLayoutPane+Widgets.swift:346,475`; `SmartStackSlot.swift:33-47`; `WidgetLayoutModel.swift:85-110` |
| Download engine | Already segmented: 4 connections by default, capped at 16, ≥1 MiB per segment, per-segment `URLSessionDownloadTask`, resume bookkeeping, assembly | `Core/Support/DownloadManager/DownloadItem.swift:19-56`; `App/Composition/DownloadManagerService.swift:359-424` |
| Glass | One sanctioned deck glass: macOS 26 `glassEffect` → `.ultraThinMaterial` → solid under Reduce Transparency, 0.75 rim | `App/Scenes/Edge/EdgeStyleTokens.swift` (`EdgeGlassSurface`, `glassRadius = 26`) |
| Localization gate | Fails on used-but-missing **and** catalog entries that are no longer referenced | `Scripts/check_localization.py:158-201` |

### 1.1 What this plan changes and what it does not

The Notch's *page roster* already lost Downloads and Storage. What remains is ownership and surface: the
deck still paints a Notch card, the Storage cleaner still lives in `App/Scenes/Notch/`, and storage is
still a resting-notch ear, a wide-bar item and a Dock section. SD-3 removes those three leaks. The shell
redesign is SD-1/SD-2.

---

## 2. Ownership split — zero overlap

| Dimension | Left SideDeck (this plan) | Right Edge Bar (unchanged) |
| --- | --- | --- |
| Shell | Detached floating rail + full-height glass panel + header capsule | Compact edge pill/strip that fans into tabs and buttons |
| Owner | `WindowDrawerController` + `App/Scenes/Edge/Deck*` | `EdgeBarPanelController` + `Core/Support/EdgeBarPrefs` |
| Pages | Command Bar, Launcher, Weather forecast, Downloads & Torrents, Storage, EasyDict, Notifications, Dashboard | Quick utility slots only: apps, notes/clothesline, status, productivity, Sydedock cards |
| Settings | New **Settings › SideDeck** pane (SD-8) | Existing **Settings › Edge Bars** pane |
| Swap | `SideDeckConfig.side` with a shared "Swap Left / Right Sides" option | Same option, inverted |

The current contradiction — `SettingsLayoutPane+EdgeBars.swift:18` promises "Left edge stays free for the
Window Drawer" — is resolved by the swap setting in SD-1: each surface owns one edge, and the owner may
exchange them.

---

## 3. Design source of truth

Measured from the three approved reference renders. Treated as targets, not exact KatiKati pixels.

| Element | Spec | Slice |
| --- | --- | --- |
| Resting handle | Vertical capsule on the active screen edge, ~4 × 44 pt, r2, accent at 0.25 opacity, starting **below the 44 pt menu bar** and ending above the Dock. Hover target padded by at most 6 pt. | SD-1 |
| Rail | Detached capsule, 56–64 pt wide, r24–26, 20–22 pt glyphs, 10–12 pt spacing, 8 pt inset. Selected item sits on a filled plate with a soft shadow; bottom `chevron` collapses the deck; gear pinned at the foot. | SD-1 |
| Identity strip | Optional 24–28 pt strip between rail and panel with a 90°-rotated caption, a hairline divider and a Settings capsule at its foot. **Off by default** (a second text surface costs localization and vertical room). | SD-1 |
| Header capsule | 52–56 pt tall, spans the panel width, full radius: 32–36 pt avatar + 15 pt greeting, translucent search pill with a 24 pt leading glyph, trailing segmented pill + bell with an unread dot. | SD-2 |
| Panel | Full height, 16–24 pt below the menu bar, r26 (`EdgeStyleTokens.glassRadius`), 16 pt padding, 12–14 pt gap. Bento columns: 3 at ≥900 pt, 2 at 620–900 pt, 1 below. | SD-1 |
| Cards | r18–20 on `EdgeGlassSurface`, 0.75 hairline rim, 44 pt circular tiles, 28–34 pt rounded numerals, 18 pt count badges. No second material, no second radius. | SD-3a/3b surface, SD-3d content |
| Bottom page dock | 44 pt floating capsule, white selected pill, trailing `+` that opens the page-visibility list (SD-8) — not a new feature. | SD-2 |
| Motion | Panel fade + 0.98→1 scale on the existing deck spring `spring(response: 0.34, dampingFraction: 0.84)`, 20 ms content stagger. Reduce Motion → opacity only. Panel **frames** are never animated (existing rule). | SD-1 |

---

## 4. Activation design (input-hygiene safe)

1. **Default — edge push/hover.** A 4 pt `NSTrackingArea` on the resting handle below the menu bar. Dwell
   delay 180 ms (configurable), `mouseEntered`/`mouseExited` only. **No** global `.mouseMoved` monitor, and
   the current 7 Hz `NSEvent.mouseLocation` timer retires with SD-1. Top 44 pt (traffic lights/menu bar) and
   bottom 60 pt (Dock) are excluded from the strip.
2. **Merged Weather handle (opt-in).** When `mergeWeatherHandle` is on, the resting pill shows temperature
   and condition; the pill expands the deck on click or dwell. Off by default: Weather stays a page.
3. **Hotkey.** `ShortcutAction.windowDrawer` (⌃⌥W) keeps working; SD-1 adds per-page actions so
   `Downloads`, `Storage` and `EasyDict` can each carry a key.
4. **Opt-in gesture.** Two-finger swipe in from the active edge, or a Hot Corner. Off by default.

Compliance: no `addGlobalMonitorForEvents` for pointer movement; the existing click-outside monitor stays
scoped to while the panel is open and is removed in `close()`. `Scripts/check_input_hygiene.py` must stay green.

---

## 5. Widgets (reuse, never reimplement)

| Widget | Behaviour | Engine |
| --- | --- | --- |
| Word of the Day | Daily word, part of speech, phonetics, gloss. Clicking opens EasyDict **with the search field focused**. | `DictionaryEntry`, `DictionaryService.define`, `TranslationSession` |
| Active Downloads | Aggregate speed, active count, segmented progress, pause/resume all; click opens Downloads. | `DownloadManagerService`, `TorrentEngine` |
| ClearDisk gauge | Free space + reclaimable developer cache with one click into Storage. | `StorageScanService`, `CleanerService` |
| Notification digest | Grouped unread count + latest 2–3 previews with quick clear/open. | `NotificationMirrorService`, `NotificationHistoryEntry` |
| Today glance | Current weather, clock, next calendar event, top unfinished todos. | `WeatherService`, `CalendarService`, `DailyHelpersService` |

All five must render on the SideDeck Dashboard, Desktop Boxes and Dock Wings, and must hold 0.0 % idle CPU
(no polling while off screen; feeds acquired on appear, released on disappear).

---

## 6. Licensing audit (verified against the repositories, 2026-11-25)

| Reference | Licence | Porting rule |
| --- | --- | --- |
| `niruvai/odm` | **MIT**, native Swift (macOS 13+, SwiftPM) | Segmentation/handoff **patterns** only. Its video path shells out to yt-dlp (Unlicense), Deno (MIT) and FFmpeg (LGPL/GPL) — those binaries are never bundled or redistributed. |
| `ja7ad/hydra` | Repository **GPL-3.0**; `hydra-core`, `hya-net`, `hya-ffi`/`libhydra` and the plugin crates are **MIT OR Apache-2.0** (`LICENSING.md`) | Read **only** the MIT/Apache crates, at a pinned commit; record file + commit in the commit message and a `NOTICE` row. The CLI/GUI is GPL and is off-limits. |
| `imputnet/cobalt` | **AGPL-3.0**; `web/` additionally **CC BY-NC-SA-4.0** | UX reference only: zero code, zero assets, zero CSS. |
| `bysiber/cleardisk` | **MIT**, Swift/SwiftUI (macOS 14+) | Direct port of the developer-cache catalogue, risk levels and Trash-first cleaning. |
| `tisfeng/Easydict` | **GPL-3.0** | Zero code. |
| `tisfeng/Raycast-Easydict` | MIT (claimed) | Verify `LICENSE` at SD-6 before porting any UX pattern. |

KatiKati is GPL-3.0-or-later; every donor row above must reach `NOTICE` in the same slice that lands code.

---

## 7. Slices

Each slice: pure Core first with `-only-testing:` unit tests, then the UI half, ≤300 diff lines, gates green
(`check_localization.py`, `check_debug_switches.py`, `check_input_hygiene.py`). `project.pbxproj` is
hand-appended, never regenerated; past ~30 lines for a file addition the slice is rejected.

| Slice | Deliverable | Anchors | Tests |
| --- | --- | --- | --- |
| **SD-1** | `SideDeckConfig` (side, swap with Edge Bar, edge strip + dwell, merged weather handle, page order/hidden, width) in Core behind `com.katikati.sidedeck.prefs.v1` with one-way migrators for `drawer.edgeHover` and `drawer.pinned`; detached rail + r26 full-height panel + resting handle via `NSTrackingArea`; side swap; identity strip (off by default) | `Core/Support/EdgeBarPrefs.swift`, `Core/Support/SideDeckConfig.swift` (new), `App/Composition/WindowDrawerController.swift`, `App/Scenes/Edge/DeckViews.swift` | new `SideDeckConfigTests`, migration + clamp + order |
| **SD-2** | Header capsule; Command Bar fills the panel; Launcher embedded; Weather page width-matched; bottom page dock wired to page visibility | `DeckViews.swift`, `App/Scenes/CommandBarView.swift`, `App/Scenes/LauncherView.swift`, `App/Scenes/Weather/*` | `SideDeckConfigTests` (order/hidden), geometry |
| **SD-3a** | Downloads pane leaves the Notch folder, wears `sideDeckCard()` | `App/Scenes/Edge/SideDeckDownloadsPane.swift` (moved), `DeckViews.swift`, `WindowDrawerController.swift` | compile + gates |
| **SD-3b** | Storage leaves the resting notch: cleaner folded into `SideDeckStorageView`; ears, wide-bar item, 60 s timer and Settings choices removed; `NotchRestContent` migrated | `App/Scenes/Edge/DeckViews.swift`, `Core/Support/NotchBehavior.swift`, `App/Scenes/Notch/NotchDockChips.swift`, `NotchWideBarView.swift`, `App/Scenes/LiveIslandSettingsBlock.swift` | `NotchHoverMachineTests`, `NotchGestureTests`, migration |
| **SD-3c** | Storage leaves the Dock: `.drives` out of picker/order/render, stored visible chips hidden once | `Core/Support/BarSection.swift`, `WidgetLayoutModel.swift`, `DockStripView.swift`, `SettingsLayoutPane+Widgets.swift`, `SmartStackSlot.swift` | `WidgetLayoutModelTests`, `DockWidgetLogicTests` |
| **SD-3d** | ClearDisk catalogue: Xcode, node_modules, CocoaPods, SPM, Docker, pip, Cargo with risk badges, storage-pressure gauge, one-click reclaim; reuse `DrivesDockWidget` for the gauge | new `Core/Support/DevCacheCatalog.swift`, `SideDeckStorageView` | new `DevCacheCatalogTests` |
| **SD-4** | IDM-class downloads: configurable 1–32 connections, dynamic range stealing (finishing worker splits the largest remaining chunk), statistical stall detection + reconnect, flat positioned writes, persisted pause/resume, smart folders | `DownloadManagerService.swift`, `Core/Support/DownloadManager/DownloadItem.swift`, `TorrentEngine.swift` | extend download planner tests (finalisation split, stall windows, resume state) |
| **SD-5** | Opt-in media URL resolver UX (quality / audio / mute / filename), backed by a user-configured local `yt-dlp` or self-hosted endpoint. Clean-room: zero cobalt code or assets | `SideDeckDownloadsPane.swift`, new resolver in Core | pure URL/quality selection tests |
| **SD-6** | EasyDict page: offline system dictionary + `TranslationSession` + history; Word of the Day widget that opens the definition and focuses search | `DictionaryService`, `DictionaryEntry`, `TranslatePanelController`, `DeckViews` | `DictionaryEntryTests`, new word-of-day selection tests |
| **SD-7** | Notification Centre page (grouped by app, clear/filter) + Dashboard bento widgets (Downloads, ClearDisk, Notification digest, Today glance) | `DeckViews`, `NotificationMirrorService`, widget files | `SideDeckBadges`/grouping tests, widget format tests |
| **SD-8** | Settings › SideDeck and Settings › Edge Bar panes, shared swap option, 12-locale catalog, `check_localization.py` / `check_debug_switches.py` / `check_availability_warnings.py` / `check_input_hygiene.py`, livecheck, idle CPU/RSS | `SettingsTab.swift`, `SettingsWindowView.swift`, `App/Scenes/Settings*`, `Resources/Localizable.xcstrings` | `SettingsTabTests`, livecheck script |

### 7.1 Landed in this batch

| Commit | Scope |
| --- | --- |
| `docs(sidedeck)` | This document. |
| `refactor(sidedeck)` | SD-3a — Downloads pane moves to `App/Scenes/Edge/`, deck card surface, wrapper removed. |
| `feat(notch)` | SD-3b — Storage leaves the resting notch; cleaner folded into the deck; migration + tests. |
| `feat(dock)` | SD-3c — `.drives` retires from the Dock. The drop happens in `WidgetLayout.init` (every path funnels through it), so it is idempotent and needs no defaults stamp; the enum case stays decodable, and the menu-bar Drives item + Dock Downloads tile are untouched. |

SD-1, SD-2 and SD-3d onwards follow in their own batches.

---

## 8. Verification gates

Per slice, inside `../KatiKati-sidedeck` with an isolated build cache:

```bash
xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati \
  -derivedDataPath /tmp/katikati-dd-sidedeck -only-testing:KatiKatiTests/<Suite>
python3 Scripts/check_localization.py
python3 Scripts/check_debug_switches.py
python3 Scripts/check_input_hygiene.py
```

Merge-back (on `main`, once): `HYBRID_PLAN.md` slice note · `CHANGELOG.md` Unreleased → Changed · prune any
catalog orphans · `graphify update .` and commit the graph · live-check on a spare display (rail, handle,
Downloads, Storage, notch rest, Dock) with before/after shots.

### 8.1 Risk register

| Risk | Answer |
| --- | --- |
| `check_localization.py` fails on **unused** catalog keys after a view is deleted | Carry every localized string verbatim into the new pane first; if a key still goes unused, hand-delete just that entry (single-anchor edit) and record the hot-file touch. Never regenerate the catalog. |
| Stored preferences resurrect a removed surface | Raw values stay reserved (`NotchPage` 0/1 pattern) and every retirement ships a stamped one-way migration: `com.katikati.migration.<name>.v1`. |
| `project.pbxproj` churn | Hand edits only; a move is 2 lines per file (`name` + `path`), a deletion is 4 lines. |
| Hidden costs a reflection of the live app | Never run `Scripts/build_and_run.sh` in a parallel worktree; it re-signs for Accessibility and steals the live app. Targeted tests only. |

---

## 9. Non-goals

- No new dependencies. Sparkle stays the only one.
- No Rust/FFI (`libhydra`) in SD-4. The native Swift engine is the plan; FFI is reconsidered only if
  `URLSession`/`Network.framework` proves the bottleneck on multi-gigabit lines.
- No copied AGPL/GPL code or assets (cobalt, Easydict), and no bundled yt-dlp/Deno/FFmpeg.
- No new pages beyond the eight listed, no accounts, no analytics.
