# Pinboard retirement (Phase 16m, 2026-10-13, owner-ordered full delete)

The full-screen / floating Pinboard widget wall is gone. Its content moved; nothing was
abandoned. Stored `com.katikati.pinboard.*` prefs are no longer read (fresh Control Center
prefs start from the defaults below).

## Where everything went

| Pinboard piece | Disposition | New home |
|---|---|---|
| Clock / Calendar / Weather / Now Playing / Countdown cards | already in the widget pane since 16a / Phase 5 | `CalendarPanelView.swift` (`TileKind`) |
| Calculator / Screen Time / Network / Battery / Top Apps / Batteries cards | ported 16k | `CalendarPanelView.swift` (same services, `TileKind`) |
| Network / Battery / Batteries on the widget pane | removed from the pane 2026-10-13 (owner: this page keeps Calculator, Screen Time, Top Apps); still hosted in the Control Center | `ControlCenterView` |
| Weather / System / Bluetooth on the widget pane | removed from the pane 2026-10-13 with their tile structs, `TileKind` cases and accents (owner); deck buttons keep their own flyouts | — |
| Now-playing tile on the widget pane | removed 2026-10-13 with its struct, `TileKind` case and accents (owner); lives in Quick Settings on the live MediaRemote feed | `ControlCenterView` now-playing card |
| Calculator / Screen Time / Top Apps in Quick Settings | removed from the CC default 2026-10-13 (owner); stay on the widget pane; stored-old extras filtered at read | `TileKind.controlCenterDefault` |
| Network / Battery / Batteries full tiles | replaced by compact rows in Quick Settings 2026-10-13 (owner: no-scroll panel); full-tile structs deleted | `ControlCenterNetworkRow` / `BatteryRow` / `BatteriesRow` |
| Battery + Batteries rows in Quick Settings | merged into one topmost card 2026-10-13 (owner); either Settings pick shows it (This Mac follows battery, devices follow batteries) | `ControlCenterBatteryCard` |
| Quick Settings sliders | moved to the bottom (volume, brightness, keyboard) 2026-10-13 (owner) | `ControlCenterView` body order |
| Quick Settings card (14 switches + True Tone + VPN) | the Control Center grid | `ControlCenterView` (`StatusTrioView.swift`) |
| Right-FAB opener, `⌃⌥Space`, CC utility row | repointed 16l | `ControlCenterPanelController.toggle()` |
| `.weather` / `.clock` shortcut single-views | repointed 16l | `WidgetPanelController.weather` / `.calendar` |
| `PinboardWidget` / `PinboardLayout` / `PinboardStyle` / `PinboardPlacement` / `PinboardGrid` | deleted 16m | — (no replacement; wall packing retired) |
| `com.katikati.pinboard.style/widgets/toggles/keepOnTop/origin` | deleted 16m, not migrated | superseded by `com.katikati.controlcenter.toggles/widgets/side` |
| Keep-awake behind the Pinboard panel | rewired 16m | `QuickToggleEngine.shared` (shortcut, runtime, toast) |
| `QuickToggleID` + `VPNServiceParser` | kept, moved verbatim 16m | `Core/Support/QuickToggles.swift` |
| `BatteryHealth` / `TopProcess*` + readers | kept, moved verbatim 16m | `SystemMonitorMath.swift`, `Platform/SystemStatus/SystemHealthReaders.swift` |
| Platform `VPNService` duplicate | merged 16m (paid the 16i-2 debt) | thin wrapper over `VPNServiceParser` |
| `ShortcutAction.pinboard` raw value | kept (stored bindings survive; fires the Control Center; labeled "Control Center" since 16n) | `Core/Support/Shortcuts.swift` |
| `Platform/Pinboard/` directory name | kept (engine + pinch monitor live there) | — |

## Strings

Removed keys: `Pinboard`, `Calendar`, `Pinboard Style`, `Full Screen`, `Floating Panel`,
`Reset Pinboard Position`, `Keep Pinboard on Top`, `Quick Settings Switches`.
Added keys: `Control Center`, `Side` (drafts, see `Docs/translation-review-phase16.csv`).
