# Modern context menus — widgets and the other surfaces

Date: 2026-11-25 · `main`, debug build, locally signed.

## The grammar

`DockMenuChrome.header` (the Dock surface header already used by the trash, folder and taskbar
menus) now accepts an SF Symbol instead of an app icon. A new `MenuChrome` helper adds the rest of
the language: 15 pt template symbols on rows, quiet symbol + caption section labels that bring their
own separator, and submenus with the same leading icon. All labels reuse strings already in the
catalog, so no new localization keys.

## Surfaces changed

- **Strip widgets** (`WidgetMenuBuilder`): header with the section symbol, name, size/stack status,
  and Settings / Edit / Hide tiles; inline Size rows with checkmarks; iconised Style submenus;
  Layout and Position sections; iconised Widget Settings, Apply Preset, Edit Widgets and Hide.
- **App chips** (`LauncherChip`): app icon and name in the header, state pill when hidden, Open /
  Show–Hide / Edit / Quit tiles, and symbols on Open, Show, Hide and Customize Icon.
- **Live Island** (`LiveIslandMenuBuilder`): activity header (music / focus / timer / stopwatch /
  countdown / clock), Start–Pause, 25m, Keep Awake and Play–Pause tiles, Focus / Timer / Keep Awake /
  Now Playing sections with symbols.
- **Dock utility tiles** (`DockUtilityMenuBuilder`): Screenshots, Clipboard, Dictionary, Terminal and
  Downloads each open with their glyph, Open + Hide tiles (plus Capture Area or Paste Latest Plain),
  and symbolised rows.
- **Shelf** (`ShelfChip`) and **app groups** (`DockAppGroupChip`): header with item/app count and
  Open / Clear / Add Folder, or Open / Auto-Group / Delete tiles; rows and the Icon Grid submenu
  carry symbols.
- **Edge note tabs** (`DeckTab`): the four bare SwiftUI buttons became a native menu with the note's
  name and pin state, Pin / Archive / Delete tiles, a checked colour list and symbolised rows.

## What was seen on screen

1. Right-click the weather chip (`01`): header `Weather` with the `Medium` pill and three tiles
   (Settings, Edit, Hide), then Size (Small/Medium/Large, Medium checked), Temperature Unit,
   Weather Style, Layout (Smart Stack, Calendar/System/Devices in Stack), Position (Move Left/Right),
   Widget Settings…, Apply Preset, Edit Widgets, Hide. Not a bare list.
2. Right-click the Finder chip (`02`): header with the Finder icon and four tiles (Open, Show, Edit,
   Quit App), the recent folders, then Show / Hide App / Keep in Dock / App Groups / Customize Icon… /
   Close Window / Quit App with symbols.
3. Right-click the WhatsApp chip (`03`): same header shape with three tiles, then Open, Keep in Dock,
   Pin as App Icon, App Groups, Customize Icon….
4. Right-click the Clipboard utility tile (`04`): `Clipboard` header with Open and Hide tiles, then
   Open Clipboard / Hide rows.
5. The Live Island menu (`05`, showing alongside a widget menu in the same capture): `Now Playing`
   with Start–Pause, 25m, Keep Awake, Play–Pause tiles and the Focus / Timer / Keep Awake / Now
   Playing sections.

## What was not verified live

- Shelf, app-group and edge-note menus: neither a shelf item nor an app group was on the strip, and
  the note rail was not opened in this pass. They compile and share the same header/builder code.
- Desktop To-Do keeps its per-row SwiftUI menu (Important / Delete); the box itself still has no
  surface-level right-click.
- The Live Island capture shows two menus because the widget menu was also open; the island menu
  itself is the upper one.

## Checks

- `build_and_run.sh`: exit 0, app re-signed and relaunched.
- Full suite: 3845 tests, 2 skipped, 0 failures.
- Localization and debug-switch gates green (94 switches).
