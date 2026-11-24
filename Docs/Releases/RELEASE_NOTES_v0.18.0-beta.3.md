# KatiKati 0.18.0 beta 3

**Locally signed, unnotarized beta.** Signed with `"KatiKati Local Code Signing"` (not Developer ID notarized). On first launch on a new Mac, right-click the app and choose **Open**. Because this build is not notarized with a Developer ID certificate, macOS may ask for **Accessibility**, **Downloads**, **Calendar**, or **Input Monitoring** permissions again. Includes GPL-3.0 `LICENSE`.

## What is new since beta 2

### Modular Dock, Launcher & Native-Tight Spacing (`DO-1`–`DO-10`)
- **Native macOS-tight default spacing:** Icon Spacing now defaults to `1 pt` (range `-2...12 pt`, including `0 pt`) and Section Spacing to `6 pt` (range `3...20 pt`), with a **Reset to Default** button in **Settings › App Icons & Hover**. Wide mode keeps app icons, App Pills (`2 pt` horizontal inset), and utility/tool tiles strictly at your chosen Icon Spacing, absorbing spare bar width at major zone boundaries (`WideZoneSpacerPlan`). `.dictionary` and `.terminal` slots now match the `40 pt` icon tile grid, `DockUtilitiesClusterView` follows your live Icon Spacing, and a tight hairline divider separates utility tools from Clock.
- **Launcher + Drawer consolidation & 4-square `Background & Activity` tile:** Folded the standalone Drawer into **Launcher** as a **Drawer** presentation preset (`LauncherPresentation.drawer`) and promoted the 4-square **Background & Activity** tile onto the main Dock strip with five icon faces (`3×3 App Grid`, `RAM %`, `CPU %`, `RAM Pressure Ring`, `App Count`) and a zero-idle-CPU `Processes & RAM` inspector.
- **Modular trailing capsule:** Replaced the trailing capsule default with a Liquid Glass **Control Center** disc (`Wi-Fi + circular Volume ring`, scroll-wheel volume isolated from bar panning), configurable across `Control Center`, `Background & Activity`, `Trash`, `Launcher`, `Shelf`, or `Off` in **Settings › Dock Layout** and Onboarding.
- **Dock App Groups (`DockFolders`), App Icon presets & anti-overflow solver:** Added `2×2`/`3×3` Dock folder tiles with category auto-grouping, drag-to-group, and optional two-way Launcher folder sync; five App Icon presets (`App Pills`, `Icons Only`, `Window Cards`, `Windows 11 Grouped`, `Windows 10 Taskbar`); 3-stage dynamic anti-overflow resizing; and `Keep in Dock` default context menus.
- **Tactile multi-page widgets & Peripherals:** Added dot-strip click cycling with spring pulse and haptic detent plus phase-aware trackpad swipe paging (`WidgetPageScrollEngine`) across Weather and Now Playing; upgraded the Battery wing to **Battery & Peripherals** and added a **Peripherals** Notch page with audio-output switching.
- **Reorganized Dock & Widget Settings:** Split Dock settings cleanly across **Dock Layout**, **App Icons & Hover**, **Bar Widgets**, and **Widget Wings**, and prevented four-finger pinch gestures from falsely firing four-finger-tap Launcher triggers.

### SideDeck, 13-Pillar Capability Audit & Window Management
- **SideDeck Waves 1–4 & Cursor Clipboard (`#18`):** Complete SideDeck edge workflow and cursor-anchored clipboard popup.
- **Live telemetry & Menu Bar polish:** Menu Bar Network stat displays live `↓/↑` throughput; Menu Bar and Drive settings deep-link cleanly; Drives menu switched from 10 s polling to `NSWorkspace` mount/unmount events with Eject support; Battery popovers surface cycle count, health %, charge/discharge ETA, opt-in Apple Silicon IOHID SoC temperature, Disk I/O, and top 3 CPU processes.
- **Clipboard `⌘1`–`⌘9` & `Work` category:** Instant `⌘1`–`⌘9` pinned-slot paste and origin-app `Work` filtering in the clipboard popup.
- **Unlocked platform features:**
  - **Shelf:** Vision subject/background removal (`VNGenerateForegroundInstanceMaskRequest`) plus **Merge PDF** and **Convert** parity in selection and context menus.
  - **Window Snapping & Tiling:** Hold `⌥` while dragging to screen edges for horizontal thirds snapping; persistent `WindowLayoutMemory` (`window-layouts.json` + backup/restore) plus `tile float` and `tile retile` shortcuts and Command Bar commands.
  - **Control Center:** Microphone input device switcher, keyboard backlight brightness slider, and multi-VPN selector menu.
  - **Weather & Wallpaper:** `WarningsTile` severe weather alerts, live Moon Phase illumination, Desktop Box weather units/cities, and atmospheric moon glow matching the wallpaper stage.
  - **App Usage, Notes, Live Island & Profiles:** App usage metrics, leftover review flow, note title archiving & error UI, Live Island camera mirror & alerts, unified Dock Profiles with live Settings refresh, and universal widget surface / desktop wing controls.

### Mission Control (Experimental), Wellness Wings & Notch
- **Experimental defaults & multi-display plumbing:** Mission Control stays explicitly labeled experimental (`Docs/MissionControlResearch.md`); introduces **Traffic Light** (default), **Colourful Everything**, **Liquid Glass**, and **Paper** looks while defaulting borders and keyboard/type-to-filter inputs to opt-in, tearing overlays down reliably on exit, and adding multi-display & Stage Manager geometry.
- **Pause & Hydrate wings, PingPlace & Notch:** Added **Pause** and **Hydrate** dock wings (respecting Reduce Motion and Smart Pause), a 3×3 per-display **PingPlace** notification grid, and a unified single-card Notch page deck.

### Performance & Idle-CPU Livecheck Fixes
- **Idle CPU reduced to ~0.2%:** Gated `HydrationController`, `NutritionController`, and `QuitOnLastWindowService` idle timers; deduplicated `SystemMonitorController`; and eliminated main-thread idle polling hotspots in Notch meeting detection, `LiveActivityFeed`, and CoreWLAN Wi-Fi refreshes.
- **Reliability fixes:** Fixed multi-file `ditto` ZIP staging overwrite, DropClip toggle state, `AVSpeechSynthesizer` retention, `"wifipw"` macro refresh, Wallpaper stage moon altitude/glow, Weather warning rows, and Menu Bar Settings picker alignment.

## Known limits
- **Mission Control is experimental:** Detection relies on undocumented WindowServer window-list geometry (`macOS` has no public Mission Control API) and is only live-verified on a single display without Stage Manager; keyboard navigation and type-to-filter remain opt-in.
- **Accessibility & hardware toggles:** Accessibility is optional (needed only for per-window cards and window automation); Bluetooth, Night Shift, and Apple Silicon thermal interfaces rely on system frameworks that can change between macOS releases.
- **Local signature:** Built universal (`x86_64` + `arm64`), stripped, and signed locally without Developer ID notarization.
- **Localizations:** All 12 locales pass completeness checks, with recently added translations awaiting native review.
