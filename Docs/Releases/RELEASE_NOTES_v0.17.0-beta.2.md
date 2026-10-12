# KatiKati 0.17.0 beta 2

**Unsigned beta.** On first launch, right-click the app and choose Open (macOS warns because this build is not notarized).

What is new since beta 1
- **Launcher:** 8 icons across and bigger; sliding pages by default (swipe, scroll, arrow keys or the dots) or one scrolling page; drag to reorder All Apps; right-click to open, show in Finder, copy the path, pin, move to start or hide an app; Settings can show all hidden apps and reset the order.
- **Pinboard:** the full-screen wall is a dense grid scaled to fill the screen.
- **Weather:** it now loads (a null last forecast day used to break the whole forecast), keeps the last forecast for each place for up to 7 days so it works offline, and has an "Allow Location Access" button.
- **Bar:** a fresh install keeps Finder, Safari, System Settings and Messages on the bar.
- **No more feedback or license tabs:** nothing is sent to the upstream project's servers.
- **New app icon and menu-bar icon.**
- **Fixed:** the Notes Keychain item is no longer read at launch, so no password prompt appears until you open the deck or a note.

Known limits
- Accessibility is optional; Bluetooth and Night Shift switches use system interfaces that can change between macOS releases.
- New translations are drafts. Drag-to-reorder, Hide and the pinch gesture were not exercised on real hardware before this beta.
- If the pinch gesture also opens macOS's own app list, turn off Launchpad in System Settings > Trackpad > More Gestures.
- Some auto-quit utilities close apps when their last window closes; exclude KatiKati from them.
