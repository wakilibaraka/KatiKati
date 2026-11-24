# Liquid Notch Porting Plan (`LQ-1` → `LQ-6`)

> **Status:** Read-only architecture audit complete; awaiting approval to begin `LQ-1`.  
> **Reference Repo:** [`fellipegoncalvesleite/liquid-notch`](https://github.com/fellipegoncalvesleite/liquid-notch) (MIT License)  
> **Target:** KatiKati (`KatiKati.xcodeproj`, macOS 15+, Swift 6)

---

## 1. Executive Summary & Strategy

Porting **Liquid Notch** as KatiKati's new default Notch shell while preserving all existing KatiKati Notch designs (`Full`/`.boring`, `Compact`/`.classic`, `Dynamic Island`/`.dynamicIsland`, and `Wide bar`/`.wideBar`) as selectable presets gives KatiKati:

1. **Liquid/metaball pouring & splitting physics** (`LiquidShape.metal` + `ShapeSDF.swift` + `ShapeState.swift` + `ShapeAnimator.swift`) with album-art OKLab ambient glow.
2. **Ear-based compact & hover-peek UX** (cover left, reactive audio bars right, hover preview, click-to-expand player, click-cover centered synced lyrics via `LRCLIB`).
3. **Detached activity balls & +N overflow** (`IslandCore` `Arrangement` / `IslandDirector` model) for timers, meetings, battery/AirPods, downloads, Focus, camera, screen recording, and interactive Claude Code / Codex permission balls.
4. **Zero engine duplication**: every background data source (`NowPlayingService`, `CalendarService`, `BluetoothDeviceReader`, `ShelfStore`, `ClipboardMonitor`, `AgentUsageService`, `SystemStatusService`, `CameraMirrorService`, `LiveEventCenter`) stays KatiKati's single source of truth.
5. **Zero idle CPU & opt-in extras**: Sports (ESPN), Lyrics (`LRCLIB`), Video-in-Island/PiP, Lock Screen card, Notch Notifications, and Claude/Codex socket hooks are **off (`false`) by default** until opted in.

---

## 2. License & Attribution Checklist

Add the following attributions to KatiKati's `NOTICE` file (and surface in Settings › About/Credits if applicable):

- [ ] **Liquid Notch — MIT License**
  - Copyright © 2026 Fellipe Gonçalves Leite (`fellipegoncalvesleite/liquid-notch`)
  - Scope: Liquid/metaball Metal shader & SDF, `IslandCore` arrangement/priority model, motion springs/frame clock, ear/card/lyrics/HUD/tray/agent-hook/sports/PiP UI & helpers.
- [ ] **mediaremote-adapter — BSD 3-Clause License** *(Conditional — only if upgrading `NowPlayingService` later)*
  - Copyright © 2025 Jonas van den Berg and contributors (`ungive/mediaremote-adapter`)
  - Note: KatiKati's `Core/Support/NowPlayingService.swift` already reads MediaRemote via `/usr/bin/swift` + `AppleScriptNowPlaying` fallback. `mediaremote-adapter` is **not required** for `LQ-1`–`LQ-6` unless we later remove the Xcode CLT `/usr/bin/swift` dependency.
- [ ] **AirPods 4 3D Model — CC BY 4.0** *(If bundling `airpods-4.usdz` in `LQ-4`)*
  - Model: *AirPods 4* by Falah3D (`sketchfab.com/3dFalah`), licensed under CC BY 4.0.
- [ ] **Studio HDRI — CC0** *(If bundling `studio.hdr` in `LQ-4`)*
  - Lighting: *Studio Small 08* from Poly Haven (`polyhaven.com`), CC0.
- [ ] **Third-Party Data Endpoints (Privacy / Non-Affiliation)**
  - Lyrics: `LRCLIB` (`lrclib.net`) — queried only when the user opens the lyrics view.
  - Sports: ESPN public site API (unofficial) — queried only when the user follows a team.
  - Not affiliated with Apple, Anthropic, OpenAI, or ESPN.

---

## 3. Component-by-Component Mapping Table

### A. Pure State, Geometry & Color (`IslandCore` & `Color`)

| Liquid Notch Source (`/tmp/liquid-notch-ref/Sources/...`) | KatiKati Target | Strategy | Notes |
| --- | --- | --- | --- |
| `IslandCore/Island.swift` | `Core/Support/LiquidNotch/LiquidIslandState.swift` | **Port As-Is (Minor Tweaks)** | Pure state machine: `PresentationMode`, `Party`, `Arrangement`, `DesktopContext`, `ActivityInstance`. Rename/namespace cleanly alongside existing `Core/Support/Island/IslandStore.swift`. |
| `IslandCore/Activity.swift` | `Core/Support/LiquidNotch/LiquidActivity.swift` | **Port As-Is (Minor Tweaks)** | `ActivityID`, `ActivitySpec`, priority rules. Map KatiKati `LiveActivity` / `LiveActivitySources` into `ActivityInstance`. |
| `IslandCore/Agents.swift` | `Core/Support/LiquidNotch/LiquidAgents.swift` | **Port As-Is (Minor Tweaks)** | Agent session & permission ball models; bridge with `Core/Support/AgentUsage/AgentApproval.swift`. |
| `IslandCore/Notices.swift` | `Core/Support/LiquidNotch/LiquidNotices.swift` | **Port As-Is (Minor Tweaks)** | Transient notice queue; feed from `LiveEventCenter` / opt-in `NotificationStore`. |
| `LiquidNotch/Color/OKLab.swift` | `Core/Support/LiquidNotch/LiquidOKLab.swift` | **Port As-Is** | Perceptual album-art glow color extraction; complements `NotchMusicGlow.swift`. |
| `LiquidNotch/Render/ShapeSDF.swift` | `Core/Support/LiquidNotch/LiquidShapeSDF.swift` | **Port As-Is** | CPU mirror of `LiquidShape.metal` for exact hit-testing of ears, neck, balls, and card. |
| `LiquidNotch/Render/ShapeState.swift` | `Core/Support/LiquidNotch/LiquidShapeState.swift` | **Port As-Is** | Uniform struct (`ShapeUniforms`) + animated blob/drop/ball parameters. |
| `LiquidNotch/Presentation/ShapeTargets.swift` | `Core/Support/LiquidNotch/LiquidShapeTargets.swift` | **Port As-Is (Minor Tweaks)** | Target geometry per `PresentationMode`; add non-notch floating pill target. |
| `LiquidNotch/Presentation/IslandDirector.swift` | `Core/Support/LiquidNotch/LiquidDirector.swift` | **Port As-Is (Minor Tweaks)** | Orchestrates `Arrangement` → `ShapeTargets` + lyrics timing offset. |
| `LiquidNotch/Window/NotchGeometry.swift` | `Core/Support/NotchGeometry.swift` (extend) | **Wire / Extend** | Reuse KatiKati's `NotchMetrics` & `IslandDisplayTopology`; add `.liquid` external-display pill fallback. |

### B. Rendering, Motion & Windowing (`Render`, `Motion`, `Window`)

| Liquid Notch Source | KatiKati Target | Strategy | Notes |
| --- | --- | --- | --- |
| `LiquidNotch/Render/LiquidShape.metal` | `Resources/Shaders/LiquidShape.metal` (or `App/Scenes/Notch/Liquid/LiquidShape.metal`) | **Port As-Is** | Single-pass SDF fragment shader with `smin`, superellipse corners, bezel flare, card bridge, and glow. Compile at runtime via `MTLDevice.makeLibrary(source:options:)`. |
| `LiquidNotch/Render/LiquidRenderer.swift` | `App/Scenes/Notch/Liquid/LiquidRenderer.swift` | **Port As-Is (Minor Tweaks)** | `CAMetalLayer` + `LiquidView` NSView host. Zero idle ticks when `.idle`. |
| `LiquidNotch/Motion/Spring.swift` | `App/Scenes/Notch/Liquid/LiquidSpring.swift` | **Port As-Is** | Critically/under-damped spring solver for pouring/splitting blobs. |
| `LiquidNotch/Motion/ShapeAnimator.swift` | `App/Scenes/Notch/Liquid/LiquidShapeAnimator.swift` | **Port As-Is** | Drives `ShapeUniforms` toward `ShapeTargets`. |
| `LiquidNotch/Motion/FrameClock.swift` | `App/Scenes/Notch/Liquid/LiquidFrameClock.swift` | **Port As-Is (Minor Tweaks)** | `CVDisplayLink` / `CADisplayLink` clock that **stops completely when settled/idle** (0% idle CPU). |
| `LiquidNotch/Window/NotchSurfaceController.swift` + `NotchPanel.swift` | `App/Entry/NotchPanelController.swift` (wire) + `App/Scenes/Notch/Liquid/LiquidNotchHostView.swift` | **Wire to KatiKati Engine** | Keep KatiKati's `BoringNotchWindow` + `NotchPanelController` per-display lifecycle and `NotchHoverMachine`; swap content root based on `NotchShellPreset`. |
| `LiquidNotch/Window/DropView.swift` | `App/Composition/ShelfStore.swift` + `LiquidNotchHostView.swift` | **Wire to KatiKati Engine** | Drag-and-drop onto notch routes directly into KatiKati's `ShelfStore`. |
| `LiquidNotch/Window/VideoMirror.swift` + `VideoPiP.swift` | `App/Scenes/Notch/Liquid/LiquidVideoMirror.swift` + `LiquidVideoPiP.swift` | **Port As-Is (`LQ-5`, Opt-In)** | ScreenCaptureKit browser video crop + floating PiP; disabled by default. |
| `LiquidNotch/Window/LockScreen.swift` + `LockWallpaper.swift` + `WallpaperTint.swift` | `App/Scenes/Notch/Liquid/LiquidLockScreen.swift` | **Port As-Is (`LQ-5`, Opt-In)** | Private SkyLight space lock-screen card + safe wallpaper backup/restore; disabled by default. |

### C. Content Views, Audio & Tray (`Content`, `Audio`, `Tray`)

| Liquid Notch Source | KatiKati Target | Strategy | Notes |
| --- | --- | --- | --- |
| `LiquidNotch/Content/NotchContentView.swift` + `EarMetrics.swift` + `Marquee.swift` | `App/Scenes/Notch/Liquid/LiquidContentView.swift` | **Port As-Is (Minor Tweaks)** | Left/right ears, peek preview, expanded player card, ball slots. |
| `LiquidNotch/Content/ActivityViews.swift` + `MoreViews.swift` + `NoticeViews.swift` | `App/Scenes/Notch/Liquid/LiquidActivityViews.swift` | **Port As-Is (Minor Tweaks)** | Activity balls, `+N` overflow card, transient notice banner. |
| `LiquidNotch/Content/AgentViews.swift` + `AskViews.swift` | `App/Scenes/Notch/Liquid/LiquidAgentViews.swift` | **Port As-Is (`LQ-3`)** | Per-agent balls with Allow/Deny/Answer + `⌥Space` Quick Ask sheet. |
| `LiquidNotch/Content/BudsStage.swift` + `AirPaneViews.swift` | `App/Scenes/Notch/Liquid/LiquidAirPodsView.swift` | **Port As-Is (`LQ-4`)** | 3D SceneKit `BudsStage` (if `.usdz`/`.hdr` bundled) or crisp SF-Symbol/SwiftUI fallback, wired to `BluetoothDeviceReader`. |
| `LiquidNotch/Content/FocusViews.swift` + `SportsViews.swift` | `App/Scenes/Notch/Liquid/LiquidExtrasViews.swift` | **Port As-Is (`LQ-4`/`LQ-5`)** | Focus badge + ESPN sports live score card. |
| `LiquidNotch/Audio/{AudioBars,AudioSpectrum,BeatTracker,OutputLatency,SystemAudioTap}.swift` | `App/Scenes/Notch/Liquid/LiquidAudioBars.swift` + `LiquidAudioTap.swift` | **Port As-Is (Minor Tweaks)** | Reactive music bars; `SystemAudioTap` is opt-in (falls back to animated bars without Screen & System Audio permission). |
| `LiquidNotch/Tray/{TrayModel,TraySources,FocusSwitcher,TrayView}.swift` | `App/Scenes/Notch/Liquid/LiquidTrayView.swift` | **Wire to KatiKati Engine** | Double-click notch tools tray wired to KatiKati's `ShelfStore`, `ClipboardMonitor`, `FocusTimerController`, and Shortcuts. |

### D. Agents, Activities, Context & Existing KatiKati Engines

| Liquid Notch Source | KatiKati Target | Strategy | Notes |
| --- | --- | --- | --- |
| `NowPlaying/*` (`AdapterStream`, `NowPlayingMonitor`, etc.) | `Core/Support/NowPlayingService.swift` | **Reuse KatiKati Engine** | Do **not** duplicate media polling. Wire `NowPlayingService` + `LiveActivityFeed` to `LiquidDirector`. |
| `LiquidNotch/Activities/Lyrics.swift` | `Core/Support/LiquidNotch/LyricsClient.swift` | **Port As-Is (`LQ-2`)** | `LRCLIB` (`lrclib.net`) fetcher + LRC parser; called **only** when lyrics view is opened. |
| `LiquidNotch/Activities/MediaKeys.swift` | `Platform/SystemStatus/SystemStatusService.swift` + `App/Scenes/Notch/Liquid/LiquidHUDView.swift` | **Wire to KatiKati Engine** | Reuse `SystemStatusService` volume/brightness events; port Liquid Notch's draggable HUD UI. |
| `LiquidNotch/Activities/AirPane.swift` | `Platform/SystemStatus/BluetoothDeviceReader.swift` | **Reuse KatiKati Engine** | Feed AirPods battery/connection state from `BluetoothDeviceReader`. |
| `LiquidNotch/Activities/{LiveSources,TransferWatcher,ScreenRecorder}.swift` | `App/Composition/{CalendarService,DownloadManagerService,CameraMirrorService}.swift` | **Reuse KatiKati Engine** | Reuse KatiKati's Calendar, Downloads, and Camera/Recording services; port ScreenRecorder helper only if needed for notch-initiated recording. |
| `LiquidNotch/Activities/Football.swift` | `App/Composition/LiquidNotch/SportsFeedService.swift` | **Port As-Is (`LQ-5`, Opt-In)** | ESPN public API poller; **off by default**, zero network traffic unless teams are followed. |
| `LiquidNotch/Activities/{NotificationStore,MessageStore,CallBannerProbe}.swift` | `App/Composition/LiveEventCenter.swift` + opt-in `LiquidNotificationBridge.swift` | **Wire / Opt-In (`LQ-5`)** | Route `LiveEventCenter` into Liquid notices; Full Disk Access notification reader is opt-in (`false` by default). |
| `LiquidNotch/Agents/{AgentSocket,AgentHooks,HookInstaller,AgentLibrary,AgentReply,QuickAsk}.swift` | `App/Composition/LiquidNotch/AgentHookService.swift` + `Resources/Scripts/agent-hook.sh` | **Port As-Is (`LQ-3`, Opt-In)** | Fail-open local Unix socket + `~/.claude/settings.json` & `~/.codex/hooks.json` backup/restore; bridged into `AgentUsageService`. |
| `LiquidNotch/Context/{ContextMonitor,ContextSensing,FocusDatabase}.swift` | `App/Composition/LiquidNotch/LiquidContextAdapter.swift` | **Wire Safely** | Read frontmost app / fullscreen / menu / typing / lock state via `NSWorkspace` & KatiKati's existing state — **never** modify the 5 frozen files. |
| Existing KatiKati Notch (`NotchHomeView`, `NotchWideBarView`, `IslandSurfaceView`, etc.) | `App/Scenes/Notch/*` | **Shelve Intact as Presets** | Preserved under `NotchShellPreset` / `LiveIslandSkin` (`.liquid` default; `.katikati`/`.boring`, `.compact`/`.classic`, `.dynamicIsland`, `.wideBar` selectable in `Settings › Notch`). |

---

## 4. Minor Tweaks & Guardrails Spec

### 4.1 Preset Preservation (`NotchShellPreset`)
- Introduce `NotchShellPreset` (or extend `LiveIslandSkin` in `Core/Support/NotchLayoutSpec.swift` with `.liquid` as the new default):
  - `.liquid` (**Default**): Liquid Notch metaball shell, ears, detached balls, synced lyrics, agent balls, draggable HUD, double-click tray.
  - `.katikati` (`.boring` Full): Existing multi-panel `NotchHomeView` + `NotchToolsView` preserved untouched.
  - `.compact` (`.classic`): Existing single-row compact player card preserved untouched.
  - `.dynamicIsland`: Existing `IslandSurfaceView` preserved untouched.
- External display `NotchDesign` (`.notch`, `.wideBar`, `.off`) continues to work per-display; `.liquid` on a non-notch display renders as a centered top Dynamic Island pill.

### 4.2 External / Non-Notch Display Fallback
- Upstream Liquid Notch hides completely when `NSScreen` has no `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` notch.
- In KatiKati's `LiquidShapeTargets` + `NotchPanelController`: when `!metrics.hasHardwareNotch`, anchor the `.liquid` shape 6–8pt below the top edge (or flush with menu bar top) as a centered floating Dynamic Island pill with rounded top & bottom superellipse corners, and allow auto-hide at rest when no activity is live.

### 4.3 Zero Idle CPU Gating
- `LiquidFrameClock` (`CADisplayLink` / `CVDisplayLink`) **must pause** whenever `LiquidShapeAnimator.isSettled == true` and no live audio-bar/spinner animation is active.
- All optional modules default to `false`:
  - `liquidSportsEnabled = false`
  - `liquidLyricsAutoFetch = false` (only fetches `LRCLIB` on explicit cover click)
  - `liquidVideoInIslandEnabled = false`
  - `liquidLockScreenEnabled = false`
  - `liquidOSNotificationsEnabled = false`
  - `liquidAgentHooksEnabled = false`
  - `liquidSystemAudioTapEnabled = false`

### 4.4 `KatiKati.xcodeproj/project.pbxproj` Handling
- `KatiKati.xcodeproj` uses explicit `PBXFileReference` and `PBXBuildFile` entries (not `PBXFileSystemSynchronizedRootGroup`).
- **Metal Shader (`LiquidShape.metal`):** Add to `Resources` (`PBXResourcesBuildPhase`) so `LiquidRenderer` loads and compiles it at runtime via `MTLDevice.makeLibrary(source:options:)`. This avoids requiring the optional Xcode Metal Toolchain CLI.
- **3D AirPods Assets (`LQ-4`):** `airpods-4.usdz` (3.1 MB), `studio.hdr` (1.4 MB), and `airpods-buds.png` (52 KB) total ~4.5 MB. Either add those 3 files to `Copy Bundle Resources` in `LQ-4` for the full SceneKit `BudsStage`, or use a lightweight SwiftUI/SF-Symbol fallback if keeping bundle size minimal (decision point at `LQ-4`).
- **New Swift Files:** Register new `.swift` files cleanly per wave in `project.pbxproj` (`KatiKati` target for `App/`/`Platform/`, `KatiKati` + `KatiKatiTests` for dual-compiled `Core/Support/LiquidNotch/` files).

### 4.5 Strict Zero-Edit Protection (5 Behavior-Frozen Files)
The following 5 files **MUST NOT BE MODIFIED** during `LQ-1`–`LQ-6`:
1. `App/Composition/WindowLiftAvoidanceController.swift`
2. `Platform/AppTracking/AppTracker.swift`
3. `App/Composition/DragController.swift`
4. `Platform/Accessibility/AccessibilitySource.swift`
5. `Platform/CoreGraphics/FullscreenIntentMonitor.swift`

---

## 5. Atomic Slice Roadmap (`LQ-1` → `LQ-6`)

### Wave `LQ-1` — Preset Switcher & Liquid Shape Engine
- [x] **LQ-1.1 (`≤ 250` LOC):** Add `.liquid` preset to `LiveIslandSkin` / `NotchShellPreset` (new default for fresh installs, preserving existing presets) + pure `Core/Support/LiquidNotch/` state & SDF (`LiquidIslandState.swift`, `LiquidShapeSDF.swift`, `LiquidShapeState.swift`, `LiquidShapeTargets.swift`, `LiquidOKLab.swift`). — `DONE — 04c35271`
- [x] **LQ-1.2 (`≤ 250` LOC):** Pure unit tests in `Tests/Unit/LiquidNotchCoreTests.swift` covering `Arrangement` priority, `DesktopContext` hiding rules, `LiquidShapeSDF` hit-testing, and non-notch floating pill targets. — `DONE — 04c35271`
- [x] **LQ-1.3 (`≤ 300` LOC):** Port `LiquidShape.metal`, `LiquidRenderer.swift`, `LiquidSpring.swift`, `LiquidShapeAnimator.swift`, `LiquidFrameClock.swift` (with strict idle pause), and wire `.liquid` preset routing in `NotchPanelController.swift` + `NotchIslandView.swift`. — `DONE — 37266ac1`

### Wave `LQ-2` — Music Ears, Expanded Player & Synced Lyrics
- [x] **LQ-2.1 (`≤ 280` LOC):** Port `LiquidDirector.swift` & `LiquidContentView.swift` (cover-left / bars-right ears, hover-ear peek preview, click-to-expand player with seek/skip/AirPlay) wired to `NowPlayingService` + `LiveActivityFeed`. — `DONE — f1e7e25a`
- [x] **LQ-2.2 (`≤ 250` LOC):** Port `LyricsClient.swift` (`LRCLIB` on-demand fetch + LRC parser) + centered synced lyrics view on cover click, plus `LiquidAudioBars.swift` (with opt-in `LiquidAudioTap.swift` and animated fallback). — `DONE — 61fa3d11, f1e7e25a`
- [x] **LQ-2.3 (`≤ 150` LOC):** Pure unit tests in `Tests/Unit/LiquidLyricsTests.swift` for LRC timestamp parsing, active-line selection with output latency offset, and `NowPlayingService` → `LiquidDirector` state mapping. — `DONE — 61fa3d11` (in `NowPlayingProgressTests.swift`)

### Wave `LQ-3` — Interactive Claude Code & Codex Permission Balls
- [x] **LQ-3.1 (`≤ 280` LOC):** Port `AgentHookService.swift` (fail-open local Unix socket + `HookInstaller` with timestamped `~/.claude/settings.json` & `~/.codex/hooks.json` backup/restore) + `agent-hook.sh` resource, bridged into `AgentUsageService`. — `DONE — 7a00d462, 20d34755`
- [x] **LQ-3.2 (`≤ 250` LOC):** Port `LiquidAgentViews.swift` (per-agent detached balls, Allow / Deny / Answer card actions, and `⌥Space` Quick Ask sheet). — `DONE — 20d34755` (Allow / Deny / Answer balls; `⌥Space` Quick Ask deferred to `LQ-4` Tray/Shortcuts)
- [x] **LQ-3.3 (`≤ 150` LOC):** Pure unit tests in `Tests/Unit/LiquidAgentHookTests.swift` for JSON hook install/uninstall round-trip, backup preservation of user hooks, and socket payload parsing. — `DONE — 7a00d462` (in `AgentApprovalTests.swift`)

### Wave `LQ-4` — Activities, 3D AirPods, Draggable HUD & Double-Click Tray
- [ ] **LQ-4.1 (`≤ 280` LOC):** Port `LiquidActivityViews.swift` (charging/low battery, next meeting + Join, camera light, Focus, timers, downloads, screen recording, `+N` overflow) wired to `CalendarService`, `SystemStatusService`, `CameraMirrorService`, and `DownloadManagerService`.
- [ ] **LQ-4.2 (`≤ 250` LOC):** Port AirPods battery card (`BudsStage` 3D SceneKit or SwiftUI fallback) wired to `BluetoothDeviceReader` + draggable Volume/Brightness HUD (`LiquidHUDView.swift`) wired to `SystemStatusService`.
- [ ] **LQ-4.3 (`≤ 250` LOC):** Port double-click tools tray (`LiquidTrayView.swift`) wired to `ShelfStore`, `ClipboardMonitor`, `FocusTimerController`, and Shortcuts.

### Wave `LQ-5` — Opt-In Extras (Sports, Video-in-Island, Lock Screen, Notifications)
- [ ] **LQ-5.1 (`≤ 250` LOC):** Port `SportsFeedService.swift` + `LiquidExtrasViews.swift` (ESPN Football, NFL, NBA, MLB, NHL live score balls & cards, off by default).
- [ ] **LQ-5.2 (`≤ 280` LOC):** Port `LiquidVideoMirror.swift` + `LiquidVideoPiP.swift` (ScreenCaptureKit browser video-in-island & PiP, off by default).
- [ ] **LQ-5.3 (`≤ 250` LOC):** Port `LiquidLockScreen.swift` (optional lock-screen card + safe wallpaper backup/restore) and opt-in `LiquidNotificationBridge.swift` wired to `LiveEventCenter`.

### Wave `LQ-6` — Settings Unification, Credits, 12-Locale Gate & Livecheck
- [ ] **LQ-6.1 (`≤ 250` LOC):** Organize `App/Scenes/LiveIslandSettingsBlock.swift` (Preset selector with `.liquid` default + Liquid toggles + preserved Classic/Full/Dynamic Island settings) and update `NOTICE` with MIT / CC BY 4.0 / CC0 credits.
- [ ] **LQ-6.2 (`≤ 200` LOC):** Update all 12 locales in `Resources/Localizable.xcstrings` (`en`, `zh-Hans`, `zh-Hant`, `ja`, `de`, `fr`, `es`, `es-419`, `pt-BR`, `pt-PT`, `it`, `ko`) and pass `python3 scripts/check_localization.py`.
- [ ] **LQ-6.3:** Full verification pass (unit tests, `0.2%` idle CPU check, livecheck on notched + external displays, and `graphify update .`).

---

## 6. Verification Commands

### Unit Tests (Pure Core & Synchronous `-only-testing:`)
```sh
xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati -destination 'platform=macOS' \
  -only-testing:KatiKatiTests/LiquidNotchCoreTests \
  -only-testing:KatiKatiTests/LiquidLyricsTests \
  -only-testing:KatiKatiTests/LiquidAgentHookTests \
  -only-testing:KatiKatiTests/NotchLayoutSpecTests \
  -only-testing:KatiKatiTests/NotchGeometryTests \
  -only-testing:KatiKatiTests/IslandEngineTests
```

### Localization Gate (12 Locales)
```sh
python3 scripts/check_localization.py
```

### Livecheck & Idle CPU Gate
- Build & run Debug/Release on a notched MacBook + external non-notch display.
- Verify `.liquid` renders as notch-hugging liquid on built-in display and centered floating pill on external display.
- Verify switching presets (`.boring` Full, `.classic` Compact, `.dynamicIsland`, `.wideBar`) works live with zero regressions.
- Measure idle CPU (`≤ 0.2%`) with all opt-in extras disabled and `.liquid` settled at rest.
