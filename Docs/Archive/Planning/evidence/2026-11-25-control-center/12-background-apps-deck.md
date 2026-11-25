# 12 — Background Apps deck, polished

**Surface:** standalone edge Control Panel (`ControlCenterPanelController`), Home = Menu Bar.
**How it was opened:** a real left click on KatiKati's dock capsule
(`AXButton`, help `Control Center • Volume: 21%`, window 86×86 at 1612,1044);
`AXPress` on that element is swallowed, a `CGEvent` click opens the panel.
**Window:** 360×994 at 1338,50 (fills the space between menu bar and dock).

## Accessibility tree

`AXGroup ×1`, `AXImage ×10`, `AXStaticText ×12`. Text values in order:

```
Background Apps
10
BetterAndBetter
Caffeine
CaskHub
Claude
ClipRelay
Easydict
Freebuff
glance
Google Chrome
Google Drive
```

No `Quick Settings`, so the panel is in its Background Apps role. No
`loginwindow`, `WindowManager`, `MenuBarAgent`, `Wallpaper`, `Finder`, or
`Google Chrome Helper (Aperitif)`: OS machinery and nested workers are filtered
by `BackgroundActivity.belongs` (prohibited processes, Apple accessory agents,
Finder, helpers), and the list is name-sorted and capped at ten.

Every row carries a resolved bundle icon (colour visible — Chrome, Drive, Claude
and the rest), and any app whose bundle cannot resolve falls back to a tinted
monogram in the panel's own accent gradient, so no row is a bare white square.

## Deterministic coverage

`BackgroundAppClassifierTests`:
- `testBackgroundActivityDropsOSMachineryButKeepsUserApps`
- `testVisibleListIsFilteredSortedAndCapped`
- `testMonogramFallbackIsAlwaysLegible`
