# KatiKati 0.18.0 beta 1

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).
Accessibility may need to be granted again after installing a new unsigned build.

What is new since beta 3
- **The Clipboard has its own Settings page**, above Tools, with four sections: Behavior, Storage & Sorting, Privacy & Ignore Types and
  Appearance & Popup. Nothing about the history moved anywhere else; Tools keeps Custom Commands, Text Snippets, the Key Visualizer and the
  Cheat Sheet.
- **Maccy-style keyboard control in the clipboard popup.** `⏎` copy, `⌥⏎` paste into the app behind the popup, `⌥⇧⏎` paste as plain text,
  `⌥P` pin, `⌥⌫` delete, `⌥⌘⌫` clear unpinned, `⇧⌥⌘⌫` clear all. Pins show permanent `⌘1`–`⌘9` badges and a shortcut footer explains the keys.
- **Privacy you can switch.** Concealed/transient/password-manager copies, auto-generated copies and Universal Clipboard can each be ignored,
  per-app and pattern ignores are edited on the page, and **Ignore Next Copy** skips exactly one copy. Sorting is Last Copied, First Copied
  or Most Used; History Limit is 50/100/250/500 and retention 24 hours/7 days/30 days/Forever.
- **Dock hover, click and running-marker styles.** Hover: None, Magnification, Spring Lift, Jiggle, Color Aura, Sliding Pill, Magnetic Pull.
  Click: Tactile Squish, Launch Bounce, Ripple, Flip 3D. Running marker: classic dot, Windows 11 pill (frontmost width plus window pips) or a
  KDE Latte brand line tinted to the app's own icon colour. Reduce Motion replaces every moving style with the colour tint.
- **The Drawer is a DockPops-style pop** with its own dock icon, holding up to 25 apps, files and folders; drag a window card onto it to stash
  the app. The capsule beside the bar is now Background Apps only.
- **Dock layering.** Settings › Window Management offers eight modes, from Always on Top to Click-Through Ghost Mode and Working-Area Strut
  Clamping, with zero-permission fallbacks.
- **Space switching with a transition**, and a **Drives widget plus Drives menu-bar item**.
- **Every macOS 26 icon style** is rendered, **permissions are asked once during setup**, quitting follows one table, and launcher search ranks
  like a launcher should. The command bar opens on `⌥⇧Space`.
- **Fixes:** the dock no longer returns over full-screen apps, chips can no longer be click-dead, and the layering engine idles in the default
  mode.

Known limits
- Accessibility is optional; Bluetooth and Night Shift switches use system interfaces that can change between macOS releases.
- New translations are drafts awaiting review.
- This build is ad-hoc signed without the hardened runtime, so macOS may ask for Downloads, Calendar or Accessibility access again.
