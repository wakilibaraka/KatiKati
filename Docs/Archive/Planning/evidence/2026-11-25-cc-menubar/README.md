# Control Centre in the Menu Bar — live evidence

Date: 2026-11-25 · Debug build, locally signed, Accessibility grant intact.

## What the option does

`ControlCenterSurfaceMode` (`com.katikati.controlcenter.surface`) has two homes. `edge` is the
standalone deck; `menuBar` hands the panel to the status-item surface and turns the edge deck into the
Background Apps activity view (`EdgeFlyoutController` picks `BackgroundActivityDeckView`). The menu-bar
item hosts Control Centre or the Creative Hub, never both — `MenuBarHubPanelController` picks the root
by the same key.

The switch prompt (`ControlCenterEdgeRole.promptSeenKey`) is shown once, on the switch that moves
Control Centre to the menu bar. Both buttons dismiss it: **Keep in Menu Bar** (default) or **Use Edge
Instead**, which writes the surface back to `edge`; Escape is wired to the revert button. Switching
closes whichever surface is open (`AppDelegate.controlCenterSurfaceDidChange`) so the Hub cannot be
left floating behind Control Centre.

## What was seen

1. Fresh state (`surface=edge`, prompt key cleared), Settings › Control Center › Home = Edge.
   Clicking **Menu Bar** (`01`) raises the alert over Settings: title "Control Centre is now in the
   Menu Bar", the Background Apps explanation, buttons **Keep in Menu Bar** / **Use Edge Instead**;
   defaults already read `surface=menuBar`, `promptSeen=1`.
2. Clicking **Use Edge Instead** (`02`) wrote `surface=edge` and left the prompt key at 1 — the revert
   path works and does not re-nag.
3. Clearing the prompt key and switching again showed the same alert (`03`); **Keep in Menu Bar** wrote
   `surface=menuBar`, `promptSeen=1`.
4. Left-clicking the status item (`04`) opened the Control Centre dropdown — a 360×792 panel at
   1342,38 with the Wi-Fi / Bluetooth cards, quick toggles and Network sliders, not the Creative Hub.
5. Clicking the Dock capsule (`05`) opened Background Apps — 360×994 at 1338,50, AX title
   "Background Apps", rows `BetterAndBetter`, `Caffeine`, …; no alert.
6. Quit and relaunch: defaults still `surface=menuBar`, `promptSeen=1`. The status item again opened
   Control Centre (`06`, 360×792) and the capsule again opened Background Apps (`07`, no AXDialog in
   the tree — the prompt does not come back).
7. Settings › Home = **Edge** (`08`) wrote `surface=edge` with no prompt. The status item then opened
   the Creative Hub surface (`09`, hub toggles such as Now Playing / Notch / Desktop, no Wi-Fi cards),
   and the capsule opened the standalone Control Centre again (`10`, 360×994, Wi-Fi / Bluetooth).
8. After the revert, the Dock chip hub menus still open with header and tiles: trash chip `11`
   (`Trash` + Settings / Control Center / Auto-Hide / Position + Open Trash) and Downloads folder chip
   `12` (`Downloads` + the same four tiles + Preview Contents / Open in Finder / Sort by / Add Folder…
   / Remove from Taskbar).

## What was not verified

- The switch while the Creative Hub panel is physically open: the code hides it
  (`controlCenterSurfaceDidChange`), but the live pass switched from Settings, where no hub panel was
  up.
- Locale rendering of the two new button strings beyond English; all twelve catalogs carry values and
  the localization gate is green.
