# Control Centre on the edge host — presets, drag, Reduced Motion, AX

2026-11-25. Installed `/Applications/KatiKati.app`, 0.18.0 (54), built from this branch by
`Scripts/install_local_release.sh`. Screen 1710×1112 pt. Panel region captured is the edge panel's
frame, `360×994 at 1338,50`.

The panel is reached with `com.katikati.shortcut.quickSettings = "key:3:12"` (⌃⌥Q) written through
`defaults` **for this test only** — the shipping default is `.off`, and the binding was deleted
again before handover.

## Files

| File | What it shows |
| --- | --- |
| `edge-classic.png` | Classic preset: header, System & Peripherals, Wi-Fi/Bluetooth, 18-toggle grid, Network, Volume/Brightness/Keyboard sliders, quick-launch footer, account row. |
| `edge-modular.png` | Modular preset: connectivity hero pair on top, Network under it, toggle grid in the middle, sliders under the grid, System & Peripherals last. |
| `edge-bento.png` | Bento preset: connectivity pair, System & Peripherals, sliders and Network grouped as compact blocks, grid at the bottom. |
| `drag-after-drop-edit-mode.png` | After a **real pointer drag** with Edit on: header pill reads `Done`, System & Peripherals has moved below the toggle grid (above Network). |
| `drag-after-relaunch.png` | Same panel after quitting and relaunching the app: order unchanged, header pill back to `Edit`. |
| `reduced-motion-modular.png` | Reduce Motion on, preset switched to Modular, panel opened — full, opaque, interactive. |
| `alpha-motion-on-slide.txt` | Window-server samples while opening with animation = `slide` and Reduce Motion off. |
| `alpha-reduced-motion-slide.txt` | The same samples with Reduce Motion on. |
| `ax-classic.txt`, `ax-modular.txt`, `ax-bento.txt` | Accessibility tree of the panel only (window filter 359×900), one file per preset. |
| `ax-custom-after-relaunch.txt` | AX tree after the drag + relaunch, in the custom order. |

All PNGs are the panel region as captured; nothing is cropped, retouched or composited. Two
screenshots of the same preset differ only in clock and network-rate text.

## Preset switching

`defaults write com.katikati.app com.katikati.controlcenter.preset -string <preset>`, then the panel
is closed and reopened so the surface is built from the stored value, exactly as it is on launch.
Reading order in the AX dumps matches the pictures: classic `peripherals → connectivity → grid →
network → sliders`, modular `connectivity → network → grid → sliders → peripherals`, bento
`connectivity → peripherals → sliders → network → grid`.

## Drag → Custom

Method: press the header Edit pill (AX press, a normal button action), then a genuine pointer drag
from the System & Peripherals card body at `1400,129` to the Network card at `1500,790` through
`CGEvent` mouse events (`mouseDown`, 40 interpolated `mouseDragged`, `mouseUp`) — no SwiftUI state is
set from outside the gesture path.

- Immediately after the drop: `defaults read com.katikati.app com.katikati.controlcenter.preset`
  → `custom`, and the stored layout became
  `v1|custom|classic|section.header:hero,…,section.nowPlaying:hero,section.peripherals:hero,section.network:hero,…`.
- After quitting and relaunching: preset still `custom`, layout string unchanged, panel renders in
  the dragged order (`ax-custom-after-relaunch.txt`).
- The drag was repeated from a clean `classic` preset to produce the two screenshots above; both
  runs ended in the same state.

## Reduced Motion

Sampling the real window (owner, width 340–380, x ≥ 1000) from the window server while the panel
opens, with the panel's animation set to `slide` (the only animated choice; the shipping default is
`instant`):

- Motion on: `t=325ms alpha=0.00 x=1356` … `t=474ms alpha=0.95 x=1339` … `t=524ms alpha=1.00
  x=1338` — it slides 18 pt in and fades.
- Reduce Motion on (app launched with the setting on): the first sampled frame is `alpha=1.00
  x=1338` — no offset, no fade, the panel is final on its first frame.

Panel open/close and a preset switch under Reduce Motion were exercised for the screenshot above;
the panel was fully visible and reachable in AX right after opening.

Limitation: toggling Reduce Motion while the app was already running did not take effect until the
next launch in this build (the second sample in `alpha-slide-reduced.txt` was taken that way and
still animated). Launch-time behaviour is verified; live toggling is not, and is recorded in the plan
as open.

## Accessibility

`ax-*.txt` are raw `AXUIElement` dumps of the panel window only. In every preset:

- each card is one named `AXGroup` — `System & Peripherals`, `Wi-Fi`, `Bluetooth`, `Network`,
  `Volume`, `Brightness`, `Manage accounts`;
- the toggle grid is an `AXOpaqueProviderGroup` whose 18 `AXButton`s carry `value="On"/"Off"`
  (e.g. `AXButton desc="Dark Mode" value="Off"`);
- the battery pill is a single element, `AXUnknown desc="Battery"` with `AXValueDescription = 90%`,
  and the panel has **no** `This Mac` row — the only `This Mac` text in the app is the Settings
  window's own label, which is not in these dumps because the panel-only filter excludes it;
- the Network card's inner heading is hidden from AX so the card name is announced once.

## Test-environment notes

- Accessibility TCC: the installer runs `tccutil reset`, the Privacy pane lists no Accessibility row
  for the app, and adding it raises a password/Touch ID sheet. The behaviour above was therefore run
  with the project's own `DOCK_DEV_SKIP_PERMISSIONS=1` switch; the AX and window-server evidence is
  unaffected by that switch, the global gesture paths are the only thing it stands in for.
- Apple Music Automation prompt: allowed for this test environment so the now-playing card could
  report state.
