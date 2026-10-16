# Phase 32 — evidence

Phase 32 (dock/widget motion language + circular icon look) is being built one slice per commit, with
an owner eyeball after every UI-visible slice. This directory holds each slice's witness as it lands.

## Slice 32d — the circular icon look is packed (commit `9cfe9bf`)

**What changed.** The `Dock App Icon Shape` row left Settings › Appearance, `DockIconShape.title` went
with it, and the dock icons' frame is now fixed at launch by the registered `DOCK_ICON_FRAME` switch
(unset = today's squircle). The on-disk key `com.katikati.dock.iconShape` is ignored from now on. One
shared `dockIconMask(size:)` in `App/Scenes/DockTheme.swift` replaced the same `if/else` that
`ChipView`, `LauncherChip` and `DrawerCapsuleButton` each carried.

**Gate.** `xcodebuild test` **2443 tests, 0 failures** on a cold build of the committed tree in an
isolated `git worktree` (the working tree's 2475 includes earlier phases' uncommitted tests, which are
not in this commit); `check_localization.py` 879 keys = 879 entries; `check_debug_switches.py` 85/85;
`check_availability_warnings.py` clean.

**Live, on the owner's bar** (captures are the bar band `screencapture -R0,1043,1710,69` at 2x):

| capture | what it is |
|---|---|
| `dock-icons-unset-squircle.png` | the bar with the switch unset — today's squircle |
| `dock-icons-env-circle.png` | the same bar with `DOCK_ICON_FRAME=circle` in the app's environment (`ps eww` confirms the variable reached the process) |
| `dock-icons-final-build-unset.png` | the committed build, relaunched the normal way |
| `dock-icons-red-test-drastic-mask.png` | a deliberately drastic mask (`Circle().scale(0.75)`), used to prove the probe can see a shape change, then reverted |

Measured over the 16 app chips, artwork pixels inside each chip's own frame:

- unset: **3120**, `DOCK_ICON_FRAME=circle`: **3121** — and the artwork's top-row chord (42 px of the
  ~58 px artwork box) is identical in both.
- red test (drastic mask): **2286** pixels, chord **22 px**. The probe is not blind; the shapes really
  do render alike.

**Finding (recorded, not fixed).** The mask clips at the *icon's frame size* while the artwork is fit
*inside* that frame, so a circle never reaches the artwork's corners — macOS icon artwork is already a
rounded square whose corners sit inside the circle. The circular option was therefore invisible on the
dock even before it was packed; making it visible is the redesign this phase's `DockIconFrame` token
proposes (a frame token, not just an image clip), and it is not part of packing. `HYBRID_PLAN.md`'s
Phase 32 entry carries the same note.
