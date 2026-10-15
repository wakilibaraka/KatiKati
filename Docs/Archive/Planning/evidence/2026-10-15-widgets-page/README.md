# Widgets page onto the row system — live evidence (2026-10-15, plan step A3)

`Widgets.png` is the page as it runs after the rewrite (Debug build via
`Scripts/build_and_run.sh`, Settings at ⌘,), with what the accessibility tree reported on the same
run. The window is 900 pt wide.

The page is now **three** sections, where it was three cards plus a bare block of rows sitting at
the page margin:

| Section | Rows |
|---|---|
| **Widget Appearance** | Widget Layout · Widget Colors · **Clock Tile Style** · Glass · Now Playing Theme · Widget Animation · Show Notes Widget · Show Stopwatch & Countdown · Keep Both Widgets Open · the *Widget Styles & Presets* group row (its explanation moved to that row's ⓘ) · Clock Style · Weather Style · Now Playing Style · Right FAB Style |
| **Weather** | Temperature Unit · Wind Speed Unit · Weather Layout · Hero Style · Weather Animations · Heat Warning (Feels Like) 35°C · Wind Warning 50 km/h · Snow Warning 5 cm |
| **Widgets** | the ordered widget list, its presets and the context presets (unchanged) |

Measured on that run, not inferred:

- **Every label sits at x = 42 pt.** The weather rows used to start at 28 pt — they were the one
  block on the page with no card around them; they now share the grid with everything else.
- **The duplicate label is gone.** The page carried two rows named *Clock Style*: the clock tile's
  look (`CalendarClockStyle`) and the dock clock's preset (`com.katikati.clock.preset`). The tile's
  is now **Clock Tile Style**; the dock's keeps *Clock Style*. Both keys are unchanged.
- **No row was lost.** A diff check over the three touched files found 26 literals removed from the
  old code, and every one of them is still present in the new code — the rewrite converted rows to
  `SettingsRow`/`SettingsToggleRow`/`SettingsPickerRow`/`SettingsSegmentedRow`/`SettingsStepperRow`
  instead of dropping any.
- The steppers report their value in a trailing readout (35°C, 50 km/h, 5 cm) and the row's own
  accessibility label, so the control is not nameless (`Docs/SETTINGS.md` rule 9).
- The style presets moved out of `SettingsLayoutPane` into this block with their keys unchanged
  (`com.katikati.clock.preset`, `.weather.chipPreset`, `.media.preset`, `.widgets.fabStyle`); that
  move is what takes the page from four sections to three (rule 5).
