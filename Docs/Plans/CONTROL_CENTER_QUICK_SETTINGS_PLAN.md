# Control Centre → Quick Settings Hub (`CC-1` → `CC-5`)

> **Status:** Complete (`2026-11-25`) · `CC-1` → `CC-4` landed (`9dfa2298`, `457e3648`, `cf516427`, `9082b956`, `a7c8b8d4`); `CC-3b` drawn Bluetooth rune done; `CC-5` verified — localization/debug/input gates green, 3921-test suite green, signed Release 0.18.0 (54) installed fresh. Idle CPU was not re-measured during the final pass because the desktop was in active use.
> **Guardrails:** `<= 300` LOC per commit · `0` `project.pbxproj` edits · `0` edits to the 5 frozen files
> (`WindowLiftAvoidanceController`, `AppTracker`, `DragController`, `AccessibilitySource`,
> `FullscreenIntentMonitor`) · `0.0 %` idle CPU · pure Core + tests before UI, every slice.

## 1. What already exists (grounded, not assumed)

| Concern | Where it lives today | Consequence for this plan |
|---|---|---|
| Panel shell, edge placement, Esc/outside-click, animation | `App/Entry/EdgeFlyoutController.swift` → `ControlCenterPanelController` (`show`, `panelFrame`, `railInset`, `bottomReserve`) | Do **not** build a second panel manager. Extend this controller with layout/preset hooks. |
| Panel content | `App/Scenes/Edge/StatusTrioView.swift` → `ControlCenterView` (~lines 140–1000) | All new rendering goes here (same file — keeps `project.pbxproj` untouched). |
| Menu Bar surface | `MenuBarCreativeHubView` (same file, MB-6a→6c) + `MenuBarHubPanelController` (`App/Composition/MenuBarSystemItem.swift:510`) | The hub already exists: left-click status item → 344×472 hub with `Switches` / `Status & Audio` tabs. Tandem work, not a rebuild. |
| Mutual exclusion | `App/Entry/AppDelegate.swift:106-114` (hub hides CC) and `:184-191` (CC hides hub) | Already correct. Keep it; only add the shared vocabulary. |
| Sizes / anchor / skin / animation | `Core/Support/ControlCenterLayout.swift` — `ControlCenterSize` (300/360/440), `ControlCenterAnchor`, `ControlCenterStyle` (`classic`/`ipad`), `ControlCenterAnimation`, `ControlCenterGrid` (4→5 columns) | Presets extend this file; do not replace these keys. |
| Toggles | `Core/Support/QuickToggles.swift` — `QuickToggleID` (20 cases), `HubSwitchID`/`HubSwitchCatalog` (order + hide + search, already shared with the hub) | Reuse `HubSwitchCatalog` as the CC tile catalogue so both surfaces show one vocabulary. |
| Widget tiles | `TileKind.controlCenterDefault = [.network, .battery, .batteries]` (`Core/Support/CalendarPanelModels.swift:276`) | Battery/peripherals/network are already opt-in widgets — the dedupe model plugs in here. |
| Theme / glass | `DockThemeStyle` (13 presets + `auto`/`custom`) and `ThemeTuning` (vibrancy/contrast/translucency), injected through `\.dockThemeStyle` / `\.themeTuning` | CC already wears the dock's plate. "3 glass styles" = a CC-local finish modulator, **not** a second theme system. |
| Settings page | `App/Scenes/SettingsLayoutPane+ControlCenter.swift` (Style / Side / Size / Anchor / Animation, widget + toggle checklists) | Presets, glass, dedupe and Customize live here. |
| Settings stage preview | `App/Scenes/Settings/SettingsStagePanels.swift` → `StageControlCenter` | Must learn tile spans, or the thumbnail lies about the layout. |
| Tests | `Tests/Unit/ControlCenterScrollTests.swift` already hosts `ControlCenterGridTests` | Put CC model tests in this existing file: a new test file would need a `project.pbxproj` append. |

### Verified defects on `main` today
1. **No `bluetooth` SF Symbol exists.** Checked locally on macOS 27.2.1:
   `NSImage(systemSymbolName: "bluetooth")` → `nil`. `antenna.radiowaves.left.and.right`,
   `dot.radiowaves.left.and.right`, `wave.3.forward` all resolve. So the "proper Bluetooth icon" must be a
   **drawn rune** (vector path), not a symbol rename.
2. **Three different Bluetooth glyphs are in use.**
   `dot.radiowaves.left.and.right` (`QuickToggleID.symbolName`, `DockControlCenterWidgetView.swift:99`),
   `antenna.radiowaves.left.and.right` (`App/Scenes/Edge/DeckViews.swift:173`), `wave.3.forward`
   (`InlineQuickTogglePill`, same `StatusTrioView.swift`). One rune, one source.
3. **Battery is printed twice** in the panel: header `batteryPill` *and* the `System & Peripherals` card's
   "This Mac" row (`ControlCenterView.peripheralsCard`), plus a third time in the Menu Bar Status Trio.
4. **Now Playing is duplicated across surfaces**: CC `nowPlayingCard`, hub `Status & Audio`, notch music page,
   dock music widget — all reading the same `NowPlayingService.shared`, with no "owned elsewhere" rule.
5. **Ordering is not user-controlled for toggles** — `controlCenterToggles` is filtered against
   `QuickToggleID.defaultOrder`, so the panel order is always `allCases` order; the checklist only hides.
6. **No per-tile size model.** `ControlCenterGrid` chooses 4-or-5 equal columns; nothing can be wide/hero.

## 2. Design decisions locked for this plan

1. **One panel, three presets, custom on top.** `ControlCenterPreset`: `classic` (today's layout, byte-for-byte
   default), `modular` (iOS/iPadOS: connectivity hero + square 2×2 tiles + tall slider tiles), `bento`
   (HyperOS: dense mixed-span grid, hero brightness/volume). Editing any tile flips the preset to `custom`
   with `basedOn` recorded, so the user never loses the preset they started from.
2. **`ControlCenterStyle` stays the skin** (`classic`/`ipad`). Presets choose a default skin but do not remove
   the existing key (`com.katikati.controlcenter.style`) — no migration, no behaviour delta for existing users.
3. **Tile identity is wider than `QuickToggleID`.** `ControlCenterTileID` = `.section(ControlCenterSection)` |
   `.toggle(QuickToggleID)`, where sections are `header`, `peripherals`, `connectivity`, `nowPlaying`,
   `network`, `sliders`, `utilities`, `account`. Toggles come from the shared `HubSwitchCatalog`.
4. **Sizes:** `.icon` (glyph only), `.standard` (today's cell), `.wide` (2 columns), `.hero` (full width, with
   a live detail line). Sections are `standard`/`hero` only. A pure packer resolves spans to rows; below
   ~400 pt it degrades to a single column instead of clipping (tested).
5. **Dedupe is opt-out, not magic.** `ControlCenterDedupe` takes `(enabledTiles, surfacesOn, options)` and
   returns suppressed sections:
   - `singleBattery` (default **on**): header pill keeps the reading; the "This Mac" row is hidden when the
     pill is visible. The peripherals *device* list is unaffected.
   - `singleNowPlaying` (default **on when** the notch or dock music surface is enabled): CC hides its
     now-playing card and offers a "Show anyway" override in Settings.
   - The rules never hide a section the user explicitly re-enabled in edit mode.
6. **Glass = finish, not theme.** `ControlCenterGlassStyle` `.clear` / `.semi` / `.tinted` maps to
   (plate material, card fill alpha, tint mix) values layered on the dock theme's own colours; macOS 26
   `#available` glass path stays behind its existing gate.
7. **Menu Bar tandem, not duplication.** Left-click stays the hub; Control Centre stays the edge deck. Both
   read `QuickToggleEngine.shared` and `SystemStatusService`; the hub's `Switches` tab and the CC catalogue
   share `HubSwitchCatalog`; a new `Open Control Center` entry joins the right-click config's allowed tokens;
   `HubActionSlotID` gains `.controlCenter` so a hub box can open the deck.
8. **Zero new files** (hence zero `project.pbxproj` edits): models → `Core/Support/ControlCenterLayout.swift`,
   UI → `App/Scenes/Edge/StatusTrioView.swift`, settings → `SettingsLayoutPane+ControlCenter.swift`,
   stage → `SettingsStagePanels.swift`, tests → `Tests/Unit/ControlCenterScrollTests.swift`.

## 3. Slices

### `CC-1` — Read-only grounding & fresh-install baseline (no source edits)
- Back up `~/Library/Preferences/com.katikati.app.plist` to `/tmp/katikati-prefs-<date>.plist`
  (**never** `defaults delete` without a restore copy — the real profile is in use).
- Relaunch through `Scripts/build_and_run.sh` (never bare `xcodebuild` + `open`), then
  `Scripts/bench_katikati.sh --idle-only` for idle CPU/RSS.
- Capture, at 300/360/440 pt and both skins: header, peripherals, connectivity, now-playing, grid, sliders,
  utilities, account; count duplicate battery/music readings visible at once.
- Record: default key set, panel frame per screen, grid columns chosen, Bluetooth glyph actually drawn.
- **Exit:** baseline note in `HYBRID_PLAN.md`, numbers in the slice note, zero diff.

### `CC-2` — Pure Core: presets, tile model, packer, dedupe, glass (+ tests)
- Add to `Core/Support/ControlCenterLayout.swift`:
  `ControlCenterPreset`, `ControlCenterLayoutSpec`, `ControlCenterSection`, `ControlCenterTileID`,
  `ControlCenterTileSize`, `ControlCenterTileSpec`, `ControlCenterPacker`, `ControlCenterDedupe`,
  `ControlCenterGlassStyle`, `ControlCenterLayoutCodec` (versioned `...layout.v1`, tolerant parse).
- Tests in `Tests/Unit/ControlCenterScrollTests.swift`: preset parity for `classic`; packer
  (span→row, no dangling gaps, stable order, 1-column degradation, unknown tokens dropped);
  dedupe truth table; glass clamping; codec round-trip + legacy fallback.
- **Exit:** `./Scripts/build_and_run.sh --test -only-testing:KatiKatiTests/ControlCenterLayoutTests`
  (+ `ControlCenterScrollTests`, `ControlCenterGridTests`) green; no UI change.

### `CC-3` — Bluetooth rune, sized tiles, one source of truth for glyphs
- `BluetoothRune: Shape` (normalised 21-pt rune, `stroke` 1.9, round caps) + `BluetoothGlyph` wrapper;
  replace `dot.radiowaves.left.and.right` in `QuickToggleID.symbolName`, `DockControlCenterWidgetView`
  and `InlineQuickTogglePill`; keep `symbolName` as the fallback for non-SwiftUI surfaces.
- Render `.icon`/`.standard`/`.wide`/`.hero` via `ControlCenterPacker`; `classic` preset must be
  pixel-identical to today (witness screenshot pair).
- **Exit:** targeted test run + before/after shots in `build/shots/`; ⌘-click labels unchanged.

### `CC-4` — Presets UI, Edit mode, glass, dedupe, Menu Bar sync
- Settings card: preset grid (same `presetCard` shape as `SettingsLayoutPane+Launcher.swift`), glass
  segmented row, dedupe toggles, "Customize…" and "Reset to preset".
- Edit mode in `ControlCenterView`: toolbar pill, drag-to-reorder (`onDrag`/`onDrop` with a Core
  `move(_:moving:before:)` helper modelled on the launcher's), size cycle (badge click), add/remove from
  `HubSwitchCatalog`, live "unsaved changes" state; panel keeps Esc/outside-click behaviour.
- Glass finish applies to plate + card fill only; dock theme colours untouched.
- Menu Bar: `MenuBarRightClickConfig.allowedTokens += "openControlCenter"`; `HubActionSlotID.controlCenter`;
  CC gained a "Menu Bar" row showing the hub's current open shortcut? (no — see assumptions).
- Stage thumbnail learns spans (`StageControlCenter`) so Settings does not preview a layout that never ships.
- **Exit:** targeted tests + three preset screenshots + edit-mode recording; idle CPU still `0.0 %`.

### `CC-5` — 12-locale gate, full suite, signing, livecheck, docs
- New keys (hand-appended ×12, integrator hot file): `Presets`, `Customize`, `Done`, `Reset Layout`,
  `Clear`, `Semi`, `Tinted`, `Tile Size`, `Small`, `Standard`, `Wide`, `Hero`, `Add Tile`,
  `Single Battery Readout`, `Single Now Playing`, `Show Anyway`, `Based On`, `Open Control Center`.
  (`Customize` is absent from the 2,574-key catalogue today; the rest are new.)
- Gates: `check_localization.py`, `check_debug_switches.py` (only if a `DOCK_*` switch is added — plan: none),
  `check_availability_warnings.py /tmp/katikati-test.log` from a **clean** build, full `xcodebuild test`,
  signing report, `bench_katikati.sh --idle-only`, fresh-install livecheck with prefs restore.
- Docs: `CHANGELOG.md`, `HYBRID_PLAN.md` CC section, `LANES.md` claim (lane B owns `ControlCenter*`).

## 4. Assumptions (stated, not asked)
- `classic` preset = today's exact panel; existing users see no change until they pick a preset.
- Battery single-source defaults to the header pill (it is already the always-visible reading).
- Music dedupe defaults on only when another music surface is enabled; notch wins over the CC card.
- Resizing changes tile spans inside the fixed panel width; it never resizes the window (Size presets already
  do that).
- Presets may pin a minimum Size: `modular`/`bento` need ≥ 400 pt, so on `small` the packer falls back to
  one column and the Settings row notes it rather than silently switching Size.

## 5. Risks
- `StatusTrioView.swift` is already 1,515 lines and holds the hub too; adding four tile sizes risks a file
  that is hard to review. Mitigation: one view per size as small `@ViewBuilder` helpers, and each slice's
  diff stays under 300 lines.
- Drag-and-drop inside a non-activating `NSPanel` can swallow `mouseDown`; the panel already takes key when
  shown, but verify drag start on first click (witness recording).
- Dedupe rules interacting with the notch/dock music settings could hide a card the user expects; the
  "Show anyway" override and the stage preview are the guardrails.
- `check_availability_warnings.py` needs a clean-build log; incremental logs make the gate meaningless.

## 6. Copy-paste prompt (Antigravity / DeepSeek — no brackets)
```markdown
Use ponytail and impeccable design skills (no square brackets). Work read-only first on main: investigate
the existing Control Centre, Quick Settings, Menu Bar hub, glass, icon and settings code, then report and
wait for my go-ahead before editing any Swift file.

Constraints: zero edits to KatiKati.xcodeproj/project.pbxproj; keep WindowLiftAvoidanceController.swift,
AppTracker.swift, DragController.swift, AccessibilitySource.swift and FullscreenIntentMonitor.swift
untouched; at most 300 diff lines per commit; pure Core models plus synchronous unit tests before UI;
run check_localization.py, check_debug_switches.py and check_availability_warnings.py on every slice.

Already true on main: ControlCenterView lives in App/Scenes/Edge/StatusTrioView.swift, hosted by
ControlCenterPanelController in App/Entry/EdgeFlyoutController.swift; the Menu Bar Creative Hub (MB-1..MB-6c)
already exists in the same file and MenuBarSystemItem.swift; ControlCenterStyle already has classic and ipad;
there is no SF Symbol named "bluetooth" (verified on macOS 27), so the Bluetooth glyph must be drawn.

Plan CC-1..CC-5 exactly as written in Docs/Plans/CONTROL_CENTER_QUICK_SETTINGS_PLAN.md.
```
