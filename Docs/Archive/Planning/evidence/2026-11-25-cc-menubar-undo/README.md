# Control Centre in the menu bar — in-panel undo and row menus

Date: 2026-11-25 · `main`, debug build, locally signed.

## What was already there, and what this pass added

Current main already had the presentation switch (`ControlCenterSurfaceMode`, key
`com.katikati.controlcenter.surface`), the menu-bar host choosing `ControlCenterView` over the
Creative Hub, the edge deck choosing `BackgroundActivityDeckView`, and the one-time alert with
**Keep in Menu Bar** / **Use Edge Instead**. What it did not have was the requirement that the owner
can *see and undo* the change from the repurposed panel. This pass adds:

- **A footer in Background Apps** (`BackgroundActivityDeckView`): “Control Centre is now in the Menu
  Bar” and a **Use Edge Instead** button. It writes `edge`, posts
  `.controlCenterSurfaceDidChange` (closing the deck) and reopens the same panel as the Control
  Centre grid, so the undo is visible rather than a silent preference change.
- **Settings follows that undo**: the Home row listens to `.controlCenterSurfaceDidChange`, so an
  undo taken from the panel is reflected in Settings even while Settings stays open.
- **Shared-chrome row menus** in Background Apps: right-clicking an app opens the standard header
  (app icon, name), Open / Show / Quit App tiles, the same rows with symbols, and **Hide from
  Background Apps** (new catalog key, twelve locales). No bare lists.

## Seen on screen

1. Server state reset (`surface=edge`, prompt key cleared), Settings › Control Center › Home →
   **Menu Bar** raises the alert (`01`); **Keep in Menu Bar** writes `menuBar`, `promptSeen=1`.
2. The menu-bar item opens Control Centre: 360×792 at 1342,38, AX `Wi-Fi, Not Connected` (`04`).
3. The dock capsule opens Background Apps: 360×994 at 1338,50, AX title “Background Apps”, the app
   rows, and the new footer at the bottom — “Control Centre is now in the Menu Bar” plus
   **Use Edge Instead** (`05`).
4. Right-clicking a row opens the shared-chrome menu: header with the app icon and name, Open /
   Show / Quit App tiles, Open / Show / Quit App rows, and Hide from Background Apps (`06`).
5. **Use Edge Instead** in the footer wrote `surface=edge` and the same panel came back as the
   Control Centre grid (Wi-Fi / Bluetooth cards, sliders) (`07`).
6. With Settings open, the Home row showed **Edge** after that undo (`08`).
7. Switching to Menu Bar again, quitting and relaunching kept `menuBar` with no second prompt: the
   menu-bar item still opened the Control Centre dropdown (360×792, Wi-Fi, `09`) and the capsule
   still opened Background Apps with the undo footer (`10`).
8. Settings → **Edge** restored the standalone Control Centre (360×994, Wi-Fi card, `11`).

## Not covered

- The alert and the new footer text were rendered in English only; the other eleven catalogs carry
  the strings and the localization gate passes.
- The Creative Hub exclusivity was verified in the previous pass and is unchanged here (the host
  still picks one surface by the same key); this pass did not re-open the Hub.

## Checks

- `build_and_run.sh`: exit 0.
- Full suite: 3845 tests, 2 skipped, 0 failures.
- Localization and debug-switch gates green (94 switches).
