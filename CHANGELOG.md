# Changelog

All notable changes to KatiKati are documented in this file.

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
