# Menu-bar Control Centre — exclusivity explained, row actions proven

Date: 2026-11-25 · HEAD after the SideDeck merge · debug, locally signed.

This pass re-checked the two things the previous one left unproven on the rebased tree, repaired
what was missing, and drove both on screen.

## 1. Control Centre dropdown ↔ Creative Hub, both directions

Both surfaces are still the one status item, chosen by `ControlCenterSurfaceMode` inside
`MenuBarHubPanelController.show` (the menu-bar item) and `ControlCenterPanelController.show` (the
deck); neither builds a second engine. Quick toggles stay on `QuickToggleEngine`, status reads on
`SystemStatusService`, and the switch vocabulary on `HubSwitchCatalog` — no duplicate paths were
added.

What was missing was the *explanation*. Before this pass the Hub did not vanish without a trace —
the right-click row was renamed “Control Centre” — but nothing said where the Hub went, and
Settings kept offering Hub customisation with no hint that it was paused.

- `StatusMenuController.rebuildMenuBarContextMenu` now puts a gray, disabled
  **“Creative Hub is paused while Control Centre is in the Menu Bar.”** row (pause symbol) above the
  **Control Centre** row while the dropdown presentation is on. Spelled inline with
  `NSImage(systemSymbolName:)` because this controller is compiled into the test target, which has
  no scene layer — the same symbol-plus-gray-row grammar, without importing `AppMenuFragments`.
- Settings › Control Center shows the same line directly above the **Home** row while Menu Bar is
  selected (`ControlCenterAppearanceSettings`).
- Settings › Menu Bar’s **Left-Click Creative Hub** card shows it at the top of the card while the
  dropdown owns the icon (`MenuBarHubSettingsBlock`), so the Hub’s own settings page says why its
  toggles are idle.
- Both new views re-read the stored surface; the note disappears when Edge is chosen again.

### Seen on screen

1. **Edge**: Settings › Control Center with Home on Edge, no note (`01`); the status item opens the
   Creative Hub — 380×570 at 1322,38 (`02`).
2. **Menu Bar**: Settings shows the pause line above Home (`03`); the status item opens Control
   Centre — 360×792 at 1342,38, Wi-Fi and Bluetooth cards (`04`).
3. **The Hub refuses, in words**: right-click on the icon shows the gray pause line, then
   **Control Centre**, Settings, About, Quit (`05`).
4. **Edge again**: `surface=edge`, and the same icon opens the Creative Hub again (`07`); Settings
   loses the pause line (`01`).

The menu you can see in `02`/`07` is the Hub’s Switches tab (2×2 box grid + switch rows); it was
mistaken for a context menu mid-session and re-checked.

## 2. Background Apps row menu, every action

`BackgroundActivityDeckView.menu(for:)` keeps the shared chrome: `DockMenuChrome.header` with the
real app icon, name, and Open / Show / Quit App tiles, then the `MenuChrome` rows for the same three
actions and **Hide from Background Apps**.

- **Open** and **Show** were one `activate` call away from a no-op: a windowless agent can refuse
  activation. Both now unhide first, and fall back to `NSWorkspace.openApplication(at:)` when
  `activate` returns false; Show always exits the hidden state.
- **Hide** wrote the shared ignore list and the row disappeared, but there was no way back from the
  deck. The deck now shows a compact strip — count + **Show Hidden Apps** — whenever that list is
  non-empty; it calls the same `BackgroundAppsStore.unignoreAll()` as Settings › Behavior’s
  “Reset Ignored Apps”.
- **Quit** terminates through `NSRunningApplication.terminate()`.

### Seen on screen, with process state read back

- Chrome renders (`09`: header wells Open/Show/Quit App, name, rows, Hide).
- **Hide** on BetterAndBetter: row disappears, `com.katikati.drawer.backgroundIgnored` becomes
  `("cn.better365.BetterAndBetter")`, and the deck shows the hidden strip (`10`).
- **Show Hidden Apps**: preferences back to empty and the BetterAndBetter row returns (`11`).
- **Show** on Claude after hiding it (`visible=false`): the row menu ran, and System Events read
  `visible=true` afterwards.
- **Open** on hidden Claude: `visible=true` and Claude became the frontmost process (`12`).
- **Quit App** on Caffeine: pid 99137 was gone after the click (`13`); Caffeine was relaunched.

## Checks

- App build: exit 0.
- Full suite: 3914 tests, 2 skipped, 0 failures (run twice; the first attempt exposed the
  test-target import and was fixed by keeping `StatusMenuController` scene-free).
- Localization gate ✅ (two new keys × 12 locales), debug-switch gate ✅, input hygiene ✅.
- Presets, single battery and single Now Playing were not touched; their unit tests pass, the
  Settings pane still shows Classic/Modular/Bento and both dedupe switches (`03`).
