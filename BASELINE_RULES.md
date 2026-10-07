# KatiKati — Baseline Rules (Phase 0 import contract)

> What "baseline" means, how the tungsten import is verified, and what must stay
> true before any Phase 1+ work begins. Companion to `STANDING_RULES.md`.
> Locked: 2026-10-08 · Snapshot: tungsten-edge @ a4e1a55 (2026-10-07).

## 1. What the baseline is

1. The baseline is tungsten-edge at commit `a4e1a55`, imported as a **clean tree**
   (no tungsten git history), then rebranded behavior-neutrally to KatiKati.
2. Rebrand = names/ids/assets/strings only: product + target + scheme names,
   bundle ids (`com.caye.macosdockcc.v2*` → `com.katikati.app`), defaults domain
   (`com.tungsten.edge.*` → `com.katikati.*`), display name + icon, Sparkle feed
   URL + key, login-item/single-instance scope, README/CI strings, `Info.plist` +
   `.xcstrings` display names.
3. **Zero behavior delta in Phase 0.** If the app behaves differently from tungsten
   at `a4e1a55` in any way not listed in the Phase 0 log, that is a defect, not a
   feature.

## 2. Directory and target contract

1. Layout preserved: `App/` (Composition/Entry/Scenes) · `Core/` · `Platform/` ·
   `UI/` · `Tools/WindowLab/` · `Tests/` · `Scripts/` · `Resources/` ·
   `.github/workflows/` · `Docs/Archive/Releases/`.
2. Target graph preserved: app + unit tests + `window-lab` CLI. Only names change.
3. Downward-only folder rule preserved: `Core` (no AppKit, no AX) → `Platform`
   (system adapters) → `App` (composition + UI). `Tools/WindowLab` not shipped.


## 3. Forbidden in the baseline

1. No new features, no layout-mode code, no widget ports, no donor code of any
   kind. Phase 0 is import + rebrand + verify.
2. No SwiftPM migration, no target-graph redesign, no folder restructuring.
3. No string-value changes beyond display-name/bundle renames (all 12 languages
   must keep passing `check_localization.py`).
4. No `DOCK_*` switch additions/removals/renames.
5. No Sparkle removal or replacement — only feed URL + key rotation.

## 4. Baseline verification (exit gate for Phase 0)

1. **Tungsten gate green** on the renamed tree: `xcodebuild test …`
   `CODE_SIGNING_ALLOWED=NO`, `check_localization.py`, `check_debug_switches.py`,
   conformance-availability check. Test count must equal tungsten's (~1,300) ±
   renamed-only adjustments; any dropped/added test is listed in the phase log.
2. **Launch check:** built via `Scripts/build_and_run.sh`; bar appears; settings +
   welcome guide open; window chips switch/minimize; drawer/drag/badges/shelf/
   trash/folders behave as tungsten. Record the check with a short log note.
3. **Side-by-side check:** KatiKati installs and runs alongside a tungsten build
   without sharing defaults, login items, or Accessibility grants.
4. **Trademark audit:** repo-wide search for "Tungsten Edge"/"钨极"/tungstenedge.app
   returns only allowed factual attributions (`NOTICE`, `README` credit line,
   `TRADEMARK.md` note, code comments quoting upstream rationale).

## 5. Change control after baseline lock

1. Once Phase 0 is accepted, the baseline is frozen: tungsten-file behavior changes
   only via planned slices with tests + witnesses (Standing Rules §4.5).
2. Suspected tungsten bugs found later → fix as a slice with a regression test,
   and note the upstream divergence in the commit + phase log (so a future
   upstream re-sync can find it).
3. Donor code enters only through HYBRID_PLAN §5 allow-list rows, one row per
   slice, with the source file + commit pinned in the commit message.
