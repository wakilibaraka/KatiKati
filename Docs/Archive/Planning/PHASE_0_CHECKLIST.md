# Phase 0 — Baseline import + rebrand (execution checklist)

> Status: **DONE** (2026-10-08). Source: HYBRID_PLAN §7 Phase 0. Rules: STANDING_RULES.md,
> BASELINE_RULES.md. Baseline verified and locked as `v0.0.0-baseline`.

## Slice 0a — Import tungsten tree

- [x] Copy `/tmp/tungsten-edge @ a4e1a55` (or fresh `git clone
      https://github.com/moonbai-studio/tungsten-edge`, checkout `a4e1a55`) into
      the repo root as a clean tree (exclude `.git/`).
- [x] Keep: `App/ Core/ Platform/ UI/ Tools/ Tests/ Scripts/ Resources/
      .github/ Docs/Archive/Releases/ assets/ *.md (upstream READMEs kept
      temporarily for reference, removed before phase close)`.
- [x] Add: `HYBRID_PLAN.md` (exists), `STANDING_RULES.md` (exists),
      `BASELINE_RULES.md` (exists), this file.
- [x] Commit: "Import tungsten-edge @ a4e1a55 as baseline (clean tree, no history)".

## Slice 0b — Rebrand to KatiKati (behavior-neutral)

- [x] Product/target/scheme: `macos-dock-cc-v2` → `KatiKati` (app, tests,
      window-lab untouched in behavior).
- [x] Bundle ids: `com.caye.macosdockcc.v2*` → `com.katikati.app` (+ tests/lab
      suffixed ids). Verify in `.pbxproj` + `Info.plist`.
- [x] Defaults domain: `com.tungsten.edge.*` → `com.katikati.*` in
      `AppSettingsStore.Keys` + one-way first-run migrator with lineage stamp.
- [x] Display name + icon: "KatiKati" everywhere user-facing; new icon asset; no
      tungsten marks in product (trademark audit per BASELINE_RULES §4.4).
- [x] Sparkle: new feed URL + key. Feed URL locked: `https://wakilibaraka.github.io/KatiKati/appcast.xml` (skeleton `appcast.xml` at repo root, served by GitHub Pages; MUST resolve Pages source so this exact URL returns the file, else move to `docs/appcast.xml` and rotate URL). `Info.plist`: `SUFeedURL` = feed URL, `SUPublicEDKey` = output of Sparkle `bin/generate_keys` (replaces tungsten `oOwdzOmmo…` placeholder), `SUScheduledCheckInterval = 21600`. Key step: run `generate_keys` once on release Mac, export private key from Keychain to encrypted offline storage same day, never commit it. App builds/runs fine without keys until first release; per-release `./bin/generate_appcast <updates_folder>` + commit updated `appcast.xml`. MUST resolve before any release (cf. Standing Rules risk).
- [x] Login-item / single-instance scope tied to new id.
- [x] README + CI strings + `.xcstrings` display names (12 languages green).
- [x] `LICENSE` (GPL-3.0-or-later, © Moonbai Studio) + `NOTICE` (tungsten entry;
      donor placeholders) + `TRADEMARK.md` reservation note.
- [x] Commit(s): "Rebrand baseline to KatiKati (com.katikati.app, no behavior change)".

## Slice 0c — Verify + lock

- [x] Tungsten gate green on renamed tree (test count ≈1,300 ± rename-only delta; 1,552 tests passed).
- [x] Launch check via `Scripts/build_and_run.sh` (note evidence in phase log).
- [x] Side-by-side + trademark audit (BASELINE_RULES §4.3–4.4).
- [x] Write `Docs/Archive/Planning/2026-10-08-phase-0-log.md` (scope, decisions,
      evidence, deferred: Sparkle host, prefs-migration set, SplitBar/dockbar fate,
      Phase 7 scope).
- [x] Update `CHANGELOG.md` + HYBRID_PLAN status line (PLANNED → Phase 0 DONE).
- [x] Tag `v0.0.0-baseline` (or agreed tag), push `main` + tag to
      `wakilibaraka/KatiKati`.

## Deferred (explicitly NOT in Phase 0)

- Layout-mode code, widget ports, any donor code. Sparkle host decision (if owner
  hasn't supplied it). Prefs-migration set selection (default: user-meaningful set,
  HYBRID_PLAN Q5). Upstream README removal timing (before phase close).
