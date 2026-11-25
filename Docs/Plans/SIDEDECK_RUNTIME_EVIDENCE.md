# SideDeck replatform — runtime evidence (2026-11-25)

Black-box pass on the replatform, run from `/Users/baraka/Desktop/KatiKati-sidedeck` (branch
`feat/sidedeck-replatform`). The app was built with `xcodebuild build -scheme KatiKati` and launched
with `open -n`; nothing was re-signed for Accessibility and `Scripts/build_and_run.sh` was not used.
The deck was opened through its own resting handle (edge activation on, 0.08 s dwell) and driven
through the accessibility tree; state was read back with `defaults read com.katikati.app`.

## SD-7 — ClearDisk before and after the Storage measurement

`defaults read com.katikati.app com.katikati.devcache.snapshot.v1` → *key not found* (nothing has
measured yet). Dashboard accessibility tree, Storage card:

```
AXStaticText | Storage   | 20.30 GB
AXStaticText | Notifications ...
```

Press the rail's Storage item, which measures with its own scan. Four seconds later the page writes
its snapshot and the measurement is persisted:

```
com.katikati.devcache.snapshot.v1 = v1|1795599453|3330863104   (3 330 863 104 bytes)
Storage page header:  223.31 GB used   |   3.33 GB
Storage page rows:    Xcode 3.24 GB (Low) · Swift Package Manager 86.4 MB (Low) · pip 49 KB (Low)
```

Return to the Dashboard (the panel never re-measured — the snapshot epoch is unchanged across
repeated visits):

```
AXStaticText | Storage      | 20.30 GB
AXStaticText | Reclaimable  | 3.10 GB
```

The dashboard reads the persisted total once on appear and adds no scan of its own: after three
Dashboard visits the snapshot key still read `v1|1795599453|3330863104`.

### Corrected figure (same bytes, same unit)

The first pass showed the card as `3.10 GB` and the Storage header as `3.33 GB` for the same
3 330 863 104 bytes: the card formatted with `DownloadItem.formatBytes` (1024-based, labelled GB)
while the page header used `SystemMonitorFormat.bytes` (1000-based, like Finder). The card now
formats both its figures at the callsite with `SystemMonitorFormat.bytes`, the page's own formatter,
without touching either shared formatter:

```swift
// SideDeckDashboardView.clearDiskCard
Text(verbatim: SystemMonitorFormat.bytes(Double(freeBytes)))
...
Text(verbatim: SystemMonitorFormat.bytes(Double(reclaimableBytes)))
```

For 3 330 863 104 bytes that function returns `3.33 GB` — the value the Storage header printed for the
same count — so the two surfaces now state one number. The card's free-space figure moves with the
same formatter, so the card stays internally consistent instead of mixing the two conventions.

**Re-driven after the change (2026-11-25, merged tree `6259c01b`).** A clean Debug build was launched
with the snapshot key deleted; the card showed free space alone (`Storage 12.63 GB`, no Reclaimable
row). Pressing the rail's Storage item measured the caches and wrote
`v1|1795607718|3328528384` (3 328 528 384 bytes) under a header of `232.48 GB used | 3.33 GB`; back on
the Dashboard the card read `Storage 12.63 GB` and `Reclaimable 3.33 GB`. Two further Dashboard visits
(through Downloads and Dictionary) left the key at `v1|1795607718|3328528384`, and the free-space figure
moved with the disk while `Reclaimable` stayed at the stored total. Screenshot of the deck, taken in
that session: `/tmp/card-postfix-final.png` (local only; machines rebuild `/tmp`).

The first drive attempt in the earlier pass failed because the sibling worktree's install script
replaced the running app mid-script; this run completed with that build at rest.

## SD-8 — Settings › Side Deck controls write through

Pane renders with its controls (accessibility dump, `/tmp/ev-sidedeck-pane.txt`): Edge popup `Left`,
Size `400 pt`, Edge Activation `1`, Identity Strip `0`, Open Dwell `0.08 s`, Weather Handle `0`, and
the swap row. Each control was driven and the stored config read back:

| Control | Action | `com.katikati.sidedeck.prefs.v1.*` afterwards |
|---|---|---|
| Identity Strip | toggle, toggle back | `identityStrip` 1 → 0 |
| Weather Handle | toggle, toggle back | `mergedWeatherHandle` 1 → 0 |
| Edge Activation | off | `edgeActivation` 0; the 14×54 pt handle window disappears (10 → 9 windows) |
| Edge Activation | on | `edgeActivation` 1; the handle returns (9 → 10 windows) |
| Open Dwell | increment, decrement | `dwell` 0.08 → 0.10 → 0.08 |
| Size | increment ×2, decrement | `width` 400 → 410 → 420 → 400 |
| Edge | popup `Left` → `Right` → `Left` | `side` left → right → left, and `com.katikati.edge.side` right → left → right |

Open Dwell reports `enabled=false` while Edge Activation is off (the row is disabled, not merely
dimmed), and is enabled again once activation is on.

## SD-8 — the shared swap

With the deck on the left and the Edge Bar on the right, one press of the pane's swap row:

```
before: deck=left   edge bar=right
swap 1: deck=right  edge bar=left
swap 2: deck=left   edge bar=right
```

One button press moves both surfaces, and pressing it again restores both.

## Idle cost — like-for-like, same sampler, 60 s each

Both builds were made with `xcodebuild build -scheme KatiKati` (Debug), staged outside `/tmp` (the
app installs itself on launch, so a bundle under `/tmp` does not survive) and measured with
`Tools/Bench/benchtool`, the sampler `Scripts/bench_katikati.sh` uses: `cpu <app> 60` reports the
process-group CPU over 60 s, `mem <app>` reports each process's `phys_footprint` (Activity Monitor's
"Memory" column). One app at a time; default preferences (`edgeActivation` off, deck closed).

| Build | Revision | CPU, 60 s sample | KatiKati footprint | Group footprint |
|---|---|---|---|---|
| Pre-SideDeck main | `54380aca` | **0.00 %** (two consecutive runs) | **168.3 MB** | 268.1 MB |
| Branch (replatform + fixes) | working tree on `feat/sidedeck-replatform` | **0.00 %** (settled 25 s); one earlier run 1.74 % during launch churn | **162.2 MB** | 261.6 MB |

```
pre:    cpu_pct=0.00                       mem: KatiKati 168.3 MB · swift-frontend 75.4 MB · group 268.1 MB
branch: cpu_pct=0.00  (first run: 1.74)    mem: KatiKati 162.2 MB · swift-frontend 75.0 MB · group 261.6 MB
```

**Verdict:** the 0.0 % idle figure reproduces on both builds under this measurement, so the deck adds
no measurable idle cost; the branch is 6.1 MB *below* the pre-SideDeck build in footprint and equal at
0.00 % CPU. The single 1.74 % reading was the branch sampled 12 s after launch — with the same 25 s
settle the pre-SideDeck build's own first seconds show comparable churn. `ps rss` (~1.2 GB) is shared
pages, not footprint; the numbers above are the comparable ones.

### Re-measured on the closeout tree (2026-11-25, `docs/sidedeck-closeout`)

Same sampler, run from `../KatiKati-sidedeck` on the tree that carries this document, staged outside
`/tmp` (the sampler cannot match a bundle under `/tmp`) and measured with `Tools/Bench/benchtool`:

| Build | Tree | CPU, 60 s sample | KatiKati footprint | Group footprint |
|---|---|---|---|---|
| Debug, fixes included | `docs/sidedeck-closeout` | **0.00 %** | **214.6 MB** | 312.2 MB |

```
idle_cpu_pct=0.00
KatiKati 214.6 MB · swift-frontend 81.9 MB · MTLCompilerService 13.6 MB · group 312.2 MB
```

`Scripts/bench_katikati.sh --idle-only` completed its 60 s CPU window at 0.00 %; the app then exited
before the script's own memory read, so the memory figures come from `benchtool mem` after a 60 s
settle on the same build. **One static surface must stay open**: this is an accessory app that exits
when its last window closes, so it was launched with `DOCK_OPEN_SETTINGS=general` and the Settings
window was left untouched. Ten seconds after launch the same process read 1.99 GB `phys_footprint`;
that transient is launch-time Metal shader compilation (an `MTLCompilerService` child appears with it)
and settles to 214.6 MB by the 60 s mark — a release instance running on this machine during the same
window also read ~1.99 GB while settling, so the transient is not a property of this tree.

Harness note: this app enforces "the newer instance takes over", and the sibling worktree's build
script installs that build into `/Applications` and relaunches it, so long windows die mid-sample.
Every figure above is from a run that completed its full 60 s window.

## Defect found and fixed

The settings "gel" button rows drew their title but exposed no accessible name — the swap row read as
an unlabelled `AXButton`, so VoiceOver and AX automation could not tell it from any other button in
the pane. `SettingsButtonRow` now sets `.accessibilityLabel(title)` (`App/Scenes/SettingsCard.swift`),
which names every row built from it, including both swap rows.

## Deck click path — driven on the closeout tree (2026-11-25)

`Scripts/live_check_side_deck.py` drives the deck through real HID input and asserts the accessibility
tree, closing the earlier pass's gap ("the resting handle's click path was not re-driven"). Run from
`../KatiKati-sidedeck` against the Debug build in `/tmp/katikati-dd-sidedeck`:

```
python3 Scripts/live_check_side_deck.py \
    --app /tmp/katikati-dd-sidedeck/Build/Products/Debug/KatiKati.app \
    --shots build/live-check/side-deck-shots
```

Output (exit 0):

```
  ✅ handle        14x54 at 56,548 (edge +3)
  ✅ open          400x1038 at 64,58 (edge +101)
  ✅ rail          16/16 buttons
  ✅ page dock     5/5 tabs
  ✅ pin toggle     accessibility label present
  ✅ Settings gear  accessibility label present
  ✅ Storage        click 110,526 renders 'Developer & Cache', 'used'
  ✅ Downloads      click 110,388 renders 'URL RESOLVER', 'IN-FLIGHT TRANSFERS', 'TORRENT HUB'
  ✅ collapse      click outside closed the deck
  ✅ Settings      1080x700 — Side Deck pane is listed
```

The pointer move that opens the panel is a `CGEvent` HID move onto the handle's 14 x 54 pt hit window,
not an `AXPress`; the panel then appeared at the configured 400 pt width, full height (58 → 1096 on a
1112 pt screen, matching `SideDeckConfig.topInset` 20 and `bottomInset` 16). The rail clicks are HID
clicks at the positions AX reports, and the assertion is the pane text that appears afterwards, so a
rail that stopped swapping panes would fail even though the window still opened.

Two behaviours the render promised do not exist in this build. They are recorded rather than assumed:

- **There is no chevron control.** The rail's foot is the **Pin Strip Open** toggle; no view in
  `WindowDrawerController` draws a collapse chevron. Collapse ships as a click outside the panel (its
  global click monitor), which the check drives and asserts.
- **Escape is inert.** `DrawerPanel.cancelOperation` exists, but the panel is a `nonactivatingPanel` in
  an accessory app and never holds key focus. A synthetic Escape posted to the app's own event queue
  left the panel open, with the process confirmed alive before and after.

## Defect found and fixed — the deck's Settings gear

The identity strip's gear called `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from:
nil)`. No responder in this app implements `showSettingsWindow:` — every other surface opens Settings
through `AppDelegate.openSettings(selecting:)` — so the button did nothing: the deck drive clicked it
at its reported position and no window appeared. It now calls
`AppDelegate.shared?.openSettings(selecting: .sideDeck)` and carries
`.accessibilityLabel(Text("Settings"))`, so VoiceOver and AX automation read a name instead of the SF
Symbol fallback "Gear Shape".

## Closeout gate run — merged tree `6259c01b`

Run inside `../KatiKati-sidedeck` from a branch cut at `origin/main` (`6259c01b`), 2026-11-25. Every row
below is a command's exit code or an accessibility read, not an inference.

| Gate | Command | Result |
| --- | --- | --- |
| Clean build | `xcodebuild build -project KatiKati.xcodeproj -scheme KatiKati -derivedDataPath /tmp/dd-clean` (full compile, no `-quiet`) | exit 0 — log `/tmp/clean-build.log` |
| Availability | `python3 Scripts/check_availability_warnings.py /tmp/clean-build.log` | exit 0; `grep "is only available in macOS"` = **0** |
| Nine suites | Settings, SideDeck, DevCacheCatalog, DevCacheSnapshot, DeckGeometry, ControlCenterLayout, ControlCenterReadability, NotificationDigest, DownloadEnginePolicy | **63 passed, 0 failed**, exit 0 |
| Settings livecheck | `python3 Scripts/live_check_settings_tabs.py --app … --shots …` | all **34** pages, exit 0, 34 screenshots |
| ClearDisk card | driven through AX on that build | `Reclaimable 3.33 GB` = header `3.33 GB` |

### Re-run on the closeout branch (2026-11-25, `docs/sidedeck-closeout`)

| Gate | Command | Result |
| --- | --- | --- |
| Ten suites | Settings, SideDeck config + logic, DevCacheCatalog, DevCacheSnapshot, DeckGeometry, ControlCenterLayout, ControlCenterReadability, NotificationDigest, DownloadEnginePolicy | **80 passed, 0 failed**, exit 0 (`/tmp/sidedeck-gate/xcodebuild-after-fix.log`) |
| Localization | `python3 Scripts/check_localization.py` | exit 0 — 2 630 keys × 12 locales, no orphans |
| Debug switches | `python3 Scripts/check_debug_switches.py` | exit 0 — 94 registered |
| Input hygiene | `python3 Scripts/check_input_hygiene.py` | exit 0 |
| Availability | `python3 Scripts/check_availability_warnings.py <test-build log>` | exit 0, no cross-version warnings |
| Deck click path | `python3 Scripts/live_check_side_deck.py …` | exit 0 — section above |
| Idle | `Scripts/bench_katikati.sh --idle-only` + `benchtool cpu/mem 60` | 0.00 % CPU, 214.6 MB |

### Livecheck harness fix

`Scripts/live_check_settings_tabs.py` waited 7 s (14 x 0.5 s) for a Settings window. `AppDelegate`
presents the page 3 s after the strip starts, so a cold launch on a loaded machine exceeded that: the
first run missed seven pages and the second still missed `widgets`, while the same page opened fine by
hand. The poll now runs to 20 s and still stops at the first window; the confirming run opened all 34.
This was a gate defect, not a pane defect — no app source changed for it.

## Open / limitations

- **No chevron control exists in the deck.** The render's bottom chevron never shipped; the rail's foot
  is the **Pin Strip Open** toggle. Collapse is a click outside the panel, which the deck live-check
  drives and asserts.
- **Escape does not close the deck.** The panel is a `nonactivatingPanel` in an accessory app, so it
  never holds key focus and `cancelOperation` never fires; an Escape posted to the app's own event
  queue left it open with the process confirmed alive. A behaviour gap, named rather than glossed.
- **The identity strip is off by default**, so its gear exists only with
  `com.katikati.sidedeck.prefs.v1.identityStrip = true`. The deck live-check saves, enables and
  restores that value and `edgeActivation` around its run; the user's own values were `0` and were put
  back to `0`.
- **The deck live-check asserts the accessibility tree, not pixels.** It reads the sixteen rail labels,
  the five page-dock tabs, the Pin toggle and the gear, then the pane text each rail click renders, and
  that the gear opens a window listing **Side Deck**. Screenshots are captured per step but not
  compared.
- **The Settings livecheck (`live_check_settings_tabs.py`) still asserts only window size**; it does
  not read page content. The deck check is the one that reads rendered content.
- **Idle was measured with one static surface open** (Settings › General): the app exits when its last
  window closes, so a windowless idle sample is not possible with this harness.
- Screenshots from the deck check live in `build/live-check/side-deck-shots/` — the repo's own
  gitignored live-check workspace, which is why they are not committed. The earlier
  `/tmp/sidedeck-livecheck-shots4/` and `/tmp/card-postfix-final.png` were local only and are gone.
