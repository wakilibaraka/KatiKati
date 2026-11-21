# KatiKati 0.18.0 beta 2

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).
Accessibility may need to be granted again after installing a new unsigned build.

What is new since beta 1
- **Mission Control has its own Settings section** under Window & Workspace. While the Dock's overview is open, KatiKati draws Space names,
  app and window-title badges, focus/hover/full-screen borders, app group frames, a Space pill, a type-to-filter readout and optional hover
  buttons on every window. Close, minimize, zoom, hide and quit go through each window's own Accessibility buttons; hover keys and
  right/middle-click bindings are configurable.
- **Make the overview yours.** Border width, corner radius, badge opacity, group padding, and top/bottom/leading/trailing placement for badges,
  the Space pill and the filter readout. App-category colours are assigned automatically and every bundle-ID or category rule is editable;
  window states can have their own border style and colour, Spaces can have their own accents, and thumbnails can carry a tint.
- **Keyboard navigation.** Tab and the arrow keys move the keyboard target through the windows the filter still shows, Return raises that window
  and leaves the overview, Escape clears the filter and then closes the overview. The target follows filtering, and a refresh during an AX or
  Space change no longer wipes what you typed.
- **Detection that works on macOS 26.** Mission Control publishes no readable Dock accessibility windows on current macOS, so KatiKati detects
  the overview from the WindowServer's own window list and reads each thumbnail's real scaled frame. Entry is event-driven from the gesture,
  click or key that opens it — there is still no timer and no polling while Mission Control is closed.
- **Input Monitoring is now reported.** Keyboard navigation and hover shortcuts listen to the keyboard globally, which macOS gates behind
  Input Monitoring, separately from Accessibility. Settings reports and links that grant; the overlay and mouse actions work without it.
- **Fixes:** window frames are no longer mirrored vertically against their thumbnails, pointer actions target the hovered window instead of the
  keyboard target, and the badge/Space/filter placements are honoured instead of collapsing leading and trailing into top and bottom.

Known limits
- Detection is geometry-based because macOS has no public Mission Control API; a future macOS that changes the overview's window list can make
  the overlay report unavailable.
- Accessibility is optional; Bluetooth and Night Shift switches use system interfaces that can change between macOS releases.
- New translations are drafts awaiting review.
- This build is ad-hoc signed without the hardened runtime, so macOS may ask for Downloads, Calendar, Accessibility or Input Monitoring access.
