# Multi-display (`MD-1`…`MD-6`) — live re-check on the delivered tree

Date: 2026-11-26 21:40 · `main` at `2b732371`, identical to `origin/main`. The notch rebase that
touched the island files landed in the same tree (`e4fc67d6`), and the running build was the signed
Debug app built from it by `Scripts/build_and_run.sh --verify` (the local signing identity kept the
Accessibility grant). No code changes were needed in this pass; this folder is evidence only.

Desk: built-in `1710×1112` at Quartz `(0,0)`, LG HDR 4K `1920×1080` at `(-164,-1080)` — stacked, so
the shared boundary is the horizontal seam at `y = 0`.

## Observed

1. **Control Centre rows carry their names and the panel's own value.** The status item opened Quick
   Settings with the `com.katikati.controlcenter.surface = menuBar` override; the card drew four
   labelled rows — **Volume 100**, **Brightness 100**, **Display Volume 30**, **Keyboard 1**
   (`01-quick-settings-labelled-rows.png`). The display row's 30 is the LG's VCP `0x62` read-back while
   the system volume reads 100, so it is the external panel's value reached through
   `DisplayTargetRule` for the pointer's display, not a copy of the system slider. The key was deleted
   and the app relaunched afterwards; the default `edge` surface is back.
2. **DDC/CI transport, live.** Brightness `100 → 80 → 100` read back `80/100` then `100/100`; volume
   `30 → 50 → 30` read back `50/100` then `30/100`. Every write was accepted and every read-back
   agreed with it. The read path matches each reply to the VCP that answers it (`reply[4] == vcp`),
   because the panel repeats frames and a stale one passes the checksum.
3. **Cursor jump across the seam.** Pointer on the LG at Cocoa `(1174.27, 1367.27)`: planned
   `(1191.89, 1110.0)`, Quartz `(1191.89, 2.0)`, read-back `(1191.0, 1110.0)` — 0.89 pt off,
   `insideTarget=true`, pointer restored to `(1174, 1367)`. With only two displays, both `step: 1` and
   `step: -1` land on the other panel, which is the intended wrap.
4. **Hygiene gate (`MD-6`), two displays.** `Scripts/live_check_input_hygiene.py --pid <app>` under
   Python 3.14 + PyObjC: exit 0, 13 onscreen windows on the built-in and 9 on the LG, 0 active
   `.defaultTap`s (LR2 ✓). Beyond the summary it printed four LR4 notes for the dock plate's 18 pt
   shadow margin crossing under the menu bar — the benign case the gate reports as a note.
5. **Window inventory (`MD-2`/`MD-3`).** Islands: 340×54 notch on the built-in at `(685,0)` and
   640×44 wide bar on the LG at `(476,-1080)` — what the default `IslandPlacementMode.allDisplays`
   resolves (`notch` for the hardware cutout, `wideBar` elsewhere). Decks: rails at `x 1696–1710`
   (built-in) and `x 1742–1756` (LG), both on their display's outer right edge, none on the seam.
6. **Layout memory (`MD-4`).** `com.katikati.desktop.topologyArchive` stores one entry per display
   signature, each with a `normalizedFrame` per window keyed by display UUID (the two-display
   signature is present). The hot-plug path itself still needs a hand at the desk — see the plan's
   "Still open" list.

Final machine state: Control Centre on its default `edge` surface, LG at brightness `100/100` and
volume `30/100`, pointer back over the built-in display, app running on `2b732371`.
