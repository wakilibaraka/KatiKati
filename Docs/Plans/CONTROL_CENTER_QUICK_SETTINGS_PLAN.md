# Control Centre → Quick Settings Hub (`CC-1` → `CC-5`)

> **Status:** Complete (`2026-11-25`) · `CC-1` → `CC-4` landed (`9dfa2298`, `457e3648`, `cf516427`, `9082b956`, `a7c8b8d4`); `CC-3b` drawn Bluetooth rune done; `CC-5` verified — localization/debug/input gates green, 3922-test suite green, signed Release 0.18.0 (54) installed fresh. `CC-6` (the home choice: edge deck **or** menu-bar dropdown, with the one-time Background Apps notice) landed as `174eebde` on top of the menu-bar hosting work. Verified against the installed Release: **1.85 %** of one core and **358.2 MB** deep idle, one screenshot per preset, prefs restored — see §7 and `Docs/Archive/Planning/evidence/2026-11-25-cc-presets/`.
> **Guardrails:** `<= 300` LOC per commit · `0` `project.pbxproj` edits · `0` edits to the 5 frozen files
> (`WindowLiftAvoidanceController`, `AppTracker`, `DragController`, `AccessibilitySource`,
> `FullscreenIntentMonitor`) · `0.0 %` idle CPU · pure Core + tests before UI, every slice.

## 1. What already exists (grounded, not assumed)

| Concern | Where it lives today | Consequence for this plan |
|---|---|---|
| Panel shell, edge placement, Esc/outside-click, animation | `App/Entry/EdgeFlyoutController.swift` → `ControlCenterPanelController` (`show`, `panelFrame`, `railInset`, `bottomReserve`) | Do **not** build a second panel manager. Extend this controller with layout/preset hooks. |
| Panel content | `App/Scenes/Edge/StatusTrioView.swift` → `ControlCenterView` (~lines 140–1000) | All new rendering goes here (same file — keeps `project.pbxproj` untouched). |
| Menu Bar surface | `MenuBarCreativeHubView` (same file, MB-6a→6c) + `MenuBarHubPanelController` (`App/Composition/MenuBarSystemItem.swift:510`) | The hub already exists: left-click status item → 344×472 hub with `Switches` / `Status & Audio` tabs. Tandem work, not a rebuild. |
| Home of Control Centre | `ControlCenterSurfaceMode` (`com.katikati.controlcenter.surface`, `edge`/`menuBar`), `ControlCenterMenuBarSurface`, `ControlCenterHosting`, `ControlCenterEdgeRole` in `Core/Support/ControlCenterLayout.swift` | One stored choice decides **one** surface: the status item hosts either the Hub or Control Centre, and the edge deck hosts either Control Centre or Background Apps. `ControlCenterHosting.isExclusive` is the tested invariant. |
| Mutual exclusion | `App/Entry/AppDelegate.swift:106-114` (hub hides CC) and `:184-191` (CC hides hub), plus `.controlCenterSurfaceDidChange` closing whichever panel was open | Already correct. Keep it; only add the shared vocabulary. |
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
7. **Menu Bar tandem, not duplication — and the user picks the home.** Default (`edge`): Control Centre is
   the standalone deck and left-click on the status item is the Creative Hub — today's behaviour, unchanged.
   Choosing `menuBar` hands the panel to the status item and gives the deck a different job: the existing
   `BackgroundActivityDeckView`, so the two surfaces never show the same grid and never stack. Whichever home
   is chosen, both panels read one engine and one vocabulary: `QuickToggleEngine.shared`, `SystemStatusService`,
   `HubSwitchCatalog`; a new `Open Control Center` entry joins the right-click config's allowed tokens and
   `HubActionSlotID` gains `.controlCenter` so a hub box can still reach the panel.
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

### `CC-6` — Home: standalone deck or menu-bar dropdown (landed, `174eebde`)

Requested after `CC-5`: Control Centre may live as the **menu-bar dropdown**, and the standalone panel then
gets a different job instead of duplicating it.

- **One stored choice, one resolved host.** `ControlCenterSurfaceMode` (`edge` | `menuBar`, key
  `com.katikati.controlcenter.surface`, default `edge`) is read by `MenuBarSystemItem` (via
  `ControlCenterHosting.resolve`) and by `EdgeFlyoutController`; no panel builds its own decision.
  `ControlCenterHosting` exposes `menuBarShowsControlCentre`, `standaloneShowsBackgroundActivity` and
  `isExclusive` (`menuBarShowsControlCentre != standaloneShowsControlCentre`), pinned by
  `testHostResolvesExactlyOneSurfacePerMode` for every case, so the Hub and the dropdown can never stack.
- **The panel becomes Background Apps, and says so once.** `ControlCenterEdgeRole.implied(by:hasBeenTold:)`
  returns `needsPrompt` only when the deck takes the `backgroundActivity` role and the owner has not been
  told (`com.katikati.controlcenter.menuBarRolePromptSeen`). Settings › Control Center › **Home** shows the
  notice as a segmented `Edge` / `Menu Bar` row; switching raises one alert — “Control Centre is now in the
  Menu Bar” with “The edge Control Panel now shows Background Apps.” — offering **Keep in Menu Bar** (default)
  and **Use Edge Instead** (Escape). Both dismiss; the second writes `edge` back, so the choice is never a trap
  and never nags twice. The deck resolves to the existing `BackgroundActivityDeckView` — no new tracker.
- **No third “paused Hub” explanation gap.** Settings › Control Center, the Hub’s own Left-Click card and the
  right-click menu each say the Creative Hub is paused while Control Centre is in the menu bar.
- **Tests:** mode parsing/default, persistence round-trip, the exclusivity matrix, and the prompt truth table
  (`hasBeenTold` false→prompt, true→silent, `edge`→never). Localization carries both new strings ×12.

## 4. Assumptions (stated, not asked)
- `classic` preset = today's exact panel; existing users see no change until they pick a preset.
- Battery single-source defaults to the header pill (it is already the always-visible reading).
- Music dedupe defaults on only when another music surface is enabled; notch wins over the CC card.
- Resizing changes tile spans inside the fixed panel width; it never resizes the window (Size presets already
  do that).
- Presets may pin a minimum Size: `modular`/`bento` need ≥ 400 pt, so on `small` the packer falls back to
  one column and the Settings row notes it rather than silently switching Size.
- The home choice is the only thing that moves Control Centre, and the default keeps today's arrangement;
  Background Apps is the deck's replacement job because it already exists as a full view.

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

## 7. Verification record

Run on the installed `/Applications/KatiKati.app`, 0.18.0 (54), built by `Scripts/install_local_release.sh`
from this branch. Three evidence folders:

- `Docs/Archive/Planning/evidence/2026-11-25-cc-presets/` — menu-bar host, presets, ink crops, bench numbers.
- `Docs/Archive/Planning/evidence/2026-11-25-cc-edge-pass/` — edge host: presets, drag → Custom, Reduce
  Motion, AX dumps. Its `README.md` carries the method, the raw numbers and the limits.
- `Docs/Archive/Planning/evidence/2026-11-25-cc-dock-pass/` — dock-anchored panel (`side=right`,
  `anchor=bottom`): presets, drag → Custom, Reduce Motion, AX dumps, plus the dock-strip door measurement.

### Verified here

- **Presets on both hosts.** Menu-bar home captured earlier; the standalone edge panel captured now for
  `classic`, `modular` and `bento` from the shipped build, each built from the stored preset after closing
  and reopening the surface. AX reading order per preset matches the pictures
  (`ax-classic.txt`, `ax-modular.txt`, `ax-bento.txt`).
- **Drag → Custom, real pointer.** With the header's Edit pill pressed, a `CGEvent` pointer drag from the
  System & Peripherals card to the Network card moved it; `com.katikati.controlcenter.preset` became
  `custom` and the layout string moved `section.peripherals` after `section.nowPlaying`. After quitting and
  relaunching, the preset was still `custom` and the panel drew the dragged order
  (`drag-after-drop-edit-mode.png`, `drag-after-relaunch.png`, `ax-custom-after-relaunch.txt`). Repeated
  from a clean `classic` preset; both runs ended identically. The edit path's logic also passes 14
  standalone assertions over `move(_:before:)` and the codec/store.
- **Reduced Motion.** With the panel animation set to `slide` (the only animated choice; the shipping
  default is `instant`), window-server samples while opening show `alpha=0.00 x=1356 → alpha=1.00 x=1338`
  with motion on, and `alpha=1.00 x=1338` on the first sampled frame with Reduce Motion on: no slide, no
  fade, nothing behind an animation (`alpha-motion-on-slide.txt`, `alpha-reduced-motion-slide.txt`). Panel
  open/close and a preset switch were exercised under Reduce Motion; the panel was visible and reachable
  in AX immediately (`reduced-motion-modular.png`).
- **Accessibility per preset.** Every card is one named `AXGroup` (`System & Peripherals`, `Wi-Fi`,
  `Bluetooth`, `Network`, `Volume`, `Brightness`, `Manage accounts`). The 18 toggles are `AXButton`s that
  carry `value="On"/"Off"`. The battery pill is a single element (`desc="Battery"`,
  `AXValueDescription = 90%`) and the panel has no `This Mac` row, so the readout is not duplicated. The
  Network card's inner heading is hidden from AX so the card name is announced once.
- **Gates.** `check_localization.py`, `check_input_hygiene.py` and `check_debug_switches.py` all pass;
  Release build and install succeed; no new localized keys were introduced (Edit/Done/On/Off/Battery and
  the card titles already existed).
- **Idle CPU/RSS** — `Scripts/bench_katikati.sh --idle-only`: **1.85 %** of one core for KatiKati and
  **2.16 %** for its process group, **358.2 MB** resident (442.8 MB group) after a 120 s settle and a
  60 s sample. Two honest caveats: the sample needs one static window open because a not-yet-trusted fresh
  install enables AppKit automatic termination, and 0.32 % / 82.5 MB of the group is the existing
  `NowPlayingService` `swift-frontend` helper, not the panel. `powermetrics` rows are `n/a` (no passwordless
  sudo on this Mac).

### Dock-anchored pass

`side = right`, `anchor = bottom`, the panel flush to the dock's side of the screen. Method and raw
numbers in that folder's `README.md`; the head lines:

- **There is no separate dock-hosted panel object.** One `ControlCenterPanelController`, placed by
  `com.katikati.controlcenter.side` and `.anchor`. Measured: at the shipped height (994 pt, the whole band
  between menu bar and dock) `anchor = top` and `anchor = bottom` both land on `1338,50 360×994`, so the
  anchor picker changes nothing a user can see.
- **The dock strip is not a door to it.** A real `CGEvent` click on the strip's control chip (and an
  `AXPress` on the same element) opened a 660×620 popover at `64,428`; the standalone panel stayed ordered
  out (`onscreen=?`, absent from `AXWindows`). The drawer-capsule region changed no window. Captures in
  this pass therefore opened the panel with the app's own Quick Settings shortcut.
- **Presets redraw from the stored key** on the dock-anchored panel, one close/reopen each, three distinct
  frames (`panel-classic.png`, `panel-modular.png`, `panel-bento.png`).
- **Drag → Custom.** A `CGEvent` press/move/release from the toggle grid onto the Network card wrote
  `preset = custom` and `v1|custom|bento|…network:wide…`; after quit + relaunch the panel drew that layout
  (`panel-custom-after-relaunch.png`). Host difference from the edge run: the release must land on a card
  that does **not** re-flow; dropping into a toggle slot lifts the drag (`drag-in-progress.png`) but no
  delegate sees the drop, because the grid re-flows under the cursor mid-drag.
- **Reduced Motion.** `alpha=1.00 x=1338` on the first sampled frame with Reduce Motion on — instant
  branch, final geometry, no dependence on the fade/slide (`alpha-reduced-motion.txt`,
  `reduced-motion-bento.png`).
- **AX.** Panel window alone, 62 lines per preset: 7 named `AXGroup`s, 18 toggles with `value="On"/"Off"`,
  exactly one `desc="Battery"`, no `This Mac` row (`ax-classic.txt`, `ax-modular.txt`, `ax-bento.txt`,
  `ax-custom-after-relaunch.txt`).

### Commit size history

Every commit in this plan is under the 300-line cap except `8336876a` (the edge-pass evidence commit,
466 diff lines of raw AX dumps). `git reset` and `git commit --amend` are refused in this environment,
so that commit stands as the single over-cap exception; it is evidence-only and changes no source.

### Blocked, with the specific gate

- **Accessibility grant.** `Scripts/install_local_release.sh` runs `tccutil reset`, the Privacy pane shows no
  Accessibility row for the app, and adding it raises the Touch ID/password sheet, which is a user-only
  action. Behaviour above therefore ran with the project's existing `DOCK_DEV_SKIP_PERMISSIONS=1` switch;
  the AX and window-server evidence is unaffected by it, and only the global gesture paths it stands in
  for remain untested against a real TCC grant.
- **Reduce Motion toggled while running.** A system toggle changed mid-session was not picked up until the
  next launch in this build; launch-time behaviour is the verified half. Recorded as open below.
- **XCTest execution.** `xcodebuild build-for-testing` fails on this machine before reaching any test:
  `CameraMirrorService.swift:82 cannot find 'PermissionBootstrap' in scope` in the Debug configuration
  (exit 65), a build-graph problem unrelated to the Control Centre files. The new `ControlCenterEditTests`
  are therefore committed but unexecuted; the same assertions were run as a standalone harness instead.

### Still open

- `ControlCenterAnchor` is a no-op while the panel fills the band; either size the panel to content or drop
  the picker — not changed here, it needs a design call on the fill rule.
- The dock strip exposes no Control Centre door: its chips open their own popover. Either wire one to
  `onToggleControlCenter` or stop presenting the strip as a CC host.
- A drag dropped into a re-flowing toggle slot is lost; the release needs to resolve against the
  pre-drag frame (or the grid must not re-flow while `dragging != nil`).
- The live Reduce Motion toggle (above), if it turns out not to be a first-frame artifact.
- A real-TCC-grant pass over the global gestures once the grant can be given at the keyboard.
- Longer `powermetrics` wakeup figures once a passwordless sudo path exists on the bench machine.
