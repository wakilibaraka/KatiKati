# The Shortcuts page: three sections behind a find field — live evidence (2026-10-15, plan step A4)

Three screenshots from the running app (Debug build via `Scripts/build_and_run.sh`, Settings at ⌘,),
taken after the last source edit of the slice, plus the accessibility tree of the same three states.
The window is 900 × 1074 pt; nothing here is read off the source.

| Shot | State | What it shows |
|---|---|---|
| `Shortcuts-full.png` | the page as it opens | **Shortcuts** (the find field, then the eleven feature actions), **Snap Hotkeys** with its ⓘ and the four captioned groups, and both lower cards |
| `Shortcuts-filtered-left.png` | `left` typed into the field | five rows — Snap Left Half, Snap Top-Left, Snap Bottom-Left, Snap Left Third, Snap Left Two-Thirds — and only the captions of the groups that still hold a row |
| `Shortcuts-empty-state.png` | `zzzz` typed into the field | the empty state, "No shortcuts match.", with the Keyboard and Radial Dial cards unaffected |

`shortcuts-ax.txt`, `shortcuts-ax-left.txt` and `shortcuts-ax-zzzz.txt` are the accessibility dumps
of those same three states.

Measured on those runs, not inferred:

- **Every label sits at x = 42 pt** in all three states — the only `AXStaticText` x value in each
  dump is 42.0 — so the find field and the three cards share the grid the rest of the window uses
  (rule 1). The binding menus (x = 627) and the Record buttons (x = 791) line up to the point on all
  26 assignment rows.
- **The page is three sections:** Shortcuts, Keyboard, Radial Dial, where it was one card of ~35 rows
  two screens long (rule 5's budget for a page).
- **The find field matches what the reader sees.** `left` leaves 5 of the 26 rows, with the empty
  groups' captions gone too; `zzzz` leaves none and says so; the field reports `Search Shortcuts` as
  its `AXDescription`, so the control is not nameless (rule 9).
- **The four snap captions are translatable now.** Before this slice they were bare `String`s handed
  to `Text(verbatim:)`, so they stayed English in all twelve languages; they are catalog keys now
  (Halves, Quarters, Thirds, Full) with the English placeholder + `needs_review` rule for the rest.
- **Typing into the page changed no setting.** `defaults export com.katikati.app` taken before and
  after the three text entries differs in one data blob the app rewrites itself
  (`com.katikati.wallpaper.original.v1`) and in nothing else.

The text was typed for real (AX focus on the field, then `System Events` keystrokes), not written
through the accessibility `AXValue`: setting that attribute on a SwiftUI `TextField` leaves the
binding untouched, which is what the first attempt at this shot showed as an unfiltered list.

Still unexercised here: the ⓘ popovers' behaviour (the same gap the other pages carry — the text is
in the row, the popover is not opened in this pass), and any rendering on macOS 12.
