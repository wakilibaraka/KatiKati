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

## Operated round trip (installed 0.18.0 (54), same day)

The fold-in fix was made so the Home row stays reachable in a menu-bar home, and this run operated that
control on the installed Release instead of only looking at it. The prefs were backed up to
`/tmp/kkprefs-rt/`, a distinctive layout was seeded (`preset=bento`, `toggles=darkMode,nightShift`), and
the app was restarted so the store read it.

1. Settings › Control Center › Home → **Menu Bar** (real click at the segment, 1265/1337 × 915 on this
   screen) raised the fresh prompt (`09`); **Keep in Menu Bar** wrote `surface=menuBar` and
   `menuBarRolePromptSeen=1`. In that state the Home row is on screen with **Menu Bar** tinted and
   **Edge** beside it (`10`) — the row the old stacked note had pushed out.
2. Repurposed surfaces before the switch: the deck is Background Apps with its undo footer, and the status
   item opens Control Centre with bento cards and only Dark Mode / Night Shift.
3. Clicking **Edge** in the same row wrote `surface=edge` with no second prompt, and Settings redrew with
   **Edge** tinted (`11`). The standalone panel opened as the bento Control Centre with the same two
   toggles and one battery pill (`12`), not the factory order.
4. The status item then opened the Creative Hub (`13`) — the homes stayed exclusive.
5. Back again: **Menu Bar** in the Home row wrote `surface=menuBar` again with no prompt (the key stays
   `1`), the dropdown drew the stored bento layout (`14`) and the deck was Background Apps with the undo
   footer (`15`).
6. Prefs were restored from `/tmp/kkprefs-rt/` and the app relaunched: no `controlcenter.*` or test
   shortcut key remains.

One honest detail about `10`: at the default scroll position the Home row sits at the page's cut — the
row and both segments are drawn and clickable, while the note folded under the label falls just past the
viewport edge. One wheel turn over the page brings the whole row and the sentence "Creative Hub is paused
while Control Centre is in the Menu Bar." into view (`16`) and the pane keeps scrolling to the rows below
(`17`), so nothing about the revert control needs a workaround. (The earlier note that this pane "did not
respond to synthetic wheel events" was a tooling artefact: plain `CGEvent` scrolls were ignored, while a
wheel event carrying begin/changed/ended scroll phases moves it.) The click at the row's centre landed on
the first attempt once the coordinate was taken from the segment rather than the gap beside it.

## After the pass

The three test keys (`controlcenter.surface`, `.preset`, `.toggles`) and the pass-only
`shortcut.quickSettings` were deleted; `menuBarRolePromptSeen` was cleared so a first switch still
prompts. The `/tmp` copy taken before the first switch did not survive the mid-pass reboot, so the
domain was returned to its pre-pass shape key by key instead of by file restore. `defaults read
com.katikati.app` afterwards lists no `controlcenter.*` key beyond the app-written
`showNowPlayingAnyway` default.

## Not checked here

- The Settings **Home** row was later operated (see the round trip below); what this first pass did not
  do was click it, so the undo paths exercised here were the alert's second button and the deck footer
  (5).
- No AX dump of the 360×792 dropdown: the menu-bar window is not exposed to System Events on this
  machine, so the reading above comes from the picture and the stored keys.
