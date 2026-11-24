# Music Wallpaper & Lock-Screen Plan (`ML-1` → `ML-6`)

> **Status:** Audit complete, zero-`pbxproj` refinement applied; awaiting sign-off to begin `ML-1`.
> **Branch:** `feat/music-lockscreen-wallpaper` (worktree at `../KatiKati-music-lockscreen`, branched from `origin/main`).
> **Reference:** [`slopyydev/halo-music`](https://github.com/slopyydev/halo-music) (MIT) + Canapé interaction design.
> **Target:** KatiKati (`KatiKati.xcodeproj`, macOS 15.0 deployment target, Swift 6).

---

## 1. Reference audit: what `halo-music` actually does

**License:** MIT (repo page + `LICENSE`). `THIRD-PARTY-NOTICES.md` covers its Electron/npm stack; that stack is irrelevant to a native port. Attribution belongs in `NOTICE`/Settings › Credits only for anything we actually copy — this plan copies the *visual language and perf rules*, not code.

**Its "lock-screen controls" are not an overlay.** The README documents three layers:

1. **Audio survives the lock.** Chromium treats a locked Mac as occluded and throttles the renderer; Halo disables `backgroundThrottling`, `disable-renderer-backgrounding`, `disable-backgrounding-occluded-windows` and `CalculateNativeWinOcclusion`, and holds a `prevent-app-suspension` power blocker *only while playing*.
2. **Metadata reaches the system.** `navigator.mediaSession.metadata` (title/artist/album/artwork in five sizes) plus position state on every seek.
3. **System buttons drive playback.** Handlers for `play`/`pause`/`stop`/`nexttrack`/`previoustrack`/`seek*`, so Control Center, media keys and AirPods gestures work.

There is **no lock-screen window, window level or Space trick** in the project. So there is nothing to port for a "floating card above Touch ID": layers 1–3 are what any *player* gets for free, and KatiKati is not the player.

**Portable parts**

| Halo rule | Native application here |
| --- | --- |
| Monochrome black/white/grey gradients | Card palette in all three glass modes |
| One `backdrop-filter` in the whole app | One `NSVisualEffectView`/glass surface per card, no nested blurs |
| Animate only `transform`/`opacity` | Waveform via `scaleY`, motion via offset/opacity |
| Static painted background, no animated full-screen orbs | Classic backdrop: one cached file, zero timers |
| Targeted updates, early-exit progress loop | The card re-renders only on published state change |

**Non-portable:** the power blocker and occlusion flags (KatiKati plays nothing); media-session registration (see §2.4).

---

## 2. macOS API constraints (honest limits)

### 2.1 Drawing over the Lock Screen needs a private SkyLight space
No public API exists for a third-party view above the lock UI. The working route — used by `Lakr233/SkyLightWindow` (MIT), by t3code's native lock-screen helper, and already planned as `LQ-5.3` in `Docs/Plans/LIQUID_NOTCH_PORT_PLAN.md` — is a private SkyLight space at a privileged level.

KatiKati already owns that machinery: `Platform/CoreGraphics/OverlaySpaceHost.swift` (`SLSMainConnectionID` → `SLSSpaceCreate` → `SLSSpaceSetAbsoluteLevel` → `SLSShowSpaces` → `SLSSpaceAddWindowsAndRemoveFromSpaces`), and `App/Composition/DockWindowManager.swift` reinforces levels through `CGSSetWindowLevel`. ML-3 uses those, not a new subsystem.

Limits to document in-app:
- **Private API.** A macOS update can break it; symbols are resolved with `dlsym` and a missing symbol must degrade to "no card", never to a crash.
- **Ownership of the auth UI.** `loginwindow`/SecurityAgent owns the Touch ID and password fields. A card can *draw* near them; synthesized input into that context is rejected, so the card must be click-through-safe and never claim to control the auth UI.
- **Layering is not guaranteed above the password prompt on every version.** The card anchors a fixed offset above the bottom safe area; the anchor is a preference, not a promise.
- **One engine.** ML-3 absorbs `LQ-5.3` and reuses `LiquidExtrasKeys.lockScreenEnabled` (`Core/Support/NotchLayoutSpec.swift`) so there is exactly one lock-screen setting in the app. If ML-3 ships first, `LQ-5.3` is cancelled in `LIQUID_NOTCH_PORT_PLAN.md`; nothing else in the notch track changes.

### 2.2 There is no separate Lock Screen wallpaper
`NSWorkspace.setDesktopImageURL` is the only wallpaper API. macOS composites the *desktop* picture, blurred, behind the lock UI. Therefore "album art on the Lock Screen" means: set the desktop image and let the system blur it (optionally hand it a pre-blurred variant so the double blur reads intentionally). No entitlement, no private call, no extra surface.

### 2.3 AirPods listening modes have no public API
Route options in the wild: `AVOutputDevice.setCurrentBluetoothListeningMode:` (undocumented, works only for some outputs), Accessibility-driven menu clicking (`AirPodsToggle`), or a private L2CAP/AAP stack (`airpods-ctl` — changes the mode but costs a ~1.7 s reconnect). This plan uses **only** a runtime capability probe in `AudioOutputSwitcher`; when it fails, the Listening Mode row is not rendered at all. No private L2CAP code, no AX menu automation.

### 2.4 Do not become the Now Playing app
`MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` would let KatiKati put *its own* tile in Control Center, but it would also fight or steal the real player's media keys. KatiKati is a controller: it reads through `NowPlayingService` and sends `MRMediaRemoteSendCommand`, and must never register itself as the now-playing application.

### 2.5 Entitlements
`Resources/KatiKati.entitlements` currently carries only `com.apple.security.automation.apple-events`; the app is not sandboxed. Wallpaper writes, CoreAudio device switching, IOKit battery reads, and `NSAppleScript` transport all work under that. No new entitlement is required by any slice.

---

## 3. Engine reuse map (no duplication)

| Surface | Reuses | Notes |
| --- | --- | --- |
| All three cards | `NowPlayingService` (`state`, `togglePlayPause`, `nextTrack`, `previousTrack`, `seek`) | `App/Scenes/Desktop/DesktopVinylBoxView.swift` already shares one instance via `DesktopWidgetServices.nowPlaying` |
| Lyrics everywhere | `LyricsStore` + `LyricsTrack` (`Core/Support/NowPlayingService.swift`, `Core/Support/NowPlayingProgress.swift`) | Already lrclib.net + cached, gated by `LyricsTrack.enabledKey`. **No new `LyricsService`.** |
| Wallpaper | `WallpaperEngine` (+ `TerrainWallpaperRenderer`, `WallpaperCache`) | Extended with a lease arbiter and a second source; not forked |
| Output picker | `AudioOutputSwitcher` / `AudioOutputMenu` | CoreAudio on demand, no listener — stays that way |
| AirPods battery | `BluetoothDeviceReader` + `BluetoothDevices` | Already merges `system_profiler` with the HID registry |
| Desktop widget host | `DesktopWidgetPanelController` (`.music` case, panel level `desktopIconWindow + 1`), `DesktopWidgetChromeView` (`DesktopBoxMaterialStyle`: `inheritDock`/`frostedGlass`/`tintedGlass`/`solidCard`), `DesktopTabWheelCatcher` | Glass modes map onto the existing enum; **no parallel glass enum** |
| Favourites | New KatiKati-local store keyed `title|artist` | Spotify/Music expose no player-agnostic favourite API; a local store is honest and works everywhere |

---

## 4. Wallpaper ownership: `WallpaperLease`

### 4.1 The failure mode being fixed
`WallpaperEngine` today: `captureOriginalIfNeeded()` writes the per-screen originals to `com.katikati.wallpaper.original.v1` **only when no capture exists**; `stop()` and `restoreForQuit()` (called from `AppDelegate.applicationWillTerminate`) restore and then **delete** the key. One owner is fine. Two owners corrupt the chain:

1. Weather engine ON → captures the user's real wallpaper.
2. Music mode applies album art (weather's capture still on disk, no second capture).
3. Music restores on pause → deletes the capture.
4. Weather's next refresh calls `captureOriginalIfNeeded()` → captures **album art** as "the user's original".
5. Quit → the user's wallpaper is now permanently the album art.

### 4.2 Design
A pure arbiter in `NowPlayingProgress.swift`, owned by `WallpaperEngine`:

- `WallpaperSource`: `.weather`, `.music` — the lease holders.
- `WallpaperLeaseState`: `.unowned` / `.held(sources: Set<WallpaperSource>)` with the number of active applies.
- Rules: the capture is taken **once per lease chain** (first acquire only); a release by one source while another still holds keeps the capture; the capture is restored only when the **last** holder releases; `.restoreNow()` forces a full release; a persisted `pendingRestore` marker survives a crash and is honoured on next launch before any paint.
- Invariant (unit-tested): *no sequence of acquire/release/quit/relaunch can leave a capture whose content is not the user's original.*
- Music source additionally refuses to apply when `desktopCovered`/screen-locked logic in `WallpaperMotionGuard` would require animation — the static path never animates.

`LockScreenWallpaperBackup` is the same machine expressed for the lock-screen card's own needs (pure state, storage injected), so ML-3 does not invent a second one.

---

## 5. Canapé parity spec (the actual UI contract)

### 5.1 Card (Lock Screen and Desktop use the same view)
- Rounded liquid-glass surface driven by the shared `MusicSurfaceTheme` presets (§5.7): **Clear / Semi / Tinted** glass, **OLED Black**, **Crisp Light**; hairline specular rim (1 px inner highlight, no drop shadow inside the card).
- Layout comes from the shared `MusicCardLayout` (§5.7): `.slim`, `.full`, or Mooziac-style `.hero` with the large rounded artwork and optional 3-line centred lyrics.
- Header: bold track title above a secondary artist line, both single-line truncated.
- **Right-aligned waveform bars** animated with `scaleY` only (never `height`), paused when not playing or under Reduce Motion / Low Power Mode; the scrubber itself can be Slim, Dotted or Waveform per `MusicScrubberStyle` (§5.7).
- **Scrubbable progress bar** with elapsed `1:52` on the left and remaining `-1:52` on the right; drag seeks via `NowPlayingService.seek(to:)`, optimistic like every other KatiKati surface.
- Transport row, exactly: `[Left Slot]  ⏮  ⏸/▶  ⏭  [Right Slot]`.
- Lyrics view: active line highlighted from `LyricsStore`; when enhanced LRC word tags exist, the active word is emphasised, otherwise line-by-line — never both.

### 5.2 Configurable slots
`MusicControlSlot`: `lyrics`, `favorite`, `shuffle`, `repeat`, `output`, `copy`.
- Left and right must be **distinct**; the assignment validates and falls back deterministically (left→`lyrics`, right→`output`).
- `lyrics` opens/closes the lyrics drawer; `favorite` toggles the local store for `title|artist`; `shuffle`/`repeat` are only offered when `NowPlayingService` can actually command them (otherwise hidden, never a dead button); `output` opens the popover; `copy` copies `title — artist`.

### 5.3 Desktop widget gestures
- **Two-finger vertical swipe** toggles Slim Bar ↔ Full Controls with a spring that honours Reduce Motion.
- **Two-finger horizontal swipe** skips tracks (debounced, velocity-aware, never fires on a diagonal).
- **Edge stash:** tuck to the left or right display edge; reveal on hover/click; clamped to the display's `visibleFrame` and restored to the pre-stash frame.

### 5.4 Inline output & AirPods popover
Volume slider at the top, output device picker (`AudioOutputSwitcher`), AirPods Left/Right/Case battery (`BluetoothDeviceReader`), and a `Listening Mode` row (`Off`, `Transparency`, `Adaptive`, `Noise Cancellation`) rendered **only** when the runtime probe in §2.3 succeeds.

### 5.5 Classic backdrop (0.0% idle CPU)
Static album art as the desktop picture rendered from the shared `MusicWallpaperStyle` (§5.7: blurred album, adaptive tint, OLED black, crisp light, hero artwork): one CoreImage pass per track, written once into the generated cache, applied once per track change, **zero timers, zero display link, zero overlay**. Animated art is opt-in and off by default.

### 5.6 Menu Bar quick-control popover (ML-5)
Compact popover with three circular icon toggles — `Desktop`, `Status Bar`, `Now Playing` — each showing `On`/`Off`, plus a `Settings…` row. Pure toggles of existing state; no new engine.

### 5.7 Shared design system: one card, three surfaces (Canapé + Mooziac)

Every visual decision is a **pure value in ML-1**, so the wallpaper (ML-2), the lock-screen card (ML-3) and the desktop widget (ML-4) render the same look from the same numbers. No surface invents its own theme, scrubber or layout; a surface may only *choose* which value to use.

Port doctrine for `shirkeharsh/mooziac` (MIT): the **styling and the pure geometry** are ported and re-expressed in KatiKati patterns, never the app shell. Mooziac's playback client is out of scope (§5.9).

**`MusicSurfaceTheme`** — `.clearGlass`, `.semiGlass`, `.tintedGlass`, `.oledBlack`, `.crispLight`. One preset resolves material, rim opacity, text tone, background luminance and whether the surface needs a dark backing. Applied as a single environment value, so `MusicGlassCardView` has no per-surface branches and the lock card and desktop card cannot drift apart.

**`MusicCardLayout`** — `.slim`, `.full`, `.hero`.
- `.slim`: one-line pill (title, scrubber, transport).
- `.full`: header + scrubber + transport + lyrics drawer (§5.1).
- `.hero`: Mooziac's large rounded artwork card, optional 3-line centred lyrics overlay (previous line faded, active line bold, next line faded), artwork scaling with available height.
- Pure data: intrinsic heights, artwork side, lyric slot count. The desktop panel's height callback and the lock-screen card both read these, so a layout change is one number, not two implementations.

**`MusicScrubberStyle`** — `.slim`, `.dotted`, `.waveform`.
- Bar count and heights are generated **deterministically** from a seeded PRNG over `title|artist` (FNV-1a seed, same hash as the wallpaper cache key). No audio tap, no touch to the audio pipeline, same track ⇒ same shape every launch.
- Elapsed/remaining is applied as an interpolation across the precomputed heights, so a progressing track never rerolls the shape and never rebuilds the array.

**`MusicWallpaperStyle`** — `.blurredAlbum`, `.adaptiveTint`, `.oledBlack`, `.crispLight`, `.heroArtwork`. Consumed by `MusicWallpaperRenderer` (ML-2), so the wallpaper is literally the card's theme rendered full-bleed: `.heroArtwork` is the crisp art card over a blurred surround, `.oledBlack` is the art dimmed on black, `.crispLight` is a bright art plate.

**Adaptive palette** — `MusicArtworkPalette` in ML-1: one CoreImage pass per **track change** (downsample to 24×24, bucket-cluster, pick accent/secondary, derive `isDark` and `textTone`), cached by artwork hash. Produced once by the track-change path and passed to wallpaper, lock card and widget; never per frame, never on a timer, never on a hover.

### 5.8 Per-surface selection and the match toggle

`MusicStyleSelection` holds theme + scrubber + layout + wallpaper style, plus an optional per-surface override map (`lockScreen`, `desktop`, `wallpaper`). Default is the **`Match across Wallpaper, Lock Screen & Desktop`** toggle **on**: one picker group drives all three. Switching it off reveals three compact pickers; overrides persist independently and the default values are the shipped ones, so an untouched install looks identical to the pre-Mooziac plan.

### 5.9 Out of scope (explicitly not ported)

From Mooziac: the YouTube / YouTube Music `WKWebView` client, the 4K video window, SponsorBlock, `yt-dlp`, network downloads, and any Google account/auth flow. KatiKati is not a streaming client, and §2.4 (do not become the Now Playing app) forbids the media-session hijack those features imply. **Ported in ML-6 instead:** the local audio player and the 1 mm multitouch trackpad edge volume slider.

---

## 6. File fence and the zero-`pbxproj` rule

### 6.1 Hands-off until the ML-5 rebase
`App/Scenes/Notch/*`, `App/Scenes/Launcher*`, `App/Scenes/DockStripView*`, `App/Scenes/SettingsWindowView.swift`, `App/Scenes/SettingsLayoutPane+Widgets.swift`, `Resources/Localizable.xcstrings`, `HYBRID_PLAN.md`, `CHANGELOG.md`, and **`KatiKati.xcodeproj/project.pbxproj`**.

### 6.2 Behavior-frozen files (never touched)
1. `App/Composition/WindowLiftAvoidanceController.swift`
2. `Platform/AppTracking/AppTracker.swift`
3. `App/Composition/DragController.swift`
4. `Platform/Accessibility/AccessibilitySource.swift`
5. `Platform/CoreGraphics/FullscreenIntentMonitor.swift`

### 6.3 Zero `project.pbxproj` churn
The project has ~1026 explicit `PBXFileReference` entries and no `PBXFileSystemSynchronizedRootGroup`, so a new `.swift` file means a pbxproj edit — which this track does not do. **All ML-1 → ML-4 code lands in existing tracked files:**

| New type / change | Existing file |
| --- | --- |
| `MusicControlSlot`, `MusicControlAssignment`, `MusicSwipeMachine`, `MusicEdgeStash`, `WallpaperLease`/`LockScreenWallpaperBackup`, `LyricsLine` word timings | `Core/Support/NowPlayingProgress.swift` |
| Glass-mode mapping, widget state keys | `Core/Support/Desktop/DesktopBoxModel.swift` |
| Lease arbiter + music source | `App/Composition/WallpaperEngine.swift` |
| Widget UI | `App/Scenes/Desktop/DesktopVinylBoxView.swift` |
| Panel-level stash | `App/Entry/DesktopWidgetPanelController.swift` |
| Lock-screen card | `Platform/CoreGraphics/OverlaySpaceHost.swift` consumer code in existing `App/` files |
| `MusicSurfaceTheme`, `MusicCardLayout`, `MusicScrubberStyle` + deterministic bar heights, `MusicWallpaperStyle`, `MusicArtworkPalette`, `MusicStyleSelection` | `Core/Support/NowPlayingProgress.swift` (ML-1, pure) |
| Tests | `Tests/Unit/NowPlayingProgressTests.swift`, `Tests/Unit/DesktopBoxCoreTests.swift` |

Consequence: ML-5's rebase touches no pbxproj, so it cannot conflict with the parallel agent's project-file edits.

### 6.4 Isolation protocol
All work happens in `../KatiKati-music-lockscreen` on `feat/music-lockscreen-wallpaper`. The main checkout (which currently carries the other agent's uncommitted Notch/CHANGELOG/README edits) is never modified. Shared wiring — Settings rows, Menu Bar popover, 12-locale strings — is deferred to ML-5, after `git rebase origin/main`.

---

## 7. Slice roadmap

| Slice | Deliverable | Files | Acceptance |
| --- | --- | --- | --- |
| **ML-1** | Pure core: slots + assignment validation, swipe machine (axis lock/threshold/velocity/cooldown), edge-stash clamp math, lease + backup state machines, `LyricsLine` word timings with line fallback, **plus the shared design system (§5.7): `MusicSurfaceTheme`, `MusicCardLayout`, `MusicScrubberStyle` with deterministic seeded bar heights, `MusicWallpaperStyle`, `MusicArtworkPalette`, `MusicStyleSelection`** | `Core/Support/NowPlayingProgress.swift`, `Core/Support/Desktop/DesktopBoxModel.swift`, `Tests/Unit/NowPlayingProgressTests.swift`, `Tests/Unit/DesktopBoxCoreTests.swift` | `xcodebuild test -only-testing:KatiKatiTests/NowPlayingProgressTests` and `…/DesktopBoxCoreTests` green; ≤300 diff lines |
| **ML-2** | Music wallpaper: lease arbiter wired into `WallpaperEngine`, static album-art frame rendered from `MusicWallpaperStyle` + `MusicArtworkPalette` (single cached CoreImage pass per track), apply on track change only, restore on pause/stop/disable/quit, animated opt-in | `App/Composition/WallpaperEngine.swift` (+ core from ML-1) | Wallpaper returns to the user's original after every path in §4.2; idle sample shows no timer wakeups |
| **ML-3** | Lock-screen card: private SkyLight space via `OverlaySpaceHost`, shared `MusicSurfaceTheme` + `MusicScrubberStyle` + `MusicCardLayout` (compact pill or `.hero` with 3-line synced lyrics from `LyricsStore`), opt-in through `com.katikati.liquid.lockScreenEnabled`, absorbs `LQ-5.3` | existing `App/` files + `Platform/CoreGraphics/OverlaySpaceHost.swift` consumer | Missing SkyLight symbol ⇒ no card, no error; card never becomes key; `LQ-5.3` marked superseded |
| **ML-4** | Desktop widget: identical shared card — theme, scrubber, layout including `.hero` + 3-line lyrics — plus Slim/Full, two-finger resize + skip, panel-level edge stash, slot picker, output/AirPods popover, lyrics drawer | `App/Scenes/Desktop/DesktopVinylBoxView.swift`, `App/Entry/DesktopWidgetPanelController.swift`, `App/Scenes/Desktop/DesktopWidgetChromeView.swift` (additive) | Gestures work with a trackpad; stash clamps to `visibleFrame`; Reduce Motion respected |
| **ML-5** | Rebase + shared wiring: unified theme/scrubber/layout pickers with per-surface override and the match toggle (§5.8), Settings toggles, three menu-bar toggles + popover, optional Menu Bar Synced Lyrics (active `LyricsStore` line, off by default, redraws only on line change), optional Discord Rich Presence over the local `discord-ipc-0` Unix socket (event-driven, no dependency, silently absent when Discord is not running, off by default), 12-locale strings, MIT attribution for `shirkeharsh/mooziac` in `NOTICE`, gates, livecheck, graph update | `App/Scenes/SettingsAppearancePane.swift`, `Core/Support/QuickToggles.swift`, `App/Scenes/AppMenuFragments.swift`, `Resources/Localizable.xcstrings` | All three `check_*.py` scripts pass; full test suite; measured idle CPU reported |
| **ML-6** | Local audio player + 1 mm multitouch edge volume slider: `AVAudioPlayer`-backed local-file playback registered as a **local source** inside `NowPlayingService` (never the system Now Playing app, §2.4), feeding the same state the other surfaces already read; a 1 mm dead-band–style trackpad edge strip on the card maps vertical travel to `AudioOutputSwitcher.setOutputVolume`, with a visible level HUD and no timer while idle | `App/Composition` local-source + `App/Scenes/Desktop/DesktopVinylBoxView.swift`, `Platform/SystemStatus/AudioOutputSwitcher.swift` | Local file plays and drives all three surfaces; edge slider changes volume without stepping; idle sample unchanged with the player loaded but stopped |

Each slice ≤300 diff lines, pure core + synchronous `-only-testing:` tests first. ML-6 follows the same fence and the same rule: no new `.swift` file, so no `project.pbxproj` change.

---

## 8. Verification

```sh
# core (pure, synchronous)
xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS' \
  -only-testing:KatiKatiTests/NowPlayingProgressTests \
  -only-testing:KatiKatiTests/DesktopBoxCoreTests

# project gates (ML-5)
python3 scripts/check_localization.py
python3 scripts/check_debug_switches.py
python3 scripts/check_availability_warnings.py

# livecheck
python3 scripts/live_check_wallpapers.py

# architecture graph after code changes
graphify update .
```

**Idle CPU is measured, not asserted:** take a real CPU-time delta (`ps -o cputime= -p <pid>` twice, 20–30 s apart) with the card visible and the music wallpaper applied, plus a sample of the animated path while playing. `top -l <n> -pid` is fine as a cross-check, but its first samples include process launch and overstate a quiet app; a number is only reported when it was actually sampled.

---

## 9. Risks and open decisions

- **Private SkyLight space (ML-3)** — highest-risk item; opt-in, symbol-checked, and removable without touching ML-1/2/4.
- **Wallpaper ownership (ML-2)** — the corruption path in §4.1 is a real bug today; the arbiter is the fix and its invariants are unit-tested before any UI lands.
- **`shuffle`/`repeat`** — no player-agnostic command exists in `NowPlayingService`; they are only offered where commandable, otherwise hidden.
- **`favorite`** — KatiKati-local store by design (documented above), not a pretend player API.
- **Canapé visual copy** — layout, spacing and motion are reproduced as behaviour; Canapé's name/marks are not used.
- **Mooziac styling (MIT)** — themes, layouts, scrubber shapes and the hero lyrics treatment are re-expressed as pure KatiKati values with attribution in `NOTICE`; no app-shell code is copied. Its streaming client stays out of scope (§5.9).
- **Palette extraction** — one pass per track change by design. If it ever moves to a frame or a tick, it becomes the 0% idle CPU bug; the cache key is the artwork hash, and the test asserts a second call for the same hash does no work.
- **Discord Rich Presence** — the socket may not exist; the client is opt-in, event-driven, and its absence is silent, never a reconnect loop.
