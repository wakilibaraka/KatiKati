# KatiKati 0.17.0 beta 4

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).
Accessibility may need to be granted again after installing a new unsigned build.

What is new since beta 3
- **Dock:**
  - **Drawer pop.** The Drawer is a dock icon left of Downloads and the Trash. It holds up to 25 apps, files and folders; drop anything on it, click to open, and browse folders inside it. Stashed apps move in on first launch. The capsule beside the bar now shows Background Apps only.
  - **Dock Layering.** Settings > Window Management offers eight layering modes. The default mode is idle, the dock no longer comes back over fullscreen apps, and the Piggyback mode asks before it changes your Dock and gives your settings back when you leave it.
  - **Dock widgets.** Calendar, System, Devices and Drives widgets with hover previews, plus a Widget Look setting.
  - **Chip menus.** Right-click a chip for the app's own New Window and New Tab rows; ⌥-click hides an app, ⌘-click minimises a window.
- **Command bar:**
  - **Menu search.** Type `m ` or `menu ` to search the menus of the app you were just in, and press Return to run the item.
  - **Bar profiles.** `profile <name>` applies a saved bar (kept apps and order, pinned folders, layout); `profile save <name>` stores the current one.
- **Settings:**
  - **Backup and restore.** Settings > General > Backup writes one `.katikati` file; restoring first saves a "Before restore" copy. Notes are included only with a password.
  - **One quit table.** Hold ⌘Q, pass-through and quit-on-close rules are one table of apps with three switches.
  - **Notifications page.** Low-battery levels, charge milestones, plug changes and peripheral alerts, shown as a compact pill or a banner.
  - **Translucency** slider, Space switching with a fade transition (macOS 26), Fixed Space Order, and Focus Follows the Mouse.
- **Notch and panels:**
  - **Battery card.** Click the battery in the open notch for time remaining, watts, thermal state, health and cycles.
  - **Weather redesign.** A new dock chip and panel, with an optional full-screen Overview.
  - **Control Center.** Rebuilt to match the dock theme, with an iPadOS-style second preset, scroll-to-change volume and an option to sit at the bar's right end.
  - **Launcher.** It can open as a centred or popover card, and an optional floating orb opens it.
- **Claude Code (off by default):** approve Claude Code permission requests from a small card, and track Claude's turns with a hook so the notch knows when it stops.

Known limits
- Several features in this beta have only been checked by automated tests, not by hand on a real Mac: the Drawer pop, menu search, the Backup card and the Claude Code approval card.
- Menu search does not yet work in Electron apps. Quicklinks are not in this build.
- New translations are drafts. The README screenshots predate the notch and Settings redesign.
- This build is ad-hoc signed without the hardened runtime, so macOS may ask for Downloads, Calendar or Accessibility access again.
