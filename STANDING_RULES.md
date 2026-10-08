# KatiKati — Standing Rules

> How we work on this repo, every session, every phase. Change only with owner
> sign-off; record changes in `CHANGELOG.md`.
> Locked: 2026-10-08 · Owner: Emmanuel Baraka · Core: tungsten-edge @ a4e1a55
> License: GPL-3.0-or-later · Bundle id: `com.katikati.app` · Defaults: `com.katikati.*`

## 1. Session discipline (slow, incremental, always shippable)

1. **One slice at a time.** Each work item is small, reviewable, test-backed. Past
   ~300 lines of diff or two concerns mixed → split before starting.
2. **Plan → implement → verify, every slice.** State files to touch + tests to
   add/update *before* editing. End every slice with the tungsten gate green (§4).
3. **No drive-by refactors.** Tungsten code is behavior-frozen unless the slice's
   stated goal requires it. Extension and re-skin over rewrite, always.
4. **Ask when in doubt.** Ambiguous requirement, conflicting tungsten behaviors, or
   more than one faithful port reading → stop and ask the owner. Record the decision
   in the commit message.
5. **External sources where applicable.** AX/CG/Spaces/fullscreen facts, Apple API
   availability, signing/notarization rules → check current Apple docs or a minimal
   local experiment, never memory alone. Link the source in commit or comment.
6. **Structured edits first (owner 2026-10-08).** Source edits use precise,
   single-anchor editor operations (one replacement, visible diff before write).
   Regex/`sed`-class scripted edits only when **all three** hold: the pattern's
   occurrence list is verified with `git grep` first; the pattern is anchored /
   word-boundary (never blanket `let`/`var`/identifier class matches); and the edit
   is verified by build + targeted tests + a grep proving the old token is gone.
   **Forbidden regardless:** heredoc (`cat <<EOF`) appends into source; throwaway
   scripts in the repo root (`/tmp` only, if unavoidable); `rm <glob>` inside the
   repo. Value-frozen files (`Core/Support/*Tokens*`) and comment-as-spec files get
   hand edits only, with the test diff in the same commit. Scripted-edit
   justification goes in the commit message.

7. **Agent hygiene — no vibe-coding damage (owner 2026-10-08).** Exhibits from the
   4d slice (2026-10-08): a helper script rewrote `project.pbxproj` wholesale
   (~2,500 churned lines for a 4-file addition); a second script bulk-wrote
   `Localizable.xcstrings` (+847 lines of unreviewed translations); throwaway
   scripts + `build.log` landed in the repo root; unscoped ±line edits rode along
   in orchestrator/coordinator/strip files. Rules, binding on every agent:
   a. **Generated files are append-only by hand.** `project.pbxproj`,
      `*.xcstrings`, `Package.resolved`: add entries with single-anchor editor
      ops; never regenerate, re-sort, or script-rewrite. pbxproj diffs past
      ~30 lines for a file addition are rejected on sight.
   b. **Translations are human-reviewed.** Scripted `xcstrings` writes are
      drafts only; every non-English value needs a speaker or back-translation
      pass before merge. The localization gate checks completeness, not
      correctness — never cite it as proof of translation quality.
   c. **Repo root stays clean.** No `*.py`, no `*.log`, no scratch files at root
      or in `Scripts/` unless the file is a permanent, plan-authorized tool.
      Scratch goes to `/tmp`. `git add` names files explicitly — never bare
      `git add .` on a tree another agent may be editing.
   d. **Scope receipts.** Every touched file outside the slice's stated file
      list gets one commit-message line: what changed there and why the slice
      required it. Untouched-by-design files with diffs are drive-bys (§1.3).
   e. **No eager singletons for gated features.** Feature-gated services
      (weather, now-playing, edge bars) initialize lazily behind their
      `com.katikati.*` key — never as eager stored properties on app launch.
   f. **Diff budget enforced at commit time.** `git diff --stat` over ~300
      lines or touching generated files → stop, split, and ask before
      committing. A green suite never excuses an unreviewable diff.


## 2. Architecture invariants (HYBRID_PLAN §§3–4)

1. **Tungsten vocabulary stays canonical.** New names only for the layout-mode layer
   (`BarLayoutMode`, `BarSection`, `IslandLayoutSolver`, `displayUUID#slot`). Never
   rename a tungsten type to "fit" KatiKati.
2. **Pure decisions live in `Core/Support`, get unit tests.** No AppKit, no AX in
   Core. Pure function of facts → Core first, tested, *then* wired into UI. This is
   why tungsten's suite is large without a UI harness — keep it that way.
3. **Extend the orchestrator, never fork it.** Multi-island work goes through
   `TaskbarScreenOrchestrator.rebuildUnits` + per-`Unit` `PanelCoordinator`. No
   parallel panel manager, no second strip engine.
4. **Modes change where chips render, never what a chip means.** `StripItem`
   identity (`groupID`), optimistic states, toggle planning, per-display filtering
   behave identically in every island and every mode.
5. **Geometry authority order:** tungsten `PanelGeometry`/`PanelLayoutMetrics`
   (outer frames, clamps, anchors) → `IslandLayoutSolver` (pure island split,
   validated by tungsten clamps) → views (read, never recompute).
6. **Port allow-list is normative** (HYBRID_PLAN §5). Unlisted = not ported. Donor
   code adapts to tungsten APIs — never the reverse.


## 3. Compatibility and identity rules

1. **Bundle id `com.katikati.app`, defaults `com.katikati.*`.** Never read/write
   `com.tungsten.edge.*` / `com.caye.macosdockcc.v2` except in the one-way first-run
   migrator (Phase 0). Never reuse `com.baraka.splitbar` — side-by-side installs stay
   possible.
2. **macOS floor 12.0, Swift 5.0, Xcode project build.** New APIs `#available`-gated;
   Liquid Glass only behind `#available(macOS 26.0, *)` with tungsten fallback. CI
   stays `macos-26` + newest Xcode 26.
3. **Twelve localizations stay green.** Every user-facing string in every language;
   `Scripts/check_localization.py` must pass. No hardcoded user-facing English.
4. **Every `DOCK_*` switch registered** in `Core/Support/DebugSwitch.swift` with
   polarity + purpose; `Scripts/check_debug_switches.py` must pass.
5. **One dependency: Sparkle (pinned).** No additions without owner sign-off +
   license check. Donor ports stay dependency-free.

## 4. Quality gates (every slice, every phase)

1. **Tungsten gate green:** `xcodebuild test` (renamed project/scheme,
   `CODE_SIGNING_ALLOWED=NO`) + `check_localization.py` + `check_debug_switches.py`
   + conformance-availability check. No slice merges red.
2. **New behavior ⇒ new/updated tests.** Pure logic → XCTest Core-style. Panel
   frames/anchors → geometry tests. "Tested manually" is never the only evidence
   where a unit test could cover it.
3. **No warnings-as-errors regressions.** Fix new warnings in touched code;
   pre-existing warnings elsewhere are out of scope unless your slice caused them.
4. **Dev loop only via `Scripts/build_and_run.sh`.** Never bare `xcodebuild` +
   `open` — the Accessibility grant follows the signing identity.
5. **Behavior deltas need a witness.** Intentional tungsten-behavior changes ship
   with a test, log excerpt, or screenshot. Unintentional deltas are bugs.


## 5. Licensing and trademark (absolute)

1. **GPL-3.0-or-later governs the repo** (confirmed 2026-10-08). Keep `LICENSE`, keep
   copyright notices, document changes per version, ship source (or written offer)
   with binaries.
2. **Never ship Moonbai Studio's marks.** No "Tungsten Edge"/"钨极", no tungsten icon,
   no tungstenedge.app links, no official cask/feed in product, menu bar, website, or
   listings. Factual "based on Tungsten Edge" in code/docs is allowed and required.
3. **Attribution stays intact:** `NOTICE` carries tungsten (GPL-3.0-or-later,
   © Moonbai Studio) + donor entries as code lands (SplitBar-old MIT, DockBar MIT).
   SketchyBar & yabai = study only, never paste. Private API (SkyLight/SLS,
   `NSGlassEffectView`) isolated + `#available`-gated + flagged in PRs.

## 6. Documentation and visibility

1. **Every commit message:** what changed, why (plan section/issue), how verified
   (gate + named check), decisions taken with owner answers summarized.
2. **`CHANGELOG.md` in the same PR** as any user-visible change, tungsten
   release-note style, archived per version under `Docs/Archive/Releases/`.
3. **HYBRID_PLAN stays the map.** Implementation diverging from plan → update the
   plan section in the same PR. Superseded text struck through with date, not
   deleted, until the phase closes.
4. **Phase logs:** each phase gets a dated entry under `Docs/Archive/Planning/`
   (scope in/out, decisions, evidence, deferred items). New sessions start by
   reading the latest phase log.
5. **Screenshots/logs for UI slices.** Before/after shots or panel-frame logs in the
   PR so reviewers without a build still see the effect.
