# Control Centre — dock-anchored pass (2026-11-25)

Shipped build: `/Applications/KatiKati.app` 0.18.0 (54), from `main` at `22ad0cc6`.
Machine: 1710 × 1112 pt, single display (`visibleFrame` 56,0,1654,1074), native dock visible.

## What "dock host" means in this build

There is **one** standalone Control Centre window: `ControlCenterPanelController`
(`App/Entry/EdgeFlyoutController.swift`). It is placed by two stored keys:

| Key | Values | Effect |
|---|---|---|
| `com.katikati.controlcenter.side` | `left`, `right` | which screen edge it hugs |
| `com.katikati.controlcenter.anchor` | `top`, `center`, `bottom` | where along that edge it sits |

There is no second "dock-hosted" panel object. The dock-anchored configuration tested here is
`side = right`, `anchor = bottom` — the panel flush to the dock's side of the screen. Two measured
facts come out of that:

1. **`anchor` is a no-op at the shipped height.** `show()` sizes the panel to
   `maxHeight = visibleFrame.height - 24 - bottomReserve` (994 pt here), and
   `PanelGeometry.controlCenterFrame` then offsets it by the anchor. Because the panel eats the
   whole band, `anchor = top` and `anchor = bottom` both land at `1338,50 360×994` (A-B-C captured
   under the earlier top-anchored run and again here under `bottom`). A user picking "Bottom" gets
   the same frame as "Top".
2. **The dock strip is not a door to this panel.** Its AX tree is a strip window
   (`AXWindow 147,1044 1361×86` → `AXScrollArea 167,1064 1321×46`) whose chips carry no
   Control-Centre label. A real `CGEvent` click at the first chip (`190,1087`), and an
   `AXPress` on the same element, opened a 660×620 popover at `64,428` and left the standalone
   panel ordered out:
   `layer=3 alpha=1 onscreen=? 1338,50 360x994` (CGWindowList keeps the window, `AXWindows`
   never lists it). Pressing the drawer capsule region (`1360,1087`, `AXUnknown 1271,1070
   183×34`) changed no window at all. So the dock strip's control chips are not wired to
   `onToggleControlCenter` in this build; the panel was opened with the app's own Quick Settings
   shortcut for every capture below.

## Environment choices (test only, not product decisions)

- `DOCK_DEV_SKIP_PERMISSIONS=1` to skip the password-gated Accessibility installer.
- "Allow" on the macOS *Documents* TCC prompt the dock chip raised; no Touch ID/password flow.
- Temporary `com.katikati.shortcut.quickSettings = key:3:12` (⌃⌥Q), deleted at handover.
- `~/Library/Preferences/com.katikati.app.plist` backed up to
  `/tmp/katikati-prefs-dockhost-20261125/` before any state change and restored afterwards.
- `com.apple.universalaccess reduceMotion` written for the Reduced Motion run, then deleted.

## Presets — dock-anchored panel, one close/reopen per preset

Each frame is the stored preset drawn after the panel was closed (Esc) and reopened, captured with
`screencapture -x -R 1338,50,360,994`. All three differ (md5 `da3593e3…`, `27d8757c…`, `884b35fb…`):

- `panel-classic.png` — header + System & Peripherals + connectivity + toggle grid + Network + sliders.
- `panel-modular.png` — battery pill top-right, connectivity first, Network card above the grid.
- `panel-bento.png` — sliders grouped under System & Peripherals, Network row above the footer,
  toggles last.

## Drag → Custom (real pointer)

With the header's Edit pill pressed, a `CGEvent` press/move/release from the toggle grid onto the
**Network section card** committed the move:

```
com.katikati.controlcenter.preset      = custom
com.katikati.controlcenter.layout.v1   = v1|custom|bento|
  section.header:hero,section.connectivity:wide,section.peripherals:wide,
  section.sliders:hero,section.nowPlaying:hero,section.network:wide,
  section.utilities:standard,section.account:standard
```

`panel-custom-after-relaunch.png` is that stored layout after quit + relaunch + reopen: Network is
drawn at the bottom of the column, i.e. Custom survived the relaunch.

Host-specific difference from the edge-host run: **the drop target has to be a card that does not
re-flow.** Dropping onto a toggle slot failed repeatedly because `dragging` is set in `.onDrag`, the
grid re-flows while the drag is live, and the release point then falls between rows — the drag lifts
(`drag-in-progress.png` shows the source tile faded and the grid mid-reflow) but no drop delegate
sees it. Releasing over a fixed section card commits. Earlier attempts in this folder's session were
also lost to the `swift` interpreter aborting mid-drag (`dyld … start + 6652`); compiling the event
helper to a binary fixed that, and the commit above is from the compiled helper.

## Reduced Motion

`com.apple.universalaccess reduceMotion = true`, app relaunched, panel opened while the window-server
sampler was running. First sampled frame: `alpha=1.00 x=1338` (no fade, no slide) —
`alpha-reduced-motion.txt`, `reduced-motion-bento.png`. The panel's `show()` takes the `.instant`
branch from `accessibilityDisplayShouldReduceMotion`; geometry is the same final frame in both cases.

## Accessibility

`ax-classic.txt`, `ax-modular.txt`, `ax-bento.txt`, `ax-custom-after-relaunch.txt` are the panel
window alone (62 lines each, filtered by window frame, not the whole app):

- 7 named `AXGroup`s per preset (`System & Peripherals`, `Wi-Fi`, `Bluetooth`, `Volume`,
  `Brightness`, `Network`, `Manage accounts`).
- 18 toggles announcing `value="On"` / `value="Off"`.
- exactly one `AXUnknown desc="Battery"` (the header pill), and no "This Mac" row in the panel.

Captured in normal (not Edit) mode after a relaunch per preset.

## Not verified here

- Debug test target still fails to build (`CameraMirrorService.swift:82:19`, missing
  `PermissionBootstrap`) — untouched, as instructed.
- The drag-on-a-reflowing-toggle-slot failure above is a real behaviour, not a measurement artefact;
  it is reported, not fixed, because the fix would need a rebuilt binary and this pass has to
  evidence the installed 0.18.0.
