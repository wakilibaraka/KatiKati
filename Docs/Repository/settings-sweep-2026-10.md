# Settings sweep — baseline (2026-10-15, installed Release 0.17.0 (51))

Method: Settings opened with ⌘, on the installed app; every tab's controls enumerated through the macOS accessibility tree (role / label / current value) and the Appearance theme switch exercised live with screenshots of the right-edge drawer. Counts below are controls found, not yet individually toggled (see "Not yet exercised").

| Tab | Window | Controls found | Notes |
|---|---|---|---|
| General | 560×1074, scrolls | ~65 | Language, appearance mode, edge hotkey, widget layout/colors/clock/glass, Weather block, Now Playing theme, Live Island, Utility (links, clipboard, daily helpers, teleprompter, launcher, snippets, shelf, Restore Dock), drawer position, scroll reverse |
| Layout | 560×1074, scrolls | ~320 AX rows | Biggest surface: dock style/mode, widgets, edge bars, chips, launcher, control center, shortcuts, keyboard, dial, presets |
| Appearance | 560×1074 | 14 theme cards + icon set/shape + 5 behaviour toggles + wallpaper | |
| Tiling | 560×248 | 1 (enable) while off; preset/gaps/floating/shortcut rows appear only when on | by design, verify on |
| Advanced | 560×275 | 1 toggle (full-screen prediction) | |
| About | 560×271 | version, Check for Updates, auto-update toggle, Diagnostic Info copy | |

## Findings
1. **Theme switch works** (plan item "does nothing" NOT reproduced). `com.katikati.theme.material` changes (auto → crystalClear → auto confirmed via `defaults`) and the drawer tint follows: Ember Sunset warm, Forest Moss green, Auto blue-grey. The effect is a subtle tint — Crystal Clear / Rose Quartz / Translucent are almost indistinguishable from Auto on a dark backdrop. Real gap: **low visible contrast between themes** (12f eyeball item) and surfaces on separate theme systems (launcher, dial, notch, pinboard) — not yet checked live.
2. **Accessibility gap:** ~18 checkboxes in Layout (Edge Bars tile toggles, Control Center widget/quick-setting toggles, several Chips toggles) expose no label to VoiceOver; same for the Appearance behaviour toggles. Fix when those blocks are relocated.
3. **Appearance hint text** says "Light or dark is set in General › Appearance" — fine today, must be updated if 12b moves Appearance.
4. **No License UI exists** (12d has nothing to move).
5. Notch/helpers/teleprompter settings are in General (below Now Playing Theme), not Advanced.

## Not yet exercised (next sweep pass)
Per-control toggling of Layout edge bars/control center/radial dial, shortcut recorders, wallpaper, Tiling with enable on, About › Check for Updates, language switch (relaunch). Layout notches/lock/launcher surfaces' own themes.
