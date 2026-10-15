# Tools page + About's retirement — live evidence (2026-10-15, Phase 12 plan steps A1+A2)

Three screenshots from the running app (`Scripts/build_and_run.sh`, Settings at ⌘,), taken after the
last source edit of the slice, plus what the accessibility tree said on the same run. The window is
900 pt wide; nothing here is read off the source.

| Page | Shot | What it shows |
|---|---|---|
| General | `General.png` | The **About** card (version + Check for Updates, auto-update, diagnostics) as the page's third section, after Permissions, with Show Setup Guide Again below it. Window is 880 pt tall — the About rows added ~280 pt to the 598 pt page. |
| Launcher | `Launcher.png` | The launcher and the Control Center, then the launcher's own rows (Script Commands, Show Command Hints, Fast File Index, Replace Spotlight + its steps). The tools are no longer here. |
| Tools | `Tools.png` | The new tab: Clipboard (Clean Copied Links, Copy Sounds, Copy Notifications, Ignore Patterns), Custom Commands, Text Snippets, Shelf. Window 918 pt. |

Facts measured on that run, not inferred:

- **Tab strip, in order:** General · Appearance · Widgets · Notch · Edge Bars · Window Management ·
  Launcher · Shortcuts · Advanced · **Tools** — ten items, `Tools` in the slot `About` occupied, its
  icon `doc.on.clipboard` drawn (see the selected tab in `Tools.png`).
- `press About` → `ERR no tab About`: the page is gone rather than hidden.
- Every content row on all three pages starts at the same **42 pt** inset (28 page margin + 14 card
  padding) — the grid the form-and-function pass landed, unchanged by this slice.
- Rows kept their identity through the move: the tools page carries the same switch and editor rows
  the launcher page carried before, and the launcher page carries the launcher rows.

Still owed on these two pages (recorded in `Docs/SETTINGS.md` §3, not claimed here): placeholders
and first-run hints on the two editors (rule 8), the Spotlight steps' four hard-coded lines becoming
an ⓘ (rule 4), and the Tools page carrying four sections where rule 5 allows three.
