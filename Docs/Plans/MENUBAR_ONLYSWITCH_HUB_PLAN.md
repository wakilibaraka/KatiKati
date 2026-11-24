# Menu Bar Creative Hub (`Status Trio` + `Hop` 4-Box Grid + `OnlySwitch`)

> **Status:** Approved (`2026-11-24`) · Tier A (`MB-1` → `MB-8`), Tier B opt-in (`MB-9` → `MB-11`)  
> **Guardrails:** `<= 300` LOC per commit · `0` `project.pbxproj` edits · `0` edits to the 5 frozen files · `0.0%` idle CPU

## Locked Architecture Decisions
1. **Primary Status Item (`Status Trio` Ring):** Default icon (`MenuBarIconMode.statusTrio`, `Regular` stroke) with 1-click `Classic KatiKati Icon` fallback, `Light`/`Regular`/`Bold` strokes, adaptive monochrome template by default, plus `Settings › Menu Bar` toggles for `Semantic Alerts` and `Compact % Readout`.
2. **Left-Click Creative Hub (`Hop` 2×2 Grid + `OnlySwitch` Tabs):** Borderless `KeyableFlyoutPanel` + `DockGlassBackdrop` hosting a customizable 2×2 tactile action grid (defaults: `Keep Awake`, `Dark Mode`, `Capture/OCR`, `Dynamic Notch`; **zero color picker**) and 4 hideable tabs (`Switches`, `Status & Audio`, `Shortcuts & Evolutions`, `Schedules`).
3. **Customizable Right-Click Simple Menu:** Menu bar right-click (`menuBarContextMenu`) opens a clean, customizable toggle list + `Open Creative Hub`, `KatiKati Settings…`, `About KatiKati`, `Quit KatiKati`. **Taskbar/Dock right-click (`popUpFromTaskbar`) remains untouched.**
4. **Test Target Hygiene:** Keep `StatusMenuController.swift` free of `Platform/` imports via closure injection.

## Slice Roadmap
- [x] **`MB-1` (`Core`):** `NetworkLinkKind`, `MenuBarIconMode`, `StatusTrioStrokeWeight`, `StatusTrioRenderKey`, `MenuBarHubTab`, `HubActionSlotID`, `MenuBarRightClickConfig` + unit tests + `NOTICE`.
- [x] **`MB-2` (`Platform/Renderer`):** Event-driven `NWPathMonitor` link status + `toggleMute()` in `SystemStatusService` + cached `StatusTrioIconRenderer` in `MenuBarSystemItem`.
- [x] **`MB-3` (`Menu Bar Split`):** Left-click vs customizable right-click `NSMenu` in `StatusMenuController` (keeping `popUpFromTaskbar` untouched) + `MenuBarStatusCoordinator`.
- [x] **`MB-4` (`Core`):** `KatiKatiSurfaceToggle`, `HubSwitchID` / `HubSwitchCatalog`, `EvolutionItem` codec, `HubScheduleRule` + unit tests.
- [x] **`MB-5` (`Platform`):** `.muteOutput`/`.cleanKeyboard`, `ShortcutsCatalogRunner` (5 s watchdog), `EvolutionRunner`, `HubScheduleCoordinator`.
- [x] **`MB-6a` (`UI`):** `MenuBarHubPanelController` + `MenuBarCreativeHubView` shell (tab strip, search, customizable 2×2 action grid).
- [x] **`MB-6b` (`UI`):** `Switches` tab (AirPods ANC pill + searchable switchboard).
- [x] **`MB-6c` (`UI`):** `Status & Audio` tab (telemetry cards, output selector, volume/brightness/backlight sliders).
- [x] **`MB-7` (`UI`):** `Shortcuts & Evolutions` + `Schedules` tab views.
- [ ] **`MB-8` (`Settings + L10n`):** `Settings › Menu Bar` customization UI + 12-locale `Localizable.xcstrings` + `CHANGELOG.md`.
- [ ] **`MB-9`..`MB-11` (Tier B, Opt-In):** AI Agent switches (`MB-9`), macOS 14.2+ Per-App Audio Mixer (`MB-10`), App Uninstaller (`MB-11`).
