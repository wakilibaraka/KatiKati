# Changelog

All notable changes to KatiKati are documented in this file.

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
  system switches (Dark Mode, Keep Awake, Wi-Fi, Bluetooth and the rest), shared with the Pinboard.
- **Glass tiles (16f):** the pane tiles are solid by default; a Settings switch ("Glass") draws them on
  blur instead.

### Changed
- **Control Center panel (16g):** the Quick Settings shortcut and the deck's wifi button now open a side
  panel that hugs the screen edge next to the dock (default right) instead of the full-screen Pinboard.
  It steps clear of a dock rail on the same edge and closes on Esc or a click outside. The full-screen
  Pinboard keeps its Quick Settings card.

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
