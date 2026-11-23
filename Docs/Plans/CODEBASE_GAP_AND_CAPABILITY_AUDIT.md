# KatiKati 13-Pillar Codebase Capability, Gap & Reuse Audit

**Branch:** `main`
**Audit Scope:** Read-only code-grounded diff of `Core/`, `Platform/`, `App/Composition/`, `App/Entry/`, `UI/ReadModel/`, `Resources/`, and `Scripts/` against `App/Scenes/` and Settings across all 13 product pillars.
**Governance & Frozen Boundaries Respected:** `CLAUDE.md`, `BASELINE_RULES.md`, `STANDING_RULES.md`, `.github/workflows/ci.yml`, `.github/workflows/bench.yml`.

---

## Live Progress Tracker

### Batch 1 — Correctness & Idle-CPU Fixes
- [x] **Quick Win #9 / Slice 1.2** — Idle timers & shared `SystemMonitorController` (`cf03222f`)
- [x] **Quick Win #8 / Slice 1.3 (ZIP)** — Multi-file `ditto` staging fix (`4e18742c`)
- [x] **Quick Win #7 / Slice 1.3 (DropClip / CommandBar)** — Toggle, `AVSpeechSynthesizer` retention & `"wifipw"` (`091c339c`)

### Batch 2 — Broken-UI & Live-Readout Polish
- [x] **Quick Win #1 / Slice 1.1** — Menu bar network speed, `.menuBar` deep-link & Drive Eject/events (`a2a7f546`)
- [x] **Quick Win #5 / Slice 2.3 (Clipboard)** — `⌘1`–`⌘9` paste & `Work` category (`09c73eeb`)
- [x] **Quick Win #2 / Slice 2.1** — Battery cycles/health/ETA, IOHID toggle, Disk I/O & top processes (`ae014e00`)

### Batch 3 — High-ROI Feature Unlocks
- [x] **Quick Win #4 / Slice 2.3 (Shelf)** — Vision Background Removal & Transform Parity (`DONE`)
- [ ] **Quick Win #10 / Slice 4.4 (Snap)** — Hold `⌥` During Drag-to-Edge for Thirds Snapping
- [ ] **Quick Win #6 / Slice 2.4** — Control Centre Mic Input Switcher, Keyboard Backlight Slider & Multi-VPN Menu
- [ ] **Quick Win #3 / Slice 2.2** — Weather Warnings, Moon Phase & Desktop Weather Units

### Remaining Wave 3 & Wave 4 Architecture Slices
- [ ] **Slice 3.1** — Real AI Usage Receipt Metrics, 7-Day Heatmap & Screen Time Export
- [ ] **Slice 3.2** — Real App-Leftover Scanner & Review-First Trash Flow on Notch Storage Page
- [ ] **Slice 3.3** — Encrypted Note Titles, Archive Filter & Decrypt-Error Banner in `NoteSheetView`
- [ ] **Slice 3.4** — Live Island Camera Mirror Subscription, Weather/Alarm Alerts & Sixth-Sense Controls
- [ ] **Slice 4.1** — Dock Profiles Studio, `groupAdjacentUtilities` Toggle & `DockSlotLayout` Migration
- [ ] **Slice 4.2** — Universal Widget Surface Pins (`.shelfCard`), Per-Display Wings & Desktop Wing Hosting
- [ ] **Slice 4.3** — Dynamic Wallpaper Solar-Position Glow, `SkyAtmosphere` Stage Preview & Sky Pack Aliases
- [ ] **Slice 4.4 (Remaining)** — Persistent `WindowLayoutMemory` & Per-Window Float/Retile Shortcuts

---

## Behavior-Frozen Files (Do Not Touch)

Per `STANDING_RULES.md` §2.3 and `CLAUDE.md`, the following five files are behavior-frozen and **must remain untouched** across every slice in this plan unless an explicit bug ticket names them:

1. `App/Composition/WindowLiftAvoidanceController.swift` (2,754 lines) — Dock window lift/dodge coordinator.
2. `Platform/AppTracking/AppTracker.swift` (2,607 lines) — AX + CGWindow + NSWorkspace running-app and window tracker.
3. `App/Composition/DragController.swift` (1,992 lines) — Dock chip drag-reorder and drop session state machine.
4. `Platform/Accessibility/AccessibilitySource.swift` (1,350 lines) — Low-level AXObserver and AXUIElement read/write bridge.
5. `Platform/CoreGraphics/FullscreenIntentMonitor.swift` (1,049 lines) — Event-tap full-screen transition predictor.

All roadmap slices below operate strictly outside these five files.

---

## 1. Executive Summary Table (All 13 Pillars)

| # | Pillar | Current Maturity | Top Unexposed / Half-Wired Backend Capabilities (`file:line`) | Highest-ROI Features to Add Next |
| :--- | :--- | :--- | :--- | :--- |
| **1** | **Dock Replacement** | `Mature` | • `DockSlotLayout.groupAdjacentUtilities` (`Core/Support/BarSection.swift:600, 709`) has no Settings toggle<br>• `BarProfile` (`Core/Support/BarProfile.swift:10-43`) & `BarProfileService` (`App/Composition/BarProfileService.swift:14-124`) have zero Settings UI and hardcode `widgetPresetID: nil` (`L122`)<br>• `StatusMenuController.rebuildAddItemsMenu` (`App/Entry/StatusMenuController.swift:763-781`) & `WelcomeGuideView.widgetsStep` (`App/Scenes/WelcomeGuideView.swift:202, 264-295`) mutate legacy `BarSection` instead of `DockSlotLayout` | **Dock Profiles Studio & Unified Slot Controls:** Expose `BarProfileService` in Settings + Status Menu, persist `DockSlotLayout` + `DockWingsConfiguration` inside `BarProfile` (and `SettingsBackupService`), add the `groupAdjacentUtilities` toggle, and migrate `StatusMenuController` / `WelcomeGuideView` to `DockSlotLayout`. |
| **2** | **Notch Replacement** | `Mature` (UI) / `Partial` (Live Sources) | • `SurfaceTimeTravelCoordinator` (`Core/Support/NotchBehavior.swift:305-395`), `NotchTimeTravelBuffer` (`L188-224`), `DeferredFocusQueue` (`L227-255`), and `SuggestionBackoffTracker.reset` (`L258-295`) have no Settings UI<br>• `IslandLiveBridge` stores `cameraService` (`App/Composition/IslandLiveBridge.swift:16, 29, 44`) and defines `ActivityID.camera` (`L16`), but `start()` (`L72-106`) never subscribes<br>• `LiveEventDetector` (`Core/Support/LiveEventDetector.swift:16-18`) defers Reminder/Alarm and Weather warnings despite existing services | **Live Island Event & Camera Wiring + Sixth-Sense Controls:** Wire `CameraMirrorService`, `AlarmStore` / `CalendarService` meetings, and `WeatherWarningEngine` into `IslandLiveBridge` / `LiveEventCenter`, and add Focus Deferral + Sixth-Sense backoff reset controls to `LiveIslandSettingsBlock`. |
| **3** | **Menubar Utility** | `Partial` | • `MenuBarStatModel.statusText` for `.network` (`Core/Support/MenuBarStatModel.swift:82-129`) always returns `"–"` because `styles(for: .network)` is `[]` and `fraction(metric: .network)` is `nil`<br>• `AppMenuSearchReader` (`Platform/Accessibility/AppMenuSearchReader.swift:11-94`) + `MenuSearch` (`Core/Support/MenuSearch.swift:24-71`) only reachable via Command Bar `m ` prefix<br>• `DriveMenuBarItem` (`App/Composition/DriveMenuBarItem.swift:36-38, 63-78`) polls every 10s and lacks an Eject action | **Live Network Speed Menu Bar Stat + Drive Eject & Event-Driven Mounts:** Add `.throughput` style to `MenuBarStatModel` so `.network` renders live `↓/↑` rates, add one-click Eject to `DriveMenuBarItem`, replace its 10s timer with `NSWorkspace` mount notifications, and deep-link `openSettings(selecting: .menuBar)`. |
| **4** | **Productivity Apps** | `Partial` | • `ShelfActions.removeBackground` (`App/Composition/ShelfActions.swift:218-258`) Vision cutout has zero UI buttons<br>• `NotesController.edit(id:title:body:)`, `setArchived(id:_:)`, and `lastError` (`Platform/Notes/NotesController.swift:19, 48, 65, 107`) have no UI in `NoteSheetView` (`App/Scenes/Edge/NoteSheetView.swift:24-89`)<br>• Clipboard `Work` filter (`App/Scenes/Edge/ClipboardFlyoutView.swift:61-74, 184`) is always empty; `⌘1`–`⌘9` pin badges (`L195`) are unhandled in `handleKey` (`L149-164`)<br>• `HydrationController` (`Core/Support/HydrationController.swift:77, 261-284`) & `NutritionController` (`Core/Support/NutritionController.swift:108, 195-209`) run unconditional 1 Hz timers in `Core/` | **Zero-Idle-CPU Productivity Polish + Vision Cutout & Clipboard/Notes Completion:** Gate `HydrationController`/`NutritionController` timers on surface visibility, wire `⌘1`–`⌘9` and `originBundleID` in `ClipboardFlyoutView`, add Vision Background Removal to `ShelfGridPopupView`, and expose note titles/archive/error banner in `NoteSheetView`. |
| **5** | **Tools App** | `Partial` | • `DropClipPolicy.enabledKey` (`Core/Support/Translate.swift:121`) is ignored by `TranslatePanelController.toggleSelection()` (`App/Entry/TranslatePanelController.swift:20-28`); `.cut`/`.paste` are no-ops (`L60-61`) and `.speak` (`L69-73`) drops local `AVSpeechSynthesizer` immediately<br>• `CommandBarModel.generateValue` (`App/Scenes/CommandBarView.swift:62`) checks `"wifi"` instead of `"wifipw"` (`Core/Support/CommandBar.swift:254`)<br>• `DesktopFileOperations.compressToZip` (`Platform/Desktop/DesktopFileOperations.swift:178-185`) overwrites `archiveURL` per loop iteration on multi-file zip | **DropClip & Command Bar Bug Fixes + Unified Archive Engine:** Respect `DropClipPolicy.enabledKey`, retain `AVSpeechSynthesizer`, wire real `.cut`/`.paste`/`.ai` actions, fix `"wifipw"` refresh and `{clipboard}`/`{selection}` Quicklink values, and pass all URLs in one `ditto` invocation in `compressToZip`. |
| **6** | **Weather App** | `Mature` (Core) / `Partial` (View Parity) | • `MoonPhase` (`Core/Support/WeatherDetail.swift:114-141`) is never rendered in any Weather view<br>• `WeatherModernPanel` (`App/Scenes/Weather/WeatherModernPanel.swift:60-92`) and `WeatherFullScreenView` (`App/Scenes/Weather/WeatherFullScreenView.swift:56-79`) omit `WeatherWarningEngine` (`Core/Support/WeatherWarnings.swift:52`)<br>• `DesktopWeatherBoxView` (`App/Scenes/Desktop/DesktopWeatherBoxView.swift:7-39`) ignores `WeatherUnits.temperatureKey` and has no city switcher | **Cross-Surface Weather Parity (Warnings, Moon Phase, Desktop Units & GeoIP Fallback):** Surface `WarningsTile` and `MoonPhase` in `WeatherModernPanel` and `WeatherFullScreenView`, wire `WeatherUnits.degrees` + city stepping in `DesktopWeatherBoxView`, and add opt-in `GeoIPLookupService` fallback when CoreLocation is denied. |
| **7** | **Control Centre** | `Partial` | • `AudioOutputSwitcher.devices(input: true)` and `setDefault(id, input: true)` (`Platform/SystemStatus/AudioOutputSwitcher.swift:14, 28`) have no UI menu<br>• `KeyboardBacklight` (`Platform/Pinboard/QuickToggleEngine.swift:239-265`) is omitted from `DockControlCenterSliderCard` (`App/Scenes/DockWidgets/DockII/DockControlCenterWidgetView.swift:139-211`)<br>• `VPNServiceParser.list()` (`Core/Support/QuickToggles.swift:61-88`) parses all VPN services but UI only toggles the first<br>• `QuickToggleEngine.micPrevious` (`Platform/Pinboard/QuickToggleEngine.swift:20, 74-75`) never records pre-mute input volume | **Audio Input Selector, Keyboard Backlight Slider & Per-VPN Menu:** Add microphone device selection to `AudioOutputMenu` / Control Centre, add the `KeyboardBacklight` slider to `DockControlCenterSliderCard`, save real pre-mute mic volume in `QuickToggleEngine`, and add a multi-VPN profile picker menu. |
| **8** | **Widgets App** | `Partial` | • `WidgetSurfaceKind.shelfCard` (`Core/Support/DockWingModels.swift:647`) is omitted from `DockIIConfigureSheet.surfacePinsSection` (`App/Scenes/WidgetLookSettingsBlock.swift:405`)<br>• `DockWingsConfiguration.perDisplay` (`Core/Support/DockWingModels.swift:91, 129-199`) has no per-display UI in `WidgetWingsSettingsBlock` (`App/Scenes/WidgetLookSettingsBlock.swift:160-226`)<br>• `WidgetInstance.stack: [BarSection]?` (`Core/Support/WidgetLayoutModel.swift:81`) has no custom Smart Stack editor<br>• `DockWidgetPresetType` wing widgets cannot be placed on Desktop Boxes (`DesktopWidgetKind`, `Core/Support/Desktop/DesktopBoxModel.swift:64-66`) | **Universal Widget Surface Bridge & Per-Display Wings / Smart Stack Editor:** Expose `.shelfCard` and reorder/collapse in `DockIIConfigureSheet`, add a display selector to `WidgetWingsSettingsBlock`, allow hosting `DockWidgetPresetType` inside Desktop Boxes, and add a custom Smart Stack builder. |
| **9** | **Wallpaper App** | `Mature` | • `SolarDaylightEvaluator.sample` (`Core/Support/SolarPhase.swift:101-168`) computes 6-step `DaylightPhase`, `progress`, `altitude`, and `luminance`, but `WallpaperEngine.refresh` (`App/Composition/WallpaperEngine.swift:179-185`) collapses it to 5-step `SolarPhase`<br>• `SolarPosition.at` (`Core/Support/WallpaperSelector.swift:357-369`) has zero production callers (`TerrainWallpaperRenderer.render` hardcodes glow center at `L430`)<br>• `WallpaperStageView` (`App/Scenes/SettingsAppearancePane.swift:567-593`) omits `SkyAtmosphere` (stars, moon, clouds, meteor) and live city terrain resolution (`L455`) | **True Solar-Position & Atmospheric Stage Preview + Intra-Phase Blending:** Drive `TerrainWallpaperRenderer` glow position from `SolarPosition.at` and `DaylightSample.progress`, render `SkyAtmosphere` stars/moon/clouds in `WallpaperStageView`, and resolve `WallpaperSelector.skyPackAliases` for custom packs. |
| **10** | **Window Management** | `Mature` | • `SnapZonePlanner.Layout.thirds` (`Core/Support/WindowSnap.swift:77-81, 117-124`) is never used by `SnapDragMonitor.dragged()` (`Platform/Windows/WindowSnapService.swift:223`)<br>• `WindowLayoutMemory` (`Core/Support/WindowLayoutMemory.swift:7-59`) is in-memory only (`WindowLayoutRestoreController.swift:15`), losing saved topology layouts on app relaunch<br>• `TilingEngine.releaseWindow` (`App/Composition/TilingEngine.swift:495`) & `retileAll()` (`L381`) have no `ShortcutAction` or Command Bar trigger | **Persistent Topology Layout Memory, Modifier Drag-to-Thirds & Per-Window Float Hotkey:** Persist `WindowLayoutMemory` to Application Support, hold `⌥` during edge-drag in `SnapDragMonitor` to snap into `.thirds`, and add `ShortcutAction` + Command Bar actions to float/retile the focused window. |
| **11** | **Tracking** | `Partial` | • `NotchAIPageView` (`App/Scenes/Notch/NotchAIPageView.swift:115-125`) passes hardcoded dummy numbers (`activeDuration: 3600, linesAdded: 120, linesDeleted: 24, streakDays: 3`) to `AIStatsReceiptCalculator.calculate`<br>• `AgentUsageSnapshot.weeklyHeatmap` (`Core/Support/AgentUsage/AgentUsageModels.swift:258`) & `AgentLiveTurn.activeTool` (`L142`) are never populated in `AgentUsageService.refreshAsync()` (`App/Composition/AgentUsageService.swift:138-336`)<br>• `QuitOnLastWindowService.start()` (`App/Composition/QuitOnLastWindowService.swift:85-87`) runs a 60s timer even when `idleThresholdSeconds == 0` and never passes `isAgentWorking` (`L192`)<br>• `ScreenTimeHourlyBarTile` & `AILimitDualBarTileView` (`App/Scenes/Edge/ScreenTimeViews.swift:212-273`) have zero call sites | **Real AI Usage Receipt & 7-Day Heatmap + Zero-Idle-CPU Idle-App Guard:** Compute real duration, diff lines, streak, and 7-day heatmap in `AgentUsageService`, gate `QuitOnLastWindowService.idleTimer` on `idleThresholdSeconds > 0`, pass `AgentUsageService.shared.snapshot.activeTurn != nil` as `isAgentWorking`, and add Screen Time CSV/JSON export. |
| **12** | **Storage** | `Partial` | • `NotchStoragePageView.reviewLeftovers` (`App/Scenes/Notch/NotchStoragePageView.swift:93-110`) is hardcoded to `"com.spotify.client"` / `"Spotify"` and never checks disk existence or calls `CleanerService`<br>• `StorageScanService.candidates()` (`App/Composition/StorageScanService.swift:84-95`) and `StorageScanMath.isScannable` (`Core/Support/StorageScanMath.swift:36-39`) are dead code in production | **Real App-Leftover Scanner & Trash Flow:** Replace the hardcoded Spotify stub in `NotchStoragePageView.reviewLeftovers` with an actual scan of `~/Library` against installed apps using `AppLeftoverScanPlan.candidatePaths`, listing orphaned app leftovers with a review-first `Move to Trash` confirmation. |
| **13** | **Monitoring** | `Mature` (Samplers) / `Partial` (UI & Deduplication) | • Three separate `SystemMonitorController` instances run independent 1 Hz timers (`ProductivityServices.shared.systemMonitor`, `DockSystemFeed.shared.monitor` at `App/Composition/DockWidgetFeeds.swift:52`, `DockTelemetryFeed.shared.monitor` at `App/Composition/DockTelemetryFeed.swift:13`)<br>• `BatteryHealthReader.read()` (`Platform/SystemStatus/SystemHealthReaders.swift:9-12`) parses `cycleCount` and `healthPercent` (`Core/Support/SystemMonitorMath.swift:141-162`), and `PowerFactsReader` reads `secondsRemaining` (`Platform/SystemStatus/SystemHealthReaders.swift:33-35`), but `DockTelemetryFeed` (`App/Composition/DockTelemetryFeed.swift:111-122`) discards all three<br>• `SystemMonitorFlyoutView` (`App/Scenes/Edge/SystemMonitorFlyoutView.swift:24-33`) drops `s.diskRead`/`s.diskWrite`, GPU, Battery Health, and `TopProcessReader.read` (`Platform/SystemStatus/SystemHealthReaders.swift:62-76`) | **Shared Ref-Counted `SystemMonitorController` + Battery Cycles/Health/ETA & Top Processes UI:** Share one singleton `SystemMonitorController` across `ProductivityServices`, `DockSystemFeed`, and `DockTelemetryFeed`; surface `cycleCount`, `healthPercent`, and `secondsRemaining` in `BatteryPeripheralsPopoverCard`; and add Disk I/O + Top Processes to `SystemMonitorFlyoutView`. |

---

## 2. Detailed Pillar-by-Pillar Findings (1–13)

### Pillar 1: Dock Replacement
* **Behavior-Frozen Files to Leave Untouched:** `App/Composition/WindowLiftAvoidanceController.swift`, `App/Composition/DragController.swift`, `Platform/AppTracking/AppTracker.swift`, `Platform/Accessibility/AccessibilitySource.swift`, `Platform/CoreGraphics/FullscreenIntentMonitor.swift`.
* **A. Built in `Core/` or `App/Composition/`, Not Exposed in UI:**
  * `DockSlotLayout.groupAdjacentUtilities: Bool` (`Core/Support/BarSection.swift:600, 709`) controls whether adjacent utility slot items (`.clockCalendar`, `.weather`, `.system`, `.devices`, `.drives`, `.nowPlaying`, `.space`, `.launcher`, `.controlCenter`, `.keepAwake`, `.quickSettings`, `.notchTools`) merge into a single continuous island/rail cluster or render as separate glass pods. It is persisted in `DockSlotLayout` JSON (`com.katikati.dock.slotLayout.v1`) and consumed by `DockSlotLayout.resolveSections()` (`L709`), but has **no toggle** in `App/Scenes/SettingsLayoutPane+Widgets.swift:80-252`.
  * `BarProfile` (`Core/Support/BarProfile.swift:10-43`) and `BarProfileService` (`App/Composition/BarProfileService.swift:14-124`) provide named layout profiles (`Work`, `Personal`, `Gaming`, etc.) stored in `~/Library/Application Support/KatiKati/profiles.json`. However, there is **zero Settings UI** or Status Menu submenu to list, apply, save, or delete profiles — they are only reachable if a user knows to type `profile ` or `profile save <name>` in the Command Bar (`Core/Support/CommandBar.swift:451-462`).
  * `DockClickPolicy` (`Core/Support/DockClickPolicy.swift:6-17`) implements `⌥-click` to hide an app (`.hideApp`) and `⌘-click` to minimize a window (`.minimizeWindow`) on Dock chips, but this modifier behavior is undocumented in `SettingsTab.mouse` and `SettingsTab.appIcons`.
* **B. Partial / Half-Wired Gaps:**
  * `BarProfileService.currentState()` (`App/Composition/BarProfileService.swift:120-123`) hardcodes `widgetPresetID: nil`, and `BarProfile` (`Core/Support/BarProfile.swift:10-21`) only stores `layoutMode`, `alignment`, `dockStyle`, and `widgetLayout` (`[WidgetInstance]`), omitting `dockSlotLayout`, `stripPlacementMap`, and `dockWings`. Furthermore, `SettingsBackupService.applicationSupportFiles` (`Core/Support/SettingsBackup.swift:233-238`) omits `profiles.json`.
  * `StatusMenuController.rebuildAddItemsMenu()` (`App/Entry/StatusMenuController.swift:763-781`) still reads and mutates legacy `store.widgetLayout` (`BarSection.canonicalOrder`) and `store.dockUtilities.hidden` (`DockUtilityKind.allCases`) instead of `store.dockSlotLayout` (`DockSlotItem.allCases`), omitting slot-only items `.shelf`, `.backgroundApps`, and `.controlCenter` (`Core/Support/BarSection.swift:533`).
  * `WelcomeGuideView.widgetsStep` (`App/Scenes/WelcomeGuideView.swift:202, 264-295`) toggles legacy `BarSection.canonicalOrder` (including monolithic `.utilities` and separate `.clock` + `.calendar`) instead of `DockSlotLayout` (`DockSlotItem.clockCalendar` and individual utility slots).
* **C. High-Leverage Reuse Opportunities:**
  * Add a **Dock Profiles** card in `App/Scenes/SettingsLayoutPane+Widgets.swift` (and a `Profiles` submenu in `StatusMenuController`) backed by `BarProfileService.shared`, extending `BarProfile` to snapshot `dockSlotLayout` and `dockWings` and adding `"profiles.json"` to `SettingsBackupService.applicationSupportFiles`.
* **D. Consolidation & Cleanup:**
  * `App/Scenes/SettingsLayoutPane+Widgets.swift:116-213` renders `store.dockSlotLayout.items` (`L116-154`) and then renders duplicate legacy rows for `Show Shelf` (`L156`), `Show Trash` (`L161`), `Background Apps` (`L166`), and `Mid-Dock Utilities` (`L188-213`) on the same card.
  * `App/Scenes/StatusMenuWidgets.swift:17-240` (`PreferenceSliderCommitTracker`, `PreferenceSliderMenuItemView`) and `L323-384` (`NativeDockApplyRowView`) are ~300 lines of dead AppKit views left behind after the 2026-10-21 status menu simplification (`App/Entry/StatusMenuController.swift:231`).

---

### Pillar 2: Notch Replacement
* **A. Built in `Core/` or `App/Composition/`, Not Exposed in UI:**
  * `SurfaceTimeTravelCoordinator` (`Core/Support/NotchBehavior.swift:305-395`), `NotchTimeTravelBuffer` (`L188-224`, 25-entry ring buffer for `Option+Scroll` event replay across `.notch` and `.island`), `DeferredFocusQueue` (`L227-255`, queues non-critical live events while Focus mode is active), and `SuggestionBackoffTracker` (`L258-295`, auto-mutes Sixth-Sense contextual rules after 5 consecutive dismissals with `reset(ruleKey:)` at `L279-285`) have **no Settings controls** in `App/Scenes/LiveIslandSettingsBlock.swift` to toggle Focus alert deferral, inspect recent event history, or reset muted Sixth-Sense suggestions.
  * `IslandPresets.call(...)` and `IslandPresets.etaTemplate(...)` (`App/Composition/IslandLiveBridge.swift:431-452`) are implemented and showcased in `IslandPlaygroundSheet` (`App/Scenes/LiveIslandSettingsBlock.swift:741-742`), but have no live producer feeding them.
* **B. Partial / Half-Wired Gaps:**
  * `IslandLiveBridge` (`App/Composition/IslandLiveBridge.swift:16, 29, 44, 72-106`) holds `private let cameraService: CameraMirrorService` (`L29`) and defines `ActivityID.camera = "katikati.camera"` (`L16`), yet `start()` (`L72-106`) **never subscribes to `cameraService`** and has no `syncCamera()` method.
  * `LiveEventDetector` (`Core/Support/LiveEventDetector.swift:16-18, 22-43`) explicitly notes that Reminder/Alarm due and Weather severe alert triggers were deferred waiting on sources, even though `AlarmStore` (`App/Composition/CalendarService.swift:264`), `CalendarService.reminders` (`L39`), and `WeatherWarningEngine` (`Core/Support/WeatherWarnings.swift:52`) are now in tree.
  * `NotchPagingPolicy.defaultPage` (`Core/Support/NotchSectionPaging.swift:142-153`) only prioritizes `downloadsActive`, `aiTurnActive`, and `nowPlayingActive`, ignoring active Focus timers (`.studioHub`), imminent calendar meetings (`.calendar`), or active `KeepAwakeService` (`.keepAwake`).
* **C. High-Leverage Reuse Opportunities:**
  * Wire `CameraMirrorService`, `AlarmStore` / `CalendarService` imminent meetings (using `IslandPresets.call` / `etaTemplate`), and `WeatherWarningEngine` into `IslandLiveBridge` and `LiveEventDetector`.
* **D. Consolidation & Cleanup:**
  * `App/Scenes/LiveIslandSettingsBlock.swift:224, 296, 305-322, 359-406, 435-466, 486-546` uses dozens of unlocalized `Text(verbatim:)` strings (`"Notch Behavior"`, `"Notch At Rest"`, `"Notch Layout"`, `"Notch Pages"`, etc.) that bypass `Resources/Localizable.xcstrings`.

---

### Pillar 3: Menubar Utility
* **A. Built in `Core/` or `Platform/`, Not Exposed in UI:**
  * `AppMenuSearchReader` (`Platform/Accessibility/AppMenuSearchReader.swift:11-94`) + `MenuSearch` (`Core/Support/MenuSearch.swift:24-71`) walk the frontmost app's entire menu bar hierarchy up to depth 4 (1,500 items) and score/trigger any menu item via AX, but are only reachable if the user types `m ` or `menu ` in the Command Bar (`Core/Support/CommandBar.swift:499-500`), with no standalone `ShortcutAction` or Status Menu entry.
* **B. Partial / Half-Wired Gaps:**
  * **Broken Network Menu Bar Stat (`Core/Support/MenuBarStatModel.swift:82-129`):** `MenuBarStatModel.styles(for: .network)` returns `[]` (`L87`), `defaultStyle(for: .network)` returns `.percentage` (`L91`), and `fraction(metric: .network, values:)` returns `nil` (`L110`). As a result, `statusText(metric: .network, style: .percentage, values:)` (`L119-128`) **always returns `"–"`** in the macOS menu bar, even though `MenuBarSystemItem.refresh()` (`App/Composition/MenuBarSystemItem.swift:69-70`) populates `values.down` and `values.up` every second and `menuRowText` (`MenuBarStatModel.swift:145-146`) formats them!
  * `MenuBarSystemItem.openSettings()` (`App/Composition/MenuBarSystemItem.swift:116-119`) and `DriveMenuBarItem.openSettings()` (`App/Composition/DriveMenuBarItem.swift:85-88`) call `(NSApp.delegate as? AppDelegate)?.openSettings(nil)` instead of `openSettings(selecting: .menuBar)`.
* **C. High-Leverage Reuse Opportunities:**
  * Add an **Eject** submenu or action for removable volumes (`volume.isRemovable`, `Core/Support/DriveInventory.swift:10`) in `DriveMenuBarItem.menuNeedsUpdate` (`App/Composition/DriveMenuBarItem.swift:63-78`), reusing `NSWorkspace.shared.unmountAndEjectDevice(at:)`.
* **D. Consolidation & Cleanup:**
  * `DriveMenuBarItem.apply()` (`App/Composition/DriveMenuBarItem.swift:36-38`) runs a continuous 10s polling timer (`Timer.scheduledTimer(withTimeInterval: 10, repeats: true)`) even when the menu is closed; it should observe `NSWorkspace.didMountNotification` and `NSWorkspace.didUnmountNotification` and refresh free-byte counts lazily inside `menuNeedsUpdate(_:)` (`L63`).

---

### Pillar 4: Productivity Apps (Tasks, Reminders, Goals, Bookmarks, Notes, Focus, Shelf, Clipboard)
* **A. Built in `Core/`, `Platform/`, or `App/Composition/`, Not Exposed in UI:**
  * **On-Device Vision Background Removal (`App/Composition/ShelfActions.swift:218-258`, `Core/Support/PDFReducePlan.swift:66-78`):** `ShelfActions.removeBackground(_:into:)` runs `VNGenerateForegroundInstanceMaskRequest` off-main-thread and writes `<stem>_nobg.png`, and `FileTransformAction.removeBackground` is modeled in `Core/Support/PDFReducePlan.swift:69`, but there is **no button or context menu item** for it anywhere in `App/Scenes/ShelfGridPopupView.swift`!
  * **Encrypted Note Titles, Archiving & Error Surfacing (`Platform/Notes/NotesController.swift:19, 48, 65, 107`):** `NotesController.edit(id:title:body:)`, `setArchived(id:_:)`, and `@Published private(set) var lastError: Error?` are implemented and unit-tested, but `NoteSheetView` (`App/Scenes/Edge/NoteSheetView.swift:24-89`) only binds the body `TextEditor`, color dots, pin toggle, and delete button — no title field, no archive toggle/filter, and no error banner when `notes.sealed` fails to decrypt.
* **B. Partial / Half-Wired Gaps:**
  * **Clipboard `Work` Category Tab Always Empty (`App/Scenes/Edge/ClipboardFlyoutView.swift:61-74, 184`, `Core/Support/ClipboardPlus.swift:79-106`):** `ClipboardFlyoutView` displays `All`, `Work`, `Personal` filter pills, but calls `ClipboardCardMetadata.classify(text: entry.text)` at `L184` with default `originBundleID: nil` and `workBundleIDs: []`. Because `ClipEntry` (`Core/Support/ClipboardHistory.swift:4-19`) does not store `originBundleID`, `resolveCategory` (`Core/Support/ClipboardPlus.swift:102-106`) classifies every entry as `.personal`, leaving the `Work` tab permanently empty.
  * **Clipboard `⌘1`–`⌘9` Pin Badges Displayed But Unhandled (`App/Scenes/Edge/ClipboardFlyoutView.swift:127-132, 149-164, 194-198`):** `MaccyPinShortcutAssigner` assigns slots `1...9` and `ClipboardFlyoutView` draws `"⌘1"`…`"⌘9"` badges on pinned items (`L195`), but `handleKey(_ press: KeyPress)` (`L149-164`) only checks `MaccyKeyAction.action` (`Return`, `⌥P`, `⌫`) and never handles `⌘1`–`⌘9`.
  * **Clipboard `ignoredBundleIDs` Unwired (`Core/Support/ClipboardPlus.swift:220, 246-247`, `Platform/Clipboard/ClipboardMonitor.swift:130-146`):** `MaccyPasteboardFilter.Rules.ignoredBundleIDs` exists in Core, but `ClipboardMonitor.filterRules` never populates it.
  * **Shelf Compact Grid vs Floating Bar Action Parity (`App/Scenes/ShelfGridPopupView.swift:128-160, 186-211, 475-502`):** `Merge PDF` and `Convert` (`PNG`/`JPEG`/`WEBP`) are wired in `floatingTransformBar` (`L479-489`) but omitted from compact-grid `selectionBar` (`L128-160`) and right-click `shelfMenuItems` (`L186-211`).
  * **Fake 30-Day Habit Streak Seeded on Fresh Install (`Core/Support/HabitStreakStore.swift:164-166, 179-195`):** `HabitStreakStore.seedSampleHistory()` writes 22 fake completed days and a fake 5-day streak into `history` when `com.katikati.habits.data` is absent, with no Reset button in UI.
* **C. High-Leverage Reuse Opportunities:**
  * Wire `ShelfActions.removeBackground` (`App/Composition/ShelfActions.swift:218`) and `DesktopFileOperations.extractZip` (`Platform/Desktop/DesktopFileOperations.swift:192`) into `ShelfGridPopupView` (`floatingTransformBar`, `selectionBar`, and `shelfMenuItems`).
* **D. Consolidation & Cleanup (Critical Idle-CPU & Layer Violations):**
  * **1 Hz Idle-CPU & `Core/` AppKit Violation in `HydrationController` (`Core/Support/HydrationController.swift:2, 46, 77, 261-284`) and `NutritionController` (`Core/Support/NutritionController.swift:2, 81, 108, 195-209`):** Both files live in `Core/Support/` while importing `AppKit` (violating `STANDING_RULES.md` §2.2), and both start an unconditional 1.0s repeating `Timer` in `init()` that mutates `@Published var wavePhase` (`HydrationController.swift:265`) and `@Published var secondsUntilNextMeal` (`NutritionController.swift:198`) every second for the lifetime of the app, even when no Hydration or Nutrition view is on screen.
  * **Duplicate Tray & Transform Engine in `Core/Support/PDFReducePlan.swift:1-5, 267-368`:** Imports `AppKit`, `ImageIO`, `PDFKit` inside `Core/Support/` and defines a duplicate `DroppyFileTrayStore` (`L267-305`) and `FileTransformEngine` (`L307-368`) duplicating `ShelfStore` and `ShelfActions`.

---

### Pillar 5: Tools App (Capture/OCR/QR, Dictionary/Translate, Compression, Finder Keys, Command Bar, Downloads/Torrents)
* **A. Built in `Core/` or `Platform/`, Not Exposed in UI:**
  * `Quicklink.openWith: String?` (`Core/Support/QuicklinkTemplate.swift:17`) models opening a Quicklink URL/file with a specific app bundle ID, and `CommandBarView.activateQuicklink` (`App/Scenes/CommandBarView.swift:549-551`) honors it, but `Quicklink.parse` (`Core/Support/QuicklinkTemplate.swift:20-35`) and `Quicklink.serialize` (`L37-39`) only parse `Name = template` lines and drop `openWith`.
* **B. Partial / Half-Wired Gaps:**
  * **DropClip Selection Pill Ignores Its Settings Toggle & Has Broken Actions (`App/Entry/TranslatePanelController.swift:20-83`, `Core/Support/Translate.swift:121, 144-163`):**
    1. `LiveIslandSettingsBlock.swift:619` binds `@AppStorage(DropClipPolicy.enabledKey) private var dropClipEnabled = true`, but neither `TranslatePanelController.toggleSelection()` (`App/Entry/TranslatePanelController.swift:20-28`) nor `DropClipPolicy.shouldPresent` (`Core/Support/Translate.swift:144-163`) checks `UserDefaults.standard.object(forKey: DropClipPolicy.enabledKey)`!
    2. In `TranslatePanelController.performAction` (`L54-83`): `.cut` and `.paste` (`L60-61`) just call `dismiss()`; `.speak` (`L69-73`) creates a local `let synth = AVSpeechSynthesizer()` that ARC deallocates as soon as `performAction` returns; `.ai` (`L79-82`) opens the Command Bar without passing `text`; and `.quickFix` (`L74-78`) only trims whitespace (which `SelectedTextReader.selectedText()` at `Platform/Accessibility/SelectedTextReader.swift:12` already trimmed).
  * **Command Bar `"wifipw"` Generator Never Refreshes (`App/Scenes/CommandBarView.swift:61-65` vs `Core/Support/CommandBar.swift:254`):** `CommandGenerator.wifiPassword.keyword` is `"wifipw"`, but `CommandBarModel.generateValue` (`App/Scenes/CommandBarView.swift:62`) checks `if trimmed == "wifi" { self.refresh() }` in its async completion handler, so typing `"wifipw"` never refreshes the result row when the Keychain lookup completes.
  * **Multi-File ZIP Overwrite Bug (`Platform/Desktop/DesktopFileOperations.swift:168-190`):** `DesktopFileOperations.compressToZip(urls:)` loops `for url in urls` (`L178-185`) invoking `ditto -c -k --sequesterRsrc --keepParent url.path archiveURL.path`, **overwriting `archiveURL` on every iteration** so a multi-file zip only contains the last file!
  * **Quicklink `{clipboard}` and `{selection}` Not Passed in Command Bar Preview (`App/Scenes/CommandBarView.swift:529`):** `CommandBarView` calls `QuicklinkTemplate.expand(link.template, values: QuicklinkValues(query: argument))` without passing `clipboard` or `selection`.
* **C. High-Leverage Reuse Opportunities:**
  * Expose `DesktopFileOperations.extractZip` (`Platform/Desktop/DesktopFileOperations.swift:192`) in `CommandBarActionResolver.actions(for: .file)` (`Core/Support/CommandBar.swift:202-209`) when a `.zip` file is selected in Command Bar file search.
* **D. Consolidation & Cleanup:**
  * **Triple Pasteboard Polling Timers:** `ClipboardMonitor` (`Platform/Clipboard/ClipboardMonitor.swift:117`, 0.7s), `LinkCleanerService` (`App/Composition/LinkCleanerService.swift:21`, 0.7s), and `TendederoClotheslineController` (`App/Scenes/Edge/ClipboardFlyoutView.swift:411`, 1.0s) run three independent `NSPasteboard.general.changeCount` timers. Folding `LinkCleanerService` into `ClipboardMonitor.poll()` removes a continuous timer and finally activates `ClipboardToastBadge.badge(for:linkCleaned: true)` (`Core/Support/ClipboardPlus.swift:146`).

---

### Pillar 6: Weather App
* **A. Built in `Core/` or `Platform/`, Not Exposed in UI:**
  * `MoonPhase` (`Core/Support/WeatherDetail.swift:114-141`: `fraction(at:)`, `illumination(at:)`, `symbolName(at:)`) is implemented and unit-tested in `Core/Support/WeatherDetail.swift`, but **never rendered** in `WeatherDetailViews.swift`, `WeatherGlanceView.swift`, `WeatherModernPanel.swift`, `WeatherFullScreenView.swift`, or `WeatherPreviewCard.swift`.
* **B. Partial / Half-Wired Gaps:**
  * **`WeatherModernPanel` and `WeatherFullScreenView` Drop Severe Weather Warnings (`App/Scenes/Weather/WeatherModernPanel.swift:60-92`, `App/Scenes/Weather/WeatherFullScreenView.swift:56-79`):** Only `WeatherGlanceView` (`SceneHero`, `App/Scenes/WeatherGlanceView.swift:109, 123-133`) calls `WeatherWarningEngine.warnings(for: detail, thresholds: WeatherPrefs.thresholds())` (`Core/Support/WeatherWarnings.swift:52`). Both `WeatherModernPanel` (the default `.modern` preset!) and `WeatherFullScreenView` completely omit `WeatherWarningEngine` and `WarningsTile`.
  * **`DesktopWeatherBoxView` Ignores `WeatherUnits.temperatureKey` & Multi-City (`App/Scenes/Desktop/DesktopWeatherBoxView.swift:7-39`):** Uses locale-bound `Measurement(value: celsius, unit: UnitTemperature.celsius).formatted(...)` instead of `@AppStorage(WeatherUnits.temperatureKey)` (`WeatherUnits.degrees`), lacks city-switching controls (`service.step(by:)`), and displays a static `"No forecast yet"` string when `service.needsLocation` is true.
  * **`WeatherModernPanel` Drops 5 Decoded Metrics (`App/Scenes/Weather/WeatherModernPanel.swift:124-138`):** Only displays UV, Wind, and Sunset in its footer strip, dropping Humidity, Dew Point, Pressure, Visibility, and Precipitation (`DetailGrid` in `App/Scenes/Weather/WeatherDetailViews.swift:224-233` renders all 8).
* **C. High-Leverage Reuse Opportunities:**
  * Wire `GeoIPLookupService.fetchCurrentLocation()` (`Platform/SystemStatus/GeoIPLookupService.swift:37-57`) + `WeatherGeocoding` as an opt-in city fallback in `WeatherService.fallBackFromCurrentLocation()` (`App/Composition/WeatherService.swift:174-180`) when CoreLocation permission is denied and no saved locations exist.
  * Render `MoonPhase` (`Core/Support/WeatherDetail.swift:114-141`) in `DetailGrid` (`App/Scenes/Weather/WeatherDetailViews.swift:215-237`) and `WeatherFullScreenView.tiles` (`App/Scenes/Weather/WeatherFullScreenView.swift:167-192`).

---

### Pillar 7: Control Centre
* **A. Built in `Core/` or `Platform/`, Not Exposed in UI:**
  * **Audio Input (Microphone) Device Switching (`Platform/SystemStatus/AudioOutputSwitcher.swift:14, 28`):** `AudioOutputSwitcher.devices(input: true)` and `AudioOutputSwitcher.setDefault(id, input: true)` are implemented in CoreAudio, yet `AudioOutputMenu` (`L58-76`) only lists output devices (`input: false`). No UI surface exposes microphone device selection.
  * **Keyboard Backlight Slider (`Platform/Pinboard/QuickToggleEngine.swift:239-265`):** `KeyboardBacklight.isAvailable`, `current()`, and `set(_ level: Double)` are implemented via `CoreBrightness`, but `DockControlCenterSliderCard` (`App/Scenes/DockWidgets/DockII/DockControlCenterWidgetView.swift:139-211`) only renders Display and Sound sliders.
  * **Multi-VPN Service Picker (`Core/Support/QuickToggles.swift:61-88`):** `VPNServiceParser.list()` parses every configured macOS VPN service (`[Entry]` with `id`, `name`, `connected`), while `VPNServiceParser.set(_ on: Bool)` (`L92-100`) blindly toggles only the first service.
* **B. Partial / Half-Wired Gaps:**
  * **`QuickToggleEngine.micPrevious` Never Updated Before Muting (`Platform/Pinboard/QuickToggleEngine.swift:20, 48, 74-75, 105`):** `micPrevious` is hardcoded to `70` (`L20`) and never updated from the current input volume before mutating input volume to `0`, and `read(.muteMic)` spawns `/usr/bin/osascript` instead of reading CoreAudio input volume in-process.
  * **No Individual `ShortcutAction` for Quick Toggles (`Core/Support/Shortcuts.swift`, `App/Scenes/SettingsLayoutPane.swift:155-232`):** Only `.keepAwake` has a `ShortcutAction`; individual `QuickToggleID`s (`.darkMode`, `.muteMic`, `.nightShift`, `.trueTone`, `.vpn`, `.bluetooth`, `.hideDesktopIcons`, `.lockScreen`) cannot be bound to hotkeys.
* **C. High-Leverage Reuse Opportunities:**
  * Add an **Input Devices** section to `AudioOutputMenu` (`Platform/SystemStatus/AudioOutputSwitcher.swift:58-76`) and `NotchMeetingControlBar` (`App/Scenes/Notch/NotchMeetingControlBar.swift`), and add the `KeyboardBacklight` slider to `DockControlCenterSliderCard` when `KeyboardBacklight.isAvailable` is true.

---

### Pillar 8: Widgets App (Bar Widgets, Widget Wings, Desktop Boxes, SideDeck)
* **A. Built in `Core/` or `App/Composition/`, Not Exposed in UI:**
  * `WidgetSurfaceKind.shelfCard` (`Core/Support/DockWingModels.swift:647`) is part of `WidgetSurfaceKind` (`[.dockWing, .drawer, .shelfCard, .backgroundAppsPopup, .floatingStack]`), but `DockIIConfigureSheet.surfacePinsSection` (`App/Scenes/WidgetLookSettingsBlock.swift:405`) hardcodes `let surfaces: [WidgetSurfaceKind] = [.drawer, .backgroundAppsPopup, .floatingStack]`, **omitting `.shelfCard`**.
  * `DockWingsConfiguration.perDisplay: [String: DockWingPair]` (`Core/Support/DockWingModels.swift:91, 129-199`) implements per-display wing presets and sizes keyed by `displayUUID`, but `WidgetWingsSettingsBlock` (`App/Scenes/WidgetLookSettingsBlock.swift:160-226`) only edits global `left` and `right` wings.
  * `UniversalWidgetModel.isCollapsed`, `DockWidgetConfigStore.togglingCollapsed(for:on:)` (`Core/Support/DockWingModels.swift:670, 688, 769-780`), and `DockWidgetConfigStore.moving(...)` (`L800`) exist in Core, but `DockIIConfigureSheet` (`App/Scenes/WidgetLookSettingsBlock.swift:445-476`) has no reorder or collapse controls.
* **B. Partial / Half-Wired Gaps:**
  * **Siloed Widget Taxonomies:** `DockWidgetPresetType` (`Core/Support/DockWingModels.swift:5-20`: `.spotify`, `.controlCenter`, `.vpn`, `.friends`, `.telemetry`, `.ram`, `.network`, `.disk`, `.battery`, `.ai`, `.pause`, `.hydrate`) cannot be hosted inside Desktop Boxes (`DesktopWidgetKind`, `Core/Support/Desktop/DesktopBoxModel.swift:64-66`, which only supports `.folder`, `.todo`, `.quickCapture`, `.glance`, `.weather`, `.music`, `.search`) or SideDeck (`EdgeItem`, `Core/Support/EdgeBarSlot.swift:48-77`).
  * **No Custom Smart Stack UI (`Core/Support/WidgetLayoutModel.swift:81`, `Core/Support/WidgetPreset.swift:49-54`):** `WidgetInstance.stack: [BarSection]?` supports multi-widget rotating Smart Stacks on the Dock bar, but is only reachable by applying hardcoded `builtin.agenda` or `builtin.monitor` presets — `SettingsLayoutPane+Widgets.swift` has no UI to create or edit a Smart Stack.
* **C. High-Leverage Reuse Opportunities:**
  * Add `.wingWidget(DockWidgetPresetType)` (or a `wingPreset: DockWidgetPresetType?` field on `DesktopBox`) so any Dock II Wing widget (`.telemetry`, `.ram`, `.network`, `.disk`, `.battery`, `.ai`, `.controlCenter`, `.vpn`, `.hydrate`, `.pause`) can be pinned directly onto the Desktop canvas via `DesktopBoxManager`.

---

### Pillar 9: Wallpaper App (Dynamic Wallpaper, Simple Wallpapers, Panorama, Accents)
* **A. Built in `Core/`, Not Exposed in UI:**
  * `SolarPosition.at(_:latitude:longitude:)` (`Core/Support/WallpaperSelector.swift:357-369`) computes exact solar altitude and azimuth (`CelestialPosition`), but has **zero production call sites** (`TerrainWallpaperRenderer.render` at `App/Composition/WallpaperEngine.swift:430` hardcodes the sun/moon glow center to `CGPoint(x: w * 0.72, y: h * 0.66)`).
  * `SolarDaylightEvaluator.sample(at:times:)` (`Core/Support/SolarPhase.swift:101-168`) computes the 6-step `DaylightPhase` (`.night`, `.dawn`, `.morning`, `.noon`, `.goldenHour`, `.dusk`), intra-phase `progress: Double` (`0...1`), solar `altitude: Double`, and sky `luminance: Double`, but `WallpaperEngine.refresh` (`App/Composition/WallpaperEngine.swift:179-185`) immediately collapses `daylight.phase` to the coarse 5-step `daylight.phase.solarPhase` and discards `progress`, `altitude`, and `luminance`.
* **B. Partial / Half-Wired Gaps:**
  * **`WallpaperStageView` Preview Drops `SkyAtmosphere` & Live Location Terrain (`App/Scenes/SettingsAppearancePane.swift:449-457, 567-593`):**
    1. `WallpaperStageView` (`L567-593`) only draws the sky gradient, glow, and 3 silhouette layers — omitting the stars, moon phase/terminator, meteor, and cloud bands (`SkyAtmosphere`) that `TerrainWallpaperRenderer.render` (`App/Composition/WallpaperEngine.swift:420-435`) draws on the desktop.
    2. `SettingsWallpaperPane.previewEnvironment` (`L455`) passes `latitude: nil, cityName: ""` to `TerrainMimicCatalog.resolve`, so when `Environment` is set to `Auto`, the Settings preview always renders `.countryside` (`Core/Support/WallpaperSelector.swift:152`) instead of matching the user's live city/latitude from `WeatherService`.
  * **`WallpaperSelector.skyPackAliases` Unused by `WallpaperEngine.pack(folder:)` (`Core/Support/WallpaperSelector.swift:32-37` vs `App/Composition/WallpaperEngine.swift:335-344`):** `skyPackAliases` maps `<phase>` and `any-<sky>` and `default` to `<phase>-<sky>` keys, but `WallpaperEngine.pack(folder:)` never expands aliases when indexing a folder.
* **C. High-Leverage Reuse Opportunities:**
  * Use `SolarPosition.at` (`Core/Support/WallpaperSelector.swift:358`) and `DaylightSample.progress` (`Core/Support/SolarPhase.swift:103`) to position the sun glow dynamically across the horizon and blend `SkyPalette.stops` smoothly across phase transitions, and draw `SkyAtmosphere` stars/moon/clouds inside `WallpaperStageView`.

---

### Pillar 10: Window Management (Snapping, Grid/Ribbon Tiling, Switcher, Mission Control, `winfo`)
* **Behavior-Frozen Files to Leave Untouched:** `App/Composition/WindowLiftAvoidanceController.swift`, `Platform/AppTracking/AppTracker.swift`, `App/Composition/DragController.swift`, `Platform/Accessibility/AccessibilitySource.swift`, `Platform/CoreGraphics/FullscreenIntentMonitor.swift`.
* **A. Built in `Core/`, Not Exposed in UI:**
  * `SnapZonePlanner.Layout.thirds` and `.centerAndMaximize` (`Core/Support/WindowSnap.swift:77-81, 88-100, 109-130`) are implemented in `SnapZonePlanner.resolve(at:in:layout:edgeMargin:)`, but `SnapDragMonitor.dragged()` (`Platform/Windows/WindowSnapService.swift:223`) calls `SnapZonePlanner.resolve(at: mouse, in: area, edgeMargin: edgeMargin)` with the default `.edgesAndCorners` layout only — users cannot drag-snap into thirds (`leftThird`, `centerThird`, `rightThird`).
  * `TilingEngine.releaseWindow(cgWindowID:)` (`App/Composition/TilingEngine.swift:495-505`) and `TilingEngine.retileAll()` (`L381-387`) exist on `TilingEngine`, but have **no `ShortcutAction`** (`Core/Support/Shortcuts.swift`) and **no Command Bar action** to float/unfloat the currently focused window or re-tile moved windows from the keyboard.
* **B. Partial / Half-Wired Gaps:**
  * **`WindowLayoutMemory` Is In-Memory Only (`Core/Support/WindowLayoutMemory.swift:7-59`, `App/Composition/WindowLayoutRestoreController.swift:15`):** `WindowLayoutMemory` is not `Codable` and `WindowLayoutRestoreController` never persists `memory.layouts` to disk. Any app restart or macOS reboot wipes all remembered per-display-topology window layouts.
  * **No `winfo` / Window Management Diagnostics in `DiagnosticReport` (`App/Composition/DiagnosticReport.swift:7-53`):** `DiagnosticReport` only includes glass layer readings and display strings; it omits active tiling preset, `releasedCount`, `overflowCount`, Accessibility trust status (`AXIsProcessTrusted()`), and display UUID topology key.
* **C. High-Leverage Reuse Opportunities:**
  * Make `WindowLayoutMemory` (`Core/Support/WindowLayoutMemory.swift:7`) `Codable` and persist it to `~/Library/Application Support/KatiKati/window-layouts.json` (and `SettingsBackupService`), allow holding `⌥` during `SnapDragMonitor.dragged()` (`Platform/Windows/WindowSnapService.swift:223`) to switch `SnapZonePlanner.resolve` to `layout: .thirds`, and add `ShortcutAction.tilingToggleFloatFocused` + `ShortcutAction.tilingRetileAll`.

---

### Pillar 11: Tracking (Screen Time, AI Activity/Spend, App Usage)
* **A. Built in `Core/` or `App/Scenes/`, Not Exposed in UI:**
  * `ScreenTimeHourlyBarTile` and `AILimitDualBarTileView` (`App/Scenes/Edge/ScreenTimeViews.swift:212-273`, backed by `AILimitBarTileSummary` in `Core/Support/AgentUsage/AgentUsageModels.swift:342-370`) are built in `ScreenTimeViews.swift` but have **zero call sites** in any scene.
  * `AgentLiveTurn.activeTool: AgentToolCall?` (`Core/Support/AgentUsage/AgentUsageModels.swift:142, 146-170`) is modeled with diff line summaries (`+added/-deleted`), but `AgentUsageService.refreshAsync()` (`App/Composition/AgentUsageService.swift:200-210, 235-245, 285-295`) never populates `activeTool`.
  * `AgentUsageSnapshot.weeklyHeatmap: [Double]` (`Core/Support/AgentUsage/AgentUsageModels.swift:258`) is initialized to `Array(repeating: 0.0, count: 7)` and never populated by `AgentUsageService.refreshAsync()`.
* **B. Partial / Half-Wired Gaps:**
  * **`NotchAIPageView` Hardcodes Fake Receipt Numbers (`App/Scenes/Notch/NotchAIPageView.swift:115-125`):** When opening the `"Usage receipt"` popover, `NotchAIPageView` calls `AIStatsReceiptCalculator.calculate(tokens: snapshot.todayTokens, costUSD: snapshot.todayCost, activeDuration: 3600, linesAdded: 120, linesDeleted: 24, streakDays: 3)` — passing **hardcoded constants (`3600`, `120`, `24`, `3`)** instead of real session duration, line diffs, or streak days!
  * **`QuitOnLastWindowService` Runs a 60s Timer When Off & Never Passes `isAgentWorking` (`App/Composition/QuitOnLastWindowService.swift:85-87, 192, 219`):**
    1. `start()` (`L85-87`) unconditionally schedules `idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true)` even when `idleThresholdSeconds == 0` (the default off state, `L47`), waking the main thread every minute only to hit `guard threshold > 0 else { return }` at `L202`.
    2. `evaluateIdleApps` accepts `isAgentWorking: Bool = false` (`L192`) to protect terminals/IDEs while an AI coding agent is running, but the timer at `L86` calls `self?.evaluateIdleApps()` with default `isAgentWorking = false` instead of reading `AgentUsageService.shared.snapshot.activeTurn?.isActive == true`!
  * **`ScreenTimeStore` Missing from `SettingsBackupService` (`Core/Support/SettingsBackup.swift:233-238`):** `ScreenTimeStore.defaultURL` (`screen-time.json`) is not included in `SettingsBackupService.applicationSupportFiles`, and `ScreenTimeFlyoutView` (`App/Scenes/Edge/ScreenTimeViews.swift:65-90`) has no Export (CSV/JSON) button alongside `Delete Screen Time Data`.
* **C. High-Leverage Reuse Opportunities:**
  * Populate real `activeDuration` and `weeklyHeatmap` / `streakDays` in `AgentUsageService.refreshAsync()` (`App/Composition/AgentUsageService.swift:138-336`), wire `AILimitDualBarTileView` into `NotchAIPageView`, gate `QuitOnLastWindowService.idleTimer` on `idleThresholdSeconds > 0`, and pass `AgentUsageService.shared.snapshot.activeTurn?.isActive == true` into `evaluateIdleApps`.

---

### Pillar 12: Storage (ClearDisk-style Storage, Caches, Downloads, Unmounted Volumes)
* **A. Built in `Core/` or `App/Composition/`, Not Exposed in UI:**
  * `AppLeftoverScanPlan.candidatePaths(home:existingPaths:bundleID:appName:)` (`Core/Support/StorageScanMath.swift:205-214`) filters real `~/Library` directories against an app's bundle ID and name to find orphaned Application Support, Caches, Preferences, and Saved Application State entries.
  * `StorageScanService.candidates()` (`App/Composition/StorageScanService.swift:84-95`) and `StorageScanMath.isScannable(_:)` (`Core/Support/StorageScanMath.swift:36-39`) are unreferenced in production outside tests.
* **B. Partial / Half-Wired Gaps:**
  * **`NotchStoragePageView.reviewLeftovers` Is Hardcoded to `"com.spotify.client"` / `"Spotify"` (`App/Scenes/Notch/NotchStoragePageView.swift:93-110`):** Clicking `Leftovers…` on the Notch Storage page runs `let candidates = AppLeftoverScanPlan.expectedCandidatePaths(home: userHome, bundleID: "com.spotify.client", appName: "Spotify")` (`L96`) and shows an `NSAlert` with the 4 theoretical Spotify paths without checking whether those files exist on disk, scanning any other app, or offering a `Move to Trash` action!
  * **`NotchStoragePageView.rows` Lacks Context Menu Actions (`App/Scenes/Notch/NotchStoragePageView.swift:57-79`):** Clicking a row in `Files` or `Developer & Cache` reveals it in Finder (`activateFileViewerSelecting`), set with no context menu to `Move to Trash` (via `FileManager.default.trashItem`) or `Copy Path`.
* **C. High-Leverage Reuse Opportunities:**
  * Replace the hardcoded Spotify stub in `NotchStoragePageView.reviewLeftovers` (`App/Scenes/Notch/NotchStoragePageView.swift:93-110`) with an off-main-thread scan in `CleanerService` (`App/Composition/CleanerService.swift`) that compares `AppLeftoverScanPlan.targetDirectories(home:)` against installed application bundle IDs in `/Applications` and `~/Applications` (or lets the user pick an uninstalled/trashed `.app`) and moves confirmed leftovers to Trash via `CleanerService.clean`.

---

### Pillar 13: Monitoring (CPU, RAM Pressure, Processes, Battery Health/Cycles/Watts, Bluetooth Peripherals, Network, Thermal)
* **A. Built in `Core/` or `Platform/`, Not Exposed in UI:**
  * **Battery Cycle Count, Health % & Time Remaining (`Core/Support/SystemMonitorMath.swift:141-162`, `Platform/SystemStatus/SystemHealthReaders.swift:9-12, 29-40`, `Core/Support/PowerFacts.swift:7-57`):**
    1. `BatteryHealthReader.read()` returns `BatteryHealth(cycleCount: Int, healthPercent: Int?, temperatureCelsius: Double?)`, yet its only caller in the entire app (`DockTelemetryFeed.refreshTemperature()`, `App/Composition/DockTelemetryFeed.swift:113`) reads `.temperatureCelsius` and **discards `cycleCount` and `healthPercent`**!
    2. `SystemMonitorSampler.battery()` (`Platform/SystemMonitor/SystemMonitorSampler.swift:99-114`) calls `PowerFactsReader.read(isCharging:)` and returns `MenuBarBattery(fraction:isCharging:secondsRemaining:watts:)`, yet `DockTelemetryFeed.refreshTemperature()` (`App/Composition/DockTelemetryFeed.swift:119-121`) copies `fraction`, `isCharging`, and `watts` into `DockTelemetryState` and **discards `secondsRemaining`** (`PowerFacts.durationText`, e.g., `"1h 24m left"` / `"48m to full"`).
  * **Actionable Top CPU Processes Reader (`Platform/SystemStatus/SystemHealthReaders.swift:62-76`, `Core/Support/SystemMonitorMath.swift:164-201`):** `TopProcessReader.read(limit:)` and `TopProcessParser.parse(_:limit:)` parse `pid`, `name`, and `cpu` percentage from `/bin/ps`, but have **zero production UI callers** (only unit tests in `Tests/Unit/PinboardTests.swift`).
  * **Opt-In Apple Silicon IOHID SoC Temperature Toggle (`App/Composition/DockTelemetryFeed.swift:22-24`, `Platform/SystemMonitor/AppleSiliconSensorReader.swift:7-93`):** `DockTelemetryFeed` gates `AppleSiliconSensorReader.readSoCTemperatureCelsius()` behind `UserDefaults.standard.bool(forKey: "com.katikati.dockII.telemetryIOHIDEnabled")`, which defaults to `false` and has **no toggle in Settings**!
* **B. Partial / Half-Wired Gaps:**
  * **`SystemMonitorFlyoutView` Drops Disk I/O Rates, GPU, Battery Health & Top Processes (`App/Scenes/Edge/SystemMonitorFlyoutView.swift:24-33`):** `monitor.snapshot` already computes `s.diskRead` and `s.diskWrite` every tick (`Platform/SystemMonitor/SystemMonitorController.swift:79-83`), yet `SystemMonitorFlyoutView` only shows CPU, Memory, Disk free space, and Network `down`/`up`.
* **C. High-Leverage Reuse Opportunities:**
  * Surface `BatteryHealth` (`cycleCount`, `healthPercent`), `secondsRemaining` (`PowerFacts.durationText`), and an opt-in SoC temperature sensor toggle in `BatteryPeripheralsPopoverCard` / `DockTelemetryPreviewCard` (`App/Scenes/DockWidgets/DockII/DockTelemetryWidgetView.swift:435-624`), and add Disk Read/Write + Top Processes (`TopProcessReader.read(limit: 5)`) to `SystemMonitorFlyoutView`.
* **D. Consolidation & Cleanup:**
  * **Three Duplicate `SystemMonitorController` Instances (`Platform/SystemMonitor/SystemMonitorController.swift:7`):** `ProductivityServices.shared.systemMonitor` (`App/Composition/ProductivityServices.swift`), `DockSystemFeed.shared.monitor` (`App/Composition/DockWidgetFeeds.swift:52`), and `DockTelemetryFeed.shared.monitor` (`App/Composition/DockTelemetryFeed.swift:13`) each instantiate their own `SystemMonitorController`. Because `SystemMonitorController` is already ref-counted via `acquire()` / `release()` (`SystemMonitorController.swift:23, 59`), sharing a single `SystemMonitorController.shared` instance eliminates duplicate 1 Hz Mach/IOKit sampling when multiple telemetry surfaces are visible simultaneously.

---

## 3. Prioritized Execution Roadmap (Waves / Atomic Slices)

Every slice below obeys all repository gates:
- **Diff Size:** `<= 300` lines per slice.
- **Zero `project.pbxproj` Churn:** Edits existing files in `Core/`, `Platform/`, `App/Composition/`, `App/Entry/`, `App/Scenes/`, and `Tests/Unit/`.
- **Pure Core + Synchronous `-only-testing:` Unit Tests First:** Tested via `xcodebuild test ... -only-testing:KatiKatiTests/<Suite>`.
- **12-Locale Gate:** Verified via `python3 Scripts/check_localization.py` and `python3 Scripts/check_debug_switches.py`.
- **Zero Idle CPU & Behavior-Frozen Files Untouched:** Zero background timers at rest; zero edits to the 5 frozen files.

---

### Wave 1: Zero-Idle-CPU Fixes & Broken Live Readout Repairs

#### [x] DONE — `a2a7f546` · Slice 1.1 — Fix Menu Bar Network Throughput Stat & Deep-Link Menu Bar Settings (Pillar 3)
- **Effort:** `S` | **User Impact:** `High` | **Status:** `[x] DONE — a2a7f546`
- **Reused Modules:** `Core/Support/MenuBarStatModel.swift:82-148`, `App/Composition/MenuBarSystemItem.swift:65-120`, `App/Composition/DriveMenuBarItem.swift:85-88`, `Tests/Unit/MenuBarStatsTests.swift`
- **Scope:**
  1. [x] Update `MenuBarStatModel.statusText(metric: .network, ...)` (`Core/Support/MenuBarStatModel.swift:82-129`) to format compact `↓/↑` throughput (`SystemMonitorFormat.bytes(values.down) + "/s"`) and return `[.text]` (or `.percentage`) in `styles(for: .network)` so the Network menu bar item shows live speed instead of `"–"`.
  2. [x] Update `MenuBarSystemItem.openSettings()` (`App/Composition/MenuBarSystemItem.swift:117`) and `DriveMenuBarItem.openSettings()` (`App/Composition/DriveMenuBarItem.swift:86`) to call `openSettings(selecting: .menuBar)`.
  3. [x] Replace `DriveMenuBarItem`'s 10s polling timer (`App/Composition/DriveMenuBarItem.swift:36-38`) with `NSWorkspace.didMountNotification` / `didUnmountNotification` observers plus a refresh in `menuNeedsUpdate(_:)` (`L63`), and add an Eject menu item for removable drives.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/MenuBarStatsTests && python3 Scripts/check_localization.py
  ```

#### [x] DONE — `cf03222f` · Slice 1.2 — Eliminate Unconditional Idle Timers in `HydrationController`, `NutritionController` & `QuitOnLastWindowService` (Pillars 4, 11, 13)
- **Effort:** `S` | **User Impact:** `High` | **Status:** `[x] DONE — cf03222f`
- **Reused Modules:** `Core/Support/HydrationController.swift:77, 261-284`, `Core/Support/NutritionController.swift:108, 195-209`, `App/Composition/QuitOnLastWindowService.swift:85-87, 154-220`, `Platform/SystemMonitor/SystemMonitorController.swift:7`, `App/Composition/DockWidgetFeeds.swift:52`, `App/Composition/DockTelemetryFeed.swift:13`
- **Scope:**
  1. [x] Add ref-counted `retain()` / `release()` (or `setActive(_:)`) to `HydrationController` and `NutritionController` so their 1 Hz timers only run while a Hydration or Nutrition view is mounted, stopping at 0 Hz at rest.
  2. [x] In `QuitOnLastWindowService` (`App/Composition/QuitOnLastWindowService.swift:85-87, 154-158`), only arm `idleTimer` when `idleThresholdSeconds > 0`, and pass `isAgentWorking: AgentUsageService.shared.snapshot.activeTurn?.isActive == true` into `evaluateIdleApps()`.
  3. [x] Add `static let shared = SystemMonitorController()` (`Platform/SystemMonitor/SystemMonitorController.swift:8`) and point `ProductivityServices.shared.systemMonitor`, `DockSystemFeed`, and `DockTelemetryFeed` to `SystemMonitorController.shared`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/QuitOnLastWindowTests -only-testing:KatiKatiTests/SystemMonitorMathTests && python3 Scripts/check_localization.py
  ```

#### [x] DONE — `4e18742c` & `091c339c` · Slice 1.3 — Fix DropClip Selection Pill Toggle, Speech Retention & Command Bar `"wifipw"` / Multi-File ZIP (Pillar 5)
- **Effort:** `S` | **User Impact:** `High` | **Status:** `[x] DONE — 4e18742c (ZIP) & 091c339c (DropClip/CommandBar)`
- **Reused Modules:** `Core/Support/Translate.swift:121, 144-163`, `App/Entry/TranslatePanelController.swift:20-83`, `App/Scenes/CommandBarView.swift:61-65, 529`, `Platform/Desktop/DesktopFileOperations.swift:168-190`
- **Scope:**
  1. [x] Check `DropClipPolicy.isEnabled(defaults:)` in `TranslatePanelController.toggleSelection()` (`App/Entry/TranslatePanelController.swift:20-28`); retain `private let speechSynthesizer = AVSpeechSynthesizer()` on `TranslatePanelController` (`L69-73`); wire `.AI` to pass selected text into `CommandBarView`. (`091c339c`)
  2. [x] Fix `CommandBarModel.generateValue` (`App/Scenes/CommandBarView.swift:62`) to check `CommandGenerator.match(query) == .wifiPassword` (`"wifipw"`), and pass `clipboard` + `selection` into `QuicklinkValues` at `L529`. (`091c339c`)
  3. [x] Fix `DesktopFileOperations.compressToZip(urls:)` (`Platform/Desktop/DesktopFileOperations.swift:178-185`) to stage and archive all input paths in a single `ditto -c -k --sequesterRsrc --keepParent` invocation. (`4e18742c`)
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/TranslateTests -only-testing:KatiKatiTests/CommandBarTests -only-testing:KatiKatiTests/QuicklinkTemplateTests && python3 Scripts/check_localization.py
  ```

---

### Wave 2: High-Yield Backend Capabilities Exposed in UI

#### [x] DONE — `ae014e00` · Slice 2.1 — Expose Battery Cycle Count, Health %, Time Remaining & Disk I/O / Top Processes (Pillar 13)
- **Effort:** `S` | **User Impact:** `High` | **Status:** `[x] DONE — ae014e00`
- **Reused Modules:** `Core/Support/SystemMonitorMath.swift:141-201`, `Core/Support/PowerFacts.swift:7-57`, `Platform/SystemStatus/SystemHealthReaders.swift:9-76`, `App/Composition/DockTelemetryFeed.swift:107-124`, `App/Scenes/DockWidgets/DockII/DockTelemetryWidgetView.swift:435-624`, `App/Scenes/Edge/SystemMonitorFlyoutView.swift:24-60`
- **Scope:**
  1. [x] Add `batteryCycleCount: Int?`, `batteryHealthPercent: Int?`, and `batterySecondsRemaining: Int?` to `DockTelemetryState` (`Core/Support/DockWingModels.swift:455-475`) and populate them in `DockTelemetryFeed.refreshTemperature()` (`App/Composition/DockTelemetryFeed.swift:111-123`) from `BatteryHealthReader.read()` and `SystemMonitorSampler.battery()`.
  2. [x] Display cycle count, health percentage, and formatted time remaining (`PowerFacts.durationText`) in `BatteryPeripheralsPopoverCard` and `DockTelemetryPreviewCard` (`App/Scenes/DockWidgets/DockII/DockTelemetryWidgetView.swift:466-470, 548-561`), plus an opt-in toggle for Apple Silicon SoC temperature (`com.katikati.dockII.telemetryIOHIDEnabled`).
  3. [x] Add Disk Read/Write throughput (`s.diskRead` / `s.diskWrite`) and top 3 CPU processes (`TopProcessReader.read(limit: 3)`) to `SystemMonitorFlyoutView` (`App/Scenes/Edge/SystemMonitorFlyoutView.swift:27-34`).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/PowerFactsTests -only-testing:KatiKatiTests/PinboardTests -only-testing:KatiKatiTests/DockWingModelsTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 2.2 — Cross-Surface Weather Parity: Severe Warnings, Moon Phase & Desktop Weather Units (Pillar 6)
- **Effort:** `S` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/WeatherDetail.swift:114-141`, `Core/Support/WeatherWarnings.swift:52`, `App/Scenes/Weather/WeatherModernPanel.swift:60-138`, `App/Scenes/Weather/WeatherFullScreenView.swift:56-192`, `App/Scenes/Weather/WeatherDetailViews.swift:215-237`, `App/Scenes/Desktop/DesktopWeatherBoxView.swift:7-39`
- **Scope:**
  1. [ ] Render `WarningsTile` (`WeatherWarningEngine.warnings(for: detail, thresholds: WeatherPrefs.thresholds())`) in `WeatherModernPanel` (`App/Scenes/Weather/WeatherModernPanel.swift:62`) and `WeatherFullScreenView` (`App/Scenes/Weather/WeatherFullScreenView.swift:58`).
  2. [ ] Add a `MoonPhase` card (`MoonPhase.symbolName(at:)`, `MoonPhase.illumination(at:)`) to `DetailGrid` (`App/Scenes/Weather/WeatherDetailViews.swift:224-236`) and `WeatherFullScreenView.tiles` (`App/Scenes/Weather/WeatherFullScreenView.swift:167-192`).
  3. [ ] Update `DesktopWeatherBoxView` (`App/Scenes/Desktop/DesktopWeatherBoxView.swift:7-39`) to use `@AppStorage(WeatherUnits.temperatureKey)` (`WeatherUnits.degrees`) and add city prev/next buttons when `service.locations.count > 1`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/WeatherDetailTests -only-testing:KatiKatiTests/WeatherWarningsTests && python3 Scripts/check_localization.py
  ```

#### [x] DONE · Slice 2.3 — Shelf Vision Background Removal & Transform Parity + Clipboard `⌘1`–`⌘9` & `Work` Category (Pillars 4 & 5)
- **Effort:** `M` | **User Impact:** `High` | **Status:** `[x] DONE — Clipboard (09c73eeb) & Shelf (Quick Win #4)`
- **Reused Modules:** `App/Composition/ShelfActions.swift:218-258`, `App/Scenes/ShelfGridPopupView.swift:128-211, 475-502`, `Core/Support/ClipboardHistory.swift:4-19`, `Core/Support/ClipboardPlus.swift:79-106`, `Platform/Clipboard/ClipboardMonitor.swift:110-185`, `App/Scenes/Edge/ClipboardFlyoutView.swift:61-74, 149-198`
- **Scope:**
  1. [x] DONE: Add a **Remove Background** button (`ShelfActions.removeBackground`) to `ShelfGridPopupView` (`floatingTransformBar`, `selectionBar`, and `shelfMenuItems` when selection contains images), and expose `Merge PDF` + `Convert` in compact-grid `selectionBar` and `shelfMenuItems`.
  2. [x] DONE — `09c73eeb`: Add `var originBundleID: String? = nil` to `ClipEntry` (`Core/Support/ClipboardHistory.swift:4-19`), capture `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` in `ClipboardMonitor.poll()` (`Platform/Clipboard/ClipboardMonitor.swift:148-185`), and pass `entry.originBundleID` + a default work bundle ID set to `ClipboardCardMetadata.classify` in `ClipboardFlyoutView.swift:184`.
  3. [x] DONE — `09c73eeb`: Handle `⌘1`–`⌘9` in `ClipboardFlyoutView.handleKey(_:)` (`App/Scenes/Edge/ClipboardFlyoutView.swift:149-164`) to paste the corresponding `MaccyPinShortcutAssigner` slot.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/ClipboardHistoryTests -only-testing:KatiKatiTests/ClipboardPlusTests -only-testing:KatiKatiTests/PDFReducePlanTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 2.4 — Control Centre Audio Input Switcher, Keyboard Backlight Slider & Multi-VPN Menu (Pillar 7)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Platform/SystemStatus/AudioOutputSwitcher.swift:14, 28, 58-76`, `Platform/Pinboard/QuickToggleEngine.swift:20, 48, 74-75, 239-265`, `Core/Support/QuickToggles.swift:61-100`, `App/Scenes/DockWidgets/DockII/DockControlCenterWidgetView.swift:139-211`
- **Scope:**
  1. [ ] Add an **Input (Microphone)** section to `AudioOutputMenu.populate` (`Platform/SystemStatus/AudioOutputSwitcher.swift:58-76`) using `AudioOutputSwitcher.devices(input: true)` and `setDefault(id, input: true)`.
  2. [ ] Render a Keyboard Backlight slider in `DockControlCenterSliderCard` (`App/Scenes/DockWidgets/DockII/DockControlCenterWidgetView.swift:139-211`) when `KeyboardBacklight.isAvailable` is true.
  3. [ ] Save actual current input volume into `QuickToggleEngine.micPrevious` (`Platform/Pinboard/QuickToggleEngine.swift:74-75`) before mutating input volume to `0`, and add a context menu on the `.vpn` pill listing all services from `VPNServiceParser.list()`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/QuickTogglesTests -only-testing:KatiKatiTests/ControlCenterLayoutTests && python3 Scripts/check_localization.py
  ```

---

### Wave 3: Real Data Wiring for Tracking, Storage, Notch & Notes

#### [ ] Slice 3.1 — Real AI Usage Receipt Metrics, 7-Day Heatmap & Screen Time Export (Pillar 11)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/AgentUsage/AgentUsageModels.swift:181-299`, `App/Composition/AgentUsageService.swift:138-336`, `App/Scenes/Notch/NotchAIPageView.swift:115-125`, `Core/Support/ScreenTime.swift:6-57`, `App/Scenes/Edge/ScreenTimeViews.swift:65-90`, `Core/Support/SettingsBackup.swift:233-238`
- **Scope:**
  1. [ ] Compute real `activeDuration`, 7-day daily cost/token totals (`weeklyHeatmap`), and consecutive active `streakDays` in `AgentUsageService.refreshAsync()` (`App/Composition/AgentUsageService.swift:138-336`), storing them on `AgentUsageSnapshot`.
  2. [ ] Replace the hardcoded `activeDuration: 3600, linesAdded: 120, linesDeleted: 24, streakDays: 3` in `NotchAIPageView.swift:115-125` with the real values from `snapshot`.
  3. [ ] Add `"screen-time.json"` and `"profiles.json"` to `SettingsBackupService.applicationSupportFiles` (`Core/Support/SettingsBackup.swift:233-238`), and add an **Export JSON/CSV…** button in `ScreenTimeFlyoutView` (`App/Scenes/Edge/ScreenTimeViews.swift:82`).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/AgentUsageTests -only-testing:KatiKatiTests/ScreenTimeTests -only-testing:KatiKatiTests/SettingsBackupTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 3.2 — Real App-Leftover Scanner & Review-First Trash Flow on Notch Storage Page (Pillar 12)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/StorageScanMath.swift:141-215`, `App/Composition/CleanerService.swift:8-67`, `App/Scenes/Notch/NotchStoragePageView.swift:57-148`
- **Scope:**
  1. [ ] Add `CleanerService.scanLeftovers(forAppAt appURL: URL, completion:)` (or orphaned `~/Library` scan against installed apps in `/Applications` and `~/Applications`) using `AppLeftoverScanPlan.candidatePaths(home:existingPaths:bundleID:appName:)` (`Core/Support/StorageScanMath.swift:205-214`).
  2. [ ] Replace the hardcoded `"com.spotify.client"` / `"Spotify"` alert in `NotchStoragePageView.reviewLeftovers` (`App/Scenes/Notch/NotchStoragePageView.swift:93-110`) with an `NSOpenPanel` `.app` picker (or automatic orphaned-leftover list) and a review-first `Move to Trash` confirmation backed by `CleanerService.clean(_:)`.
  3. [ ] Add a right-click context menu (`Reveal in Finder`, `Move to Trash`, `Copy Path`) to rows in `NotchStoragePageView.rows(_:)` (`L57-79`).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/StorageScanMathTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 3.3 — Encrypted Note Titles, Archive Filter & Decrypt-Error Banner in `NoteSheetView` (Pillar 4)
- **Effort:** `S` | **User Impact:** `Med`
- **Reused Modules:** `Platform/Notes/NotesController.swift:19, 48, 65, 107`, `App/Scenes/Edge/NoteSheetView.swift:24-120`
- **Scope:**
  1. [ ] Add an editable title `TextField` in `NoteSheetView` (`App/Scenes/Edge/NoteSheetView.swift:63-89`) wired to `NotesController.edit(id:title:body:)` (`Platform/Notes/NotesController.swift:65`).
  2. [ ] Add an Archive/Unarchive button (`controller.setArchived(id:_:)`, `L107`) and an `Active / Archived` filter toggle in the note list header.
  3. [ ] Surface `controller.lastError` (`L19, 48`) as a non-intrusive warning banner when an encrypted `.note` file could not be read.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/NotesTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 3.4 — Live Island Camera Mirror Subscription, Weather/Alarm Alerts & Sixth-Sense Controls (Pillar 2)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `App/Composition/IslandLiveBridge.swift:16, 29, 44, 72-106`, `Core/Support/LiveEventDetector.swift:16-43`, `Core/Support/NotchBehavior.swift:188-395`, `App/Scenes/LiveIslandSettingsBlock.swift:220-550`
- **Scope:**
  1. [ ] Subscribe `IslandLiveBridge.start()` (`App/Composition/IslandLiveBridge.swift:72-106`) to `cameraService.$isMirrored` to post/end `ActivityID.camera`.
  2. [ ] Feed severe weather warnings (`WeatherWarningEngine.warnings`) and due alarms/imminent meetings (`AlarmStore` / `CalendarService`) into `LiveEventDetector` / `LiveEventCenter`.
  3. [ ] Add Settings controls in `LiveIslandSettingsBlock.swift` to toggle `DeferredFocusQueue` focus deferral and reset `SuggestionBackoffTracker`, and localize remaining `Text(verbatim:)` section headers.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/NotchBehaviorTests -only-testing:KatiKatiTests/LiveEventDetectorTests && python3 Scripts/check_localization.py
  ```

---

### Wave 4: Architecture Unification (Dock Profiles, Widget Surfaces, Wallpaper & Window Management)

#### [ ] Slice 4.1 — Dock Profiles Studio, `groupAdjacentUtilities` Toggle & `DockSlotLayout` Migration (Pillar 1)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/BarProfile.swift:10-43`, `App/Composition/BarProfileService.swift:14-124`, `Core/Support/BarSection.swift:600, 709`, `App/Scenes/SettingsLayoutPane+Widgets.swift:80-215`, `App/Entry/StatusMenuController.swift:763-781`, `App/Scenes/WelcomeGuideView.swift:202, 264-295`
- **Scope:**
  1. [ ] Extend `BarProfile` (`Core/Support/BarProfile.swift:10-21`) with optional `dockSlotLayout: DockSlotLayout?` and `dockWings: DockWingsConfiguration?`, and record the active preset/slot state in `BarProfileService.currentState()` (`App/Composition/BarProfileService.swift:120-123`).
  2. [ ] Add a **Dock Profiles** picker/save/delete card and a **Group Adjacent Utilities** toggle (`store.dockSlotLayout.groupAdjacentUtilities`) to `App/Scenes/SettingsLayoutPane+Widgets.swift`, while removing the duplicate legacy `Show Shelf` / `Show Trash` / `Background Apps` / `Mid-Dock Utilities` rows (`L156-213`).
  3. [ ] Migrate `StatusMenuController.rebuildAddItemsMenu()` (`App/Entry/StatusMenuController.swift:763-781`) and `WelcomeGuideView.widgetsStep` (`App/Scenes/WelcomeGuideView.swift:264-295`) to mutate `store.dockSlotLayout`.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/BarProfileTests -only-testing:KatiKatiTests/DockSlotLayoutTests -only-testing:KatiKatiTests/WelcomeGuideTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 4.2 — Universal Widget Surface Pins (`.shelfCard`), Per-Display Wings & Desktop Wing Hosting (Pillar 8)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/DockWingModels.swift:91, 129-199, 647-805`, `App/Scenes/WidgetLookSettingsBlock.swift:160-226, 405-476`, `Core/Support/Desktop/DesktopBoxModel.swift:64-120`
- **Scope:**
  1. [ ] Add `.shelfCard` to `DockIIConfigureSheet.surfacePinsSection` (`App/Scenes/WidgetLookSettingsBlock.swift:405`) alongside collapse/reorder controls (`DockWidgetConfigStore.togglingCollapsed` / `moving`).
  2. [ ] Add a display picker to `WidgetWingsSettingsBlock` (`App/Scenes/WidgetLookSettingsBlock.swift:160-226`) when `NSScreen.screens.count > 1`, writing to `DockWingsConfiguration.perDisplay` (`Core/Support/DockWingModels.swift:91, 165-199`).
  3. [ ] Add optional `wingPreset: DockWidgetPresetType?` to `DesktopBox` (`Core/Support/Desktop/DesktopBoxModel.swift:83`) so any Dock II Wing widget (`.telemetry`, `.ram`, `.network`, `.disk`, `.battery`, `.ai`, `.controlCenter`, `.vpn`, `.hydrate`, `.pause`) can be added to the Desktop canvas.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/DockWingModelsTests -only-testing:KatiKatiTests/DesktopBoxModelTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 4.3 — Dynamic Wallpaper Solar-Position Glow, `SkyAtmosphere` Stage Preview & Sky Pack Aliases (Pillar 9)
- **Effort:** `S` | **User Impact:** `Med`
- **Reused Modules:** `Core/Support/WallpaperSelector.swift:32-37, 357-369, 444-510`, `Core/Support/SolarPhase.swift:101-168`, `App/Composition/WallpaperEngine.swift:179-195, 335-344, 420-435`, `App/Scenes/SettingsAppearancePane.swift:449-457, 567-593`
- **Scope:**
  1. [ ] Use `SolarPosition.at(now, latitude: ..., longitude: ...)` (`Core/Support/WallpaperSelector.swift:358`) in `TerrainWallpaperRenderer.render` (`App/Composition/WallpaperEngine.swift:430`) to position the sun glow horizontally/vertically when coordinates are available, and expand `WallpaperSelector.skyPackAliases` inside `WallpaperEngine.pack(folder:)` (`L335-344`).
  2. [ ] Render `SkyAtmosphere` stars, moon disc, and cloud bands in `WallpaperStageView` (`App/Scenes/SettingsAppearancePane.swift:567-593`) so the Settings stage matches the rendered desktop frame.
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/WallpaperSelectorTests -only-testing:KatiKatiTests/SolarPhaseTests && python3 Scripts/check_localization.py
  ```

#### [ ] Slice 4.4 — Persistent `WindowLayoutMemory`, `⌥`-Drag to Thirds & Per-Window Float/Retile Shortcuts (Pillar 10)
- **Effort:** `M` | **User Impact:** `High`
- **Reused Modules:** `Core/Support/WindowLayoutMemory.swift:7-59`, `App/Composition/WindowLayoutRestoreController.swift:10-110`, `Core/Support/WindowSnap.swift:77-130`, `Platform/Windows/WindowSnapService.swift:206-230`, `App/Composition/TilingEngine.swift:381-387, 495-505`, `Core/Support/Shortcuts.swift`
- **Scope:**
  1. [ ] Conform `WindowLayoutMemory` (`Core/Support/WindowLayoutMemory.swift:7`) to `Codable` and persist/load it in `WindowLayoutRestoreController` (`~/Library/Application Support/KatiKati/window-layouts.json`, included in `SettingsBackupService.applicationSupportFiles`).
  2. [ ] In `SnapDragMonitor.dragged()` (`Platform/Windows/WindowSnapService.swift:223`), pass `layout: NSEvent.modifierFlags.contains(.option) ? .thirds : .edgesAndCorners` to `SnapZonePlanner.resolve` so holding Option while dragging to an edge snaps into horizontal thirds.
  3. [ ] Add Command Bar commands (`tile float`, `tile retile`) and `ShortcutAction` cases for floating the focused window (`TilingEngine.shared.releaseWindow`) and re-tiling all hand-moved windows (`TilingEngine.shared.retileAll()`).
- **Verification Command:**
  ```bash
  xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:KatiKatiTests/WindowLayoutMemoryTests -only-testing:KatiKatiTests/WindowSnapTests -only-testing:KatiKatiTests/TilingLayoutTests && python3 Scripts/check_localization.py
  ```

---

## 4. Quick Wins ("Low-Effort, High-Impact" Top 10 List)

Each of these 10 quick wins reuses existing `Core/` or `Platform/` code and can land in a single `<= 300`-line slice with zero new dependencies and zero `project.pbxproj` changes:

1. [x] **DONE — `a2a7f546` · Fix Menu Bar Network Speed Readout (`Core/Support/MenuBarStatModel.swift:82-129`):** `MenuBarSystemItem` already samples `down`/`up` bytes/sec every second, but `MenuBarStatModel.statusText(metric: .network)` returns `"–"` because `fraction(metric: .network)` is `nil`. Formatting `values.down`/`values.up` in `statusText` makes the Network menu bar stat work immediately (~20 lines).
2. [x] **DONE — `ae014e00` · Surface Battery Cycle Count, Health % & Time Remaining in Battery Popover (`App/Composition/DockTelemetryFeed.swift:111-122`, `App/Scenes/DockWidgets/DockII/DockTelemetryWidgetView.swift:548-561`):** `BatteryHealthReader.read()` already parses `cycleCount` and `healthPercent` and `SystemMonitorSampler.battery()` already reads `secondsRemaining`, but `DockTelemetryFeed` discards all three. Passing them through `DockTelemetryState` adds cycle count, health %, and charge/discharge ETA in ~35 lines.
3. [ ] **Add Severe Weather Warnings & Moon Phase to `WeatherModernPanel` and `WeatherFullScreenView` (`App/Scenes/Weather/WeatherModernPanel.swift:62`, `App/Scenes/Weather/WeatherFullScreenView.swift:58`):** `WeatherWarningEngine` and `MoonPhase` are already tested in `Core/Support/`, but only legacy `WeatherGlanceView` renders `WarningsTile`, and no view renders `MoonPhase` (~45 lines).
4. [x] **DONE · Expose On-Device Vision Background Removal in `ShelfGridPopupView` (`App/Composition/ShelfActions.swift:218-258`, `App/Scenes/ShelfGridPopupView.swift:475-502`):** `ShelfActions.removeBackground(_:into:)` (`VNGenerateForegroundInstanceMaskRequest`) is completely implemented and tested, needing only a button in `floatingTransformBar` / `selectionBar` / `shelfMenuItems` (~30 lines).
5. [x] **DONE — `09c73eeb` · Wire `⌘1`–`⌘9` Pinned Paste Shortcuts & `Work` Category in `ClipboardFlyoutView` (`App/Scenes/Edge/ClipboardFlyoutView.swift:149-198`):** `ClipboardFlyoutView` already draws `"⌘1"`…`"⌘9"` badges on pinned clips and `All / Work / Personal` tabs, but `handleKey` ignores `⌘1`–`⌘9` and `classify` passes `originBundleID: nil` (~45 lines).
6. [ ] **Add Microphone Input Selector & Keyboard Backlight Slider to Control Centre (`Platform/SystemStatus/AudioOutputSwitcher.swift:14, 28, 58-76`, `Platform/Pinboard/QuickToggleEngine.swift:239-265`):** Both `AudioOutputSwitcher.devices(input: true)` and `KeyboardBacklight` are already implemented in `Platform/` and just need rows in `AudioOutputMenu` and `DockControlCenterSliderCard` (~50 lines).
7. [x] **DONE — `091c339c` · Fix DropClip Selection Pill Settings Toggle, Speech ARC Drop & Command Bar `"wifipw"` (`App/Entry/TranslatePanelController.swift:20-73`, `App/Scenes/CommandBarView.swift:62`):** Checking `DropClipPolicy.enabledKey`, retaining `AVSpeechSynthesizer` as a property, and changing `"wifi"` to `"wifipw"` in `CommandBarView.swift:62` fixes three user-visible bugs in ~25 lines.
8. [x] **DONE — `4e18742c` · Fix Multi-File ZIP Overwrite Bug in `DesktopFileOperations.compressToZip` (`Platform/Desktop/DesktopFileOperations.swift:178-185`):** Passing all file paths to a single `ditto` process instead of looping and overwriting `archiveURL` on each iteration fixes multi-file Desktop Box zipping in ~15 lines.
9. [x] **DONE — `cf03222f` · Stop 1 Hz Idle Timers in `HydrationController`, `NutritionController` & `QuitOnLastWindowService` + Share `SystemMonitorController.shared` (`Core/Support/HydrationController.swift:261`, `Core/Support/NutritionController.swift:195`, `App/Composition/QuitOnLastWindowService.swift:85`, `Platform/SystemMonitor/SystemMonitorController.swift:7`):** Gating timers on active consumers/thresholds and sharing one ref-counted `SystemMonitorController` eliminates unnecessary background wakeups (~50 lines).
10. [ ] **Hold `⌥` During Drag-to-Edge to Snap Windows into Thirds (`Platform/Windows/WindowSnapService.swift:223`, `Core/Support/WindowSnap.swift:109-124`):** `SnapZonePlanner.resolve` already supports `layout: .thirds`; passing `.thirds` when `NSEvent.modifierFlags.contains(.option)` in `SnapDragMonitor.dragged()` unlocks drag-to-thirds snapping in ~10 lines.
