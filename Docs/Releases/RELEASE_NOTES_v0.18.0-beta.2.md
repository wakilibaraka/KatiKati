# KatiKati 0.18.0 beta 2

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).
Accessibility may need to be granted again after installing a new unsigned build.

## Mission Control is experimental

Mission Control has no public macOS API. KatiKati detects the overview from undocumented WindowServer behaviour and has only been
verified on a single display without Stage Manager. Treat it as an experiment, not a promise: a macOS update can change the window
list and the overlay will report unavailable instead of pretending to work.

**Safe defaults.** The border/group overlay is off, and keyboard navigation, type-to-filter and hover key shortcuts are opt-in.
Naming, category colours and the mouse/window action cluster are the parts that work without those fragile paths. The Settings
page and both READMEs carry the same label; the reviewed landscape of what survived and what died is in
[`Docs/MissionControlResearch.md`](https://github.com/wakilibaraka/KatiKati/blob/main/Docs/MissionControlResearch.md).

> **Build note.** The attached beta 2 DMG is the earlier archive from this beta. It predates the opt-in default change, so in that
> archive the border overlay and keyboard/filter paths may still start enabled. The experimental label and the off-by-default,
> opt-in behaviour described below are the product defaults from the next build onward; turn any of them off or on in
> **Settings › Window & Workspace › Mission Control**.

## What is new since beta 1

- **Mission Control has its own Settings section** under Window & Workspace. While the Dock's overview is open, KatiKati draws Space
  names, app and window-title badges, a Space pill, an optional type-to-filter readout and optional hover buttons on every window.
  Close, minimize, zoom, hide and quit go through each window's own Accessibility buttons; hover keys and right/middle-click
  bindings are configurable.
- **Named windows first (experimental look).** Badges use the real app icon, the app name in bold and the document title underneath.
  **Traffic Light** is the default look — colourful category accents and red/yellow/green action dots, with no border overlay.
  **Colourful Everything**, **Liquid Glass** and **Paper** are alternatives. *The look picker ships after this archive; the archive
  still uses the earlier badge and border rendering.*
- **Border overlay is off by default.** Focus, hover, state and app-group borders remain fully configurable, but the shipped
  default does not draw them over Mission Control's own thumbnails. Turning the border overlay on is a deliberate choice.
- **Keyboard and filter are opt-in.** Tab, the arrow keys, Return, Escape, type-to-filter and hover key shortcuts are disabled
  unless **Keyboard navigation and hover keys** is turned on. That path needs Input Monitoring, macOS may withhold keys from a
  background app while Mission Control owns the keyboard, and it has only been checked manually. The overlay and mouse actions work
  without it.
- **Detection that works on macOS 26.** Mission Control publishes no readable Dock accessibility windows on current macOS, so
  KatiKati detects the overview from the WindowServer's own window list and reads each thumbnail's real scaled frame. Entry is
  event-driven from the gesture, click or key that opens it — there is still no timer and no polling while Mission Control is closed.
  A status row reports the Dock observation instead of failing silently.
- **Multi-display and Stage Manager plumbing.** One overlay panel per display, per-display Space pills and scaling, and off-screen
  Stage Manager stages filtered out. This is implemented and unit-tested, but only exercised live on one display without Stage Manager,
  which is part of why the section is experimental.
- **Input Monitoring is reported separately.** Settings explains the grant and links to it; it is only needed for the opt-in keyboard
  path, not for the overlay, naming or mouse actions.
- **Fixes:** window frames are no longer mirrored vertically against their thumbnails, pointer actions target the hovered window
  instead of the keyboard target, and badge/Space/filter placements are honoured instead of collapsing leading and trailing into
  top and bottom.

## Known limits

- Detection is geometry-based because macOS has no public Mission Control API; a future macOS that changes the overview's window list
  can make the overlay report unavailable. There is no injection, no Dock patching and no SIP change.
- Keyboard navigation and filtering are unreliable by nature while Mission Control owns the keyboard; they are opt-in for that reason.
- Multi-display and Stage Manager support is unit-tested but not live-verified on this machine.
- Accessibility is optional; Bluetooth and Night Shift switches use system interfaces that can change between macOS releases.
- New translations are drafts awaiting review.
- This build is ad-hoc signed without the hardened runtime, so macOS may ask for Downloads, Calendar, Accessibility or Input
  Monitoring access.
