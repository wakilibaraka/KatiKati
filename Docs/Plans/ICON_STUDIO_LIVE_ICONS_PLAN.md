# Icon Studio & Live Icons Plan (`IS-1` → `IS-6`)

> **Status:** Read-only codebase audit complete on `feat/icon-studio` (`../KatiKati-icon-studio`); zero `.swift` or `project.pbxproj` edits made; awaiting approval before starting `IS-1`.  
> **Reference Inspiration:** IconSwapper (`iconswapper.app` PDF reference) + KatiKati Dock / `⌘+Tab` / Metal / Live Data pipelines  
> **Target:** KatiKati (`KatiKati.xcodeproj`, macOS 15+, Swift 5.0/6 compatible, `com.katikati.iconStudio.*` defaults, 12 locales)

---

## 1. Codebase Audit: Existing KatiKati Pipelines & Anchors

KatiKati already renders its own **Dock (`ChipView` / `LauncherChip`)** and **`⌘+Tab` Switcher (`WindowSwitcherView`)**, so layered looks, shaders, decorations, badge effects, and live-data icons can be rendered directly inside KatiKati without modifying signed `.app` bundles.

### 1.1 Icon Resolution, Masking & Caching
- **`App/Scenes/ContentView.swift:437-479` (`AppIconResolver`)**:
  - Uses a plain `[String: NSImage]` dictionary capped at `512` entries (`AppIconResolver.cache`) — **deliberately NOT `NSCache`** because `NSCache` evictions caused ~1s main-thread LaunchServices/IconServices stalls during hover/drag/heartbeat redraws.
  - Strips plated `@1x` representations (`removePlatedRepresentations`, `<128pt` where `pixelsWide <= size.width`) and sets `icon.size = NSSize(width: 32, height: 32)`.
  - **Plan Requirement:** Keep the fast plain-dictionary Dock cache intact, and add a separate high-resolution source lookup (`256×256` / `512px`) for Icon Studio baking and hero stage preview so custom finishes and shaders are never upscaled from 32pt bitmaps.
- **`App/Scenes/DockTheme.swift:503-511` (`dockIconMask(size:)`)**:
  - Shared icon shape clip modifier supporting continuous squircle (`cornerRadius: size / 4, style: .continuous`) and `.circle` with hairline `0.5pt` rim.
- **`Core/Support/IconSet.swift:7-26` (`IconSet`)**:
  - Currently a 3-case enum (`system`, `modern`, `classic`) covering Trash and menu-bar SF Symbols (`com.katikati.iconSet`). No per-app custom icon override or layered look store exists yet.
- **`App/Scenes/SettingsTab.swift:13, 48, 88, 127` + `App/Scenes/WidgetLookSettingsBlock.swift:245-388` (`AppIconsSettingsBlock`) + `App/Scenes/SettingsWindowView.swift:118`**:
  - Existing **App Icons & Hover** settings tab. Will host a clean launch card into the dedicated 3-column Icon Studio window rather than cramping the studio into the narrow `SettingsPane` column.
- **Primary Dock & `⌘+Tab` Consumers**:
  - `App/Scenes/ChipView.swift:220, 383, 506-522` (`appIcon(size:)` in `bareIconChip` and `multiWindowChip`)
  - `App/Scenes/LauncherChip.swift:220-236` (`icon(size:bounceLift:)`)
  - `App/Composition/WindowSwitcherController.swift:549, 616, 660, 686, 723, 743` (`WindowSwitcherView` across `.thumbnail`, `.list`, `.icons`, `.classicIcons`, and `.carousel`)
- **Secondary Static Custom-Icon Consumers** (automatically benefit via `AppIconResolver` lookup once static looks are cached):
  - `App/Scenes/DrawerCapsuleButton.swift:545`
  - `App/Scenes/DrawerView.swift:353`
  - `App/Composition/WindowDrawerController.swift:533, 555`
  - `App/Composition/WindowStripController.swift:250`
  - `App/Entry/PanelCoordinator+ChipPanel.swift:111`
- **Out of Scope / Untouched**: `LauncherIconCache` in `App/Scenes/LauncherView.swift:7-17`.

### 1.2 Dock Badges & Unread Counts
- **`Platform/Accessibility/DockBadgeReader.swift:49-149`**:
  - Reads `AXStatusLabel` from macOS Dock `AXDockItem` elements using KatiKati's existing Accessibility permission — zero new permissions required.
- **`App/Composition/BadgeStore.swift:16-208`**:
  - Off-main-thread `0.5s` targeted reader (`BadgeReadPlan`) that **pauses its timer completely** whenever `readableMessagingIDs.isEmpty || !taskbarVisible` (`shouldPauseTimer`).
- **`App/Composition/AppMembershipController.swift:132-141` (`badgeEligibleIDs`) + `App/Entry/AppDelegate.swift:1176-1192`**:
  - **Key Audit Finding:** Today, `AppDelegate` scopes `BadgeStore.updateMessagingContext` strictly to messaging apps ∩ running − drawer (`AppMembershipProjection.badgeEligibleIDs`).
  - To power Unread Badge Effects (`Fire`, `Sunlight`, `Wax seal`, `Glint`) and Mail/Messages unread reactions on any customized app without polling every app on the system, extend `AppDelegate.swift` + `BadgeStore.swift` to union `iconStudioBadgeEligibleBundleIDs` (only apps configured with an active badge effect or unread live icon, still intersected with `runningBundleIDs` and paused when the taskbar is hidden).
- **`App/Scenes/ChipBadgeView.swift:18-43`**:
  - Shared unread badge capsule rendered inside `ChipView.swift:256, 390` and `LauncherChip.swift:150` **before** hover/press scale transforms so badges scale cleanly with the chip. Badge effects will wrap `ChipBadgeView` at that same layer.

### 1.3 Live Data Engines
- **`App/Composition/AgentUsageService.swift:103-509` + `Core/Support/AgentUsage/AgentUsageModels.swift` + `AgentClaudeParser.swift:16-77` + `AgentStoreParsers.swift:50-162` + `ClaudeHookStatus.swift:7-29`**:
  - **Claude:** Already reads real 5h session & 7d weekly allowance `usedPercent` / `resetsAt` from `~/Library/Application Support/Claude/plan-usage-history.json`, plus active turn state (`activeTurn?.isActive`) from `~/.claude/projects/*.jsonl` and the opt-in Claude hook log (`ClaudeHookStatus.workingOverride`).
  - **Codex:** Already reads `~/.codex/sessions/*.jsonl` and `archived_sessions/*.jsonl` for tokens, estimated cost, and recent/active turns (`AgentCodexParser`), but does not yet parse `rate_limits` percentage fields. Plan: extend `AgentCodexParser` to extract optional `rate_limits` percentages when present in rollout JSONL, with a user-configurable daily/weekly allowance budget fallback.
  - **Cursor:** Currently appears in `AIProviderKind` (`AgentStoreParsers.swift:124`) only for `.cursor/mcp.json` loadout discovery — not yet in `AgentUsageService` usage readers. Plan: add an honest local-first Cursor usage provider (local activity tracking + configurable allowance budget / manual sync + interactive example percentage slider); never silently scrape Cursor auth cookies/tokens.
- **`Core/Support/NowPlayingService.swift:24-250` + `Core/Support/AppleScriptNowPlaying.swift`**:
  - `NowPlayingState` already publishes `isPlaying`, `title`, `artist`, `album`, `bundleIdentifier`, `artworkData`, `elapsed`, `elapsedAsOf`, `duration`, `rate`, and `progress(at:)` via the MediaRemote `/usr/bin/swift` helper and AppleScript fallback.
- **`App/Composition/DownloadManagerService.swift` + `Platform/Finder/*`**:
  - Existing download and Finder infrastructure available to drive Safari download-fill progress without Automation permissions.

### 1.4 Runtime Metal Shader Pipeline
- **`App/Scenes/Notch/Island/IslandPresets.swift:623-900` (`LiquidShaderSource` + `LiquidRenderer` + `LiquidMetalNSView`)**:
  - Proven runtime compilation pattern: raw MSL source string compiled via `MTLDevice.makeLibrary(source:options:)`, hosted in `CAMetalLayer`, and driven by a `CADisplayLink` initialized paused (`l.isPaused = true`) that stops immediately when settled.
  - Icon Studio's `IconShaderEngine` will reuse this exact runtime-compiled MSL pattern so **zero `.metal` resource files** or Xcode Metal Toolchain CLI dependencies are added to `project.pbxproj`.

---

## 2. Honest macOS Permission, Privacy & External API Audit

| Feature / Live Icon | Required Permissions | Default Behavior & Honest Scope |
| --- | --- | --- |
| **Layered Icon Studio** (PNG/ICNS/`.icon` drop, recolor, `Save Look`, static finishes, Dress Up, hover shaders) | **Zero extra permissions** | Enabled when configured; static looks pre-baked to disk/memory cache (`0.0%` idle CPU). |
| **Claude & Codex AI Live Icons** | **Zero extra permissions** | Reads local logs/files already watched by `AgentUsageService`. Animates strictly while `activeTurn?.isActive == true`. |
| **Cursor AI Live Icon** | **Zero extra permissions** | Local activity + configurable allowance budget + preview slider (no token/cookie scraping). Water tilt responds to pointer/hover angle (does not rely on private Apple Silicon lid/accelerometer HID APIs). |
| **Apple Music & Spotify Live Icons** | **Zero extra permissions** (uses existing `NowPlayingService`) | Spins vinyl / prismatic CD strictly while `isPlaying == true` for matching `bundleIdentifier`; freezes exact rotation angle on pause (`0.0%` idle CPU). |
| **Unread Badge Effects** (`Fire`, `Sunlight`, `Wax seal`, `Glint`) & **Mail / Messages Unread Reactions** | **Existing Accessibility grant only** (`BadgeStore` / `DockBadgeReader`) | Reads `AXStatusLabel` only for running apps with a configured badge effect or unread live icon. `0.0%` idle CPU below `unreadCount >= threshold`. |
| **Finder Companion Eyes & Idle Blink** | **Zero extra permissions** | Pointer tracking reads coordinates from KatiKati's Dock hover/pointer stream while visible; low-frequency idle blink cancels whenever Dock hides. |
| **Safari Download Progress** | **Zero extra permissions** | Reads active download progress via `DownloadManagerService` / `~/Downloads/*.download` file watcher. |
| **Finder File-Copy Concentration** | **Opt-in (`false` by default)** — uses Accessibility check | Checks Finder `AXProgressIndicator` / copy progress window only when explicitly enabled and Finder is running. Never runs when disabled. |
| **Mail Compose Envelope-Open** | **Opt-in (`false` by default)** — `DockSnapshot` / Accessibility window metadata | Checks Mail compose window presence only when enabled and Mail is running. Never reads email bodies or Automation unless opted in. |
| **Messages Typing Indicator** | **Opt-in (`false` by default)** — Accessibility active-window check | **Honest limit:** macOS does **not** expose remote-party typing bubbles via `AXStatusLabel`, AppleScript, or `~/Library/Messages/chat.db` (even with Full Disk Access). Do **not** request FDA; support local compose/unread hop cleanly. |
| **Safari Page-Loading Needle & Chrome Active-Tab Spinner** | **Opt-in (`false` by default)** — Automation (Apple Events) or AX toolbar stop/reload probe | Triggers OS Automation consent only when the user explicitly turns on tab-loading detection; polls strictly while that browser is running & frontmost/visible. |
| **`macOSicons` Community Search** | **Opt-in BYO `x-api-key`** (user-provided) | Official `macosicons.com` API requires an API key (free tier ~50 searches/month). Zero background requests; local PNG/ICNS/`.icon` drop works 100% offline. |

---

## 3. Architecture, Layer Stack & Zero-Idle-CPU Cache Contract

### 3.1 Canonical 6-Layer Render Pipeline
Every customized Dock and `⌘+Tab` icon resolves through this deterministic layer order:

1. **Base Artwork**: App bundle high-res icon (`AppIconResolver`), dropped `PNG`/`ICNS`/`.icon`, or `macOSicons` downloaded asset.
2. **Color / Tint / Recolor**: Original, monochrome tint, duotone/gradient map, or hue/saturation shift (`IconRecolorSpec`).
3. **Finish / Shader**:
   - *Static finishes* (baked once off-main-thread): `Liquid Glass`, `Gloss`, `Gold`, `Light Leather`, `Tooled Leather`, `Wood Inlay`, `Carved Marble`, `Embroidery`, `Brushed Metal`, `Stained Glass`, `Classic Mac`.
   - *Animated runtime Metal shaders* (active only on hover or live-state trigger): `Holographic Foil`, `VHS`, `CRT`, `Lava Lamp`, `Neon Sign`.
4. **Live Data Layer** (optional per supported bundle ID): AI Usage (`Claude`, `Codex`, `Cursor`), Now Playing (`Apple Music`, `Spotify`), `Finder` Companion face, or Opt-in App Live State (`Mail`, `Messages`, `Safari`, `Chrome`).
5. **Dress Up Decorations**: `String lights` (configurable spacing), `Pine` sprig, `Snow globe` dome — positioned with normalized draggable `(x, y)` anchor offsets.
6. **Badge & Unread Effect**: `ChipBadgeView` wrapped by `Fire`, `Sunlight`, `Wax seal`, or `Glint`, gated by `parsedUnreadCount >= threshold`.

### 3.2 Two-Tier Cache Contract
- **Tier 1 — Fast `@MainActor` Lookup Dictionary**:
  - Plain `[IconCacheKey: NSImage]` dictionary capped at `512` entries (matching `AppIconResolver`'s proven no-`NSCache` stall design), keyed by `(bundleID, lookHash, pixelBucket)` at `64px` (`32pt @2x`) and `128px` (`64pt @2x`).
  - Guarantees `0.0ms` synchronous reads inside `ChipView`, `LauncherChip`, and `WindowSwitcherView` body evaluations.
- **Tier 2 — Off-Main-Thread Static Baker & Disk Cache (`IconBakeActor`)**:
  - Swift `actor` rendering `Base Artwork → Recolor → Static Finish` at `256px` / `512px` via CoreGraphics/CoreImage/offscreen Metal.
  - Writes baked PNGs to `~/Library/Caches/com.katikati.app/IconStudio/<sha256>.png` and promotes downsampled Tier 1 bitmaps to `@MainActor` on completion without blocking UI frames.

### 3.3 Zero-Idle-CPU & Accessibility Contract
- **Static & Unhovered Icons:** `0.0%` CPU — rendered purely from Tier 1 cached `NSImage`.
- **Animated Metal Shaders:** `CADisplayLink` starts paused (`isPaused = true`) and runs strictly while `isHovered` (default trigger) or `isActiveLiveState` (when configured for active trigger); stops immediately on exit.
- **AI Live Icons:** Tide/tracer/water animations tick strictly while `activeTurn?.isActive == true` for that provider.
- **Now Playing Live Icons:** Disc rotation ticks strictly while `state.isPlaying == true` and matching `bundleIdentifier`; pauses in place preserving exact angle (`0.0%` CPU when paused).
- **Unread Badge Effects:** Animate strictly while `parsedUnreadCount >= effect.minUnreadCount && taskbarVisible`.
- **Finder Companion:** Eye gaze updates only on pointer movement events over/near the Dock; idle blink timer cancels when the Dock hides.
- **Reduced Motion (`@Environment(\.accessibilityReduceMotion)`):** Freezes animated shaders, disables disc spin/tide/hop/fire flicker, and falls back to crisp static renders.

---

## 4. Visual & Interaction Design Spec (`/design`)

Following Impeccable **`Operate` mode** (`impeccable/reference/operate.md`) and **`katikati-design-expert`**, the Icon Studio editor is a focused macOS creative utility where scanability, native affordances, and live legibility at Dock scale outrank decorative chrome.

### 4.1 Surface Topology & Entry Points
- **Dedicated Resizable Studio Window (`IconStudioWindowController`)**: `960×660pt` default (`820×560pt` minimum) using `DockGlassBackdrop` and `DockThemeTokens`. Never cram the 3-column studio inside the narrow single-column `SettingsPane`.
- **Entry Points**:
  1. A concise launch card inside `SettingsTab.appIcons` (`AppIconsSettingsBlock`).
  2. A `"Customize Icon…"` item in Dock chip context menus (`ChipView` / `LauncherChip`).

### 4.2 3-Column Studio Layout
1. **Left Column (~210pt, secondary neutral sidebar surface)**:
   - `Search apps` filter field.
   - `Live icons` section: compact `Live` badge + live miniature preview + subtle percentage/state readout and local source subtitle.
   - `Custom icons` section: user-customized apps (with instructive empty state when none are added yet).
   - Sticky bottom toolbar: `+ Add App` application picker + Studio preferences popover (opt-in live probes & `macOSicons` BYO API key).
2. **Center Stage (~360pt flexible)**:
   - Bold app title header.
   - Rounded high-contrast preview canvas with top-right Share/Export button (`square.and.arrow.up`), `160×160pt` interactive hero preview (with draggable Dress Up handles when active), and a `44×44pt` **1:1 Dock-scale preview** directly beneath so legibility at real Dock size is never guessed.
   - Drag-and-drop target (`Drop a PNG, ICNS, or .icon here`) with visual drop highlight.
   - `Light | Dark | Wallpaper` segmented stage backdrop switcher (live desktop wallpaper sample via existing `WallpaperEngine` read).
   - Preview controls: `Show Dock and Command-Tab` (reveals live mini Dock + `⌘+Tab` preview strip), `Try an example percentage` slider (`.monospacedDigit()`), and `Show Dock badge` toggle.
   - Bottom-left `Restore Original Icon` action.
3. **Right Inspector (~340pt, scrollable accordion)**:
   - Context-aware live source status card (account/source label, refresh icon, `Open <App>` button).
   - `Appearance` header bar with `Save Look…` and `Looks ▾` preset picker.
   - Collapsible disclosure rows with right-aligned active-value summaries:
     - `Badges` (Effect: `None | Fire | Sunlight | Wax seal | Glint` + unread threshold stepper)
     - `Artwork` (App Original / Custom File / `macOSicons` search)
     - `Color` (Original / Tint / Recolor hue & strength)
     - `Shaders` (15 finishes & shaders + strength slider + trigger mode `Hover | Active | Off`)
     - `Dress Up` (`String lights` + spacing, `Pine`, `Snow globe` + reset position)
     - Context-aware Live section (`Usage` `None | Used | Remaining` + `Color fill | Water | Fade tide | Tracer`; `Now Playing` `CD jewel case | Vinyl record | Prismatic disc` + `Countdown | Progress bar`; `Finder` face parts & colors; `Mail` / `Messages` / `Safari` / `Chrome` opt-in toggles).
   - Bottom-right `Remove Live Icon` / `Open <App>` actions.

### 4.3 Typography, Motion & Quality Floor
- SF Pro system font throughout; tight scale ratio (`11pt` captions, `12–13pt` controls, `18pt` stage title); `.monospacedDigit()` on all percentages (`52%`, `65%`) and countdowns (`-0:18`).
- All materials, rims, and neutral layers come from `DockThemeTokens` and `DockGlassBackdrop`. Accent color is reserved strictly for active selection, primary actions, and live indicators.
- Every interactive control ships complete states (default, hover, focus, active, disabled, loading skeleton for `macOSicons` search, empty/error states).
- Animations are value-scoped (`150–250ms`, `katikati-design-expert` springs) with zero unbounded `.repeatForever` loops.
- **Execution Gate:** Read `/Users/baraka/.gemini/config/plugins/impeccable/skills/impeccable/reference/craft-floor.md` immediately before writing any UI code in `IS-5`.

---

## 5. Guardrails, File-Ownership & Parallel-Work Map

### 5.1 Behavior-Frozen Files (ZERO EDITS)
The following 5 files **MUST NOT BE MODIFIED** during `IS-1`–`IS-6`:
1. `App/Composition/WindowLiftAvoidanceController.swift`
2. `Platform/AppTracking/AppTracker.swift`
3. `App/Composition/DragController.swift`
4. `Platform/Accessibility/AccessibilitySource.swift`
5. `Platform/CoreGraphics/FullscreenIntentMonitor.swift`

Additionally, keep Notch (`App/Scenes/Notch/*`), `WallpaperEngine`, and Launcher (`App/Scenes/LauncherView.swift`) untouched.

### 5.2 Repository Rules (`STANDING_RULES.md`)
- `≤ 300` LOC diff per commit; one slice/sub-slice at a time.
- `KatiKati.xcodeproj/project.pbxproj` and `Resources/Localizable.xcstrings` are **append-only by hand** (`pbxproj` diff `≤ 30` lines per file addition).
- Lazy initialization behind `com.katikati.iconStudio.*` defaults keys (zero eager singletons on app launch when unused).
- Any new `DOCK_*` debug switch must be registered in `Core/Support/DebugSwitch.swift` and pass `Scripts/check_debug_switches.py`.
- All 12 locales in `Resources/Localizable.xcstrings` (`en`, `zh-Hans`, `zh-Hant`, `ja`, `de`, `fr`, `es`, `es-419`, `pt-BR`, `pt-PT`, `it`, `ko`) must pass `python3 Scripts/check_localization.py`.

### 5.3 File-Ownership Map
| Area | New Files | Modified Existing Files |
| --- | --- | --- |
| **Core Models (`IS-1`, `IS-3`, `IS-4`)** | `Core/Support/IconStudio/IconStudioModels.swift`<br>`Core/Support/IconStudio/IconStudioStore.swift`<br>`Core/Support/IconStudio/LiveIconMetrics.swift`<br>`Core/Support/IconStudio/FinderCompanionGeometry.swift` | `Core/Support/AgentUsage/AgentStoreParsers.swift` *(Codex `rate_limits`)*<br>`Core/Support/AgentUsage/AgentUsageModels.swift` *(optional Cursor provider slot)* |
| **Baker, Cache & Clients (`IS-2`, `IS-5`, `IS-6`)** | `App/Composition/IconStudio/IconBakeActor.swift`<br>`App/Composition/IconStudio/MacOSIconsClient.swift`<br>`App/Composition/IconStudio/LiveAppActivityProbe.swift` | `App/Composition/BadgeStore.swift`<br>`App/Entry/AppDelegate.swift`<br>`App/Composition/AgentUsageService.swift` |
| **Shaders & Icon Renderers (`IS-2`–`IS-4`, `IS-6`)** | `App/Scenes/IconStudio/IconShaderEngine.swift`<br>`App/Scenes/IconStudio/IconStudioIconView.swift`<br>`App/Scenes/IconStudio/AILiveIconViews.swift`<br>`App/Scenes/IconStudio/MusicLiveIconViews.swift`<br>`App/Scenes/IconStudio/IconBadgeEffectView.swift`<br>`App/Scenes/IconStudio/IconDressUpOverlayView.swift`<br>`App/Scenes/IconStudio/FinderCompanionIconView.swift`<br>`App/Scenes/IconStudio/AppActivityLiveIconViews.swift` | `App/Scenes/ContentView.swift` *(Tier-1 `AppIconResolver` lookup)*<br>`App/Scenes/ChipView.swift`<br>`App/Scenes/LauncherChip.swift`<br>`App/Composition/WindowSwitcherController.swift` |
| **Studio Window & Settings (`IS-5`)** | `App/Entry/IconStudioWindowController.swift`<br>`App/Scenes/IconStudio/IconStudioWindowView.swift`<br>`App/Scenes/IconStudio/IconStudioInspectorView.swift`<br>`App/Scenes/IconStudio/MacOSIconsSearchSheet.swift` | `App/Scenes/WidgetLookSettingsBlock.swift` *(launch card in `AppIconsSettingsBlock`)* |
| **Unit Tests** | `Tests/Unit/IconStudioCoreTests.swift`<br>`Tests/Unit/IconStudioBakeTests.swift`<br>`Tests/Unit/LiveIconMetricsTests.swift`<br>`Tests/Unit/FinderCompanionGeometryTests.swift`<br>`Tests/Unit/MacOSIconsClientTests.swift` | — |

---

## 6. Phased Atomic Slice Roadmap (`IS-1` → `IS-6`)

### Wave `IS-1` — Pure Core Icon Studio Model & Persistence
- [x] **IS-1.1 (`≤ 260` LOC):** Pure Core Icon Studio models (`IconStudioDefaultsKeys`, `IconArtworkSource`, `IconRecolorSpec`, `IconAnimationTrigger`, `IconShaderPreset`/`IconShaderSpec`, `IconDecorationKind`/`IconDecoration`, `IconUnreadBadgeParser`, `IconBadgeEffectSpec`, `LiveIconKind`/`LiveIconConfig`, `IconRenderLayer`, `IconLook` + `staticBakeFingerprint`, `SavedIconLookPreset`, `IconStudioState`) placed in `Core/Support/IconSet.swift` (zero `project.pbxproj` churn). — `DONE — 9d5fbffa`
- [x] **IS-1.2 (`≤ 260` LOC):** `IconStudioPersistence` JSON codec (`Core/Support/IconSet.swift`) + 7 synchronous unit tests in `Tests/Unit/IconSetTests.swift` covering Codable/file round-trip, corrupt/future schema fallback, badge threshold parsing, zero-idle/reduce-motion shader policy, canonical layer order, static bake fingerprint isolation, preset save/apply/restore, and opt-in probe defaults. — `DONE — b5145929`

### Wave `IS-2` — Static Finish Baker, Runtime Metal Shaders & Two-Tier Cache
- [x] **IS-2.1 (`≤ 280` LOC):** `AppIconResolver.highResIcon`, `IconAssetLoader` (PNG/ICNS/`.icon` bundle), `IconBakeActor` (Tier-2 disk PNG cache + CoreImage recolor & 11 static finishes), and `IconStudioController` (Tier-1 plain dictionary cache + persistence) in `App/Scenes/{ContentView,DockTheme}.swift` + test in `Tests/Unit/IconSetTests.swift` (zero `pbxproj` churn). — `DONE — 6c776150`
- [x] **IS-2.2 (`≤ 280` LOC):** `IconShaderEngine` (`MTLDevice.makeLibrary(source:options:)`, 5 animated shaders + zero-idle `CADisplayLink`), `IconStudioIconView`, and Dock `ChipView`/`LauncherChip` wiring (`2cc40f87`). — `DONE — 2cc40f87`
- [x] **IS-2.3 (`≤ 220` LOC):** Folded into `IS-2.2` (`2cc40f87`: `ChipView.swift:506` & `LauncherChip.swift:220`). — `DONE — 2cc40f87`

### Wave `IS-3` — AI & Now Playing Live Icons (Highest ROI)
- [x] **IS-3.1 (`≤ 250` LOC):** `LiveIconMetrics`, `VinylAngleAccumulator`, `CursorBudgetEstimator` in `Core/Support/IconSet.swift`, `AgentCodexParser.parseRateLimit` + `AgentUsageService` `.codex` limits wiring, and synchronous tests in `Tests/Unit/IconSetTests.swift` (`79995944`). — `DONE — 79995944`
- [x] **IS-3.2 (`≤ 280` LOC):** `AILiveIconOverlay` (Claude fade tide, Codex white glyph tracer, Cursor water/color fill + hover tilt) & `MusicLiveIconOverlay` (Apple Music vinyl + pause-angle hold, Spotify CD jewel case / prismatic disc + `MusicTimecode` countdown) in `App/Scenes/ChipBadgeView.swift`, wired in `ContentView.swift` (`5378bf0c`). — `DONE — 5378bf0c`
- [x] **IS-3.3 (`≤ 260` LOC):** Folded into `IS-3.2` (`5378bf0c`). — `DONE — 5378bf0c`

### Wave `IS-4` — Unread Badge Effects, Dress Up & Finder Companion
- [x] **IS-4.1 (`≤ 240` LOC):** `AppDelegate` + `BadgeStore` targeted union for `iconStudioBadgeEligibleBundleIDs`, `IconBadgeEffectView` (`fire`, `sunlight`, `waxSeal`, `glint`) + `IconDressUpOverlayView` (`stringLights`, `pine`, `snowGlobe`) in `ChipBadgeView.swift`, wired to `ChipView`/`LauncherChip`/`ContentView` (`c8eb78bd`). — `DONE — c8eb78bd`
- [x] **IS-4.2 (`≤ 220` LOC):** Folded into `IS-4.1` (`c8eb78bd`). — `DONE — c8eb78bd`
- [ ] **IS-4.3 (`≤ 280` LOC):** Add `Core/Support/IconStudio/FinderCompanionGeometry.swift` + `App/Scenes/IconStudio/FinderCompanionIconView.swift` (customizable eyes, button/classic nose, mouth, dual-tone colors; pointer-tracking eyes driven by Dock hover/pointer coordinates; low-frequency idle blink cancelled when Dock hides) + synchronous geometry tests in `Tests/Unit/FinderCompanionGeometryTests.swift`.

### Wave `IS-5` — 3-Column Icon Studio Editor UI + `macOSicons` Search
- [ ] **IS-5.1 (`≤ 290` LOC):** Read `/Users/baraka/.gemini/config/plugins/impeccable/skills/impeccable/reference/craft-floor.md`; build `App/Entry/IconStudioWindowController.swift` and `App/Scenes/IconStudio/IconStudioWindowView.swift` (left `Live icons` / `Custom icons` / `+ Add App` sidebar + center `Light`/`Dark`/`Wallpaper` stage + `160pt` & `44pt` dual preview + mini Dock & `⌘+Tab` preview + drop zone + example percentage slider + `Restore Original Icon`).
- [ ] **IS-5.2 (`≤ 290` LOC):** Add `App/Scenes/IconStudio/IconStudioInspectorView.swift` (`Save Look…` / `Looks ▾`, `Badges`, `Artwork`, `Color`, `Shaders`, `Dress Up`, context-aware Live controls) and wire launch triggers in `App/Scenes/WidgetLookSettingsBlock.swift:245` (`AppIconsSettingsBlock`) plus `"Customize Icon…"` in `ChipView.swift` & `LauncherChip.swift`.
- [ ] **IS-5.3 (`≤ 240` LOC):** Add opt-in BYO API key `macOSicons` client (`App/Composition/IconStudio/MacOSIconsClient.swift`) + `MacOSIconsSearchSheet.swift` (skeleton loading, empty/quota/error states) + pure request/decoder tests in `Tests/Unit/MacOSIconsClientTests.swift`.

### Wave `IS-6` — Opt-In App Live Icons, `⌘+Tab` Parity, 12-Locale l10n & Livecheck
- [ ] **IS-6.1 (`≤ 280` LOC):** Add `App/Composition/IconStudio/LiveAppActivityProbe.swift` + `App/Scenes/IconStudio/AppActivityLiveIconViews.swift` with all permissioned probes strictly opt-in (`false` by default): **Mail** (unread badge reaction + opt-in compose envelope), **Messages** (unread hop + 1/2 bubbles + opt-in active-window compose check), **Safari** (zero-perm download dial/water fill + opt-in page-load needle), **Chrome** (opt-in active tab-loading disc), **Finder** (opt-in AX file-copy concentration look).
- [ ] **IS-6.2 (`≤ 200` LOC):** Wire full `⌘+Tab` Switcher parity in `App/Composition/WindowSwitcherController.swift:549-750` across all 5 styles using shared `IconStudioIconView`.
- [ ] **IS-6.3 (`≤ 260` LOC):** Add all new strings across all 12 locales in `Resources/Localizable.xcstrings`, run `python3 Scripts/check_localization.py` and `python3 Scripts/check_debug_switches.py`, run full `xcodebuild test` suite, verify `0.0%` idle CPU at rest in Instruments/Activity Monitor, and run `graphify update .`.

---

## 7. Verification Commands

### Unit Tests (Pure Core & Synchronous `-only-testing:`)
```sh
xcodebuild test -project KatiKati.xcodeproj -scheme KatiKati \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:KatiKatiTests/IconStudioCoreTests \
  -only-testing:KatiKatiTests/IconStudioBakeTests \
  -only-testing:KatiKatiTests/LiveIconMetricsTests \
  -only-testing:KatiKatiTests/FinderCompanionGeometryTests \
  -only-testing:KatiKatiTests/MacOSIconsClientTests \
  -only-testing:KatiKatiTests/IconSetTests \
  -only-testing:KatiKatiTests/WindowSwitcherModelTests
```

### Localization & Debug Switch Gates
```sh
python3 Scripts/check_localization.py
python3 Scripts/check_debug_switches.py
```

### Idle CPU & Livecheck Gate (`IS-6.3`)
- Build & run via `Scripts/build_and_run.sh`.
- Verify `0.0%` idle CPU for KatiKati at rest with static finishes applied, paused Apple Music / Spotify, idle Claude / Codex / Cursor, and unread count below badge threshold.
- Verify live hover shaders (`Holographic Foil`, `VHS`, `CRT`), active AI turn tide/tracer, active music vinyl/CD spin + pause-angle hold, `⌘+Tab` switcher parity, and `Light` / `Dark` / `Wallpaper` Studio stage previews.
