# Settings "form and function" pass — before/after evidence (2026-10-15)

Screenshots of all ten Settings pages, taken from the running app (`Scripts/build_and_run.sh`,
then the Settings window at ⌘,), plus the accessibility-tree measurements behind the numbers in
the commit and in `HYBRID_PLAN.md`.

- `before-*.png` — 08:51 on the tree as it stood before the pass (`53dcb49`).
- `after-*.png` — the same ten pages on the final tree of the pass, captured after the last
  source edit, so they show the shipped layout (including the Permissions card's row rhythm).
- `before-grid.txt`, `after2-grid.txt` — `grid.py` output over the matching AX dumps. The dumps
  themselves are scratch and not kept.

What the numbers say (window 900 pt wide, 1074 pt tall):

| | before | after |
|---|---|---|
| Card-content left inset | 20 / 28 / 42 / 108 pt (varies by page) | **42 pt on all ten** |
| Card-to-card text gap, Window Management | 23 / 75 / 67 pt | **72 pt** (grid predicts 70) |
| Window height, General / Advanced / About | 621 / 778 / 271 | 598 / 587 / 256 |
| Rows per page (14, 22, 38, 19, 29, 20, 61, 53, 13, 3) | — | identical except Advanced 13 → 12 (its six-line paragraph became an ⓘ on the row) |

Still taller than the window after the pass: Appearance 1560, Launcher & Tools 2350, Widgets
1387, Shortcuts 1309 — the grouping jobs `Docs/SETTINGS.md` §3 assigns per page, not a reason to
shrink a row. The pairs, for a reviewer with no build:

| Page | Before | After |
|---|---|---|
| General | `before-general.png` | `after-general.png` |
| Appearance | `before-appearance.png` | `after-appearance.png` |
| Widgets | `before-widgets.png` | `after-widgets.png` |
| Notch | `before-notch.png` | `after-notch.png` |
| Edge Bars | `before-edge_bars.png` | `after-edge_bars.png` |
| Window Management | `before-window_management.png` | `after-window_management.png` |
| Launcher & Tools | `before-launcher___tools.png` | `after-launcher___tools.png` |
| Shortcuts | `before-shortcuts.png` | `after-shortcuts.png` |
| Advanced | `before-advanced.png` | `after-advanced.png` |
| About | `before-about.png` | `after-about.png` |
