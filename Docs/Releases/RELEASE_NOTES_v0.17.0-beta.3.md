# KatiKati 0.17.0 beta 3

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).
Accessibility may need to be granted again after installing a new unsigned build.

What is new since beta 2
- **Notch redesign:**
  - **Storage page.** It lists the largest folders and files on the Mac, biggest first, split into Files and Developer & Cache; click a row to reveal it in Finder. It replaces the Retro Flip Clock page; the world clocks stay in the calendar panel.
  - **Closed notch dock.** Free storage sits on the left and the battery on the right.
  - **Event toasts.** They are cards with an icon tile and a bar that drains over the toast's 3 s life.
  - **Sharp Notch Edges.** The new Settings > Notch option gives square corners and removes the flared ears.
  - **Page changes.** Downloads is the first page, music and calendar are merged, and the Focus and Hardware HUD pages are removed.
  - **Smoother opening.** The open notch uses a liquid blur transition.
  - **Empty states.** The Downloads page's empty states now fit the panel.
  - **Camera mirror and notification pages.** These notch pages now exist.
  - **Real data.** The Productivity page runs on your real calendar and timer.
- **Settings redesign:**
  - **Layout and search.** A sidebar replaces the tab strip, and the window resizes freely. `⌘F` focuses search and `⌘1`...`⌘9` jump to a section. Search matches keywords, scrolls to the matching row and pulses it.
  - **Live preview stage.** A stage on Appearance, Widgets, Notch, Edge Bars, Window Management, Control Center, Radial Dial, Shortcuts and Downloads redraws as you change settings. It only reads settings.
  - **Time-of-day glow.** A glow tinted by the hour follows the clock; it is off for Reduce Motion and Increase Contrast.
  - **Revert Changes.** One action restores the keys changed this session and relaunches.
- **Stability:** reading the Accessibility tree no longer crashes off the main thread, and two force-unwraps (tiling insert, shelf folder) now fail safely.

Known limits
- Accessibility is optional; Bluetooth and Night Shift switches use system interfaces that can change between macOS releases.
- New translations are drafts. The README screenshots predate the notch and Settings redesign.
- This build is ad-hoc signed without the hardened runtime, so macOS may ask for Downloads, Calendar or Accessibility access again.
