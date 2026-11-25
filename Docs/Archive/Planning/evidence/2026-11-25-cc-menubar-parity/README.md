# Control Centre in the menu bar — parity with the edge host

Date: 2026-11-25 · `main` (`8f5d20ce` + this pass), Debug build driven by real pointer events
(`CGEvent`), macOS 26 on the 1710×1112 bench screen.

## What this pass changed

The home choice, the one-time alert and the Background Apps deck already existed on `main`. Two
parity gaps between the hosts did not:

- **The hosted Control Centre ignored the owner's layout.** `MenuBarHubPanelController` built
  `ControlCenterView` with `QuickToggleID.defaultOrder` and `TileKind.controlCenterDefault`, so a
  menu-bar home drew the factory tiles no matter what Quick Settings the owner had kept. It now takes
  `toggleOrder` / `widgets` from `AppSettingsStore` (as the edge panel already did) and drops any
  stored toggle a menu-bar panel cannot drive.
- **Its footer was inert.** Settings / Launcher / Capture / Drawer / Quit were no-op closures. They now
  hide the hub before opening the launcher or drawer, run `ScreenshotCommand.run()`, and terminate.
- **Settings clipped its own way back.** In a menu-bar home the standalone "Creative Hub is paused"
  note pushed the **Home** row out of the fixed-height detail pane. The note now rides on the Home row
  itself (`SettingsSegmentedRow(note:)`), so the row and its Edge / Menu Bar segments stay on screen.

## Seen on screen

1. Settings › Control Center › Home → **Menu Bar** raises the alert — *Control Centre is now in the
   Menu Bar / The edge Control Panel now shows Background Apps…* with **Keep in Menu Bar** and
   **Use Edge Instead** (`01`). Accepting writes `surface=menuBar` and `menuBarRolePromptSeen=1`.
2. The edge deck is now Background Apps: ten running apps, and the footer *Control Centre is now in
   the Menu Bar* + **Use Edge Instead** (`02`).
3. Clicking the status item opens the Control Centre dropdown at `1083,38 360×792`. With
   `controlcenter.toggles=darkMode,nightShift` and `preset=bento` written beforehand, it draws the
   Wi-Fi / Bluetooth hero cards, the bento order **and only those two toggles** (`03`) — the stored
   layout, not the factory one. One battery pill (`72 %`), System & Peripherals says *No connected
   devices report a battery* — no `This Mac` row.
4. **Launcher** in that footer opens the apps grid (`04`), proving the footer is wired.
5. **Use Edge Instead** in the Background Apps footer writes `surface=edge` and the same panel comes
   back as the Control Centre grid, still bento, still the two toggles (`05`) — the undo returns the
   owner to a panel they recognise.
6. From the restored edge home, `preset=classic` (`06`) and `preset=modular` (`07`) are visually
   distinct (classic pins Network/sliders to the bottom; modular moves System & Peripherals to a
   footer card and Network directly under the hero tiles).
7. With Control Centre back at the edge, the status item opens the Creative Hub again (`08`): the two
   homes remain mutually exclusive.

## After the pass

The three test keys (`controlcenter.surface`, `.preset`, `.toggles`) and the pass-only
`shortcut.quickSettings` were deleted; `menuBarRolePromptSeen` was cleared so a first switch still
prompts. The `/tmp` copy taken before the first switch did not survive the mid-pass reboot, so the
domain was returned to its pre-pass shape key by key instead of by file restore. `defaults read
com.katikati.app` afterwards lists no `controlcenter.*` key beyond the app-written
`showNowPlayingAnyway` default.

## Not checked here

- The Settings **Home** row was confirmed on screen with its Edge / Menu Bar segments visible, but this
  pass did not click the row back to Edge (pointing devices were busy elsewhere); the undo paths
  exercised were the alert's second button and the deck footer (5).
- No AX dump of the 360×792 dropdown: the menu-bar window is not exposed to System Events on this
  machine, so the reading above comes from the picture and the stored keys.
