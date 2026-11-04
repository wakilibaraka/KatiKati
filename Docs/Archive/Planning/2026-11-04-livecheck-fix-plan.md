# Livecheck fix plan — 2026-11-04

Built from the full-surface livecheck audit, the drawer-pop click fix (`e82fadf`) and the
instrumented hit-test pass that found it. Every slice names the defect, the anchor, the shape of
the fix and the proof required to close it. Slices are one pass each.

**Standing proof block** (run in every slice, report the output, never "rebuild and hope"):

```
xcodebuild -project KatiKati.xcodeproj -scheme KatiKati -configuration Debug \
  -derivedDataPath build/DerivedData build            # BUILD SUCCEEDED
xcodebuild test ... -only-testing:KatiKatiTests/<Suite>  # for the slice's own test
python3 Scripts/check_localization.py                # ✅ 全部对上 when strings change
swift build/kkclick.swift X Y ; sleep 1.2 ; screencapture -x /tmp/p.png   # live click + pixels
swift /tmp/kkwin.swift                               # what windows appeared (level/size)
```

`build/kkclick.swift` and `build/kkhover.swift` post real HID events at **points** (not retina
pixels: `points = pixels / 2`); `NSEvent.mouseLocation` is bottom-left, `CGEvent` is top-left.
Both are throwaway helpers under the gitignored `build/`.

---

## Slice 0 — One chip-frame registry (structural, blocks further chip work)

**Why first.** The drawer pop chip was hit-test-dead for a whole session because
`allStripChipFrames()` is a hand-maintained union and `popFrame` was never added to it. Trash,
folders, messaging chips and sections each had their own frame publisher plus their own dictionary
on `DockStripView`. Any ninth chip type repeats the bug, silently: the chip still hovers, still
shows its tooltip, and only the click disappears.

**Defect.** `allStripChipFrames()` (`App/Scenes/DockStripView+Hover.swift:178`) unions
`chipFrames`, `folderChipFrames`, `messagingChipFrames`, `sectionFrames`, `shelfFrame`,
`trashFrame`, `popFrame`. Seven publishers, one consumer, no compile-time link between them. The
consumer is the AppKit overlay that decides chip-vs-empty bar
(`MenuHostNSView.hitTest`, `App/Scenes/AppMenuFragments.swift`) via `StripContextMenuZone.claims`
/ `gripClaims` (`Core/Support/StripContextMenuZone.swift:29`, `:78`).

**Fix shape.** One `StripChipFrames` value that every chip reports into (a single
`PreferenceKey` carrying `[StripEntry.ID: CGRect]`), with `claims`/`gripClaims` taking that
dictionary's values. Delete the four dictionaries and the union once nothing reads them. Keep the
StripContextMenuZone maths untouched — it is correct, it was the *input* that was incomplete.

**Proof.** A unit test that fails on today's code: for each `StripEntry` case with a non-zero
frame, `StripContextMenuZone.claims(at: frame.mid)` must be `false`. Plus the live regression that
started this: click every chip in the bar in one launch (launcher, weather, each app, pop, folder
chips, shelf, Trash) and assert each fires its action — window count/size change for pop, Trash
and launcher; app activation for app chips.

**Risk.** Touching the drop-routing and jump-list consumers of the same dictionaries; keep them on
the new registry in the same commit, not a second one.

---

## Slice 1 — Downloads pop: list `~/Downloads`, ask for access once

**Defect (user-visible, most severe).** Clicking the Downloads chip shows the plate, then the empty
"Open in Finder" state, and raises a *Files & Folders → Downloads* system prompt on **every** open.
The folder has 135 items.

**Cause, from the code.** `openFolderPopup` seeds the popup from a **150 ms synchronous** preload
(`App/Entry/PanelCoordinator+Popups.swift:117`, `FolderContentsLoader.preload ... timeout: 0.15`).
On a cold, unauthorised read that returns `nil`, so `FolderGridPopupView(initialEntries: nil …)`
starts with nothing; its async `reload` (`App/Scenes/FolderGridPopupView.swift:57`) then hits the
same denied read, and on failure **replaces the contents with `[]`** and sets `loadFailed`
(line 72). Nothing stores a grant: the only `bookmarkData` use in the tree is
`Core/Support/RecentDocumentsReader.swift:113` — the folder-pin path has none.

**Fix shape.** Ask once, store the grant, load without prompting afterwards:
1. On the first open of a pinned folder that is not yet authorised, run the system's own chooser
   (`NSOpenPanel`, `directoryURL = ~/Downloads`) — that is the single prompt the user sees, and it
   comes from their click.
2. Persist a security-scoped bookmark next to the pinned path in `PinnedFolderStore`
   (`App/Composition/PinnedFolderStore.swift`), resolve + `startAccessingSecurityScopedResource()`
   around the load, and stop the load entirely (`stopAccessing…`) when the popup closes.
3. Treat "no grant yet" as its own state in `FolderGridPopupView` (a "Grant Access…" line), never as
   the empty-folder state — an empty Downloads must look different from an unauthorised one.

**Proof.** Kill the app, relaunch, click Downloads **once**: exactly one prompt; plate lists 135
items in the same first frame (screenshot); second open → no prompt, list immediate (screenshot,
0 ms preload hit). Unit test on the store: bookmark round-trip survives re-encode, and a revoked
grant lands in the "needs grant" state, not the empty state.

---

## Slice 2 — Calendar prompt at launch

**Defect.** A Files-&-Access/TCC calendar prompt appears at launch with no user action, blocking
the first seconds of the session.

**Cause.** `ClockChip.onAppear` requests full event access whenever access is `unknown`
(`App/Scenes/ClockChip.swift:337`), and `requestEvents` calls
`EKEventStore.requestFullAccessToEvents` (`App/Composition/CalendarService.swift:92`). The clock
chip is on the bar at launch, so the prompt is a launch prompt.

**Fix shape.** Drop the `onAppear` request; ask on the first *calendar-intent* action instead —
opening the calendar panel or the date flyout — and keep an inline "Allow calendar" row in that
panel for the denied state. `CalendarPanelView.onAppear` already calls `start()`
(`App/Scenes/CalendarPanelView.swift:63`); that is the right trigger.

**Proof.** Fresh launch with access `notDetermined` (reset with `tccutil reset Calendar`): no prompt
in the first 30 s of screenshots; open the calendar panel → prompt appears once; deny → panel shows
its inline row, bar keeps rendering.

---

## Slice 3 — Pop theme actually tints the pop plate

**Defect (unproven / possibly inert).** Choosing a pop theme visibly re-tints the drawer chip, but
the pop's own plate looked unchanged in the live pass. Two presets rendered side by side were not
distinguishable.

**Anchors.** The pop receives the preset (`App/Entry/PanelCoordinator+Popups.swift:193`,
`.environment(\.dockThemeStyle, store.theme ?? settingsStore.themeMaterial)`), and
`StackPopupChrome` consumes it, but only through `DockThemeTokens`
(`App/Scenes/StackPopupChrome.swift:63-64`, `:230-231`). The plate tint itself lives in
`DockThemeStyle.plateOverlay` / `plateOverlayBottom` and is applied in exactly one place —
`App/Scenes/DockGlassBackdrop.swift:121-126`.

**Fix shape.** Either route the popup plate through the same `plateOverlay` application (preferred:
one shared helper, no new option), or, if the plate is deliberately theme-neutral, remove the theme
menu from the pop rather than shipping a control that changes only the chip. Decide from the pixel
diff, not from reading.

**Proof.** Open the pop with *Match App*, screenshot; switch to *Deep Ocean*, screenshot; crop the
same plate rect and diff — a non-zero, human-visible difference in plate tint. Keep both crops in
`build/` and link them in the pass report.

---

## Slice 4 — Dock Items rows without the dev flag

**Defect (unproven surface).** Drawer and Background Apps toggles exist
(`App/Scenes/SettingsLayoutPane+Widgets.swift:113`, `:118`) but Settings could only be opened in
this session with `DOCK_DEV_SKIP_PERMISSIONS=1`; the normal status-menu path is gated on the
Accessibility grant (`App/Entry/AppDelegate.swift:509`,
`PermissionRecoveryCoordinator.launched(trusted:)`).

**Fix shape.** Nothing to build if the gate is correct — this slice is *proving* the normal path, on
a machine with Accessibility granted, and only changing code if the gate turns out to hide Settings
from a trusted install. Do not relax the gate to make testing easier.

**Proof.** On the installed, trusted copy: status menu → Settings → Layout → Dock Items; toggle
Drawer and Background Apps off/on and watch the corresponding chip and capsule appear/disappear
(screenshot each state), with the preference surviving relaunch.

---

## Slice 5 — Menubar attribution and notch widgets

**Defect (unproven, not necessarily broken).** The bar renders and the notch island narrows/expands
on click with battery `53 %` visible while audio played, but menubar item *ownership* was
unattributable because Vorssaint draws competing clock/battery items, and the island's inner pages
were never walked.

**Anchors.** `App/Composition/MenuBarSystemItem.swift:14` (`items: [MenuBarMetric: NSStatusItem]`),
`App/Composition/DriveMenuBarItem.swift:10`, `App/Entry/StatusMenuController.swift:45`,
`App/Scenes/NotchIslandView.swift`, `App/Scenes/Notch/NotchDockChips.swift`.

**Fix shape.** Probably none — measure first. If an item is duplicated against Popspec/Vorssaint,
gate it behind the existing settings toggle rather than adding a new one.

**Proof.** Log every `NSStatusItem` this app creates (creation site, length, title) and match it to
the bar by position while Vorssaint is quit; then re-check with Vorssaint running and confirm each
pill belongs to exactly one owner. For the notch: click the island (screenshot narrow → expanded),
enter each page by its own control, and confirm battery percentage stays visible while a track is
playing (screenshot with the media widget playing).

---

## Slice 6 — Make the proof repeatable

**Defect.** Every pass so far improvised its own click/screenshot helpers in `/tmp`, so findings were
not reproducible by the next pass.

**Fix shape.** One small script that starts `caffeinate`, resolves the strip window rect from
`CGWindowList`, converts a strip-space chip frame to screen points and clicks it, then screenshots.
No new product code.

**Proof.** Run it twice in a row from a clean launch and get the same result; a new pass can verify a
chip without rediscovering coordinates.

---

## Ordering rationale

0 before 1–6: the frame registry is the class of bug that just cost a session, and every later slice
that touches chips or the bar would have to be re-verified against it. 1 before 2: a popover that
cannot show its folder is a broken requested feature; a launch-time prompt is friction. 3 is small
and visible, so it rides right after the user-facing defects. 4 and 5 are *proof* slices on surfaces
that may already be correct — they are last because they change no behaviour unless the proof fails.
6 is last because it only pays off once the slices above are being verified repeatedly.

## What could not be verified from this machine, and why

- **Accessibility-gated surfaces** (Settings from the status menu, the onboarding/recovery flow):
  this dev build runs untrusted; only `DOCK_DEV_SKIP_PERMISSIONS=1` rendered Settings. Needs a
  trusted install.
- **Menubar ownership:** Vorssaint draws its own clock and battery items at the same positions, so a
  screenshot cannot attribute a pill to this app. Needs Vorssaint quit, or the logging in slice 5.
- **Downloads listing:** every attempt raised the system Files-&-Folders prompt; the grant was given
  once during the audit but the plate still listed nothing, which is the defect slice 1 fixes.
- **Pop plate theme:** the offscreen snapshot probe renders cells but no glass plate, and the live
  plate showed no visible change between presets — unproven in both directions until slice 3.
- **Synthetic clicks:** posted HID events drive hover reliably but taps were intermittent for part of
  the session (display sleep). The pop-chip verdict was taken only from a run where the click landed
  (`popChipTapped` logged) and a popup window appeared.
- **A fresh music start:** the audio session was already playing when the battery-while-playing check
  ran, so "percentage returns when playback starts" was not exercised from silence.
