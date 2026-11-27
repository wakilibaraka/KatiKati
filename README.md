<div align="center">

<img src="assets/icon.png" width="128" alt="KatiKati app icon" />

# KatiKati

**A per-window taskbar for macOS, with an app launcher, widgets and quick settings.**

*katikati* is Swahili for "right in the middle".

English · [中文](README.zh-CN.md)

[Download the beta](https://github.com/wakilibaraka/KatiKati/releases/latest) · [Report a problem](https://github.com/wakilibaraka/KatiKati/issues/new/choose) · [Changelog](CHANGELOG.md)

</div>

---

<img src="assets/screenshots/bar.png" alt="The KatiKati bar: launcher button, weather, apps, now playing, clock and Control Center button" width="100%" />

> **Beta.** Version 0.18.0 beta 3 is locally signed and not notarized. See [Install](#install). Several new screens were not yet exercised on a real
> trackpad or across displays, and all new translations are drafts awaiting review. Expect rough edges.

## What it is

KatiKati puts a floating bar at the bottom of your Mac. Each window gets its own card, so getting back to *that one window* is a glance and a
click instead of a search. Around the bar it adds a launcher, a page of live widgets and a set of quick switches, all in native Swift.

KatiKati is a fork of [Tungsten Edge](https://github.com/moonbai-studio/tungsten-edge) and keeps its window-tracking core; see [Credits](#credits).

## Features

### Taskbar

- **One card per window.** Multi-window apps split into several cards; single-window apps stay compact. Click to switch, minimize or restore.
- **Cards you can read at a glance.** A greyed title means the window is minimized or its app is hidden; windows on other Spaces stay listed and
  clicking one takes you there.
- **Five layouts.** Windows, Split 3, Split 4, Split 5 and Centered, with adjustable bar height, gaps, margins and widget widths
  (Settings > Dock Layout).
- **Island widgets on the bar.** Weather (with Modern, iPad Sky Card, Samsung Vibrant, Orion Aurora, and Not Boring 3D styles), Now Playing and a clock; the clock opens a calendar panel with year progress, countdowns and a Date Calculator, and the weather chip opens a forecast panel.
  Weather asks for Location Services (or use a city you search for) and keeps the last forecast for each place for up to seven days, so it still
  shows when you are offline.
- **Starter apps.** A fresh install keeps Finder, Safari, System Settings and Messages on the bar so it is never empty.
- **App drawer, shelf, trash and pinned folders.** Drag cards to reorder them, stash apps in the drawer, drop files on the shelf.
- **Dock motion styles.** Pick how icons answer the pointer — None, Magnification, Spring Lift, Jiggle, Color Aura, Sliding Pill or
  Magnetic Pull — and how they answer a click: Tactile Squish, Launch Bounce, Ripple or Flip 3D. The running marker can be the classic dot,
  a Windows 11 pill (wide for the frontmost app, with one pip per window up to three) or a KDE Latte brand-coloured line tinted to the app's
  own icon colour. Reduce Motion swaps every moving style for the colour tint. Settings > Dock Items.
- **Side Deck.** A full-height panel on either screen edge brings together Windows, Notifications, Downloads, Dictionary (EasyDict), Storage,
  Weather, embedded Quick Access (Command Bar & Launcher), AI Mission Control, Layouts, Emoji, Clipboard, Clothesline, Scratchpad, Markets and a combined Dashboard.
- **Edge Bars.** Configurable edge strips hold smaller cards such as Notes, Reminders, Alarms, Timer and Stopwatch, Tasks, Clipboard history,
  Capture, Screen Time, Weather, Now Playing, Bluetooth and system monitoring.
- **Multi-display.** One bar that follows your pointer, or one bar per display, each listing only its own windows.
- **Workspaces.** Switch among numbered and named workspaces, move windows between them, and apply tiling layouts from shortcuts and the workspace controls.
- **Auto-hide.** Always visible by default; it can also hide and wake from the bottom edge. `⌥⇧⌘D` toggles it.
- **Blink-free full screen.** The bar steps out of the way before a native full-screen transition (see [Privacy](#privacy)).

### Mission Control (experimental)

- **Experimental, and honest about it.** Detection relies on undocumented WindowServer behaviour; multi-display overlays and Stage Manager filtering are supported (`0.18.0 beta 3`), and keyboard navigation, type-to-filter and the border overlay are off by default. [Why experimental](Docs/MissionControlResearch.md).
- **Named, not guessed.** Turn on **Settings > Window & Workspace > Mission Control** and every thumbnail gets its real app icon, the app
  name in bold and the window title beneath it, with coloured action dots in the system's red/yellow/green. A Space pill and a live
  type-to-filter readout sit over the overview. Nothing is drawn while Mission Control is closed, and detection is event-driven — no timers.
- **Four looks.** **Traffic Light** is the default — colourful category accents, coloured action dots and no border overlay — with
  **Colourful Everything** (borders up), **Liquid Glass** and **Paper** as alternatives. Space names keyed to each Space, automatic
  app-category colours with bundle-ID and category rules, optional focus/hover/state borders, thumbnail tint and Space accents, border width,
  corner radius, badge opacity, group padding, and top/bottom/leading/trailing placement for the badge, Space pill and filter readout.
- **Keyboard and pointer.** Tab and the arrow keys move the target, Return raises it, Escape clears the filter; hover buttons, configurable hover
  keys and right/middle-click actions close, minimize, zoom, hide or quit the window through its own Accessibility buttons.

### Clipboard

Clipboard history is opt-in and lives in memory only — nothing is written to disk. It now has its own page in Settings.

<img src="assets/screenshots/settings-clipboard.png" alt="Settings, Clipboard page: Behavior, Storage & Sorting, Privacy & Ignore Types, and Appearance & Popup" width="100%" />

- **Keyboard first.** `⏎` copies, `⌥⏎` pastes into the app behind the popup, `⌥⇧⏎` pastes as plain text, `⌥P` pins, `⌥⌫` deletes, `⌥⌘⌫` clears
  everything unpinned and `⇧⌥⌘⌫` clears all. Pinned items keep a permanent `⌘1`–`⌘9` badge.
- **Privacy.** Concealed and transient copies, 1Password and other password managers, auto-generated copies and (optionally) Universal
  Clipboard are never recorded; add per-app and pattern ignores, or press **Ignore Next Copy** once.
- **Storage.** Keep 50, 100, 250 or 500 unpinned entries, drop them after 24 hours, 7 days or 30 days, and sort by last copied, first copied
  or most used. Polling runs every 100–500 ms while recording.
- **Appearance.** Show the shortcut footer and pin badges, and choose where the popup opens (at the cursor, screen centre, or under the bar).

The Maccy-derived behaviour is credited in [NOTICE](NOTICE).

### Notch

On Macs with a camera housing, and as a floating island elsewhere, the notch opens into Home (housing Music and Calendar), Shelf, AI Mission Control,
Peripherals, Studio Hub and Keep Awake pages. Teleprompter and Camera Mirror are optional pages. Downloads and Storage live in the Side Deck.
The notch also presents live activity and notification cards. Settings > Notch controls its style, page order and **Sharp Notch Edges**.

### Menu Bar Hub

The menu bar hub consolidates configurable system metrics, quick actions and switches, calendar access, and scheduled actions in one surface.

### Launcher

<img src="assets/screenshots/launcher.png" alt="The launcher: a Most Used row, a Recently Installed row and every app in one grid" width="100%" />

- **One app grid, 8 icons across.** A **Most Used** row first (the apps you actually launch; until you have enough history, System Settings, Safari, Terminal,
  Messages, Finder, Mail and Calendar fill the gaps), then **Recently Installed**, then **All Apps**. Search sits at the top, or on any side.
- **Sliding pages.** Swipe, scroll, press the arrow keys or click the dots to move between pages; or switch to a single page that scrolls down
  (Settings > Layout > Launcher).
- **Make it yours.** Drag apps in All Apps to reorder them. Right-click an app to open it, show it in Finder, copy its path, pin it, move it to the
  start or hide it from the launcher (hidden apps are still found by search). Settings shows how many are hidden and can show them all again or reset the order.
- **Open it your way.** The left button on the bar, `⌥⇧Space` (with `⌥Space` opening the Command Bar), or a four-finger pinch on the trackpad (off by default; see [Shortcuts](#shortcuts-and-gestures)).
- **Themes.** System, Light, Dark, Glass or your desktop picture, with an optional colour tint and three icon styles.

### Control Center

The Control Center is a side panel (left or right, your choice in Settings), opened from the button at the right end of the bar or with `⌃⌥Space`.
It holds the Quick Settings switches, your widgets, and the connectivity controls.

- **Widgets:** Calculator, Screen Time (opt-in), Network, Battery with
  health and cycles, Top Apps, Batteries (your Mac and connected Bluetooth devices). The same tiles also live in the widget pane.
- **Quick Settings** has 20 switches: Dark Mode, Keep Awake, Hide Desktop, Hidden Files, Dock Auto-hide, Path Bar, Mute Mic, Mute Output, Clean Keyboard, Empty Trash (asks first),
  Eject Disks, Wi-Fi, Bluetooth, Night Shift, True Tone, VPN, Screen Saver, Lock Screen (asks first), Relaunch Finder (asks first) and Screen Mirroring
  (opens Display Settings). Bluetooth, Night Shift and True Tone rely on system interfaces that macOS does not document, so they can stop
  working after a macOS update; they fail quietly. VPN covers Network-configured VPN services only.
- iPad, Apple Watch and iPhone batteries are not shown: macOS does not expose them to a Mac.

### Shortcuts and gestures

| Action | Default | Alternatives |
|---|---|---|
| Open Command Bar | `⌥Space` | `⌃Space`, `⌥⇧Space`, `⌃⇧Space`, `⌃⌥Space`, or double-tap `⌘`, `⌃` or `⌥` |
| Open the launcher | `⌥⇧Space` | same list |
| Open the Control Center | `⌃⌥Space` | same list |
| Toggle Side Deck | `⌃⌥W` | configurable in Settings > Shortcuts |
| Open Window Inspector (`winfo`) | `⌃⌥I` | configurable in Settings > Shortcuts |
| Open Radial Dial | `⌃⌥R` | configurable in Settings > Shortcuts |
| Maximize window / Window Switcher | `⌃⌥M` / `⌥Tab` | configurable in Settings > Shortcuts |
| Switch workspaces (`1`–`0`) | `⌃⌥1`–`⌃⌥0` | configurable in Settings > Shortcuts |
| Quick Settings only | off | same preset list as Launcher |
| Keep Awake on/off | off | same list (shows a short toast) |
| Show or hide the bar | `⌥⇧⌘D` | rebind in Settings > Shortcuts |
| Launcher by pinch | off | four or more fingers pinched together on the trackpad |

Double-tap shortcuts need Accessibility. The pinch gesture reads raw trackpad touches through an undocumented macOS interface and needs no
permission. macOS has its own four-finger pinch (Launchpad) that opens the system app list, so turn **Launchpad** off under System Settings >
Trackpad > More Gestures before using it. `⌃Space` may also clash with the macOS input-source shortcut.

### Works without Accessibility

KatiKati starts even before you grant Accessibility. In this *limited mode* the bar, edge decks, launcher, Control Center and shortcuts work; what needs
Accessibility is reading and managing other apps' windows (the per-window cards). The status menu shows **Grant Accessibility for Full
Functionality...**; when you grant it, KatiKati relaunches itself into full mode.

Mission Control's overlay, mouse actions and Space names need Accessibility only. Keyboard navigation, type-to-filter and hover key
shortcuts listen to the keyboard globally, which macOS gates behind **Input Monitoring**; the Settings page reports that grant separately
and the overlay keeps working without it.

### Languages

The interface follows your system language in 12 localizations: English, 简体中文, 繁體中文, 日本語, Deutsch, Français, Español (Spain and Latin
America), Português (Brazil and Portugal), Italiano and 한국어. Change it in Settings > General > Language.

## Install

Requirements: macOS 15 (Sequoia) or later, Intel or Apple Silicon (universal binary).

1. Download `KatiKati-0.18.0-beta.3.dmg` from the [latest release](https://github.com/wakilibaraka/KatiKati/releases/latest).
2. Open the disk image and drag **KatiKati** to **Applications**.
3. The beta is not notarized, so on first launch **right-click KatiKati and choose Open**, then confirm.
4. Optional: grant **Accessibility** (System Settings > Privacy & Security > Accessibility) for the per-window cards. Each new unsigned build may need
   the permission granted again.

The in-app update feed is live but has no releases in it yet, so betas are distributed through the Releases page: download new versions from there.

To build from source instead, see [Developers](#developers).

## Recommended Dock setup

KatiKati is designed to replace the Dock at the bottom of the screen. On first run it offers three checkboxes, applied in one click: hide the Dock,
use the scale minimize effect, and minimize windows into their app icon. To do it by hand, open System Settings > Desktop & Dock and:

- set **Position on screen** to **Bottom** and turn on **Automatically hide and show the Dock** (otherwise the minimize animation flies toward a side
  or top Dock);
- set **Minimize windows using** to **Scale effect**;
- turn on **Minimize windows into application icon**.

To stop the Dock reappearing at all, drag **The Dock** slider in the KatiKati status menu to `Never Wake`.

## Status menu and Settings

The **status menu** (the capsule icon in the menu bar) holds what you change mid-session: Open at Login, the bar's wake delay, the Dock's wake delay,
Taskbar Size, a Layout submenu, Show Shelf, Show Trash, Show app name on hover, Keep maximized windows above the taskbar, Dock Settings and Settings.
With two or more displays it also offers single- and multi-display modes.

The **Settings window** has a sidebar (search with `⌘F`, sections with `⌘1`...`⌘9`) and a live preview stage on most pages. Across 6 groups (**System & Bars**, **Surfaces & Shelves**, **Window & Workspace**, **Input & Shortcuts**, **Productivity & AI**, **Advanced**), its 34 sidebar pages cover:

<img src="assets/screenshots/settings-layout.png" alt="Settings, Layout tab" width="420" />

- **System & Bars:** General, Menu Bar, Dock Layout, App Icons & Hover, Bar Widgets, Widget Wings, Appearance, Icons, Live Wallpaper.
- **Surfaces & Shelves:** Notch, Control Center, Side Deck, Edge Bars, Shelf, Weather.
- **Window & Workspace:** Windows & Tiling, Workspaces, Mission Control, Snap & Focus, Spaces & Displays, App Groups, Layouts, Profiles.
- **Input & Shortcuts:** Launcher, Gestures, Shortcuts.
- **Productivity & AI:** Command Bar, Clipboard, Notes, AI Mission Control, Workflows, Usage.
- **Advanced:** Advanced (fullscreen prediction, diagnostics, backup/reset), About.

## Privacy

KatiKati has no account, no analytics and no feedback form. It does not send your data anywhere. Things that touch the network or system:

- **Update check.** Sparkle checks an update feed on a schedule (you can turn it off in Settings > About). The feed is hosted on GitHub Pages and has no
  releases in it yet, so the check currently finds nothing.
- **Weather.** The weather chip and card request a forecast for your location (if you allow it) or a city you search for.
- **Input observation, for blink-free full screen.** To hide the bar *before* a native full-screen transition, KatiKati observes global left-click,
  key-down and trackpad-gesture events and recognizes only four things: the window's green button, `Control-Command-F`, `Control-Left`/`Control-Right`
  into an adjacent full-screen Space, and a three-finger horizontal swipe. Other input is not recorded, logged or sent anywhere. Turn off **Predict
  full-screen transitions** under Settings > Advanced to disable the listener entirely.
- **Reverse mouse scroll direction** (off by default) adds a second event tap that only flips the direction of discrete mouse-wheel events, and only
  while the switch is on.
- **Screen Time** (off by default) records only which regular app is frontmost and for how long, on this Mac, with 90-day retention; it never records
  window titles, documents, keystrokes or screenshots. "Delete Screen Time Data" wipes it.
- **Bluetooth.** The Bluetooth switch asks macOS for Bluetooth access the first time it needs to read the power state.

macOS suppresses key events from event taps while Secure Input is active (for example in a password field), so the full-screen prediction shortcuts are not
recognized then; the green-button and gesture checks are unaffected.

## Credits

KatiKati is built on [Tungsten Edge](https://github.com/moonbai-studio/tungsten-edge) by Moonbai Studio (GPL-3.0-or-later): the window-tracking
engine, strip rendering, panel coordination and baseline test suite. It also uses ideas and code from SplitBar-old and DockBar (both MIT) and studies
[noty](https://github.com/aimen08/noty) and EdgeDeckBar. Full notices are in [NOTICE](NOTICE).

## License

KatiKati is licensed under the GNU General Public License v3.0 or later (`GPL-3.0-or-later`). See [LICENSE](LICENSE) and [NOTICE](NOTICE).
The names "Tungsten Edge" and "钨极" and their logo belong to Moonbai Studio and are not used here; see [TRADEMARK.md](TRADEMARK.md).
Code-signing certificates, notarization credentials and other secrets are never part of this repository.

---

## Developers

Release notes for each version are kept under [`Docs/Releases/`](Docs/Releases); the running log of decisions and slices is [`HYBRID_PLAN.md`](HYBRID_PLAN.md),
and the working rules are in [`STANDING_RULES.md`](STANDING_RULES.md).

**Build and run** (kills any running instance, builds Debug, re-signs, launches; do not run a bare `xcodebuild` and `open`, because the Accessibility
grant follows the signing identity):

```bash
./Scripts/build_and_run.sh          # dev loop
./Scripts/build_and_run.sh --lab    # window-lab diagnostic CLI
./Scripts/build_and_run.sh --resign # re-sign what is already built (after `xcodebuild test`)
./Scripts/build_and_run.sh --check-signing  # read-only gate: does the grant still match?
./Scripts/install_local_release.sh  # signed Release into /Applications, then launches it
```

Every build prints one signing line. `xcodebuild test` relinks and signs the product ad-hoc, whose designated requirement is a cdhash, so it silently loses the
Accessibility grant: window automation then does nothing and a live check reads frames where the previous pass left them. `--check-signing` exits 3 in that case
with the reason and the fix, and `--resign` puts the local identity back without rebuilding.

Only one KatiKati may exist on the Mac. Both scripts delete every other `KatiKati.app` macOS knows about (old build folders, `/Applications`,
Xcode DerivedData) and unregister copies in the Trash, because copies share the bundle id and fight over the Accessibility grant.

**Tests** (over 4,100 XCTest cases; the same commands CI runs on every push):

```bash
xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
python3 Scripts/check_localization.py     # every localized string has a value in all 12 languages
python3 Scripts/check_debug_switches.py   # every DOCK_* environment switch is registered
```

**How the code is laid out** (three Xcode targets: `KatiKati`, `KatiKatiTests`, `window-lab`; four folders that only point downward):

| Folder | What lives there | Rule of thumb |
|---|---|---|
| `Core/` | Pure decisions: window identity, placement, layout packing, shortcuts, launcher ordering, pinch detection | No AppKit, no Accessibility. If behaviour can be a pure function of facts, it goes here with a unit test. |
| `Platform/` | System adapters: Accessibility, CoreGraphics window lists, event taps, the launcher indexer, system-health readers and the quick-toggle engine | Talks to macOS and hands facts up to Core. |
| `App/` | Composition and UI: `AppDelegate`, the panel controllers, SwiftUI scenes, and the `…Store` classes that persist settings in `UserDefaults` | Large types are split into `Type+Topic.swift` extensions. |
| `Tools/WindowLab/` | A replay CLI for window-identity scenarios | Not part of the shipping app. |

**Releases.** The Xcode project signs with a local certificate on purpose. Developer ID signing, notarization and packaging happen in
`Scripts/package_release.sh` on the maintainer's machine. Beta builds can be produced unsigned with a Release `xcodebuild` and `hdiutil`, as the
beta release did.

**Contributing.** Open an issue first for anything beyond a small fix. English is the source language; a new user-facing string needs a value in all 12
localizations (`Scripts/check_localization.py` fails otherwise). In-code comments are largely in Chinese, inherited from the upstream project; if a
specific area blocks you, open an issue naming the files.
