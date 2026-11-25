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
same formatter (`20.30 GB` → `21.79 GB` for the same disk), which keeps the card internally
consistent instead of mixing the two conventions.

**What could not be re-driven after the change:** the sibling build script installs its own build
into `/Applications` and relaunches it every 30–60 seconds; this app terminates the older instance
on launch, and the last five attempts died inside the drive script (AX returned `Invalid index`).
The pre-fix drive above is the recorded rendering; the post-fix agreement is by construction (same
function, same byte count, the header's own output `3.33 GB` for those bytes) but was not photographed
in the running app.

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

Harness note: this app enforces "the newer instance takes over", and the sibling worktree's build
script installs that build into `/Applications` and relaunches it, so long windows die mid-sample.
Every figure above is from a run that completed its full 60 s window.

## Defect found and fixed

The settings "gel" button rows drew their title but exposed no accessible name — the swap row read as
an unlabelled `AXButton`, so VoiceOver and AX automation could not tell it from any other button in
the pane. `SettingsButtonRow` now sets `.accessibilityLabel(title)` (`App/Scenes/SettingsCard.swift`),
which names every row built from it, including both swap rows.
