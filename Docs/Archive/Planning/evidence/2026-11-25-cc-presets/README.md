# Control Centre presets — shipped panel, one screenshot each

Date: 2026-11-25 · installed **Release 0.18.0 (54)** at `/Applications/KatiKati.app`,
`KatiKati Local Code Signing`, macOS 27.2.1 on an M3.

Captured with the Control Centre hosted in the **menu bar** (`com.katikati.controlcenter.surface = menuBar`),
because that is the home this pass added: one status-item click yields the panel
(`Quick Settings`, 360×792 at 1096,38) with no second surface behind it. Each shot is the panel region
only (`screencapture -R 1070,20,420,830`), downscaled to 1×, so the panels can be compared without the
desktop around them.

## The three presets

| File | Preset | What the capture shows |
|---|---|---|
| `01-classic.png` | `classic` | Today's order kept: **System & Peripherals** card first (`1 Device`, no duplicate This Mac row), Wi-Fi/Bluetooth cards, 4-column toggle grid, **Network** slider card, footer tiles, account row. |
| `02-modular.png` | `modular` | Connectivity becomes two square hero tiles; sliders and **Network** sit under them; footer and account stay put; the peripherals card drops to the bottom as one compact row. |
| `03-bento.png` | `bento` | Connectivity hero pair, then peripherals, then full-width slider tiles, **Network**, footer and account, with the dense 4-column toggle grid last. |

Switching the stored preset and reopening the panel was enough — no relaunch needed for `classic` → `modular`.
Presets keep the same header pill (`90%`) and the same footer/account, so the delta really is layout only.

## Single-battery rule, seen rather than assumed

The header shows `90%` in this build, and **no** `This Mac` row appears inside `System & Peripherals`
in any of the three presets — only the device list (`1 Device`, "No connected devices report a battery").
That is `ControlCenterDedupe.singleBattery` doing its job with the pill visible.

## Secondary-text readability (1:1 crops)

- `04-ink-title.png` — `Quick Settings`, the `15:34` chip and `90%` are full-contrast.
- `05-ink-footer.png` — `Settings / Launcher / Capture / Drawer / Quit` plus the `Manage accounts`
  subtitle: the subtitle is grey but clearly readable on the plate.
- `06-ink-note.png` — `No connected devices report a battery`: legible dark grey, not washed out.

No ink needed changing; the raised-alpha floor in `ControlCenterInk` is doing what it claims.

## Idle CPU / memory (installed Release, `Scripts/bench_katikati.sh --idle-only`)

| Metric | Value |
|---|---:|
| CPU, deep idle (60 s after 120 s settle) | **1.85 %** of one core (KatiKati), **2.16 %** for the process group |
| Memory, deep idle | **358.2 MB** (KatiKati), 442.8 MB group |
| App size on disk | 65 MB |

Two caveats, stated rather than hidden:

1. **A window has to be open to hold the sample.** A freshly installed, not-yet-trusted build enables
   AppKit automatic termination, so the app goes away with its last window; the sample was taken with a
   static Settings › General surface (the recipe `bench_katikati.sh --idle-only` now uses). The 0.2 %
   at-rest figure from earlier passes is for an app with no window at all.
2. **Part of the group figure is not the panel:** 0.32 % / 82.5 MB is `swift-frontend`, the
   `NowPlayingService` helper that the app runs as `/usr/bin/swift <tmp>/katikati-nowplaying-helper.swift`.
   That is existing behaviour, not something this feature added — but it is why "app" and "group" differ.

`pm_cpu_ms_s` / `pm_wakeups_s` are `n/a`: this Mac has no passwordless `sudo` for `powermetrics`.

## What was not verified

- The edge-hosted panel at each preset (same `ControlCenterView`, but only the menu-bar home was captured).
- Reduced Motion, VoiceOver order and the 12-locale rendering of the panel at these presets.
- Drag-to-reorder inside the panel (needs a pointer pass).

## Environment notes worth keeping

The first four sampling attempts failed for reasons outside the app, and each one looked like "the app
died":

- a **Launch-at-Login item still pointing at a temp Debug build** (`/private/tmp/katikati-dd-sidedeck/...`)
  that macOS kept restarting, holding `com.katikati.app`;
- two **stale staging copies** under `~/Library/Caches/` that another session's bench kept relaunching,
  each of which sends the running instance a quit event before it dies;
- a concurrent `swift-frontend` from a graphify rebuild landing inside the measured process group.

After removing the login item, moving the temp Debug app aside for the duration, and confirming the only
running copy was `/Applications/KatiKati.app`, the sample above was stable for the full 180 s.
