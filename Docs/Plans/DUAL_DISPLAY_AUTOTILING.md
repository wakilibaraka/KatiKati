# Dual-Display Auto-Tiling Plan — `AT-1` baseline → `AT-9`

> **Status:** baseline captured 2026-11-27 on `main` (`b34679a3`). Tiling and workspaces were **off**
> for the capture, so window frames below are the last session's leftovers, not a live layout.
> Read-only capture: `build/live-check/topology.swift` (untracked harness). No Swift file, no
> `project.pbxproj` and none of the five behaviour-frozen files were touched.

## 1. Live baseline

### 1.1 Displays

| | Built-in Retina | LG HDR 4K |
|---|---|---|
| UUID | `37D8832A-2D66-02CA-B9F7-8F30A301B230` | `6A565C28-B527-4316-9C88-E604AB4BAF23` |
| Role | builtin, main | external |
| `frame` (Cocoa) | `0,0 1710×1112` | `−164,1112 1920×1080` |
| `visibleFrame` | `0,0 1710×1074` | identical to `frame` (no Dock, no menu bar) |
| Scale | 2.0 | 2.0 |
| Notch | `safeAreaInsets.top = 37.5` | `0` |
| Menu bar | 38 pt | 0 pt |

The LG sits **above** the built-in and overhangs it by 164 pt left / 46 pt right. Its work area is
the full screen: any per-display outer gap has to come from the profile, never from `visibleFrame`.

**UUID churn is real:** `Docs/Plans/MULTIDISPLAY_OPTIMIZATION_PLAN.md` recorded the same LG as
`402CE39A-032C-4ABE-A1DE-98681D3D3786`. Profiles therefore resolve **UUID → display name → role**,
and the role default is the final fallback.

### 1.2 Spaces

`com.apple.dock mru-spaces = 0` — Space order is stable, so `(display, space index)` is a usable
key for naming and cap badges. KatiKati's own workspaces remember `active = 10` for the LG.

### 1.3 Windows at capture (tiling off)

| Display | Windows |
|---|---|
| LG | TextEdit `940×978` at `x −152`, `940×978` at `x 804`, `580×360` at `1176,−1000`; Safari `940×978`; YouTube Music `940×978` |
| Built-in | 18 app windows, none tiled |

The three TextEdit frames are the previous session's two-half layout plus the parked third window
(`580×360` at the right edge). Nothing in the engine caps that to the display.

## 2. Gaps this plan closes

1. **No per-display geometry.** `TilingGaps` and `mainRatio` are one global pair; the LG and the
   notched built-in need different gaps and ratios.
2. **No explicit window cap.** `TilingOverflow` evicts only when a tile would be smaller than
   `360×240`; it cannot express "at most four windows per Space".
3. **No overflow choice.** An over-cap window has one behaviour today (stay floating where it was).
4. **No display targeting in workspace rules.** `=display:` exists only in `TilingPolicy`.
5. **No app categories.** Six media apps have to be listed by bundle id, and there is no
   "watching app" rule at all.
6. **No media notch rule.** A notchless display keeps the wide bar while a video is fullscreen.
7. **No workspace names.** The HUD, bar and control socket only know `1…10`.
8. **No retile on native Space change.** Switching the macOS Space does not re-run the pass.
9. **snApp is fixed.** Five unlabelled 92×62 cards, always anchored to the pointer, no density or
   size choice.

## 3. Decisions

- Placement/routing runs on **KatiKati Workspaces**; native Spaces only supply names and badges.
  No `SLSMoveWindowsToManagedSpace` (dead under SIP on macOS 15–27).
- Over-cap default is **Float Centered**; "throw to the other display" is per-display opt-in and
  "next workspace" reuses the existing route/park machinery.
- Multi-display management is its **own toggle**, default off. Enabling it with no saved profiles
  seeds: external **Main+Stack 58/42, gaps 8/10, cap 4**; built-in **Main+Stack 55/45, gaps 6/8,
  cap 2**. No new solver preset — the bundle is profile + existing preset.
- snApp gains placement (pointer / centre / below notch / below menu bar / full-screen), density
  (compact / regular / large), named size cards (Full, Centre, Comfortable, Focus, top/bottom
  halves) and visible labels.
- No new timers, no global mouse monitors. The snapshot stream and
  `NSWorkspace.activeSpaceDidChangeNotification` are the only triggers.

## 4. Slices

| Slice | Deliverable | Files |
|---|---|---|
| AT-1 | this baseline + probe | `build/live-check/topology.swift`, this doc |
| AT-2 | `DisplayTilingProfile`, role resolution, store, per-display gaps/ratio | `Core/Support/TilingPolicy.swift`, `App/Composition/TilingEngine.swift` |
| AT-3 | `SpaceWindowCap` + overflow policies + centered spill frame | `Core/Support/TilingLayout.swift`, `Core/Support/TilingGaps.swift`, engine |
| AT-4 | app categories, `=display:` and `=hideIsland` rules, island media policy | `Core/Support/WorkspaceRules.swift`, `Core/Support/NotchBehavior.swift`, engine, `App/Entry/NotchPanelController.swift` |
| AT-5 | workspace names, cap badge, HUD + control `status` + Mission Control pill | `Core/Support/Workspaces.swift`, `WorkspaceHUD*`, `WorkspaceControlServer`, `PanelCoordinator+Spaces` |
| AT-6 | Settings: separate multi-display card, per-display rows, preset button, names table | `App/Scenes/SettingsTilingPane.swift`, `Resources/Localizable.xcstrings` |
| AT-7 | snApp core: placement, density, size cards, expanded catalog | `Core/Support/WindowSnap.swift` |
| AT-8 | snApp UI: labelled adaptive grid, placement math, settings rows | `App/Entry/SnapPickerController.swift`, `App/Scenes/BehaviourSettingsBlock.swift` |
| AT-9 | live tuning on the LG + full gates | — |

## 5. Verification contract

- Unit tests run synchronously with `Scripts/build_and_run.sh --test -only-testing:KatiKatiTests/…`.
- Live checks use `--resign` and the control socket; no display-mode or arrangement changes.
- Gates: `check_input_hygiene.py`, `live_check_input_hygiene.py`, `check_localization.py`,
  `check_debug_switches.py`, `check_availability_warnings.py <build log>`, then `graphify update .`.
