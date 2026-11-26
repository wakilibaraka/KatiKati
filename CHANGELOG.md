# Changelog

All notable changes to KatiKati are documented in this file.

## [Unreleased]

### Added
- **Multi-display optimization (`MD-2`–`MD-6`):** edges are topology-aware. `ScreenEdgeTopology` derives which of a display's four edges are *outer* and which are *seams* from the connected frames; the right deck only binds to a display whose right edge really ends the desktop (`EdgeBarPlacement`, `com.katikati.edge.outerOnly.v1`, on from two displays up), so a side-by-side desk no longer draws two decks against the shared seam. The island gained a topology-level placement mode in Settings › Notch — **All Displays**, **Built-in Display Only**, **Follow the Pointer** and **Floating Pill on Other Displays** — above the per-display design rows, and a clamshell handover re-targets the existing island controller instead of rebuilding it, so an open island survives the lid closing. Window layout memory v2 also stores each window as fractions of its display's visible area keyed by EDID UUID, so a display that returns at another size restores proportions instead of a clamped absolute frame. External brightness is DDC/CI: `DisplayBrightness` reads and writes VCP `0x10` over the private `IOAVService` API on Apple Silicon (no entitlement, no root, no TCC prompt), falls back to a gamma transfer table when the panel does not answer, and coalesces a slider drag to last-value-wins at 50 ms on one serial queue; the built-in panel keeps its native brightness and is never gamma-dimmed. The pointer's display is also the one the controls act on: one `DisplayTargetRule` (pointer's display, else main, else first — a pointer in the dead wall beside a stacked desk falls back rather than guessing) drives brightness, the new **Jump to Next Display** shortcut (unbound by default, Carbon id 77, Settings › Shortcuts › Window & Snap) and the new **Display Volume** row, which sets the external panel's own volume over VCP `0x62` with the same 50 ms coalescing, cached read-back and hide-when-unanswered degradation — there is no software stand-in because gamma can dim a panel but cannot make its speaker quieter. On a desk with two or more displays the dock on the focused display now wears the theme's highlighted rim so it is obvious which bar is live; single-display desks are unchanged.
- **SideDeck replatform (`SD-1`-`SD-8`):** the left deck is now a full-height glass workspace with its own `SideDeckConfig` (edge, 360-560 pt width, opt-in edge activation with a dwell, identity strip, merged weather handle), a detached rail and a resting 4 x 44 pt handle on a tracking area instead of the 7 Hz pointer poll, a header capsule, a bottom page dock, Downloads moved out of the Notch, Storage with the ClearDisk developer-cache catalogue, EasyDict, a grouped Notification Centre and a bento Dashboard. Downloads gains configurable connections, stall detection and persisted pause/resume; an opt-in media URL resolver sits behind the downloads pane. Settings gains a **Side Deck** page and both it and **Edge Bars** carry one shared **Swap Left / Right Sides** control.
- **Opt-in Menu Bar modules (`MB-9`–`MB-11`, off by default):** Settings › Menu Bar gains a **Modules** card for three Tier B additions, each built only while its switch is on. **Agents** puts today's spend, the loadout profile and an approval-hook pause in the Creative Hub. **Audio Mixer** lists apps currently producing audio and sets a per-app level through a private CoreAudio process tap (100 % removes the route; closing the hub restores every app). **Uninstaller** opens a searchable app sheet that plans bundle + support-file removal with `AppRemovalPlanner` and stages everything in the Finder Trash — nothing is hard-deleted.

### Changed
- **The welcome guide is six live acts:** *Welcome to KatiKati* → *Your bar* → *Feel* → *Access* → *Daily rhythm* → *You're all set*, each one decision and each written to the store as it is chosen, so the bar behind the window changes with the answer. Every setting the old pages held survives in an act — style, edge, sections, wings, capsule, notch and AI tracking; theme, app icons and the recommended system-Dock set; the ten permissions with Accessibility alone under **Required**; the weather city, login item, the ⌘⌘ launcher and the clipboard toast. The window is a fixed 720 × 640 and its act content scrolls, short acts keep their copy and button together, the four theme swatches carry their names, and an act with more content than fits now shows a fade and chevron instead of ending mid-row. Skip (⌘.) still hands a first run over to the Accessibility window.
- **Menu Bar hub pages are distinct and readable:** the four action boxes now open on the Switches page instead of repeating above every tab; each page owns its search. Switches gains a Keep Awake timer (15m / 30m / 1h / 2h / 5h / indefinite) and an opt-in **Lid closed** switch, page two gains a **Storage** readout (used / available / bar), and a header menu chooses the finish — **Glass**, **Tinted**, **Solid** or **High Contrast** — with a scrim and secondary-ink floor so text stays legible over busy wallpapers.
- **ClearDisk reports what it can reclaim:** the Dashboard card now reads the developer-cache total the Storage page measured and persisted (`DevCacheSnapshotStore`) instead of only showing free space, and never starts a scan of its own; the dashboard card labels and the Dashboard tab title are localized, and the Side Deck pages ship in all twelve catalog locales.

### Fixed
- **External brightness and volume actually reach the panel:** the DDC/CI transport sent a shifted chip address and checksums that omitted the folded address/opcode bytes, so a real LG HDR 4K answered nothing at all, and the write path scaled the value against the panel maximum and then again as a 0–255 fraction, so a full slider wrote 39 % on a panel whose maximum is 100. `DDCCommand` now builds both frames in pure, tested code, the chip address is passed unshifted, and `DDCValue` owns the byte ↔ panel-range conversion. The panel is also flaky on the wire — it drops the first request after idle and returns an empty reply about half the time — so each request is written twice and a read retries up to three times; a probe that fails is retried later instead of writing DDC off for the session. Verified on hardware: brightness 100 → 80 → 100 and volume 30 → 50 → 30 read back exactly.
- **Dragging between displays no longer snaps on the seam:** a drag that grazed the boundary between two displays resolved a half/quarter zone and pulled the window back. `edgeZone` now takes the seam edges of the display it is testing and never resolves one unless the pointer has rested on it for 450 ms (`SnapGaps.seamDwell`) or `⌥` is held, so crossing to the other display cannot arm a snap while deliberately parking on the edge still does.
- **The live input-hygiene gate no longer passes by checking nothing:** `live_check_input_hygiene.py` crashed on the system Python 3.9 (`int | None`), and with PyObjC absent it reported "all live checks passed" while LR1/LR3 were skipped. It now runs on 3.9, exits 2 with an explicit message when Quartz is missing (override with `--allow-missing-quartz`), and attributes every window to a display — adding LR4 (an elevated window straddling a seam) and LR5 (a window parked off every display but not at the documented park point) to the per-display report.
- **A display keeps its own wallpaper after moving ports:** per-display wallpaper identity used `CGDirectDisplayID`, which changes when the monitor comes back on another port, so the display that had its own picture was repainted. It is the EDID UUID now, the same key every other per-display store uses, with the numeric id only as a fallback.
- **ClearDisk and Storage state the same number:** the card formatted the same byte count with the downloader's 1024-based helper (`3.10 GB`) while the Storage page header used the storage formatter (`3.33 GB`). Both card figures now call `SystemMonitorFormat.bytes` at the callsite, so the card reads `Reclaimable 3.33 GB` beside the header's `3.33 GB` without either shared formatter changing.
- **Settings rows announce their names:** every "gel" button row drew its title but exposed no accessible name, so the Side Deck swap row read as an unlabelled button to VoiceOver and AX automation. `SettingsButtonRow` now sets `.accessibilityLabel(title)`, naming both swap rows and every other row built from it.
- **The Side Deck's Settings gear opens Settings:** the identity strip's gear sent `showSettingsWindow:`, which no responder in the app implements, so pressing it did nothing; it now opens Settings › Side Deck through `AppDelegate` like every other surface and carries an accessible name.

## [0.18.0 beta 3] — 2026-11-24

Modular Dock & Launcher overhaul (`DO-1`–`DO-10`), native macOS-tight dock spacing, SideDeck Waves 1–4, 13-Pillar Audit Waves 1–4 (telemetry, Vision background removal, `⌥`-thirds snap, persistent window layouts, Control Center inputs), and `~0.2%` idle-CPU livecheck polish; see `Docs/Releases/RELEASE_NOTES_v0.18.0-beta.3.md`.

### Added
- **Dock, Launcher, App Icons, Widgets & Modularity Overhaul (`DO-1`–`DO-10`) & Native-Tight Spacing (`8aecaebe`):**
  - **Launcher + Drawer Consolidation & 4-Square `Background & Activity` Tile:** Folded the standalone Drawer into **Launcher** as a `"Drawer"` presentation preset (`LauncherPresentation.drawer`), retired the separate Drawer tab (`"drawer"` maps to **Launcher**), and promoted the 4-square **Background & Activity** tile onto the main Dock strip with five configurable icon faces (`3×3 App Grid`, `RAM %`, `CPU %`, `RAM Pressure Ring`, `App Count`) and a tabbed `Background Apps` | `Processes & RAM` inspector whose process/RAM monitor samples off the main thread strictly while visible (zero idle CPU).
  - **Modular Detached Bottom-Right Capsule:** Replaced the trailing capsule default with **Control Center** wearing a Liquid Glass **Wi-Fi + circular Volume ring** (local scroll-wheel volume adjustment isolated from main dock panning), configurable across `Control Center`, `Background & Activity`, `Trash`, `Launcher`, `Shelf`, or `Off` in both **Settings › Dock Layout** and Onboarding.
  - **Dock App Groups (`DockFolders`), App Icon Presets, Anti-Overflow Solver & Native-Tight Defaults:** Added iOS/iPadOS-style 2×2/3×3 Dock folder tiles with category auto-grouping, drag-to-group, and optional two-way Launcher folder sync; introduced five named App Icon presets (`App Pills` default horizontally, `Icons Only` vertical default, `Window Cards`, `Windows 11 Grouped`, `Windows 10 Taskbar`), 3-stage anti-overflow dynamic resizing, and `Keep in Dock` default context menus (`"Pin as App Icon"` opt-in). Lowered default `Icon Spacing` to `1 pt` (`-2...12 pt` incl. `0 pt`) and `Section Spacing` to `6 pt` (`3...20 pt`) with a **Reset to Default** button, kept Wide mode strictly at Icon Spacing (`WideZoneSpacerPlan`), tightened App Pill inset to `2 pt`, shrank `.dictionary`/`.terminal` slots to `40 pt`, synced `DockUtilitiesClusterView`, and separated utility tools from Clock with a tight hairline divider.
  - **Tactile Multi-Page In-Dock Widgets & Battery Peripherals:** Added dot-strip click cycling with spring pulse + alignment haptic, last-page persistence, and a phase-aware trackpad swipe detent (`WidgetPageScrollEngine`, 1 page per swipe ignoring momentum) across Weather and Now Playing cards; upgraded the Battery wing to **Battery & Peripherals** and added a DockSet-style **Peripherals** Notch page with audio-output switching (explicitly noting macOS's iPhone/Watch battery boundary).
  - **Reorganized Dock & Widget Settings:** Split configuration cleanly across **Dock Layout**, **App Icons & Hover**, **Bar Widgets**, and **Widget Wings** without duplicate switches.
- **SideDeck Waves 1–4 & Cursor Clipboard (`#18`):** Added SideDeck edge deck workflows and cursor-anchored clipboard popup.
- **13-Pillar Capability Audit & Feature Unlocks (Waves 1–4):**
  - **Menu Bar & Telemetry:** Fixed Menu Bar live `↓/↑` network speed readout, deep-linked settings to `.menuBar`, replaced Drive polling with `NSWorkspace` mount/unmount events + Eject, and surfaced battery cycle count, health %, ETA, opt-in IOHID SoC temperature, Disk I/O, and top 3 CPU processes.
  - **Clipboard & Shelf:** Wired `⌘1`–`⌘9` pinned-slot paste and origin-app `Work` filtering; exposed Vision foreground/background removal (`VNGenerateForegroundInstanceMaskRequest`), `Merge PDF`, and `Convert` parity in Shelf selection/context menus.
  - **Snapping, Persistent Tiling & Control Center:** Added `⌥`-drag horizontal thirds window snapping, `Codable` `WindowLayoutMemory` persistence (`window-layouts.json` + `.katikati` backup), `tile float` / `tile retile` shortcuts & Command Bar macros, microphone input switcher, keyboard backlight slider, and multi-VPN selector menu.
  - **Weather, Usage, Live Island & Profiles:** Wired Weather `WarningsTile`, Moon Phase illumination, and desktop box temperature units/cities; added app usage metrics, leftover review flow, note title archiving/error UI, Live Island camera & alerts, unified Dock Profiles, universal widget surface controls, and atmospheric wallpaper moon glow.
- **Mission Control experimental defaults, looks & multi-display (`09df135c..e13af5b2`):** Marked Mission Control experimental with `Docs/MissionControlResearch.md`, added four looks (**Traffic Light** default, **Colourful Everything**, **Liquid Glass**, **Paper**), switched borders and keyboard/filter shortcuts to opt-in defaults, added multi-display overlays + Stage Manager filtering, and tore down overlays cleanly on exit.

### Changed
- **Pause, Hydrate and PingPlace grew up, and they are on from the start (`3ed09b3b`, `7131f58a`):** Added **Pause** and **Hydrate** dock wings with Smart Pause, Settings › Notch › Daily Helpers consolidation, 3×3 per-display **PingPlace** notification routing, and rebuilt Notch pages on one unified card + single page pill.

### Fixed
- **Idle CPU & UI livecheck polish (`cf03222f..4e18742c`, `21e04c08`, `3f18bdae`):** Gated `HydrationController`, `NutritionController`, and `QuitOnLastWindowService` idle timers; deduplicated `SystemMonitorController`; eliminated main-thread idle polling hotspots in `NotchIslandView.detectedMeetingPlatform`, `LiveActivityFeed.refresh()`, and `SystemStatusService.refreshWiFi()` (settling idle CPU from `3.2%` to `0.2%`); fixed multi-file `ditto` ZIP staging, DropClip toggle, `AVSpeechSynthesizer` retention, `"wifipw"`, four-finger pinch vs tap trigger, Wallpaper moon glow/altitude, Dock Profiles live refresh, Weather warnings, and Menu Bar Settings picker framing.
- **The dock wings are visible on a full dock, and the small size is usable:** Parked wing width before clamping, fixed Full Width wing docking, honoured Reduce Motion and Smart Pause in Edge Deck hydration, and resolved Mission Control multi-display / Stage Manager edge cases.

## [0.18.0 beta 2] — 2026-11-22

Mission Control: Dock overviews with names, borders, colours, filtering and window actions; Dynamic Wallpapers with celestial sky & terrain rendering, Desktop Folder Boxes & Widgets (Phases 60–67), and Input & Shortcuts Settings; see `Docs/Releases/RELEASE_NOTES_v0.18.0-beta.2.md`.

### Added
- **Mission Control:** A dedicated **Settings › Window & Workspace › Mission Control** section draws custom overlays over the Dock’s overview: persistent **Space names** keyed to each Space’s ID, high-contrast **app/title badges** and type-to-filter dimming, **focus, hover, group and per-state borders**, **bundle-ID and category colour rules** (category colours assigned automatically, every rule editable), thumbnail tint and Space-title accents, plus OpenMissionControl-style **hover buttons, hover shortcuts and right/middle-click actions** (Close/Minimize/Zoom/Hide/Quit through the window’s own Accessibility buttons). Detection is event-driven (Dock AX observer plus Space changes) and every panel, monitor and observer is torn down when the overview closes, so idle CPU stays at zero; Accessibility and Screen Recording are reported explicitly, and an unobservable Dock says “unavailable on this macOS” rather than failing silently. The section includes a live stage preview. Also in this pass: a **Look & Layout** card (border width, corner radius, badge opacity, group padding, Space-title and badge placement, filter readout, accent fallback), **per-state border colours**, **per-Space accent colours** in the Naming card, **app group frames** drawn around the windows of one app, a live **filter readout** chip, and **keyboard navigation** of the overview (Tab/arrows move the target, Return raises it) alongside the hover actions.
- **Input Monitoring is reported separately:** the Mission Control readiness card now checks the Input Monitoring grant that global key
  monitoring requires, with its own row and Open Settings link. The overlay, hover and mouse actions still work without it, and the card no
  longer implies that keyboard navigation works when macOS is silently dropping the events.

### Changed
- **`Scripts/build_and_run.sh --test …` re-signs on its way out, so an ad-hoc build can't sit on disk:** `xcodebuild test` relinks the product and signs it ad-hoc, silently discarding the Accessibility grant, and every live pass afterwards measured nothing. The new mode runs the tests (all extra arguments pass through, so `-only-testing:` filters work unchanged), prints the test verdict, then re-signs with the local identity, prints that it did, and relaunches the app. It exits 3 when no identity is available, so the ad-hoc state can never be left behind quietly. `--check-signing` also stopped reporting a failure (exit 1) when no instance was running, which made gates read "not running" as "wrong signature".
- **The dynamic wallpaper is on by default, and it now paints a place rather than a gradient:** the desktop follows a six-step daylight ladder (dawn, morning, noon, golden hour, dusk, night) with the sun's height and a per-step brightness, reacts to the forecast the app already has — no extra network call, no location prompt — and draws one of three environments: **City**, **Countryside**, or **Terrain** (alpine ridges, coastal cliffs and water), with **Auto** picking from the weather location's name and latitude. Space switches, wake and display changes re-apply it, a forced re-apply hands macOS a fresh generation of the same file (it ignores a URL it is already showing), old renders are pruned, and Low Power Mode asks for no new copies. Frames are rendered per display resolution and cached under `Application Support/KatiKati/Wallpapers/terrain`; the pre-change Sky pack stays readable as the fallback for existing installs.
- **Shortcuts is split by input device, and Settings grew from 25 to 29 pages:** Settings › Shortcuts is now **Keyboard Shortcuts** — every assignment (features, snap zones, tiling) with its find field and hold time — and the behaviours that crowded it moved out: **Keyboard** (Super/Hyper, Caps Lock protection, Finder keys, pause and clean, under a **Keys & Protection** heading so it does not repeat the page title), **Key Visualizer** (the overlay's switch, filter, style, size, linger, drag position and mouse clicks — split out of Keyboard once the card outgrew remapping), **Mouse** (focus follows the pointer, scroll direction, a link to the system's mouse settings) and **Quit & Close** (the ⌘Q hold protection and the quit-on-close/idle table). Trackpad gestures keep their own page, and the Radial Dial stays the hybrid one — it answers to a key, a mouse button or a trackpad edge. The sidebar gained an **Input & Shortcuts** group for all seven.
- **BSP and Spiral are finally different shapes:** a new window used to split the newest leaf, so BSP's tree degenerated into the same staircase Spiral draws. Inserts now split the shallowest leaf, giving BSP a balanced tree whose axes follow depth — four windows form a 2×2 grid — while Spiral keeps giving each window half of the space that is left. The window list other presets place from (Columns, Rows, Grid, the strip, drag-to-slot) stays in arrival order, and the BSP tile now previews five windows so it is not mistaken for Grid.

### Added
- **`Scripts/live_check_wallpapers.py` — the wallpaper pass, in the repo:** for each solar phase × sky it relaunches KatiKati with the phase override and the pinned environment, waits for the desktop picture to point at the expected new frame in `DynamicWallpapers/Generated/`, screenshots it and writes an index; it also hashes the built-in Sky pack before and after, drops a foreign file into the generated folder to prove pruning leaves it alone, and checks that Small Animation's overlay window appears when enabled and disappears when paused, with the desktop picture never swapped. 30/30 cases and every preservation check pass on this machine.
- **Small Animation — a little weather on the desktop itself:** an off-by-default switch under Live Weather drifts a few soft clouds across the sky on a separate, click-through layer that sits behind your windows, so the desktop picture is never rewritten and nothing is swapped or re-decoded. It costs a tiny amount of CPU and GPU (measured well under one percent of a core), keeps no full-resolution frames in memory and uses a little battery while the desktop is visible; it pauses on Low Power Mode, with Reduce Motion, when the screen locks or sleeps, and while a full-screen app covers the desktop, and the settings row says when it is paused.
- **The dynamic wallpaper now draws the sky the model describes:** stars in the night sky (cut by weather, with a static twinkle so a still picture never shimmers), one seeded meteor per night, a moon placed by its real azimuth and altitude and shaped by its phase with a halo through haze, and layered cirrus, wisp and bank clouds with a storm veil and low fog — all from the same solar phase and weather the picture already used. The frame cache key now carries the renderer version and the atmosphere's numbers, so a change in either gets a fresh picture instead of an old one.
- **The sky is now a model, not a picture:** a pure celestial model gives the sun and moon's altitude and azimuth for any instant and place, the moon's phase, illumination and which limb is lit, and one `SkyAtmosphere` plan — stars, twinkle, a seeded meteor, moon halo and haze, cloud bands and horizon glow — for each solar phase and weather. It reads no clock and touches no files, so the same instant always paints the same sky, across time zones and DST boundaries alike.
- **Generated wallpaper frames moved into their own cache, and pruning can no longer touch your files:** dynamic frames now render into `Application Support/KatiKati/DynamicWallpapers/Generated/`, and only files matching KatiKati's own render names (`terrain-<scene>-<phase>-<sky>-<WxH>-<digest>[-gN].png`) are ever expired or cleaned up there. The built-in Sky pack, a custom wallpaper folder, anything you drop into the folder yourself and the original wallpaper captured at first run are left exactly as they are; the pre-change renders are retired once, after a frame exists in the new cache.
- **`Scripts/live_check_tiling_presets.py` — the nine-preset tiling pass, in the repo:** stages four TextEdit windows, writes each preset, relaunches, and reports overlaps, union coverage, off-screen area and whether every window stayed on screen, with one screenshot and a JSON per run. It refuses to start when `Scripts/build_and_run.sh --check-signing` says the bundle no longer matches the Accessibility grant, and it keeps the old pass's **"no preset moved a single window"** failure, so a lost grant reads as a failure instead of nine plausible rows. The preset list is read from `TilingLayoutPreset`, so a new layout is covered without editing the tool.
- **Weather Mood — Auto or a locked atmosphere (Settings › Wallpaper):** Auto keeps following the forecast and the clock; **Rainy Evening**, **Golden Evening**, **Snowy Day**, **Storm Night** and **Clear Night** each pin a sky *and* a time of day, so the picture (and the bar's own phase tint) stays on the chosen mood through the next weather update until Auto is chosen again. The lock persists in `com.katikati.wallpaper.mood` and the row says which mode is active.
- **The accent studio's Style control sticks:** picking Gradient (or Mesh) used to normalize straight back to Wallpaper when no stops had been typed yet, so the press appeared to do nothing; the switch now seeds the stops that style needs from the wallpaper's sampled palette (entered stops first, neutral fallback last) and keeps the choice. The Angle slider no longer loses its value to a stale draft when Apply is pressed.
- **The dock accent now fills the dock's own surfaces:** the selected/active chip pills, the running-app indicators (both the 4 pt dot and the pill indicators) and the Settings slider tracks fill from the resolved accent stops instead of the flat token — a solid colour, a multi-stop linear gradient along the accent's angle, or the palette sampled from the wallpaper on screen. With no accent configured every one of those surfaces keeps the signed-off look untouched, and Reduce Motion drops the pill's hover cross-fade.
- **Settings › Wallpaper is a page of its own:** a live stage that draws the same scene model the engine paints (scrub the time of day, switch the sky), the three pillars (Live Time & Solar, Live Weather, Environment), Space-change and Low Power Mode reliability switches, and the wallpaper folder / restore rows that used to sit on Appearance.
- **Multicolour and gradient dock accents:** the bar's phase tint now takes a **Dock Accent** — one colour, a 2–4 stop linear gradient with an angle, a multi-hue mesh, or the palette sampled from the wallpaper on screen. Stops are hex, stored repaired (invalid stops dropped, at most four, angle wrapped), and a gradient that loses its stops falls back to wallpaper-adaptive instead of painting one arbitrary colour.
- **Firefox-style drag-to-edge snapping is on out of the box:** dragging a window to a screen edge snaps it there unless the switch was turned off; it used to be off, which left the feature invisible on a fresh install. The seed runs once, only for a pristine install and only while the key was never written, so an upgrade never turns it on behind a user's back and an explicit Off wins.
- **Show Mouse Clicks (Settings › Keyboard):** `visualizerMouseClicks` was read by the overlay but no page ever wrote it, so a recording could never show the pointer. It now sits with the visualizer and draws clicks and scrolls, without recording where you clicked.
- **Tiling layouts are named, drawn and aliased:** Settings › Tiling replaces the Preset menu with a grid of nine tiles, each showing the solver's own thumbnail, a badge and the layout's name; beneath it the selected layout is spelled out (`BSP · Binary Space Partitioning`) together with the name it has elsewhere (`AeroSpace h_tiles · Amethyst Column`), so arrivals from AeroSpace or Amethyst can find the shape they know. `TilingLayoutAlias` in Core holds badge, full name and both equivalents, and is unit-tested for every preset. A window evicted because the tiles would be too small now goes back to the frame tiling found it in instead of staying at the edge a scrolling strip parked it against.
- **⌥-scroll the Tiling ribbon (off by default):** with **Settings › Tiling › Scroll the Strip with ⌥-Scroll** on, Option plus a two-finger scroll steps the ribbon to the next or previous column, one column per flick. `StripScrollGesture` turns the vertical delta stream into steps (60 pt of travel, 280 ms cooldown, momentum dropped; horizontal scrolling is left to the app, and a wheel notch counts as 10 pt), and the passive monitor only acts while the switch is on, Option is held and the window under the pointer is one the ribbon manages. Because it never consumes the event, the app under the pointer still scrolls; the row says so.
- **Desktop Folder Boxes MVP (Phase 60, off by default):** Pin real Finder folders on the desktop as native floating glass boxes (`desktopIconWindow + 1` resting layer) with snap-to-edge/sibling resizing (`50×50` min), `⌃`-drag group movement, manual/rule sorting, `QLThumbnailGenerator` previews, Finder context menu + ZIP compress/extract, spacebar QuickLook, Quick Reveal (`Esc` / click-outside dismiss), opt-in blank-desktop double-click toggle, optional 1-click starter box (`~/KatiKati/Inbox`), **Settings › Widgets › Desktop Boxes**, status menu submenu controls, and `.katikati` backup support (`desktop-boxes.json`).
- **Desktop File Stacks, Tabbed Groups, Managed Storage & Auto-Organize (Phase 61):** Group files inside any Desktop Box via **Auto by Kind** or **Manual Stacks** (expanded in Adaptive, `3×3`, or `5×5` glass popovers); merge boxes into synchronized multi-tab windows via **Option-drag** or **Group With ▸** and cycle tabs with `⌃Tab` / header trackpad scroll; create, convert (copy-first byte/manifest verified with source preserved), or export boxes using optional **Managed Storage** (`~/Library/Application Support/KatiKati/ManagedBoxes`); and tidy folders via **Preview-First Auto-Organize** with dry-run category buckets and 1-click **Undo**.
- **Desktop Theming & Cross-Widget Panorama (Phase 62):** Customize any Desktop Box from **Customize Appearance…** (`DesktopBoxAppearancePopover`: 5 material styles, emoji/SF Symbol/image icon badges, color tint/custom image/panorama backgrounds, 4 border styles w/ accent color & custom corner radius, and Auto/Shadowed/High Contrast/Monospaced text styles); render high-resolution backgrounds and icons cleanly via bounded `CGImageSource` downsampling & asset pruning (`DesktopAssetStore`); slice a shared wallpaper seamlessly across boxes via `DesktopPanoramaEngine` UV projection; and configure canvas defaults plus **Apply to All Boxes** in **Settings › Widgets › Desktop Appearance & Panorama** with full `.katikati` backup/restore support.
- **Desktop Feature Widgets (Phase 63):** Pin native desktop widgets alongside folder boxes: **To-Do** (quick-add field, open-first ordering, checklist & importance flags, shared with `tasks.json`); **Quick Capture** (newest-first note inbox with Vision OCR screen-text capture, backed up via `desktop-capture.json`); **Glance** (large day display, localized lunar date via Chinese calendar, 24 solar terms, and solar/lunar festival badges); **Desktop Weather** (live condition glyph, temperature, high/low, and description from the shared `WeatherService`); and **Vinyl Music** (spinning vinyl record album art with Reduce Motion support, track details, and system transport controls via `NowPlayingService`), all accessible from **Settings › Widgets › Add Widget**.
- **Smart Capsule Mode & Dockable Edge Capsule (Phase 64):** Collapse any Desktop widget into a compact glass capsule (icon badge, title, count, expand button) from its overflow menu, right-click menu, header button, or **Settings › Widgets › Capsule Mode** (new-widget default, Collapse/Expand All, per-box toggle); dock capsules flush to the left/right/top/bottom screen edge; hovering expands the widget after 0.15 s and collapses after 0.35 s, but inline rename, popovers, context menus and drags hold it open (`DesktopCapsuleHoverPolicy`); animated frame changes honor Reduce Motion; capsule state persists with backward-compatible decoding.
- **Multi-Display Topology Memory & Displays Settings (Phase 65):** Desktop widgets now remember their exact spot per display arrangement, keyed by a canonical sorted EDID-UUID signature (`TopologyLayoutArchive`, `com.katikati.desktop.topologyArchive`). Unplugging a display starts a configurable grace period, then either relocates its widgets proportionally onto the most similar remaining display or collapses them to capsules (`DisplayDisconnectPlanner`); reconnecting restores the exact remembered spot and capsule state, and an arrangement seen for the first time seeds from the most similar archived topology. **Settings › Desktop › Displays** lists every connected screen with its widgets, per-widget **Follow Main** / **This Display** EDID binding, one-click **Pin Layout**, **Identify Screens** number flashes, a default display, the disconnect action and grace period, and an undoable proportional **Move All Widgets Here** (`MoveAllWidgetsUndoPlan`).
- **WebDAV Scheduled Backup & Performance Modes (Phase 67A–E):** Back up to any WebDAV server on a Daily or Weekly schedule, with per-domain toggles for **Desktop Boxes & Styles**, **Todos**, **Quick Capture & Notes** and **Settings & Shortcuts**. Restores offer **Merge** (incoming items win, local-only items survive) or **Snapshot-Faithful** (the selected parts are replaced), remap `/Users/…` paths when the backup came from another Mac, and always write a local safety backup first. The client is a dependency-free `URLSession` implementation of PROPFIND, MKCOL, PUT, GET and DELETE; the password lives only in the macOS Keychain via `SecItem*`, never in `UserDefaults`. Notes travel as already-encrypted files and can only be read on the Mac that owns their key. Desktop widgets also gain **Balanced / Resource Saver / Custom** performance profiles: hidden widget SwiftUI surfaces are released until shown again, idle periods purge thumbnail and image caches, cache budgets are capped in MB, and vinyl spin, marquee scrolling, Glance rotation and capsule effects can each be switched off.
- **Unified Desktop Search (Phase 66A–B):** A new **Search** desktop widget pill opens a single search over Spotlight files, installed apps, Settings pages, notes and to-dos, ranked together (`DesktopSearchRanker`); Spotlight results pass through `SearchPathFilter` (caches, system trees, build products and user-listed paths are excluded). The results panel keeps recent-query history and favorites, supports click, ⌘-click and ⇧-click selection plus a drag rubber-band rectangle, and offers batch **Open / Reveal / Copy / Move to Box / Move to Trash** (trash confirms first). The pill can also hand its query to the Command Bar. **Settings › Desktop › Desktop Search** sets the result limit and excluded paths. 66C–D (Launcher-grid unified center popup) remain gated until the Launcher livecheck closes.
- **Dedicated Desktop settings page, on by default:** Desktop Boxes now have their own **Settings › Desktop** page (moved out of Widgets) with per-widget toggles for To-Do, Quick Capture, Glance, Weather and Vinyl Music, a **How to Use** note for every feature, and capsule controls. Desktop Boxes are on unless you turn them off, and To-Do and Quick Capture are added once on first run (never over an explicit Off or existing boxes).

## [0.18.0 beta 1] — 2026-11-17

Dock motion styles, a dedicated Clipboard page with Maccy-style keys and privacy, the DockPops drawer, dock layering,
space-switch transitions and the Drives widget; see `Docs/Releases/RELEASE_NOTES_v0.18.0-beta.1.md`.

### Changed

### Added
- **The Dock now has its own hover and click language, plus three running indicators.** Hover Animation picks
  None, Magnification, Spring Lift, Jiggle, Color Aura, Sliding Pill or Magnetic Pull; Click Effect picks Tactile
  Squish, Launch Bounce, Ripple or Flip 3D; Running Indicator picks the classic dot, a Windows 11 pill (16 pt for
  the frontmost app, 6 pt otherwise, one pip per window up to three) or a KDE Latte brand-coloured line. The aura
  and the brand line use a per-app dominant colour sampled once per session. With Reduce Motion on, every moving
  style falls back to the colour tint.
- **The Drawer is now a DockPops-style pop with its own dock icon**, at the head of the tail zone, left of
  Downloads and the Trash. It holds up to 25 apps, files and folders: drop anything on the icon from Finder or
  anywhere else, or drag a window card onto it to stash its app as before. Click the icon to open the pop; apps
  open or come forward, files open, and a folder is browsed right inside the pop with a back button. Existing
  stashed apps move in on first launch. The capsule beside the bar is now **Background Apps** only — its preview
  and its panel show running apps with no window, and nothing is stashed there any more.
- **Hybrid Dock Window Layering Engine (`DockWindowManager`)**: Settings › Window Management now has a **Dock Layering** section offering 8 selectable layering and interaction modes:
  1. *Always on Top* (Legacy preset: window level 20, always above all windows)
  2. *Dynamic Smart Z-Order* (Intellilevel: level 20 when idle, drops to level -1 under overlapping windows, peeks on 0.14s bottom edge dwell)
  3. *Same-Level Relative Order* (Keeps dock on normal level 0 and orders strictly below the covering frontmost window)
  4. *Always Below Windows with Edge Peek* (Sub-normal level -1, peeking on bottom edge dwell)
  5. *Native Auto-Hide Dodge* (Smoothly slides the dock off-screen via `NSAnimationContext` when a window overlaps the dock frame)
  6. *Click-Through Ghost Mode* (Marks dock transparent and click-through on window overlap, restoring on bottom-edge dwell)
  7. *Native Dock visibleFrame Piggyback* (Aligns at level 21 over native Dock to reserve `visibleFrame` without requiring Accessibility permissions)
  8. *Working-Area Strut Clamping* (Clamps overlapping windows to stop above the dock, with automated fallback cascade to Smart Z-Order when Accessibility is not granted)
  Zero-permission fallbacks (`CGWindowListCopyWindowInfo` geometry and the mouse-moved monitor, with 20 Hz `NSEvent.mouseLocation` polling only if the monitor cannot be installed) keep the engine fully functional without TCC prompts, while private SkyLight WindowServer fast paths and AppleScript `System Events` fallbacks reinforce reliability when permissions or helper services are enabled. First-mouse responsiveness (`acceptsFirstMouse`) is enabled across all panels so dock items respond immediately on the first click without stealing app focus.
- **Space switching with a transition**, ported from [Spacewalk](https://github.com/InsaneArts/Spacewalk) (MIT):
  Settings › Appearance has an **Effect** (Instant / Fade) and a **Duration**, and Settings › Shortcuts has **Next
  Space** / **Previous Space** (both unbound until you assign them, so the system's own ⌃← / ⌃→ keep working). A switch
  freezes the picture, lets the Dock change Space underneath it, then fades the picture that actually arrived in — so
  the transition is ours and the Dock still owns the switch. Needs macOS 26 or newer, Screen Recording and Accessibility;
  anywhere else, and with Instant picked, the switch is posted plain. Not ported from Spacewalk: the other ten effects,
  the Overview grid, the Spaces bar, the menu-bar indicator, finger-driven scrubbing, the CLI/TOML config and the updater.
- **Translucency** in Settings › Appearance, beside Vibrancy and Contrast: 100 % is the plate as it was, and lowering it
  lays the theme's tint down thicker until the plate reads solid. The tint is drawn over the backdrop, so the slider also
  reaches the macOS 26 glass, which takes no tint of its own. Only shown for a pinned theme — Auto and System tint nothing.
- **A Drives widget and a Drives menu-bar item**, after [DiskView](https://apps.apple.com/us/app/diskview/id6627346631): the dock widget shows the boot drive's free space and, on hover, the DiskView panel — one row per mounted volume with its used / total pair and a blue capacity bar that turns red past 90 %, and removable volumes carry an inline Eject. Settings › Dock Items lists it with the other dock widgets (hidden by default), it joins the Smart Stack's glance rotation and scores high when a volume passes 90 %, and Settings › Advanced › Menu Bar has a **Drives** switch for the status item, which shows the boot drive's free space and lists every drive with its bar in its menu. Free space is `volumeAvailableCapacityForImportantUsage`, the figure Finder shows.
- **The app icon now renders in every macOS 26 icon style.** Translucency was off in `Resources/AppIcon.icon`, so the
  Clear style fell back to an opaque plate; it is on now, with light/dark/tinted strengths, and the Tinted style keeps the
  teal fill instead of going white.

### Changed
- **Slices ship on green (standing rule 9).** Every slice is committed and pushed as it finishes — Core plus its
  targeted test run first, then the UI half plus the localization gate — and plan or rule edits travel in the
  same pass, so `origin/main` always holds the last verified slice.
- **Search ranks like a launcher should** (⌥Space and the command bar): one matcher now scores every app, window
  and menu row by nanolight's tiers — the whole name first, then the name's start, a word's start, the words'
  initials (`vsc` finds Visual Studio Code), the query anywhere inside, then letters merely in order — and small
  typos still land (`chorme` finds Google Chrome, `notse` finds Notes). Apps you launch often move up, capped so a
  loose match can never jump an exact one.
- **The command bar opens on ⌥⇧Space.** Its default was ⌘Space, which macOS hands to Spotlight first, so the bar
  never appeared on a stock Mac. An install that already stored that chord moves to the new one by itself; custom
  shortcuts the system does not own are left exactly as they were.
- **Every permission is asked once, during setup.** The first-run guide's Permissions step now asks for
  Accessibility, Screen Recording, Input Monitoring, Microphone, Calendar, Reminders, Notifications and Location in
  one pass (each only when still undecided), so the calendar panel, the weather chip and the first alarm no longer
  raise their own prompts in the middle of something else.
- **Quitting is one table now** (Settings › Shortcuts, beside Hold ⌘Q to Quit): every app with a quit rule of its own
  is one row with three switches — **Skip Hold** (⌘Q quits at once), **Own ⌘Q** (the app keeps its own ⌘Q, for remote
  desktops and virtual machines) and **Quit on Close** (quit once its last window closes). Apps are added by name from
  the ones that are running, or by bundle ID for one that is not, and a typed ID is checked first — the four
  comma-separated fields this replaces each swallowed a typo without a word. Skip Hold and Own ⌘Q cannot both be on,
  because the key tap reads Own ⌘Q first and the other switch would have been a lie. Turning an app's last switch off
  takes its row away, and the table names the app instead of asking you to remember `com.company.App`.
- **Quit when the last window closes** left Settings › Tiling: it was never a tiling setting, and it is the third
  column of that table now. Finder, the Dock and KatiKati itself are not offered that column; the row says why.

### Fixed
- **Ribbon columns no longer overlap when one straddles the screen edge.** Every tile was written back inside the work area, so a column the strip deliberately hangs past the viewport edge was pulled on screen by its overflow and sat on top of the column before it (measured live: a 10 pt overlap with four ¼ columns on a 1710 pt display). Strip writes now skip that clamp, so the straddling column keeps its off-screen slice and the gap to its neighbour survives; macOS still keeps that slice on screen as asked. The other eight presets are untouched — their frames never exceed the work area.
- **A pop's plate takes the theme's tint.** Choosing a theme re-tinted the drawer chip but left the pop's own
  plate exactly as it was, so two presets looked identical on the surface the setting is named after. The plate now
  takes the same tint the dock plate takes, through the same helper, arrows included.
- **The Downloads prompt waits for the Downloads chip.** Nothing read the folder before its chip was clicked on a
  fresh install, but once you had opened it, every launch read it again — so "KatiKati would like to access files
  in your Downloads folder" arrived over the desktop with no click behind it. The chip now shows its plain folder
  icon, and no download badge, until you open it once in a session; from that click on the cover, the watcher and
  the badge read it as before. (Files & Folders records its grant against a code signature, so an unsigned build
  is asked again after every rebuild — the reason a launch-time read could never be silent there.)
- **The calendar prompt waits for the calendar.** It was raised on launch, because the clock card on the bar asked
  for access the moment it appeared — a system prompt with no user action behind it, in the first seconds of a
  session. Opening the calendar panel (or the notch's calendar page) is what asks now: one prompt, for events. The
  card carries an **Allow calendar access** row while the answer is still unknown, prompting reminders waits for the
  panel's own reminders tile, and a denied calendar shows its explanation instead of an empty agenda.
- **A Finder chip brings Finder forward.** Clicking it with no Finder window open did open one — and left
  whatever was in front exactly where it was, because the opener's own activation reports success without
  raising the app. The chip now raises Finder the way every other app chip's click does, then opens the window.
- **A chip cannot be click-dead any more.** Every chip published its frame into its own table and the hit-test read
  a hand-written union of those tables, so a chip that was never added to the union still hovered and still showed
  its tooltip while every click fell through. One registry now carries every chip's frame and zone, and the menu
  zones, the resize grip, the landing anchors and the fluid lobes all read it, so a new chip kind cannot be left out.
- **The dock no longer comes back over fullscreen apps.** The layering engine re-applied the dock's level every 0.35 s
  and, in the default mode, ordered the dock to the front each time, which put back a dock that had just been hidden for
  fullscreen, a Space switch or auto-hide. It also set every surface opaque and clickable on each tick, cutting the
  fullscreen fade short and making the click-through glass plate catch clicks. It now changes a level only when it
  differs, never orders in a hidden surface, and in Click-Through Ghost mode restores exactly what it changed.
- **The layering engine is idle in the default mode.** Always on Top and Piggyback no longer run the window-list poll,
  the per-app Accessibility observers or the mouse sensor; the other modes run only what they read, with one mouse
  source instead of a monitor, a 20 Hz timer and a fifth event tap all at once.
- **Layering follows the real dock**: a left or right rail, a custom bar height, a floating gap and a bar on a second
  display are tested where they are, not as a 52 pt strip at the bottom of the main screen. Strut clamping only acts on
  a bottom bar.
- **Native Auto-Hide (Dodge Windows) brings the dock back.** Sliding back reused the off-screen position, so the dock
  never returned; it also slid down even on a side rail. It now slides out through the edge it hugs and returns with a
  normal relayout.
- **Native Dock visibleFrame Piggyback asks first and gives your Dock back.** Choosing it shows what it will change
  (Dock position, auto-hide, magnification and icon size, plus a Dock restart); your own values are recorded first and
  written back when you choose another mode. It no longer rewrites the Dock and restarts it on every launch.
- A unit test called the real native-Dock service and could restore a developer's Dock; the Dock helpers now take an
  injected service, and the shell fallback that ran `killall Dock` from a sandbox is gone.

### Removed
- The four per-app bundle-ID text fields ("Quit instantly, no hold", "Pass ⌘Q through", "Quit when the last window
  closes"). Their values are kept — the table reads and writes the same three keys.

## [Unreleased] — background apps in the capsule, and a paste-to-Finder shortcut

### Added
- **Paste Image Into Finder** (Settings › Shortcuts, unassigned by default): saves the image on the clipboard
  into the front Finder window's folder as a `.png`, named `Clipboard Image.png`, then `Clipboard Image 2.png`
  and up — it never overwrites, and the toast says what happened, including when the Finder Automation grant is
  still missing.

### Changed
- The drawer capsule's empty state now shows **how many background apps** the drawer is holding, with the RAM
  and CPU reading moved into its tooltip. A drawer with nothing in the background keeps the RAM/CPU disc.
- Clicking that count **opens the drawer on its background-app section**, and the list lands at its end when it is
  taller than the plate — a scrolled drawer otherwise always opens at the grid's top. The disc's tooltip, now the
  only place the RAM / CPU reading is shown, is no longer shadowed by an empty one from the cells above it.
- The drawer now **rules off those background apps**: a hairline and a small **Background Apps** label sit between
  the apps held in the drawer's order and the ones it lists because they have no window. The plate's title reads
  **Drawer** in both cases — it used to rename the whole drawer once a single background app appeared — and the
  drawer's row budget leaves room for the rule, so the tallest grid still clears the top of the screen.

### Removed
- The unused `DynamicGaugeFABView` wrapper (40 pt gauge FAB, no call sites); its compact disc is unchanged.

## [Unreleased] — Phase 59d: the notch battery card

### Added
- Click the battery in the **open** notch header and a small card shows what the percentage cannot: **Time Remaining**
  (or the time to full while charging), the **Watts** going in, **Thermal** pressure once the Mac is running warm,
  **Health** and **Cycles**, plus a **Low Power Mode** badge. A number this Mac cannot report — a desktop Mac, a
  registry without the key, macOS's "still calculating" sentinel — leaves its row out instead of printing a zero.

## [Unreleased] — Dock chips offer the app's own New Window / New Tab

### Added
- A dock chip's right-click menu now carries the app's own "new" rows, read from that app's File menu over
  Accessibility: Finder shows **New Finder Window** and **New Tab**, Terminal **New Window** and **New Tab**,
  in the app's own words and with its own order. At most three rows, and ⇧⌘N's New Folder is not one of them.
- Both app-level and window chips get them; the generic **New Window** remains only as the fallback when an
  app's menu reports nothing, so no chip lists it twice.

## [Unreleased] — Phase 59b–59h: the battery tells time, and the alerts have a style

### Added
- **Time to empty / to full, charging watts, thermal state and Low Power Mode** (`PowerFacts`, IOKit only, no shell):
  the menu-bar battery item can now show **Time Remaining** or **Watts** instead of a percentage, Control Center's
  *This Mac* row carries the one-line reading, and the notch battery chip shows it on hover.
- Extra low-battery steps at **25 / 10 / 5 / 1 %**, off by default and each fired once per dip, a system-sound toggle,
  and an **Alert Style** row: Compact Pill (as before) or a wider Banner under the notch.

### Changed
- **One low level for the Mac.** The Notifications page owns it; the notch's battery tint and its own slider read that
  same value, and a level stored by the Notifications page's predecessor is still honoured. A peripheral's "low" is
  likewise defined once, shared by the notch battery buddy and the peripheral alert.

### Fixed
- An 80 % charge milestone and a full charge no longer both read "Battery Charged": the milestone is **Charge
  Milestone**, only a finished charge says **Battery Charged**.

## [Unreleased] — Phase 59a: notifications are a pill, and their own page

### Added
- Settings → **Notifications**, its own sidebar page next to Notch: a low-battery alert at 10–50 % (or Off),
  80 % / 100 % charge milestones, Charging & Unplugged, peripheral alerts, the history the page lists, and a
  24-hour-or-7-day retention picker with **Clear History**. The banner-placement rows that sat at the end of
  Advanced moved here with it.
- Battery, charge-milestone, plug-change and peripheral (connected / disconnected / low) notifications, fired from
  `PowerNotificationPolicy`: transitions only, one alert per dip and one per milestone per charge session, so a
  battery sitting at 20 % is not announced on every sample. The rules are BeteriApp's settings.
- Peripherals the Bluetooth profiler lists without a charge get it from the HID driver's registry
  (`AppleDeviceManagementHIDEventService`'s `BatteryPercent`, BeteriApp's second source), merged into the profiler's
  list rather than replacing it.

### Changed
- A notification arrives as the compact capsule the track pill uses, pinned under the menu bar's centre — not the notch
  island, which takes the menu bar's width and much of the screen for one line of text.
- **Quick Settings fills the height between the menu bar and the dock** instead of opening at its content's height: the
  panel is sized to that gap, the switch grid goes five per row only when four would overflow, and the network row,
  sliders and footer sit at the bottom of the panel.

## [Unreleased] — Phase 58d: the Control Center wears the dock's theme

### Changed
- Control Center content rebuilt to the owner's design: a clock and battery header, a **System & Peripherals** card
  with a live percentage bar per device (This Mac plus connected Bluetooth peripherals, refreshed on demand), Wi-Fi
  and Bluetooth as accent bento cards, now playing with artwork and a live progress bar, the switch grid, the network
  row, the three sliders, the utility row and the account footer.
- Its chrome is the dock's: the plate takes the selected preset's own tint and rim (vibrancy/contrast included), cards
  and active accents come from the same `SettingsIridescentPalette` the Appearance swatches are drawn from, and text
  uses the dock's label tints — so Aurora, Ember, Rose Quartz and the light presets restyle panel and bar together.
- The panel opens at its content's height instead of the screen cap, so no transparent band sits under the last card
  while the first height report is in flight.

### Added
- The switch grid picks 4 or 5 cells per row from the measured panel height (`ControlCenterGrid`, unit-tested): five
  only when the panel overflows and five removes a row.

## [Unreleased] — Phase 58c: an option to put the Control Centre at the dock's right end

### Added
- Settings → Dock Items → **Control Centre on the right**, off by default. Turned on, the Wi-Fi / Control Centre
  button takes the far right of the bar and the drawer capsule moves one slot in, wired as a pair of tiles — the gap
  between them is the same 8 pt the capsule keeps from the bar. The bar keeps its length and position: the plate
  grows by the slot the disc takes over and the capsule moves inside it. One-plate bars only (Centred, Full Width);
  the split layouts, a side rail, a left-side drawer and a widget order with something after Widgets keep the
  arrangement that has shipped for months.

### Fixed
- The drawer capsule can no longer be buried by the plate: every layout commit and every Control Centre open or
  close puts it back above the bar's windows, so the tile stops vanishing when a panel is raised.

## [Unreleased] — Phase 58b: the welcome guide opens behind a glass lens

### Added
- The welcome guide's first appearance is now a native glass intro: a lens springs open into a frosted card, holds
  for a beat and dissolves onto **Pick a Layout**. Clicking it ends it early; Reduce Motion gets a plain fade
  instead of the spring. Nothing behind it can be clicked while it is up. No third-party code: one material, one
  gradient ring, one spring.

## [Unreleased] — Phase 58a: the welcome guide names the microphone

### Added
- The welcome guide's **Permissions** step now lists **Microphone** beside Accessibility, Screen Recording and
  Input Monitoring. The voice recorder and the camera mirror both need it, and without it macOS answers with
  silence rather than an error. The step already re-reads every grant once a second, so the row flips to
  Granted as soon as you allow it.

## [Unreleased] — Phase 57c: a floating orb for the launcher

### Added
- Settings → Launcher: **Floating Orb**, off by default. A small glass orb floats over your windows: click it to
  open the launcher (click again to close), drag it anywhere and it stays there — across relaunches and display
  changes. It never takes focus, keeps inside the usable screen, and is a VoiceOver button.

## [Unreleased] — Phase 57b: the launcher can be a card

### Added
- Settings → Launcher: **Presentation** — Fullscreen (the default, unchanged), Centred (four fifths of the
  screen, never over 1200 × 760) or Popover (a 640 × 520 card hanging under the pointer). The windowed modes
  keep the desktop visible around a rounded glass card; Escape or ⌥Space still closes them.

## [Unreleased] — Phase 57a: scroll the Control Center volume row

### Added
- Control Center: scrolling with the pointer anywhere on the volume row nudges the volume — 1.25 % per six
  points of trackpad travel, one mouse-wheel click counts as 2.5 %, clamped to 0–100 % and rate-limited so a
  fast flick cannot jump the level. The slider keeps its own drag and clicks.

### Fixed
- The volume row read a level that lagged a write by one audio listener hop, so rapid wheel steps were computed
  from a stale base and lost — three 2.5 % steps moved the volume 3 points instead of 7.5. The step now reads
  the device.

## [Unreleased] — track pill: readable title and artist

### Fixed
- The pill that announces a new song rendered its title and artist as thin slivers: the text column had
  no width of its own inside a pill that sizes to its contents. The pill now sizes itself to the longer
  line, capped at 170 pt, where a long title scrolls instead of stretching the pill.

## [Unreleased] — Phase 54: window management

### Added
- Settings → Tools (Shelf → System Dock): "Fixed Space Order" stops macOS from rearranging Spaces by
  most recent use. It changes a macOS setting, so the switch asks first and the Dock restarts once;
  turning it off puts your earlier setting back.
- Settings → Tiling: "Focus Follows the Mouse" raises the window under the pointer, at most once every
  120 ms, never mid-drag, never while a KatiKati panel has the keyboard and never for the app already in
  front. Off by default; needs Accessibility.
- Taskbar chips: ⌥-click hides the app, ⌘-click minimises the window. A plain click behaves exactly as
  before.

## [Unreleased] — Phase 52c: Claude Code status from a hook

### Added
- Settings → Tools: "Track Turns with a Claude Hook", off by default. It adds two hooks to
  `~/.claude/settings.json` — one when a prompt is submitted, one when Claude stops — that append to a
  local log, so the notch's AI page says ACTIVE while Claude Code works and IDLE as soon as it stops,
  instead of waiting five minutes for the transcript to go quiet. Your other settings and hooks are kept,
  the original file is backed up once, and the switch refuses to touch a settings file it cannot parse.
  Restart Claude Code after changing it.

## [Unreleased] — Phase 52a: agent usage reads the current logs

### Fixed
- AI usage: Codex's current `token_count` event was read as the session's running total, so a
  long session could add its whole total again on every turn. The per-turn figure is counted now.
- AI usage: Claude Code cache writes whose parent total is zero are counted from their
  breakdown, and `<synthetic>` zero-token lines no longer appear as turns.
- AI usage: Claude Code turn start times come from the transcript's millisecond timestamp
  instead of falling back to the file's modification time.

## [Unreleased] — Phase 53d, 55d and 55g: opt-in quit, cache review, retention

### Added
- Settings → Tiling: "Quit when the last window closes" takes a comma-separated list of bundle IDs and is
  empty (off) by default. An app on the list quits after its last window closes, gracefully, so its own
  save prompt still runs; Finder, the Dock and KatiKati itself are always ignored. Needs Accessibility.
- Notch → Storage: "Review Caches…" lists stale cache and log folders (7+ days old, 50 MB+), names the
  total in a confirmation, and moves only the folders you confirm to the Trash. No timer, nothing deleted
  without the confirmation.
- Settings → Tools: "Keep Clipboard History" keeps history Forever (default), 7 days or 30 days. Pinned
  entries never expire.

### Changed
- Clearing clipboard history and clearing unpinned shelf items now ask for confirmation first.

## [0.17.0 beta 3] — 2026-10-19

Notch redesign, Settings redesign and stability fixes; see `Docs/Releases/RELEASE_NOTES_v0.17.0-beta.3.md`.

### Fixed
- `TilingTree.insert` and `ShelfStore.shelfFolder` no longer force-unwrap.

## [Unreleased] — Phase 53 snippets and Phase 55 utilities

### Added
- Settings → Tools: "Expand Snippets Anywhere" pastes a snippet's text when you type its trigger plus a
  space, in any app. Off by default; never active in password fields, password managers or secure input.
- A "Capture Area" shortcut (default off) runs the same region-to-clipboard capture as the Radial Dial.
- The shelf can reduce an image: 75 % of the longest edge, re-encoded, saved as `<name> reduced.jpg`
  (HEIC when it has transparency).

## [Unreleased] — Phase 53: input guards

### Added
- Settings → Shortcuts: "Protect Caps Lock" ignores a quick Caps Lock tap; hold it briefly to switch. Off by
  default, needs event posting, and does nothing while Hyper Key is on.
- Settings → Shortcuts: "Finder Keys" makes ⌘X copy-and-mark and ⌘V move the selection in Finder.
- Settings → Shortcuts: "Pass ⌘Q through" lists remote-desktop and VM apps that keep their own ⌘Q while
  Hold ⌘Q to Quit is on (Screen Sharing, Parallels, VMware Fusion and UTM by default).

## [Unreleased] — Notch redesign, slices 2–4

### Added
- Closed notch dock: free storage on the left, battery on the right.
- Event toasts show as a card with an icon tile and a bar that drains over its 3 s lifetime.
- Settings → Notch: "Sharp Notch Edges" gives square corners and removes the flared ears.

## [Unreleased] — Notch redesign, slice 1: Storage page

### Added
- A Storage page in the notch lists the largest folders and files on the Mac, biggest first; click a row to
  reveal it in Finder. Whole-disk results need Full Disk Access, offered as a link to System Settings.

### Removed
- The Retro Flip Clock page and its world-clock card (the world clocks stay in the calendar panel).

## [Unreleased] — Settings redesign, Phase 7: keyboard and search

### Added
- ⌘F focuses the sidebar search and ⌘1…⌘9 jump to the first nine sections.
- The sidebar search also matches keywords (for example "torrent" finds Downloads), and Return opens the
  first match.

## [Unreleased] — Settings redesign, Phase 6: time-of-day glow

### Added
- `TimeOfDayPalette` (night, dawn, day, dusk, blended by the hour) tints a soft glow at the top of the
  Settings window and the stage's backdrop. It is off for Reduce Motion and Increase Contrast.

## [Unreleased] — Settings redesign, Phase 5b: stages for Shortcuts and Downloads

### Added
- The stage on Shortcuts (keycaps for the feature shortcuts you have bound; reads settings only, no key
  monitor) and Downloads (a queue silhouette over a 24-hour strip showing the quiet-hours window).

### Changed
- The BitTorrent rows are full-width (label left, control right) instead of side-by-side pairs.

## [Unreleased] — Settings redesign, Phase 5a: stages for Window Management, Control Center, Radial Dial

### Added
- The stage on Window Management (four sample windows laid out by the Preset, with the inner and outer
  gap), Control Center (the panel at its side, width and anchor, one block per enabled tile) and Radial
  Dial (the wedge ring in the chosen theme's colours). Each reads settings only.

### Changed
- Control Center and Window Management rows are full-width (label left, control right) instead of
  unequal side-by-side pairs.

## [Unreleased] — Settings redesign: Appearance page refinement

### Changed
- Appearance: removed the small bar preview under Layout Mode (the stage shows it). Position, Bar Height,
  Spacing, the chip toggles, preview delay/size, Icon Set / Right FAB Style and the wallpaper rows are
  now full-width rows (label left, control right) instead of unequal side-by-side pairs; the layout
  description is centred under the picker.

## [Unreleased] — Settings redesign, Phase 4: stage on Notch and Edge Bars

### Added
- The live stage now also appears on Notch (it draws the open panel of the chosen style) and Edge Bars
  (bar geometry and layout mode redraw as you change them). Same stage position picker and handle.

### Changed
- The Notch page drops its own in-page notch preview while the stage is visible (one notch, not two).

## [Unreleased] — Settings redesign, Phase 3: live stage for Appearance and Widgets

### Added
- A live preview stage above or beside the controls on Appearance and Widgets: a mini screen on the
  user's wallpaper with the notch and the bar, redrawn as settings change. It only reads settings
  (no permission prompt, window move or network call).
- Header picker for the stage position (Top / Side / Off), a drag handle to resize it (double-click
  resets), and persistence of both. `SettingsStageSize` (Core) clamps it to 160pt...60% of the window.

## [Unreleased] — Settings redesign, Phase 2b: SettingsLayoutPane split by mode

### Changed
- `SettingsLayoutPane` (1438 → 226 lines) keeps its state and `body`; each mode's sections and helpers
  live in `SettingsLayoutPane+Appearance / Widgets / Launcher / ControlCenter / EdgeBars / Shortcuts.swift`.
  Its stored state is now internal (extensions in other files need it). Pure move: same `@AppStorage`
  keys, same 246 `Text` keys, 2522 tests green.

### Fixed
- The ids the Phase 2a files got in `project.pbxproj` were 22 characters, not 24; they are repaired.

## [Unreleased] — Settings redesign, Phase 2a: the layout pane's helper views move out

### Changed
- `SettingsLayoutPane.swift` (1782 → 1438 lines) sheds the layout thumbnails/pickers and the shortcut
  recorder into `LayoutModePickers.swift` and `SettingsLayoutSupport.swift`. Pure move: the set of
  `@AppStorage` keys is identical, build and all 2522 tests pass.

## [Unreleased] — Settings redesign, Phase 1: sidebar shell and a freely resizable window

### Changed
- **Settings is a System Settings-style window.** One sidebar is the only navigation (the toolbar tab
  strip and the floating nav bar are gone); it collapses to icons under 860 pt or with the toggle.
- **Resize it to any size ≥ 640 × 440; the size and the selected section are remembered** across
  relaunches (a frame saved on a missing display is pulled back on-screen). Pages scroll instead of the
  window auto-fitting each page.
- **14 sections:** Radial Dial, Downloads and Info are now their own pages (Info holds permissions and
  About, moved off General).

## [Unreleased] — Phase 12: the Settings window measures what it actually shows, so no page hides its tail

### Fixed
- **The Settings window no longer cuts off the bottom of a page.** The window sized itself from the page
  alone, while the floating nav bar lives in the same content area above it — so every page was one nav
  bar (~54 pt) taller than the window that was meant to show it, and the last row of a page a screenful
  tall sat below the fold even at the window's maximum. The window now measures the nav bar with the page
  (General 737 → 818 pt, and `Show Setup Guide Again` is on screen).
- **Three pages that only overflowed once a control was used are fixed too**, each by pairing or folding
  rows rather than by removing a control: Appearance with a tinted theme pinned (1003 → 956 pt: the two
  plate sliders share a line), Widgets with *Context Presets* armed (1018 → 975 pt: the switch, both
  windows and their fixed hours are one line, and the widget list's rows are 37 pt, not 41), and Edge Bars
  on the *Custom* preset (1261 → 899 pt: the one-row-per-item list is folded behind a disclosure, collapsed
  by default, the shape the Shortcuts page's assignments already use).

### Changed
- **Appearance, Widgets and Tools are compacted to fit with room to spare** (Appearance 1081 → 899 pt,
  Widgets 993 → 951, Tools 1030 → 948). Narrow rows that each wanted a line now share one (the theme grid
  onto a single row, the icon set with the right-button style, the three weather warnings, both download
  ratio pairs), and the platform row's trailing space is a card's, not the page's. The one thing that left
  the page is the pair of icon-set preview tiles on Appearance (58 pt): the segmented control above them
  names and draws the same choice. Nothing else was removed — every control, key and value is in its place,
  and the before/after numbers, captures and the live walk are in
  `Docs/Archive/Planning/evidence/2026-10-18-settings-dock-live/README.md`.

## [Unreleased] — Phase 32: the dock's motion language, and the circular icon look is packed

### Added
- **The dock widgets' motion is a choice now: Settings › Widgets › Dock Motion.** *Fluid* is what the bar
  already moved with, *Snappy* is faster and firmer, *Instant* changes instantly — and Reduce Motion always
  wins over all three. The first widget wired to it is the weather one: the temperature in the detailed pod
  and in the classic pill morphs to its new reading instead of snapping. The row takes the right half of the
  *Now Playing Style* pair; **Right FAB Style** moves to Settings › Appearance.

### Changed
- **The dock app icon shape is no longer a setting.** The circular mask was packed on the owner's call
  (2026-10-16): every icon wears the standard macOS squircle again, and the one-click switch left
  Settings › Appearance. The look is not deleted — `DOCK_ICON_FRAME=circle` brings it back for a launch,
  through the app's registered debug switches (`Core/Support/DebugSwitch.swift`), and unset is exactly the
  squircle that ships today. The retired `com.katikati.dock.iconShape` key is simply ignored from now on.

## [Unreleased] — Phase 48: the notch's productivity page runs on your real day, the clock page on your world clocks

### Fixed
- **The Productivity notch page runs on your real calendar and your real timer.** The agenda card and the
  focus card were drawn from samples. The agenda now shows the day you pick on a week strip — a tap selects a
  day, the chevrons walk a week at a time — a tap on an event opens its own meeting link (or Calendar on that
  day, when the event has none), and a card whose Calendar access is off says so and opens the pane instead
  of drawing an invented day. The focus card drives the real Pomodoro (25/5/15, four runs to a cycle, with
  pause, reset and skip) and ticks off your next reminder. The random "decision" spinner is gone: it was the
  one thing on the page with nothing behind it.
- **The Retro clock page's second card shows your world clocks, not the local time again.** It repeated what
  the card above it already flips. It is now the up-to-four clocks you keep in the panel's Time zone card —
  sun or moon, city, *Tomorrow*/*Yesterday*, offset, time — with **Remove** in a row's own context menu and
  **Add City** from the same picker the panel uses. Both surfaces edit one store, so a city added in either
  place shows up in both.
- **AI Mission Control now reads every AI tool that records usage, not just Claude.** OpenCode's own
  session store and Codex rollout logs join the Claude transcripts in the day's tokens and spend, with the
  page naming the stores it actually read and saying which dollar figure is the tool's own number and which
  is estimated. Tools whose stores keep no accounting (Copilot's chat store holds message text, not tokens)
  contribute nothing rather than a converted guess, the invented "Claude 3.7 Sonnet" title is gone, and an
  empty day draws a dash instead of a zero.
- **The Top Apps rows can end a process.** Each row keeps its pid, so a tap offers the same
  Kill / Force Quit confirm the Command Bar uses and the list redraws with the process gone. A row the
  system won't let you end says why instead of pretending. Rows without a pid still only print.
- **The weather widget stays inside the dock.** Its forecast form was taller than the dock bar and stuck
  out over the top. The whole forecast now scales to fit the slot — all three days stay visible, inside.
- **A pinned Downloads folder no longer freezes the app before its first window.** The folder watcher opened
  its directory on the main thread, and on a TCC-protected folder that call blocks until the authorization
  prompt is answered. The open now happens on a background queue; the folder's cover simply arrives a moment
  later, and an unopenable folder retries on the next sync instead of hanging launch.

## [Unreleased] — Phase 47: the music surfaces answer the player, a camera mirror, mirrored notifications

### Fixed
- **The music widgets now follow the player — on the press, and on the player's own track changes.** The
  poll was the fault: the 2 s AppleScript re-read stopped as soon as a track was known, so a skip the player
  accepted never reached the notch or the island and play/pause never flipped its glyph — the widgets sat on
  the old track. The fallback now re-reads while it is the live source, re-reads 0.4 s after every press and
  flips play/pause at once. The transport was also addressed through a bundle id only some readings set,
  which could leave a command with no target at all; it now commands the player the reading itself named.
- **The tracking bars scrub.** Only the notch's vinyl page could seek; the notch music panel, the dock card
  and the popup drew bars you could not touch. One shared scrubber now sits on all four.

### Added
- **A camera mirror notch page, with the camera chosen from a dropdown.** An 8th page (Settings › Notch ›
  Camera mirror) shows a live mirrored preview of whichever camera you pick — built-in, external or
  Continuity. The camera opens only while that page is on screen and is released the moment you leave it:
  this is the app's first camera ask, and a refused grant says so and opens the Camera pane instead of
  pretending there is no camera.
- **A notifications notch page fed by Notification Center itself.** A 9th page (Settings › Notch ›
  Notifications) shows the banner Notification Center is drawing now plus the history its own database
  keeps. Accessibility feeds the live banner; Full Disk Access feeds the history, read read-only while the
  page is open. Either grant missing is stated with the Settings door, never shown as an empty list.

## [Unreleased] — Phase 46: the weather widget wears the weather, and the bar hugs the edge

### Added
- **The weather widget now has a background that matches the weather and the time.** The detailed 3-day pod
  used to be plain dock glass while the classic pill beside it already carried the reading's own sky, so the
  same reading looked like two different widgets. Both now draw the plate from the condition *and* the hour —
  a clear night is the indigo card, a rainy noon the teal one — and the two glass versions are kept as presets
  (**Glass 3-Day Forecast**, **Glass Weather Pill**), so the sky is the default look and the old one is one
  click away. The row is **Weather Style** in Settings › Widgets, and the dock's own right-click menu lists
  every preset it offers.

### Fixed
- **The weather widget no longer shows a sun at 3 a.m.** The feed's own symbol is day art (Open-Meteo's WMO
  codes carry no night variant), so the pod and the rail tile printed a **sun** all night. Both now ask the
  reading for its glyph — the same condition at the reading's own time of day — which is what the classic pill
  and the weather panel already did.

### Changed
- **Every built-in dock style hugs the bottom edge.** Islands, Classic, Minimal and Side Rail used to write the
  8 pt floating gap, so picking one — or accepting the welcome guide's pre-selected Islands — lifted a bar the
  fresh install sits on the edge. The gap stays a free control in Fine-tune (Bottom Edge, Distance From Edge).

## [Unreleased] — Phase 45: the music widgets say when they cannot read your player

### Added
- **The music widgets tell you when macOS is blocking them.** If KatiKati may not control Spotify or Music
  (Automation permission refused or still unanswered in System Settings › Privacy & Security), the media card,
  the dock/edge popup and the notch's music card now say **"KatiKati can't read Spotify"** where they used to
  say "Not Playing", with an **Open System Settings** button that lands on the Automation list. The probe rides
  the existing read, so it costs nothing extra and never guesses: only a real refusal (AppleScript error
  -1743 or -1742) raises it, while a stopped or unreadable player leaves the surfaces saying "Not Playing" as
  before. Once the grant is on, the next read puts the real track back.

## [Unreleased] — Phase 44: magnet links really download

### Added
- **The download hub runs a real BitTorrent engine.** Pasting a `magnet:` link or a `.torrent` URL into the
  notch's torrent hub now starts an actual transfer: KatiKati drives `aria2c` (the Homebrew/MacPorts build on
  your machine) as a private loopback-only child process, and the row shows the engine's own numbers — the
  torrent's real name once the metadata lands, its real size, download/upload rate, seeders and connections,
  and the ETA computed from them. Torrents land in your Downloads folder next to the other download types and
  stop uploading the moment the payload is complete (`--seed-time=0`). The engine starts on the first magnet,
  is stopped when the last torrent row leaves the hub, is shut down on quit, and exits by itself within a few
  seconds if the app is force-quit — a machine that never opens a magnet never runs it.
- **No engine installed is now a stated reason, not a silent no.** With no `aria2c` on the machine the hub says
  **"Install aria2 to download magnet links"** and still refuses the link — it never invents a swarm.
- **Torrents resume after a restart.** Unfinished torrent rows are saved and re-added through the normal path
  on next launch (completed and failed rows are not); the engine's GIDs never cross a restart.
- **Seeding and upload policy, on the Tools page.** A new BitTorrent card carries a custom engine path (blank =
  auto-detect, applies on next start), a seed ratio and seed minutes (both 0 = stop sharing at completion, as
  before), a max upload rate (0 = unlimited) and a quiet-hours window with its own upload cap. Policy pushes to
  a running engine live; the status line names the detected binary or says none was found.

### Fixed
- **A magnet row no longer reports the engine's metadata block as the download.** While the engine fetches a
  torrent's metadata (21 KB in the verified run against a 276 MB payload) the row reads CONNECTING with no size
  or speed, then switches to the payload download once that begins.
- **A torrent that fails says why.** The row carries the engine's own message instead of "FAILED" with nothing
  behind it, and a torrent still connecting can be paused.

## [Unreleased] — Phase 43: the bar's widgets stop inventing data

### Fixed
- **The now-playing widget no longer shows a song you are not playing.** With no track from the system it
  printed a hardcoded `God's Plan / Drake` and drew the progress bar at a guessed 35 %; it now reads
  "Not Playing" (naming the app when it knows it) and draws no bar unless the system reported a position.
  It had nothing to show because MediaRemote answers now-playing queries only to a trustworthily signed
  process: with no code-signing identity on this Mac, none of MediaRemote's three callbacks fires at all, so
  Spotify and Music are read through AppleScript instead. That fallback shipped with an unbalanced `if`, which
  made every read fail with -2741 — the widget stayed on "Not Playing" while Spotify played. The script
  compiles now, and the fallback is reached even when MediaRemote answers nothing at all.
- **The weather widgets no longer print a city you never chose.** The canned "Rome 26°" starting state, the
  Rome fetch when location is refused with no saved city, the Rome forecast that topped up a short 3-day
  list and the `Today/Tomorrow/Later` columns that invented ±1° are all gone. A slot with no forecast shows
  a location mark and "Add City" (the panel's own city search) instead of a temperature nobody measured;
  a short forecast simply shows fewer columns.
- **The clock widget now reads the calendar it displays.** Only the notch's calendar page started the shared
  calendar service, so a fresh launch said "No Events" for a calendar nothing had read; the clock card
  starts it on appear (events only — it asks for no reminder access) and says "Calendar access is off"
  instead of claiming an empty day when access is refused.
- **The tracking bar carries the track's length.** The dock chip's bar and the notch's audio deck now print
  elapsed on the left and the track's own duration on the right — the deck used to print the remaining time,
  which reads as a second countdown — and the bar still appears only for a position the player reported.
- **The now-playing widget's volume page works.** It never started the CoreAudio-backed status service, so it
  read a default level and every drag was a no-op; the service is now acquired while the chip is on screen
  (checked end to end: a click on the page's bar moved the Mac's real output volume, and the page read the
  device's own state back).
- **The weather pod fits its slot.** The 3-day detail columns used to run past the plate into the widget
  beside it; the pod now degrades L→M→S exactly like the classic pill, so it never overflows the width the
  preset allows.
- **The notch's audio deck shows the record the player is playing.** Album art when the player hands one over,
  the turntable — spinning only while a track plays — otherwise; the hard-coded "54 dB" badge is the real
  output volume, "Hi-Fi Turntable" is gone, and the deck's scrubber carries elapsed / duration like the dock.
- **The alarm page arms a real alarm.** It no longer invents a "Missed" alarm out of the clock (any enabled
  alarm 0–15 minutes back) and its "+20m nap" shortcut is replaced by a time picker over the same alarm store
  the calendar panel reads.
- **The download hub only shows transfers that exist.** The demo seed (a fake in-flight browser download, a
  fake torrent with seeders and peers, a fake completed file) and the tick that faked their progress are gone;
  magnet and `.torrent` input is refused rather than answered with a random swarm, and a browser `.download`
  file reports the bytes on disk instead of a guessed total and a fixed speed.

### Tests
- `NowPlayingProgressTests` compiles the AppleScript fallback (the `-2741` bug above) and parses its record
  field by field; `DownloadManagerTests` asserts the manager starts empty and refuses the torrent paths.

## [Unreleased] — Phase 12: the five Settings pages that ran past the window now fit it

### Changed
- **Appearance, Widgets, Window Management, Launcher and Shortcuts no longer scroll.** They were the
  five pages taller than the Settings window (1074 pt); all ten pages now size the window to
  themselves and none scrolls. The room came from grouping, not from dropping anything: the widget
  style presets moved next to the other widget rows, the icon rows joined the theme card, and the
  window-management geometry shares one card — the long runs of shortcut rows (26 assignments, the
  four snap groups, the six tiling assignments) start collapsed, with the Shortcuts page's search
  box opening them as you type, so every row is still one click or one keystroke away. A handful of
  unlike rows that each wanted a line now share one (Hidden Apps with Reset App Order, the weather
  warnings, both widget switches). Nothing was removed: the pass is checked row by row against the
  previous build in `Docs/Archive/Planning/evidence/2026-10-15-page-fit/README.md`.

## [Unreleased] — Phase 12 close-out: the Settings pages measured, and the widget list back on the grid

### Fixed
- **The Widgets page's widget list lines up with the rest of Settings.** The reorderable list inside
  the Widgets card was drawing its own dark well across the card's surface, starting its rows 8 pt to
  the right of every other row on the page, and running a tighter row rhythm than the rest of the
  window; it now sits on the same grid, at the same 41 pt row rhythm, with the card's own separators.
  Dragging a widget to reorder it is unchanged.

## [Unreleased] — Phase 42: the rail packs like your Dock, and your Dock's icons are on the bar

### Added
- **The apps you pinned in the macOS Dock now keep an icon on the bar** even while they are not running —
  the same apps, in the same order, as your Dock: the bar reads its pinned list directly. They behave like
  the apps you "keep in Dock" from our own menu (click to launch, right-click for the same menu), and the
  system Dock stays the record: unpin an app there and its chip goes away on the next launch.

### Changed
- **A side rail's app tray now packs exactly like the bottom bar's.** A card is 40 × 54, so on a rail its
  long side became the direction the next chip sat in — the icons were 56 pt apart vertically against 42 pt
  horizontally on the bottom bar, which made the same tray look loose running down the screen. A rail's cards
  are square now, so both axes sit at 42 pt and the icons read the same in either orientation.
- **A side rail's spacing is the Dock's.** The gap between two chips on a rail is 2 pt instead of 4 (the Dock
  leaves exactly that between two icons, and the bottom bar already used it), and an island's ends are the
  Dock's tight 4 pt instead of the bottom bar's 16 pt plate inset — worth about 20 pt of dead space per
  island on a rail at the default size, most of it on the small launcher/weather and clock/widgets islands.
  The bottom bar is untouched; its 16 pt ends are what keeps the rounded plate from clipping a chip's corner,
  a constraint a rail's centred tiles do not have.

## [Unreleased] — Phase 41: every layout on a side rail, a rail that uses its height, tighter gaps

### Added
- **All five layouts work on a left or right rail.** Split 4 and Split 5 folded into Split 3 there, so two of
  the five Layout Mode choices did nothing if you kept the dock on a side. A rail now renders whatever you
  pick: Split 4 is four stacked islands, Split 5 is five, Full Width runs the whole height, Centered stays a
  centred pill.
- **The rail's mode cards are portrait,** so Split 4 and Split 5 can actually be told apart before you pick
  one (in a landscape card the rail was a two-pixel sliver).

### Changed
- **A rail's app island fills the space it has.** With the launcher/weather group pinned to the top and the
  clock/widgets group to the bottom, the app row now stretches over everything in between instead of leaving
  dead bands above and below it — and the drawer capsule keeps its place between the app row and the group
  below.
- **Gaps are tighter in every layout, rail or bottom.** An island no longer spends 20 pt at each end (16 now —
  one plate corner, which is also what stops the rounded clip from cutting a chip), the gap between sections
  inside an island is 9 pt instead of 13, and the **Comfortable** spacing preset is 8/10 instead of 10/12.
  Compact and Airy are unchanged, so a roomier bar is still one click away. If you had the old 10/12 stored,
  the Spacing row reads **Custom** until you pick Comfortable again.
- **The app row on a rail is measured with the rail's own 40 pt pitch,** not the bottom bar's 54 pt one, so a
  chip that fits in the rail is no longer dropped.

### Fixed
- **The drawer capsule can no longer land on the next island.** The app island could be pushed most of a
  capsule-slot toward the trailing group, which on a rail would have put the capsule on the clock/widgets
  island; a filling island now sits flush against the group before it. The bottom bar shared the same latent
  overlap on a nearly full row and is fixed by the same rule.

## [Unreleased] — Phase 12 close-out: a lock that fails open, a gradient theme engine, a notch theme

### Fixed
- **The keyboard cleaning lock can no longer outlive a crash.** The lock pauses the keyboard through the
  persisted pause but never wrote its own deadline down, so a crash or force-quit during those 60 seconds
  came up with dead keys until you pressed ⌃⌥⌘P. The deadline is persisted now and a window that has
  already passed releases the lock instead of resuming it.

### Added
- **Gradient presets.** Aurora Glow, Deep Ocean, Forest Moss, Cyberpunk Glass, Ember Sunset and Rose Quartz
  now draw their plate as a gradient instead of one flat tint, on all five floating surfaces at once — and
  the Appearance swatches show it, which is what makes the twelve presets tell apart. Auto and System keep
  the untinted plate.
- **Vibrancy and Contrast sliders (Appearance).** Vibrancy sets how strongly a theme tints the plate; 55 % is
  the standard glass look you already had. Contrast pushes the tint away from mid-grey, for a desktop where
  the presets read too alike. Both appear with a pinned theme, because only a pinned theme tints the plate.
- **A notch theme.** The Dynamic Island takes the theme's tint **only as a floating island**. A hardware
  notch keeps its black plate, so the shape still meets the bezel.

### Changed
- **Window Management is three sections, not six.** Tiling, Layout, Floating Applications and Tiling
  Shortcuts share one card (each block keeps its own label); no row, key or value changed.
- **The Tools editors share one card.** Custom Commands and Text Snippets were two sections and are one;
  both editors now show a placeholder while they are empty, so the page is never two blank boxes.
- **The Spotlight hand-off steps are the row's ⓘ**, not five lines of text under a button, and the notch
  page's shape preview carries a caption saying it is a demo.

## [Unreleased] — Phase 40: vertical dock geometry & widget readability

### Fixed
- **The weather forecast no longer prints a raw date.** `DailyForecast.date` carries the API's calendar day
  (`"2026-10-15"`) and the medium and large weather widgets printed it verbatim in a 9 pt font, so three
  columns in a 230 pt chip truncated to `2026-…`. They now show the localized weekday (`Thu`), larger and bold.

### Changed
- **Every rail tile is one 40×40 squircle.** Weather and clock tiles were 44×56 with a 10 pt radius while the
  launcher and Wi-Fi buttons were 40×40 at 14 pt, and the gauge disc differed again — so the dock looked like
  several docks. They now share one size and one chrome.
- **The running-app dot sits on the screen edge on a rail,** matching the bottom bar (it used to sit on the
  workspace-facing edge, where the bottom bar and the rail disagreed).
- **Rail spacing is uniform.** A divider between rail sections no longer opens a 13 pt gap against 2 pt
  neighbours, which is what made the vertical icons read as unevenly spaced.
- **S/M/L is the only widget sizing.** The arbitrary **Widget Widths** sliders retired, so a stored width can no
  longer silently override the chosen preset.

## [Unreleased] — Phase 16: widget pane + wifi Quick Settings

### Added
- **Widget pane (16a):** the four edge-deck widgets — weather, system, bluetooth, now playing — now also
  appear as tiles in the calendar/clock pane, in the same solid tile style, reusing the same shared
  services. The edge-deck buttons keep their current behaviour; nothing was removed.
- **iPad is the default widget view (16b):** fresh installs open the widget pane in the iPad grid;
  existing saved choices are kept.
- **Clock/date as presets (16c):** the clock tile gains a **Date** preset and shows the date under the
  time; the separate date tile was absorbed, so clock and date are no longer duplicated.
- **Wi-Fi becomes Quick Settings (16d):** the deck's wifi button opens a control-panel UI of one-tap
  system switches (Dark Mode, Keep Awake, Wi-Fi, Bluetooth and the rest), shared with the Control Center.
- **Glass tiles (16f):** the pane tiles are solid by default; a Settings switch ("Glass") draws them on
  blur instead.
- **Control Center layout (16h):** the side panel now shows an iPad-style arrangement — a Wi-Fi/Bluetooth
  connectivity cluster (Wi-Fi shows the network name), a volume slider, a now-playing card with
  transport, the one-tap switch grid, and a bottom row (Settings, Launcher, Capture, Drawer,
  Quit).
- **Brightness & keyboard light (16i):** the Control Center gains a display-brightness slider and a
  keyboard-backlight slider. Both use the private display/keyboard brightness APIs and simply stay hidden
  on Macs where those APIs are unavailable.
- **True Tone & VPN toggles (16i):** two new one-tap switches (True Tone, and Network-configured VPNs)
  appear in the Control Center grid and Settings. VPN toggling covers Network-configured
  VPN services only.

### Changed
- **The minimum macOS is 15 (Sequoia) (Phase 12):** the floor moved from 12 to 15, and every version
  branch that existed only for 12–14 is gone — the legacy login-item list backend
  (`LSSharedFileList*`), the macOS 12 permission paths and System Settings deep links, EventKit's
  old `requestAccess`, the runtime “is Translate available” probe, the private
  `_windowResizeNorthSouthCursor` cursor fallback with its hand-drawn glyph, and the
  `TextEditor`/`ViewThatFits` fallbacks in the note sheet and the chips. **Hover-preview thumbnails
  are captured with ScreenCaptureKit now**: `CGWindowListCreateImage` is obsoleted in the SDK at
  this floor. macOS 12 left Apple's security updates in 2025 and 14 in August 2026, so no Mac that
  still gets security updates is dropped.
- **Advanced is the last tab (Phase 12):** the strip ends **Tools · Advanced** — the page you visit
  once is last, so the tools used mid-session are not behind it.
- **Narrow rows sit two to a line (Phase 12):** on the long pages a menu, a segmented picker, a
  switch or a lone button takes half the card and shares its line, with the two halves exactly
  equal. Measured against the previous build: **Widgets 1440 → 1114 pt**, **Launcher 1291 → 1132**,
  General 790 → 708, Appearance 1479 → 1400, Edge Bars 955 → 914, Tools 822 → 741, Advanced
  521 → 482, Window Management 1357 → 1317. Sliders, editors and rows with two controls (a shortcut
  picker and its Record button) stay full width. No setting moved and no key changed.
- **Advanced is two sections (Phase 12):** the full-screen prediction row — a card of its own with
  no header — is the first row of **Behaviour**, and the notification banner's three-line paragraph
  is now that row's ⓘ. Nothing was removed.
- **Long checklists use the window's width (Phase 12):** the Control Center's widgets and its
  eighteen quick settings, the Edge Bar's tiles, the custom edge-item list and the launcher's
  hidden apps were single columns of checkboxes — two thirds of the card empty while the page ran
  past the screen. They are two-column grids now, so the same controls fit in half the height, and
  the Edge Bars page pairs its narrower rows two to a line as well. That page also splits into
  three sections — Edge Bars, Widgets, Size & Behaviour — instead of one card of ~28 controls, and
  every row is a little tighter (8 pt inside a row instead of 11), which alone takes about 13 % off
  each long page. No setting moved and no key changed.
- **The Shortcuts page is three sections with a search field (Phase 12):** the page was one card of ~35
  rows two screens long, so finding one shortcut meant scrolling past all of them. Every key assignment
  now sits in the **Shortcuts** card behind a **Search Shortcuts** field — it matches what you read, in
  your language, and says so when nothing matches — the keyboard behaviours that change how typing
  reaches apps (Hyper key, Pause Keyboard, Hold ⌘Q, Show Keys You Type, Open Launcher with Pinch) are
  the **Keyboard** card, and the **Radial Dial** keeps its own. The four snap captions (Halves,
  Quarters, Thirds, Full) were printed in English in every language and are now translatable. No
  setting moved and no key changed.
- **Widgets page regrouped (Phase 12):** the weather widget's rows now live in their own **Weather** card
  on the shared grid (they were the one block on the page with no card, inset 14 pt shallower), and the
  widget appearance rows and style presets share one card. The clock *tile*'s row is renamed **Clock Tile
  Style** so the page stops showing two rows both called *Clock Style* — the dock clock's preset keeps that
  name. No setting moved and no key changed.
- **Settings gains a Tools page (Phase 12):** the clipboard, the command and snippet editors and the shelf move off
  Launcher & Tools onto their own **Tools** tab, which takes the slot the **About** page left. About's four rows
  (version + Check for Updates, auto-update, diagnostics) now sit in a card at the end of **General**, and the
  launcher's page keeps the launcher, the Control Center and the launcher's own switches. Ten tabs, nothing lost.
- **Settings is one grid (Phase 12 form-and-function pass):** all ten pages render through one card and
  one row type, so the content inset is the same 42 pt everywhere (it used to run 20 / 28 / 42 / 108 pt
  from page to page and the gap between two sections varied on the same page). The duplicate
  "Drawer Position" label is gone — the picker no longer prints its own label beside the row's. Pages
  that used to end in a six-line paragraph show an ⓘ on the row instead (Advanced is 190 pt shorter),
  and the window now sizes to its content wherever the content fits. Rules and the pages that still
  owe work: `Docs/SETTINGS.md`.
- **Control Center panel (16g):** the Quick Settings shortcut and the deck's wifi button now open a side
  panel that hugs the screen edge next to the dock (default right) instead of the full-screen Pinboard.
  It steps clear of a dock rail on the same edge and closes on Esc or a click outside.
- **Pinboard retired (16k–16n):** the six Pinboard-only widgets (Calculator, Screen Time, Network,
  Battery, Top Apps, Batteries) moved into the widget pane; the right-FAB, `⌃⌥Space` and
  weather/clock shortcuts now open the Control Center and the weather/calendar panes; the wall,
  its panel, catalog, `com.katikati.pinboard.*` keys and strings are deleted (registry:
  `Docs/Repository/pinboard-retirement.md`). The Control Center gains a Settings section (side,
  widget picks, switch picks) and hosts user widgets; keep-awake runs off the shared toggle engine.
- **Quick Settings rework (16r–16s):** no-scroll content-sized floating panel (borderless, above the
  dock); weather / system / bluetooth / now-playing tiles off the widget pane; calculator /
  screen-time / top-apps off the panel default (network / battery / batteries as compact rows);
  battery + batteries merged into one topmost card; sliders moved to the bottom; four new switches
  (Screen Saver, Lock Screen, Relaunch Finder, Screen Mirroring — all fire-and-done, no new
  permission); resize loop guarded against bottom-edge jitter.
- **Quick Settings presets (16v):** S/M/L panel widths, top/center/bottom edge anchor and
  instant/fade/slide open animation, all in Settings › Layout › Control Center.

### Fixed
- **Disabled buttons say why** (Phase 12): **Reset Ignored Apps** (Advanced) and **Restore Wallpaper**
  (Appearance) were disabled with nothing on the row explaining it; both now carry the reason —
  “No background app is ignored right now.” and “Turn Dynamic Wallpaper on to restore it.”
- The Widgets page's **Glass** switch (16f) was the one toggle in Settings that announced no name to
  VoiceOver: its label lived on the row. It now carries the row's name, and the audit that found it
  (every checkbox on the ten pages, read from the running app) is recorded in
  `Docs/Archive/Planning/evidence/2026-10-15-density-pass/label-audit.txt` — 76 checkboxes, none
  unnamed.

## [Unreleased] — Phase 8 in progress

### Added
- **Live Island — decision engine (8b-1):** new pure `LiveActivityPolicy` (Core) that decides which
  single live activity the Now-Playing island shows, in priority order — music → Focus/pomodoro →
  event countdown (within 7 days) → countdown timer → stopwatch → live clock — with unit tests.

- **Live Island — snapshot assembler (8b-2):** the pure source projection (`LiveActivitySources`) and
  the app-layer 1 Hz ticker (`LiveActivityFeed`) that read Music / Focus / Countdown / Timer / Stopwatch
  and publish the island's current activity, with unit tests. Split pure (dual-compiled) from app-only
  code to match the project's compile convention; the visible capsule still lands in 8b-3.

- **Live Island — capsule (8b-3):** the Now-Playing spot on the bar is now live. It shows whichever
  activity is most relevant — music while playing, Focus, an upcoming event (within a week), a running
  timer or stopwatch, otherwise the clock — and updates every second, with a symbol, a label and the
  live reading. Tapping it while music plays still opens the full Now Playing panel. (The richer
  in-app event feed and optional OS banners land next.)

- **Live Island — event detector (8b-4a):** the pure engine that notices when something worth telling
  you about just happened — a timer ran out, a Focus phase turned over, a Focus session was banked, the
  stopwatch stopped, an event reached today, or the track changed — with unit tests. It is the
  groundwork for the island's in-app alerts (landing in 8b-4b) and opt-in OS banners (8b-4c); nothing
  is shown to you yet.

- **Live Island — in-app alerts (8b-4b):** the island now tells you when something worth knowing just
  happened — a timer ran out, a Focus phase turned over or a session was banked, the stopwatch stopped,
  an event reached today, or the track changed — as a brief, click-through banner that fades on its own.
  It is **on by default** and costs nothing when idle (it reacts to changes instead of polling). The
  optional macOS Notification Center banners arrive next; nothing is sent to Notification Center yet.

## [0.17.0-beta.2] — 2026-10-12

### Added
- **Launcher:** 8 icons across and bigger; sliding pages by default (swipe, scroll, arrow keys, dots) or one scrolling page; drag to reorder All Apps;
  right-click menu (Open, Show in Finder, Copy Path, Pin, Move to Start, Hide from Launcher); Settings can show all hidden apps and reset the order.
  Ideas from LaunchNow (code written fresh, credited in NOTICE).
- **Weather:** a per-place cache of the last forecast (up to 7 days old) so weather works offline; an "Allow Location Access" button.
- **Bar:** fresh installs keep Finder, Safari, System Settings and Messages on the bar.
- **Pinboard:** the full-screen wall is a dense grid scaled to fill the screen.

### Fixed
- The resting edge deck no longer reads the Notes Keychain item at launch, so no password prompt appears until you open the deck or a note.

## [0.17.0-beta.1] — 2026-10-12 — Phase 7: edge decks, launcher, Pinboard

### Added
- **Phase 7B launcher, Pinboard and shortcuts (0.17.0 beta):**
  - **Launcher:** one app grid — Most Used (your launches first; Settings, Safari, Terminal, Messages, Finder, Mail and Calendar fill the gaps),
    Recently Installed, then All Apps — scrolling down or sideways; search field position, theme, tint and icon are settable; optional
    trackpad pinch (four or more fingers) opens it.
  - **Pinboard:** a full-screen widget wall (or the floating panel) with Clock, Calendar, Weather, Now Playing, Calculator, Countdown, Screen Time,
    System, Network, Battery and health, Top Apps, Batteries and 12 Quick Settings switches; chosen in Settings.
  - **Shortcuts:** per-action chords and modifier double-taps for the launcher, Pinboard, Quick Settings and Keep Awake.
  - **Limited mode:** the bar, edge decks, launcher and Pinboard work before Accessibility is granted; the status menu asks for it.
  - Unsigned beta; all new translations are drafts awaiting speaker review.

- **Phase 7A edge decks:** both screen edges host a noty-style deck — a resting pill that fans into shingled paper note tabs
  (rotated titles, eight paper colours, hover preview / hover-to-open, drag to reorder, ⌥-drag the pill to reposition) with
  round glass-or-coloured buttons for the rest; a note opens as a paper sheet. Layouts: Off, Notes, Notes & Status, Status,
  **Productivity + Rest (default)** and **Custom** (every item Left / Right / Hidden), each flippable to either side. Productivity
  buttons: Reminders, Alarms, Time (Timer / Stopwatch / Countdown / Focus), Tasks (to-dos + time tracker), Clipboard (opt-in, memory-only
  history), Capture (recognise text and QR codes in a screen area), Windows (snap into 15 zones). Notes are encrypted at rest with an opt-in
  iCloud Drive sync. Settings: layout, main side, deck size, button style, tab font, hover behaviours, keep open.
- **Phase 7A-1 edge-bar foundation:** `EdgeSlotSet` slot keys, `PanelGeometry.edgeBarTargetFrame`,
  `com.katikati.edge.*` settings (off by default), `DOCK_EDGE_BARS` switch and a placeholder
  edge-bar panel hidden together with the island bar in fullscreen. No visible content yet.

### Removed
- **Feedback and License tabs.** Nothing is sent to the upstream project's servers any more; the in-app feedback form,
  founding-user mailing list and license activation are gone. Report problems with GitHub issues (Settings > About > Diagnostic Info > Copy
  gives the details to paste). Archived Tungsten Edge release notes, stray patch scripts and upstream community links were removed from the repo.

### Changed
- **Standing Rules §1 new items (owner sign-off 2026-10-09):** *per-step notes, always* —
  every step (including minor/visual changes) gets a note in the active plan tracker
  (`HYBRID_PLAN.md` — owner chose the plan itself as tracker over a separate `task.md`)
  recording what was done and what significantly changed, written as the work
  happens; and *grill the owner thoroughly* — ambiguous, cut-off, or conflicting
  instructions are a stop-and-interrogate signal with concrete options, never a guess.
  Full rules in `STANDING_RULES.md` §1 items 4 and 8.
- **Standing Rules §1 new item (owner sign-off 2026-10-08):** *Agent hygiene — no vibe-coding damage* — enforced append-only-by-hand rules for generated files (`project.pbxproj`, `*.xcstrings`), mandated human review for non-English strings, banned scratch scripts and `*.log` files from the repo root, mandated explicit `git add` lists, banned eager singletons for gated features, and enforced strict diff budget checks before committing. Full rule in `STANDING_RULES.md` §1 item 7.
- **Standing Rules §1 new item (owner sign-off 2026-10-08):** *structured edits first* —
  single-anchor editor operations are the default for source changes; regex/`sed`-class
  scripted edits require a `git grep` occurrence check, anchored patterns, and
  post-edit build + targeted tests + old-token-absence verification. Heredoc appends
  into source, repo-root throwaway scripts, and `rm <glob>` inside the repo are
  forbidden. Full rule in `STANDING_RULES.md` §1 item 6.

## [Unreleased] — Phase 6: Layout + Appearance settings

### Added
- Settings › Layout: live preview and mode picker drawn from the real layout solver, bar height, island gap, side margin, centered width, widget widths, and a Floating / Hugging bottom edge (`com.katikati.layout.bottomGap`, 0–12 pt).
- Settings › Appearance: all 12 theme presets plus Auto and Custom, and an icon set switch (Modern 3D / Classic system symbols, `com.katikati.iconSet`).
- Welcome guide opens with a "Pick a Layout" step before the Dock settings.
- Status menu › Layout: switch mode and bottom edge, or open Layout settings.
- Hover titles on each island section.

### Fixed
- With edge auto-hide on, all islands on a display now hide together; hovering one island no longer lets the others hide.

## [Unreleased] — Phase 5: Hardening + Floating Widgets

### Fixed
- Lifted windows are now restored after SIGTERM/SIGINT and after a crash/`kill -9` relaunch (signal handlers + recovery file).

### Added
- Floating calendar tiles (right) and weather tiles (left) with Mac/iPad/Tall layouts, palettes, animation presets (Instant/Slide/Spring Pop).
- Timer, Stopwatch, Countdown, Notes tiles; world clocks, focus timer, alarms, reminders.
- Weather Glance layout with mountain-scene hero, sky-tinted tiles, derived warnings, saved cities. Classic layout and hero kept as presets.

## [Unreleased] — Phase 4: Widgets, Popups, and Layout

### Added
- **Weather Widget**: Integrated dynamic weather chip and popup with real-time conditions.
- **Clock Widget**: Added date/time chip with dynamic widths.
- **Tray Cluster**: Consolidated system tray icons (battery, wifi, volume) into a unified chip.
- **Now Playing**: Integrated media playback controls (NowPlayingService) matching CoolDock parity.
- **Layout Modularity**: Rewrote layout solver for perfect centering, collision truncation, and customizable widget order via Settings.
- **On-Dock Resizing**: Added direct edge-dragging on dock widgets to resize them visually.

### Removed
- **Media section**: `.media` is no longer a bar section — the widget order is hardcoded to `weather → apps → tray → clock` (legacy stored orders from the removed drag-reorder UI are ignored, not restored). Now Playing returns in the 4f tray rework as a play/pause mini icon at the apps island's right end plus a popup (owner decision, 2026-10-09); it is temporarily off-bar until then.
- **Widget resize model**: on-dock resize handles and the Settings drag-reorder visualizer are gone — width control now lives only as per-widget sliders (weather/tray/clock, 60–400 pt) in Settings, with defaults centralized in `BarSection.defaultWidgetWidth`.

## [Unreleased] — Phase 3: Flyouts, Fullscreen, Multi-Display & Space Survival

### Added
- **Per-Island Anchoring:** Added `barBoundingFrame` calculation and `onQueryBarBoundingFrame` delegate callback in `PanelCoordinator`, enabling per-chip popups (`togglePopup(content:localFrame:)`), bar-wide popups (`toggleWholeBarPopup(content:)`), and precise tooltip anchors (`tooltipAnchor(forLocalFrame:)`) mapped directly to island slot frames.
- **Atomic Fullscreen Control:** Added `units(forDisplayUUID:)` and `allSpacesPanels(forDisplayUUID:)` in `TaskbarScreenOrchestrator`, binding fullscreen transition intents atomically across all slots of a given display without affecting other monitors.
- **Space Survival:** Ensured every island panel joins all Spaces via `NonConstrainingPanel` behavior with zero stranded or lost panels on Space switches.
- **Multi-Display Reflow & Sizing:** Enforced display placement matrix (`followMouse`, `allScreens`, `allScreensPerDisplay`, `pinned`) across slots in `IslandSlotSet`, and ensured accurate per-slot frame calculation in `PanelCoordinator+Visibility.commitHoverSwitch`.
- **Test Suite Expansion:** Added 13 unit tests across `IslandAnchorTests`, `AtomicFullscreenTests`, and `PinnedIslandTests`, expanding test suite to 1,602 passing tests with 0 failures.

## Phase 2 — Island Panels (One Display, Tungsten Construction) (2026-10-08)

### Added
- **Slot-Keyed Orchestration:** Keyed taskbar units by `displayUUID#slot` (`IslandSlotSet.SlotKey`) in `TaskbarScreenOrchestrator`, with survivor reuse on mode changes to prevent flicker.
- **Island Panel Geometry:** Wired `PanelGeometry.islandTargetFrame` to calculate per-slot panel frames using `IslandLayoutSolver.layout`.
- **Coordinate Mapping:** Bound `PanelCoordinator.dockVisibleFrame` and established direct addition `screenFrame = dockVisibleFrame.origin + localFrame`.
- **Bar Bounding Frame:** Added `boundingFrame(forDisplayUUID:)` computing union of island frames for whole-bar popup anchoring.
- **Capsule Ownership:** Single capsule panel owner per display strictly tied to `.apps` slot, preventing redundant or stray panels.
- **Filtered Strip Projections:** Extended `StripProjection` and `DockStripView` to project native placeholder representations (`weather`, `tray`, `clock`) for non-apps slots while isolating live window chips to `.apps`.
- **Test Suite Expansion:** Added 17 unit tests across `IslandSlotSetTests`, `IslandPanelGeometryTests`, and `IslandStripProjectionTests`, reaching 1,589 passing unit tests with 0 failures.

## Phase 1 — Pure Layout Model (2026-10-08)

### Added
- **BarLayoutMode:** Added 4 canonical layout modes (`windows`, `split3`, `split4`, `centered`) in `Core/Support/BarLayoutMode.swift` with metadata, slot counts, and single-island predicates.
- **BarSection:** Added content sections (`weather`, `apps`, `tray`, `clock`) in `Core/Support/BarSection.swift` preserving canonical left-to-right sequence and grouping into island slots per `HYBRID_PLAN.md` Appendix A.
- **IslandLayoutSolver:** Added pure geometry engine in `Core/Support/IslandLayoutSolver.swift` porting SplitBar-old `layoutIslands` math and overflow-collapse loop, enforcing tungsten clamp discipline (in-screen bounds, 0.5pt minimum inter-island gap, bottom-left screen space coordinates).
- **Settings Persistence:** Added `barLayoutMode`, `centeredWidth`, `islandGap`, and `islandMargin` published properties, range clamping, and `UserDefaults` backing under `com.katikati.layout.*` in `AppSettingsStore`.
- **Test Suite:** Added 20 new unit tests across `BarLayoutModeTests`, `IslandLayoutSolverTests`, and `AppSettingsStoreTests`, expanding test suite to 1,572 passing tests with 0 failures.

## [v0.0.0-baseline] — 2026-10-08

### Baseline Import & Neutral Rebrand (Phase 0)
- **Baseline Foundation:** Imported clean tree of `tungsten-edge @ a4e1a55` preserving window tracking, strip layout, panel coordination, and test suite.
- **Identity & Targets:** Rebranded Xcode project, schemes, targets, and bundle identifiers (`com.katikati.app`, `com.katikati.app.tests`, `com.katikati.app.windowlab`).
- **Defaults Migration:** Rebranded defaults domain to `com.katikati.*` and added `TungstenDefaultsMigrator` for one-way migration of legacy preferences with install lineage stamp.
- **Localizations:** Rebranded user-facing product surfaces across all 12 supported languages (`en`, `zh-Hans`, `zh-Hant`, `ja`, `de`, `fr`, `es`, `es-419`, `pt-BR`, `pt-PT`, `it`, `ko`), passing all localization gates.
- **Sparkle Feed:** Configured appcast feed URL to `https://wakilibaraka.github.io/KatiKati/appcast.xml`.
- **Legal & Attribution:** Added `NOTICE` with Tungsten Edge GPL-3.0 attribution and SplitBar-old/DockBar placeholders; added KatiKati trademark reservation to `TRADEMARK.md`.
- **Quality Gates:** 1,552 unit tests passing, zero API availability warnings, 75 debug switches registered.

- Settings: "Revert Changes" appears once something changed since Settings opened; it restores those keys and restarts KatiKati.
- Settings: opening a page from search scrolls to the matching row and pulses it.
- Settings: General has a Window Glow picker (follow the clock, dawn, day, dusk, night, off).
- Settings: the preview resize handle clicks on reset and works with VoiceOver adjust.
- Settings: Tools lists its rows one per line instead of cramped side-by-side pairs.
