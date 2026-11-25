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
Dashboard visits the snapshot key still read `v1|1795599453|3330863104`. The two figures differ only
in unit convention — 3 330 863 104 bytes is 3.10 GiB (`DownloadItem.formatBytes`, same formatter as
the card's free space) and 3.33 GB (`ByteCountFormatter`, decimal, used by the Storage header).

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

## Idle cost

`Tools/Bench/benchtool` (the tool `Scripts/bench_katikati.sh` uses) on the built app, 30 s window
with the deck closed and no windows open:

```
cpu_proc pid=KatiKati          pct=2.28
cpu_proc pid=swift-frontend    pct=0.36   (the now-playing helper the app interprets)
cpu_pct=2.63                              (process group)
total_mb=161.7  →  KatiKati 77.0 MB · swift-frontend 81.9 MB · SetStoreUpdateService 2.8 MB
```

Repo baseline for comparison (`HYBRID_PLAN.md` §livecheck sweep): idle CPU `6.2 %` (`ps %cpu`) and
`9.50–10.38 %` instantaneous, RSS `68.3–143.9 MB`. The replatform's 77.0 MB app footprint sits in
that range and its group CPU is below the recorded baseline. `ps -o rss` reports ~1.2 GB for the same
process because that column counts shared pages; the footprint number above is the comparable one.

**Harness limit, stated plainly:** this app enforces "the newer instance takes over" — a second copy
of the same bundle id terminates the running one — and a concurrent build script in the sibling
worktree relaunches its own build every one to two minutes. That repeatedly truncated the long
settle/deep-idle window: `Scripts/bench_katikati.sh --idle-only` measured `error: KatiKati is not
running` after its 120 s settle, and a 60 s sample was cut short the same way. The numbers above are
the complete samples that survived; a 120 s-settle deep-idle run on an otherwise quiet machine is
still owed.

## Defect found and fixed

The settings "gel" button rows drew their title but exposed no accessible name — the swap row read as
an unlabelled `AXButton`, so VoiceOver and AX automation could not tell it from any other button in
the pane. `SettingsButtonRow` now sets `.accessibilityLabel(title)` (`App/Scenes/SettingsCard.swift`),
which names every row built from it, including both swap rows.
