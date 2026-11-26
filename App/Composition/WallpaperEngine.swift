import AppKit
import Combine
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Phase 10b-2 / DW-2 — paints the real desktop from the sun phase, the weather and the environment pin.
/// The user's original wallpaper (per screen) is captured before the first change, persisted, and restored on
/// disable / quit. On by default since DW-2: the wallpaper follows the clock and the local forecast with no
/// location prompt, no extra network call (it reads `WeatherService`'s state) and no idle CPU spin — one timer
/// armed for the next phase boundary, plus debounced re-applies on Space change, wake and display topology.
@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    private struct Saved: Codable {
        var screenKey: String
        var url: String
        var scaling: Int?
        var allowClipping: Bool?
    }

    private static let savedKey = "com.katikati.wallpaper.original.v1"
    private let defaults = UserDefaults.standard
    private var settings: AppSettingsStore?
    private weak var weather: WeatherService?
    private var cancellables = Set<AnyCancellable>()
    private var stateCancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var boundaryTimer: Timer?
    private var pendingRefresh: DispatchWorkItem?
    private var refreshTask: Task<Void, Never>?
    private var refreshRevision = 0
    private var musicRenderTask: Task<Void, Never>?
    private var musicRenderRevision = 0
    private var overlayCheckTask: Task<Void, Never>?
    private var overlayCheckRevision = 0
    private var lastApplied: [String: String] = [:]
    /// Bumped whenever a *forced* re-apply has to hand macOS a different file URL for the same picture.
    private var generation = 0
    private(set) var isRunning = false
    /// DW-10: the plan that last painted, so the overlay follows the same sky without re-planning.
    private var lastAtmosphere: SkyAtmosphere?
    private(set) var screenLocked = false
    private(set) var isAsleep = false
    private(set) var desktopCovered = false
    /// ML-2: one capture of the user's original is shared by every writer (weather plan + album art).
    private var lease = WallpaperLease()
    /// The track currently painted by the music source, so a repeat publish never re-renders.
    private(set) var musicArtworkKey: String?
    private var musicSurfaceObserver: NSObjectProtocol?

    /// The three accent hues of the picture currently on screen, as hex — what the dock accent samples when
    /// the user chooses Wallpaper-Adaptive. Published so the strip repaints when the wallpaper moves on.
    @Published private(set) var accentHexes: [String] = []

    private init() {}

    func configure(settings: AppSettingsStore, weather: WeatherService) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.weather = weather
        // Every switch that changes the picture restarts it: on/off, the mode, the folder, the environment, and the
        // mood (Auto vs a lock). A mood change must repaint immediately, not wait for the next weather update.
        Publishers.CombineLatest4(settings.$wallpaperEnabled, settings.$wallpaperMode,
                                  settings.$wallpaperFolder, settings.$wallpaperTerrain)
            .combineLatest(settings.$wallpaperMood)
            .removeDuplicates { lhs, rhs in
                lhs.0.0 == rhs.0.0 && lhs.0.1 == rhs.0.1 && lhs.0.2 == rhs.0.2
                    && lhs.0.3 == rhs.0.3 && lhs.1 == rhs.1
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] combined, _ in
                guard let self else { return }
                if combined.0 { self.start() } else { self.stop() }
            }
            .store(in: &cancellables)
        // DW-10: turning Small Animation on or off re-evaluates the overlay immediately, without repainting the frame.
        // ML-2: the album-art source runs without the weather plan and shares the same capture.
        if MusicSurfaceConfig.isWallpaperEnabled {
            MusicWallpaperController.shared.start(service: DesktopWidgetServices.nowPlaying)
            DiscordPresence.shared.start(service: DesktopWidgetServices.nowPlaying)
            MusicMenuBarLyricsBridge.shared.start(service: DesktopWidgetServices.nowPlaying)
        }
        if LockScreenMusicCardController.isEnabled {
            LockScreenMusicCardController.shared.start()
        }
        // Settings / menu-bar switches post this; start or stop the opt-in card without polling.
        musicSurfaceObserver = NotificationCenter.default.addObserver(
            forName: MusicSurfaceConfig.didChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                if LockScreenMusicCardController.isEnabled {
                    LockScreenMusicCardController.shared.start()
                } else {
                    LockScreenMusicCardController.shared.stop()
                }
            }
        }
        settings.$wallpaperAnimate
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshOverlay() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    private func start() {
        if !isRunning {
            isRunning = true
            _ = acquireWallpaperLease(.weather)
            let center = NSWorkspace.shared.notificationCenter
            // Space switches, sleep/wake and display changes all drop a Space's desktop picture on macOS; each
            // is re-applied after a short debounce so a burst (dock → display → wake) paints once, not three times.
            // The Space switch is the only one the user can opt out of (its own settings row); wake and topology
            // changes always re-apply, because a display that came back has no picture at all until they do.
            observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard self?.settings?.wallpaperReapplyOnSpaceChange != false else { return }
                    self?.scheduleRefresh()
                }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.isAsleep = false
                    if WallpaperRefreshPolicy.shouldRefresh(forWake: true, isSleep: false) {
                        self.scheduleRefresh()
                    }
                    self.refreshOverlay()
                }
            })
            observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.isAsleep = true
                    self?.refreshOverlay()
                }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshOverlay() }
            })
            // DW-10 pause points, all push notifications — no polling. The covered-desktop test runs only when the
            // desktop could have changed (activation, Space change, resize), not on a timer.
            observers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshOverlay() }
            })
            observers.append(NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshOverlay() }
            })
            for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
                distributedObservers.append(DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.screenLocked = locked; self?.refreshOverlay() }
                })
            }
            weather?.$currentState
                .map { $0.conditionFamily }
                .removeDuplicates()
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.refresh(force: false) }
                .store(in: &stateCancellables)
        }
        lastApplied = [:]
        refresh(force: true)
    }

    /// Disable: put the original wallpaper back and stop everything.
    private func stop() {
        guard isRunning else { return }
        isRunning = false
        screenLocked = false
        teardown()
        WallpaperOverlay.shared.hide()
        _ = releaseWallpaperLease(.weather)
        accentHexes = []
    }

    /// App quit: restore, but leave the setting on so the next launch resumes.
    func restoreForQuit() {
        guard isRunning || lease.isCaptured || musicArtworkKey != nil else { return }
        isRunning = false
        screenLocked = false
        teardown()
        WallpaperOverlay.shared.hide()
        lease.reset()
        musicArtworkKey = nil
        restoreOriginal()
    }

    /// Menu/Settings "Restore Wallpaper" without turning the feature off.
    func restoreNow() {
        lease.reset()
        musicArtworkKey = nil
        restoreOriginal()
        lastApplied = [:]
    }

    private func teardown() {
        boundaryTimer?.invalidate(); boundaryTimer = nil
        pendingRefresh?.cancel(); pendingRefresh = nil
        refreshTask?.cancel(); refreshTask = nil
        musicRenderTask?.cancel(); musicRenderTask = nil
        overlayCheckTask?.cancel(); overlayCheckTask = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        distributedObservers = []
        stateCancellables = []
    }

    /// Coalesces the burst of notifications a single Space switch or wake produces into one paint.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh(force: true) }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - ML-2: shared wallpaper lease

    /// Captures once per lease chain. Adopts a capture a previous run left behind, so a crash cannot make
    /// the next launch treat album art as the user's wallpaper.
    private func acquireWallpaperLease(_ source: WallpaperSource) -> Bool {
        let mustCapture = lease.acquire(source)
        captureOriginalIfNeeded()
        if defaults.data(forKey: Self.savedKey) != nil { lease.adoptCapture() }
        return mustCapture
    }

    /// Restores only when the last holder leaves; otherwise asks the weather plan to repaint so the desktop
    /// never falls back to the user's original while another surface is still painting.
    @discardableResult
    private func releaseWallpaperLease(_ source: WallpaperSource) -> Bool {
        guard lease.release(source) else {
            if isRunning {
                lastApplied = [:]
                refresh(force: true)
            }
            return false
        }
        restoreOriginal()
        return true
    }

    // MARK: - ML-2: album-art wallpaper

    private func screenTargets() -> [(id: String, size: CGSize)] {
        NSScreen.screens.map { screen in
            let scale = max(screen.backingScaleFactor, 1)
            return (
                Self.screenKey(screen),
                CGSize(width: min(screen.frame.width * scale, 5120),
                       height: min(screen.frame.height * scale, 2880))
            )
        }
    }

    @discardableResult
    private func applyRendered(_ rendered: [(id: String, url: URL)], appliedValue: String, label: String) -> Bool {
        let screensByKey = Dictionary(NSScreen.screens.map { (Self.screenKey($0), $0) }, uniquingKeysWith: { first, _ in first })
        var applied = false
        for item in rendered {
            guard let screen = screensByKey[item.id] else { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(item.url, for: screen, options: [:])
                lastApplied[item.id] = appliedValue
                applied = true
            } catch {
                NSLog("WallpaperEngine: \(label) failed: \(error)")
            }
        }
        return applied
    }

    /// Paints the artwork as the desktop picture for every screen: one cached file per track, one
    /// `setDesktopImageURL` per screen, no timer and no overlay. Returns false when nothing was applied.
    @discardableResult
    func applyMusicArtwork(_ data: Data, trackKey: String) -> Bool {
        guard !data.isEmpty, !trackKey.isEmpty else { return false }
        if !lease.holders.contains(.music) { _ = acquireWallpaperLease(.music) }
        let classic = MusicSurfaceConfig.isClassicBackdrop
        let style = MusicSurfaceConfig.wallpaperStyle()
        let screenSpecs = screenTargets()
        guard !screenSpecs.isEmpty else { return false }
        musicRenderTask?.cancel()
        musicRenderRevision &+= 1
        let rev = musicRenderRevision
        musicRenderTask = Task.detached(priority: .utility) { [weak self] in
            let palette = MusicArtworkPaletteCache.shared.palette(for: data)
            var rendered: [(id: String, url: URL)] = []
            for spec in screenSpecs {
                if Task.isCancelled { return }
                if let url = MusicWallpaperRenderer.materialize(
                    artwork: data, trackKey: trackKey, size: spec.size, blur: !classic,
                    style: style, palette: palette
                ) {
                    rendered.append((spec.id, url))
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.musicRenderRevision == rev, self.lease.holders.contains(.music) else { return }
                if self.applyRendered(rendered, appliedValue: "music-\(trackKey)", label: "music artwork") {
                    self.musicArtworkKey = trackKey
                }
            }
        }
        return true
    }

    /// Animated path: the frames are already-rendered files, so a tick is one `setDesktopImageURL` per screen
    /// and nothing else. No CoreImage work happens while the animation is running.
    @discardableResult
    func applyMusicFrame(urls: [URL], trackKey: String) -> Bool {
        guard !urls.isEmpty else { return false }
        if !lease.holders.contains(.music) { _ = acquireWallpaperLease(.music) }
        var applied = false
        for (index, screen) in NSScreen.screens.enumerated() where index < urls.count {
            do {
                try NSWorkspace.shared.setDesktopImageURL(urls[index], for: screen, options: [:])
                lastApplied[Self.screenKey(screen)] = "music-\(trackKey)-\(urls[index].lastPathComponent)"
                applied = true
            } catch {
                NSLog("WallpaperEngine: music frame failed: \(error)")
            }
        }
        if applied { musicArtworkKey = trackKey }
        return applied
    }

    /// Pause / stop / disable / quit: hand the desktop back (only the last holder actually restores).
    func clearMusicArtwork() {
        musicRenderTask?.cancel()
        musicRenderTask = nil
        musicRenderRevision &+= 1
        guard musicArtworkKey != nil || lease.holders.contains(.music) else { return }
        musicArtworkKey = nil
        lastApplied = lastApplied.filter { !$0.value.hasPrefix("music-") }
        _ = releaseWallpaperLease(.music)
    }

    // MARK: - Apply

    private func refresh(force: Bool) {
        guard isRunning, let settings else { return }
        let now = Date()
        let state = weather?.currentState ?? .empty
        let times = state.sunTimes(on: now) ?? SunTimes(sunrise: nil, sunset: nil, polar: state.isNight ? .night : .day)
        let forced = WallpaperDebugOverride.parse(DebugSwitch.wallpaperPhase.value())
        let daylight = SolarDaylightEvaluator.sample(at: now, times: times)
        let mode = WallpaperMode(rawValue: settings.wallpaperMode) ?? .both
        let liveSky = mode == .time ? WallpaperSky.clear : WallpaperSky(state.conditionFamily)
        let locked = settings.wallpaperMoodValue.resolve(weather: liveSky, phase: daylight.phase.solarPhase)
        let phase = forced?.phase ?? locked.phase
        let sky = forced?.sky ?? locked.sky
        armTimer(after: now, times: times)

        let scene = TerrainMimicCatalog.resolve(settings.wallpaperTerrainValue,
                                                latitude: state.latitude, cityName: state.cityName)
        let environment = TerrainMimicCatalog.environment(scene: scene, phase: phase, sky: sky)
        let atmosphere = SkyAtmosphere.plan(phase: phase, sky: sky, date: now, seed: Self.meteorSeed(scene: scene),
                                            latitude: state.latitude, longitude: state.longitude)
        accentHexes = environment.accent.map { DockAccentColor(r: CGFloat($0.r), g: CGFloat($0.g), b: CGFloat($0.b)).hex }
        lastAtmosphere = atmosphere
        refreshOverlay()

        guard !lease.holders.contains(.music) else { return }
        let terrainKey = "terrain-\(scene.rawValue)-\(phase.rawValue)-\(sky.rawValue)"
        let screenSpecs = screenTargets()
        let lastAppliedSnapshot = lastApplied
        let folder = settings.wallpaperFolder
        let lowPower = settings.wallpaperRespectLowPower && ProcessInfo.processInfo.isLowPowerModeEnabled
        let currentGen = generation
        let lat = state.latitude
        let lon = state.longitude
        refreshTask?.cancel()
        refreshRevision &+= 1
        let rev = refreshRevision
        refreshTask = Task.detached(priority: .utility) { [weak self] in
            let custom = Self.pack(folder: folder)
            let key = custom.isEmpty ? terrainKey
                : (WallpaperSelector.pick(phase: phase, sky: sky, mode: mode, available: Set(custom.keys)) ?? terrainKey)
            let useGeneration = WallpaperRefreshPolicy.nextGeneration(
                current: currentGen, force: force,
                keyAlreadyApplied: lastAppliedSnapshot.values.contains(key),
                lowPower: lowPower
            )
            var rendered: [(id: String, url: URL)] = []
            for spec in screenSpecs {
                if Task.isCancelled { return }
                if !force, lastAppliedSnapshot[spec.id] == key { continue }
                let url = custom[key]?()
                    ?? TerrainWallpaperRenderer.materialize(
                        environment: environment, atmosphere: atmosphere, key: key,
                        size: spec.size, generation: useGeneration,
                        latitude: lat, longitude: lon, date: now
                    )
                if let url { rendered.append((spec.id, url)) }
            }
            if !Task.isCancelled { TerrainWallpaperRenderer.prune() }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.isRunning, self.refreshRevision == rev,
                      !self.lease.holders.contains(.music) else { return }
                self.generation = useGeneration
                self.applyRendered(rendered, appliedValue: key, label: "setDesktopImageURL")
            }
        }
    }

    /// One timer for the next sun-phase boundary; re-armed on every refresh. Not created when stopped.
    private func armTimer(after now: Date, times: SunTimes) {
        boundaryTimer?.invalidate()
        let fire = SolarPhaseResolver.nextBoundary(after: now, times: times)
        let timer = Timer(fire: fire.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh(force: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        boundaryTimer = timer
    }

    // MARK: - Original wallpaper

    private func captureOriginalIfNeeded() {
        // A persisted capture means a previous run changed the wallpaper and never restored (crash): keep it.
        guard defaults.data(forKey: Self.savedKey) == nil else { return }
        let saved: [Saved] = NSScreen.screens.compactMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            let options = NSWorkspace.shared.desktopImageOptions(for: screen)
            return Saved(screenKey: Self.screenKey(screen), url: url.absoluteString,
                         scaling: (options?[.imageScaling] as? NSNumber)?.intValue,
                         allowClipping: (options?[.allowClipping] as? NSNumber)?.boolValue)
        }
        defaults.set(try? JSONEncoder().encode(saved), forKey: Self.savedKey)
    }

    private func restoreOriginal() {
        guard let data = defaults.data(forKey: Self.savedKey),
              let saved = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        for screen in NSScreen.screens {
            guard let item = saved.first(where: { $0.screenKey == Self.screenKey(screen) }),
                  let url = URL(string: item.url) else { continue }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let s = item.scaling, let scaling = NSImageScaling(rawValue: UInt(s)) { options[.imageScaling] = scaling.rawValue }
            if let c = item.allowClipping { options[.allowClipping] = c }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
        defaults.removeObject(forKey: Self.savedKey)
    }

    /// DW-10: one guard decision per event, never per frame. Inactive hides the window *and* removes its animations.
    private func refreshOverlay() {
        overlayCheckTask?.cancel()
        overlayCheckRevision &+= 1
        guard isRunning, let atmosphere = lastAtmosphere, let settings else {
            WallpaperOverlay.shared.hide()
            return
        }
        let forcedPause = DebugSwitch.wallpaperAnimate.value() == "pause"
        let isEnabled = settings.wallpaperAnimate
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled || forcedPause
        let locked = screenLocked || isAsleep
        guard WallpaperMotionGuard.isActive(
            isEnabled: isEnabled,
            reduceMotion: reduceMotion,
            lowPower: lowPower,
            screenLocked: locked,
            desktopCovered: false
        ) else {
            desktopCovered = false
            WallpaperOverlay.shared.hide()
            return
        }
        // MD-3: the overlay follows the display the pointer is on, not the menu-bar display.
        guard let screenFrame = CursorPopoverGeometry.screen()?.frame else {
            desktopCovered = false
            WallpaperOverlay.shared.update(atmosphere: atmosphere, active: true)
            return
        }
        let rev = overlayCheckRevision
        overlayCheckTask = Task.detached(priority: .utility) { [weak self] in
            let covered = Self.isDesktopCovered(in: screenFrame)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, self.overlayCheckRevision == rev, self.isRunning,
                      let currentAtmosphere = self.lastAtmosphere else { return }
                self.desktopCovered = covered
                let active = WallpaperMotionGuard.isActive(
                    isEnabled: isEnabled, reduceMotion: reduceMotion,
                    lowPower: lowPower, screenLocked: self.screenLocked || self.isAsleep,
                    desktopCovered: covered
                )
                WallpaperOverlay.shared.update(atmosphere: currentAtmosphere, active: active)
            }
        }
    }

    /// Is a normal app window covering ≥ 98 % of the main screen? Sampled on a 20×20 grid off `@MainActor`.
    nonisolated private static func isDesktopCovered(in screenFrame: CGRect) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        var rects: [CGRect] = []
        for info in list where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            if rect.intersects(screenFrame) { rects.append(rect) }
        }
        guard !rects.isEmpty else { return false }
        var hits = 0
        for column in 0..<20 {
            for row in 0..<20 {
                let point = CGPoint(x: screenFrame.minX + screenFrame.width * (CGFloat(column) + 0.5) / 20,
                                    y: screenFrame.minY + screenFrame.height * (CGFloat(row) + 0.5) / 20)
                if rects.contains(where: { $0.contains(point) }) { hits += 1 }
            }
        }
        return Double(hits) / 400 >= WallpaperMotionGuard.coveredFraction
    }

    /// A fixed per-scene seed: the meteor is the only seeded part of the plan, and it must not change between two
    /// renders of the same night (the cache key would churn every refresh).
    private static func meteorSeed(scene: WallpaperScene) -> UInt64 {
        switch scene {
        case .city: return 0x51D3
        case .countryside: return 0x2A11
        case .alpine: return 0x7E57
        case .coast: return 0x0CE4
        }
    }

    /// MD-2 / M5: per-display wallpaper identity is the EDID UUID, like every other per-display
    /// store. `CGDirectDisplayID` changes when the monitor comes back on another port, which used to
    /// repaint a display that had already been given its own picture. The numeric id stays as a
    /// fallback for a display with no UUID, and `lastApplied` is memory-only, so nothing stale is
    /// carried across a relaunch.
    private static func screenKey(_ screen: NSScreen) -> String {
        if let uuid = DisplayIdentity.uuidString(for: screen), !uuid.isEmpty { return uuid }
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    // MARK: - Packs

    /// key → lazily produced file URL, from a custom folder only. Empty when no folder is set (then the built-in
    /// scenes are painted by `TerrainWallpaperRenderer`), so a missing folder can never shadow the built-in look.
    nonisolated private static func pack(folder: String) -> [String: () -> URL?] {
        guard !folder.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [:] }
        var result: [String: () -> URL?] = [:]
        for file in files where ["jpg", "jpeg", "png", "heic"].contains((file as NSString).pathExtension.lowercased()) {
            let key = ((file as NSString).deletingPathExtension).lowercased()
            result[key] = { URL(fileURLWithPath: folder).appendingPathComponent(file) }
        }
        for (alias, canonical) in WallpaperSelector.skyPackAliases where result[canonical] != nil {
            result[alias] = result[canonical]
        }
        return result
    }
}

/// ML-2 — one cached, content-addressed blurred frame per track. The only per-track cost is this single
/// CoreImage pass; afterwards the file is reused, so an unchanging track costs nothing.
enum MusicWallpaperRenderer {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private static func fittedImage(artwork: Data, target: CGRect, blur: Bool, blurRadius: Double) -> (blurred: CIImage, clear: CIImage)? {
        guard let source = CIImage(data: artwork), source.extent.width > 1, source.extent.height > 1 else { return nil }
        let scale = max(target.width / source.extent.width, target.height / source.extent.height)
        var image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        image = image.transformed(by: CGAffineTransform(
            translationX: (target.width - image.extent.width) / 2,
            y: (target.height - image.extent.height) / 2))
        let clear = image.cropped(to: target)
        let blurred = blur
            ? clear.clampedToExtent().applyingGaussianBlur(sigma: blurRadius).cropped(to: target)
            : clear
        return (blurred, clear)
    }

    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = WallpaperCache.generatedDirectory(in: base)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func materialize(artwork: Data, trackKey: String, size: CGSize,
                            blur: Bool = true, blurRadius: Double = 55,
                            style: MusicWallpaperStyle = .blurredAlbum,
                            palette: MusicArtworkPalette = .fallback) -> URL? {
        guard let dir = directory(), size.width >= 1, size.height >= 1 else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let name = "music-\(signature(trackKey))-\(width)x\(height)-\(blur ? "b" : "p")-\(style.rawValue)\(style.isAtmospheric ? "-" + paletteTag(palette) : "").png"
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        guard let fitted = fittedImage(artwork: artwork, target: target, blur: blur, blurRadius: blurRadius) else { return nil }
        let image = painted(blurred: fitted.blurred, clear: fitted.clear, target: target, style: style, palette: palette)
        guard let cgImage = ciContext.createCGImage(image, from: target),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Animated sequence: `frameCount` frames of a slow zoom + drift around the same cached artwork.
    /// Rendered once per track and size, then looped by swapping URLs — no per-frame CoreImage work.
    static func materializeFrames(artwork: Data, trackKey: String, size: CGSize, frameCount: Int = 8,
                                  blur: Bool = true, blurRadius: Double = 45,
                                  style: MusicWallpaperStyle = .blurredAlbum,
                                  palette: MusicArtworkPalette = .fallback) -> [URL] {
        let count = max(2, frameCount)
        return (0..<count).compactMap {
            materializeFrame(artwork: artwork, trackKey: trackKey, size: size, index: $0, frameCount: count,
                             blur: blur, blurRadius: blurRadius, style: style, palette: palette)
        }
    }

    static func materializeFrame(artwork: Data, trackKey: String, size: CGSize, index: Int, frameCount: Int,
                                 blur: Bool, blurRadius: Double,
                                 style: MusicWallpaperStyle = .blurredAlbum,
                                 palette: MusicArtworkPalette = .fallback) -> URL? {
        guard let dir = directory(), size.width >= 1, size.height >= 1 else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let name = "music-\(signature(trackKey))-\(width)x\(height)-\(blur ? "ba" : "pa")\(index)-\(style.rawValue).jpg"
        let url = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let target = CGRect(x: 0, y: 0, width: width, height: height)
        guard let fitted = fittedImage(artwork: artwork, target: target, blur: blur, blurRadius: blurRadius) else { return nil }
        var image = fitted.blurred
        let progress = CGFloat(index) / CGFloat(max(1, frameCount))
        let zoom = 1.05 + 0.05 * (0.5 - 0.5 * cos(2 * .pi * progress))
        let panX = 0.010 * sin(2 * .pi * progress)
        let panY = 0.008 * cos(2 * .pi * progress)
        image = image
            .transformed(by: CGAffineTransform(translationX: -target.midX, y: -target.midY))
            .transformed(by: CGAffineTransform(scaleX: zoom, y: zoom))
            .transformed(by: CGAffineTransform(translationX: target.midX + panX * target.width,
                                               y: target.midY + panY * target.height))
            .cropped(to: target)
        image = painted(blurred: image, clear: image, target: target, style: style, palette: palette)
        guard let cgImage = ciContext.createCGImage(image, from: target),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// The Atmospheric paint pass: one CoreImage pass per track for the multi-stop mesh, the full-bleed fade,
    /// the crisp plate, the dim/brighten and the accent tint. Every style shares it, so there is still exactly
    /// one place that decides what a wallpaper looks like.
    static func painted(blurred image: CIImage, clear: CIImage, target: CGRect,
                        style: MusicWallpaperStyle, palette: MusicArtworkPalette) -> CIImage {
        var result = image
        if style == .atmosphericMesh {
            result = mesh(result, target: target, palette: palette)
        }
        if style == .fullBleedFade {
            let mask = CIImage(color: .white).cropped(to: target)
                .applyingFilter("CIGaussianGradient", parameters: [
                    "inputCenter": CIVector(x: target.midX, y: target.maxY - target.height * 0.28),
                    "inputRadius0": target.height * 0.10,
                    "inputRadius1": target.height * 0.62,
                    "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0)
                ])
                .cropped(to: target)
            let inset = target.insetBy(dx: target.width * 0.06, dy: target.height * 0.06)
            let factor = max(inset.width / max(clear.extent.width, 1), inset.height / max(clear.extent.height, 1))
            var plate = clear.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            plate = plate.transformed(by: CGAffineTransform(
                translationX: inset.midX - plate.extent.midX, y: inset.midY - plate.extent.midY))
            plate = plate.cropped(to: inset)
            let faded = plate.composited(over: result).applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: result,
                kCIInputMaskImageKey: mask.applyingFilter("CIMaskToAlpha")
            ])
            result = faded.cropped(to: target)
        }
        if style.keepsArtworkCrisp && style != .fullBleedFade {
            // The art stays readable: a crisp copy inset over the blurred base (no rounding: the card does that).
            let inset = target.insetBy(dx: target.width * 0.19, dy: target.height * 0.19)
            let factor = max(inset.width / max(clear.extent.width, 1), inset.height / max(clear.extent.height, 1))
            var plate = clear.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            plate = plate.transformed(by: CGAffineTransform(
                translationX: inset.midX - plate.extent.midX, y: inset.midY - plate.extent.midY))
            plate = plate.cropped(to: inset)
            result = plate.composited(over: result)
        }
        if style.dim > 0 || style.brighten > 0 {
            result = result.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: style.brighten - style.dim
            ]).cropped(to: target)
        }
        if style.tintMix > 0 {
            let tint = CIImage(color: CIColor(red: palette.accent.r, green: palette.accent.g, blue: palette.accent.b))
                .cropped(to: target)
            result = tint.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: style.tintMix)
            ]).composited(over: result)
        }
        return result.cropped(to: target)
    }

    /// Multi-stop adaptive mesh: one radial gradient per palette stop, over the blurred art, then a vignette so
    /// the corners sink instead of flattening. Five filters, once per track.
    private static func mesh(_ image: CIImage, target: CGRect, palette: MusicArtworkPalette) -> CIImage {
        var result = image
        let span = max(target.width, target.height)
        for stop in MusicMeshStops.stops(for: palette) {
            let center = CIVector(x: target.minX + target.width * stop.x, y: target.minY + target.height * stop.y)
            let radius = span * stop.radius
            guard let gradient = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": radius * 0.10,
                "inputRadius1": radius,
                "inputColor0": CIColor(red: stop.r, green: stop.g, blue: stop.b, alpha: 0.62),
                "inputColor1": CIColor(red: stop.r, green: stop.g, blue: stop.b, alpha: 0)
            ]), let field = gradient.outputImage else { continue }
            result = field.cropped(to: target).composited(over: result)
        }
        return result.applyingFilter("CIVignette", parameters: [
            kCIInputIntensityKey: 0.85,
            kCIInputRadiusKey: 1.9
        ]).cropped(to: target)
    }

    /// Stable palette tag so a mesh repaint happens when the colours change, not on every track tick.
    private static func paletteTag(_ palette: MusicArtworkPalette) -> String {
        func hex(_ value: Double) -> String {
            String(format: "%02x", Int((min(max(value, 0), 1) * 255).rounded()))
        }
        return hex(palette.accent.r) + hex(palette.accent.g) + hex(palette.accent.b)
            + hex(palette.secondary.r) + hex(palette.secondary.g) + hex(palette.secondary.b)
            + (palette.isDark ? "d" : "l")
    }

    /// Filename-safe, stable content key.
    private static func signature(_ key: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

/// ML-2 — the only observer of `NowPlayingService` for wallpaper purposes. Deduped by track and artwork
/// size, so a once-per-second position tick never touches the desktop.
@MainActor
final class MusicWallpaperController {
    static let shared = MusicWallpaperController()

    private var service: NowPlayingService?
    private var stateCancellable: AnyCancellable?
    private var changeObserver: NSObjectProtocol?
    private var staticKey: String?
    private var timer: Timer?
    private var frameSets: [[URL]] = []
    private var frameIndex = 0
    private var animatedKey: String?
    private var generation = 0
    /// One swap every 4 s. Each swap makes WindowServer decode a frame, and that decode — not our code — is
    /// what a tighter cadence would cost. 0.25 Hz still reads as a slow drift.
    private let frameInterval: TimeInterval = 4
    private let frameCount = 6

    func start(service: NowPlayingService) {
        guard self.service == nil else { return }
        self.service = service
        stateCancellable = service.$state
            .removeDuplicates { lhs, rhs in
                // Play state is part of the key: pause must stop the animation and resume must start it
                // without waiting for a track change.
                lhs.title == rhs.title && lhs.artist == rhs.artist
                    && lhs.isPlaying == rhs.isPlaying
                    && MusicArtworkSignature.of(lhs.artworkData) == MusicArtworkSignature.of(rhs.artworkData)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.apply(state) }
        changeObserver = NotificationCenter.default.addObserver(
            forName: MusicSurfaceConfig.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.apply(self?.service?.state ?? NowPlayingState(isPlaying: false)) }
        }
        apply(service.state)
    }

    func stop() {
        stopAnimation()
        stateCancellable = nil
        if let changeObserver { NotificationCenter.default.removeObserver(changeObserver) }
        changeObserver = nil
        service = nil
        staticKey = nil
        WallpaperEngine.shared.clearMusicArtwork()
    }

    private func apply(_ state: NowPlayingState) {
        guard MusicSurfaceConfig.isWallpaperEnabled,
              let data = state.artworkData, !data.isEmpty,
              let title = state.title, !title.isEmpty else {
            stopAnimation()
            staticKey = nil
            WallpaperEngine.shared.clearMusicArtwork()
            return
        }
        // Content identity, not byte count: a re-send of the same art must not re-render frames.
        let key = "\(title)|\(state.artist ?? "")|\(MusicArtworkSignature.of(data))"
        // Off, paused, or not playing: the cached static frame is the whole picture. No timer survives this.
        guard MusicSurfaceConfig.isAnimatedBackdrop, state.isPlaying else {
            stopAnimation()
            guard staticKey != key else { return }
            if WallpaperEngine.shared.applyMusicArtwork(data, trackKey: key) { staticKey = key }
            return
        }
        startAnimation(data: data, key: key)
    }

    /// Frames are pre-rendered off the main thread once per track, then looped at `frameInterval` (0.5 Hz).
    private func startAnimation(data: Data, key: String) {
        guard animatedKey != key || timer == nil else { return }
        generation += 1
        let generation = generation
        timer?.invalidate()
        timer = nil
        frameSets = []
        frameIndex = 0
        animatedKey = key
        staticKey = nil
        let classic = MusicSurfaceConfig.isClassicBackdrop
        let count = frameCount
        // Point size, not backing size: these frames are blurred art shown full-bleed, and the smaller file
        // is what keeps a 0.5 Hz swap cheap for WindowServer to decode.
        let sizes = NSScreen.screens.map { screen -> CGSize in
            CGSize(width: min(screen.frame.width, 5120), height: min(screen.frame.height, 2880))
        }
        Task.detached(priority: .utility) {
            let sets = sizes.map {
                MusicWallpaperRenderer.materializeFrames(
                    artwork: data, trackKey: key, size: $0, frameCount: count, blur: !classic,
                    style: MusicSurfaceConfig.wallpaperStyle(),
                    palette: MusicArtworkPaletteCache.shared.palette(for: data)
                )
            }
            await MainActor.run { [weak self] in
                guard let self, self.generation == generation,
                      sets.contains(where: { !$0.isEmpty }) else { return }
                self.frameSets = sets
                self.frameIndex = 0
                self.applyFrame()
                self.startTimer()
            }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advance() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func advance() {
        guard timer != nil, !frameSets.isEmpty,
              MusicSurfaceConfig.isWallpaperEnabled,
              MusicSurfaceConfig.isAnimatedBackdrop,
              service?.state.isPlaying == true else {
            stopAnimation()
            return
        }
        let engine = WallpaperEngine.shared
        guard WallpaperMotionGuard.isMusicSwapAllowed(
            isEnabled: MusicSurfaceConfig.isWallpaperEnabled,
            isAnimated: MusicSurfaceConfig.isAnimatedBackdrop,
            isPlaying: service?.state.isPlaying == true,
            screenLocked: engine.screenLocked,
            isAsleep: engine.isAsleep,
            desktopCovered: engine.desktopCovered
        ) else { return }
        let length = frameSets.map(\.count).min() ?? 0
        guard length > 0 else { return }
        frameIndex = (frameIndex + 1) % length
        applyFrame()
    }

    private func applyFrame() {
        guard !frameSets.isEmpty, let key = animatedKey else { return }
        let urls = frameSets.compactMap { set -> URL? in
            guard !set.isEmpty else { return nil }
            return set[min(frameIndex, set.count - 1)]
        }
        _ = WallpaperEngine.shared.applyMusicFrame(urls: urls, trackKey: key)
    }

    private func stopAnimation() {
        generation += 1
        timer?.invalidate()
        timer = nil
        frameSets = []
        frameIndex = 0
        animatedKey = nil
    }
}

/// DW-2 — paints one scene into a PNG per display resolution and hands macOS a stable URL for it.
/// Files are content-addressed (`key`, size and a palette signature in the name), so a palette change produces a
/// new file instead of macOS ignoring a URL it already shows, and `prune()` keeps disk use bounded.
enum TerrainWallpaperRenderer {
    /// DW-7: frames are generated files, so they live in their own cache — never beside the Sky pack
    /// (the simple wallpapers) and never in a folder the user or a custom pack owns.
    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = WallpaperCache.generatedDirectory(in: base)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The URL for the picture, rendering it when missing. `generation > 0` yields a *copy* under a different
    /// name: same pixels, new URL, so a forced re-apply is not silently ignored.
    static func materialize(environment: WallpaperEnvironment, atmosphere: SkyAtmosphere, key: String,
                            size: CGSize, generation: Int, latitude: Double? = nil, longitude: Double? = nil,
                            date: Date = Date()) -> URL? {
        guard let dir = directory() else { return nil }
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let coordinateKey = "\(Int((latitude ?? 0) * 1000))-\(Int((longitude ?? 0) * 1000))"
        let base = "\(key)-\(width)x\(height)-\(coordinateKey)-\(WallpaperFrameSignature.of(environment, atmosphere))"
        let source = dir.appendingPathComponent("\(base).png")
        if !FileManager.default.fileExists(atPath: source.path) {
            guard let image = render(environment: environment, atmosphere: atmosphere, width: width, height: height,
                                     latitude: latitude, longitude: longitude, date: date),
                  let dest = CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(dest, image, nil)
            guard CGImageDestinationFinalize(dest) else { return nil }
        }
        cleanLegacyOnce()
        guard generation > 0 else { return source }
        let copy = dir.appendingPathComponent("\(base)-g\(generation).png")
        if !FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.removeItem(at: copy)
            try? FileManager.default.copyItem(at: source, to: copy)
        }
        return copy
    }

    /// Drops yesterday's pictures and keeps at most two generations per picture: the cache cannot grow without
    /// bound while Space switches keep asking for fresh URLs. Only KatiKati's own render names are candidates
    /// (DW-7) — a file the user dropped into the folder survives.
    static func prune(now: Date = Date()) {
        guard let dir = directory() else { return }
        WallpaperCache.prune(in: dir, now: now)
    }

    /// The pre-DW-7 renders are retired once, after a frame exists in the new cache, and only when they carry
    /// this renderer's own names — the Sky pack beside them is the user's simple wallpapers.
    private static let legacyLock = NSLock()
    private static var didCleanLegacy = false
    private static func cleanLegacyOnce() {
        let shouldClean = legacyLock.withLock {
            guard !didCleanLegacy else { return false }
            didCleanLegacy = true
            return true
        }
        guard shouldClean,
              let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return }
        WallpaperCache.removeLegacyRenders(in: WallpaperCache.legacyDirectory(in: base))
    }

    static func render(environment: WallpaperEnvironment, atmosphere: SkyAtmosphere,
                       width: Int, height: Int, latitude: Double? = nil, longitude: Double? = nil,
                       date: Date = Date()) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard width > 0, height > 0,
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        func color(_ c: SkyRGB, _ alpha: CGFloat = 1) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: alpha) }

        // Sky. CoreGraphics origin is bottom-left: the top stop is drawn at y = height.
        if let sky = CGGradient(colorsSpace: space, colors: [color(environment.skyTop), color(environment.skyBottom)] as CFArray,
                                locations: [0, 1]) {
            ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: h), end: .zero, options: [])
        }
        // Stars before the land, so a night sky keeps them and a ridge can cover them. The atmosphere decides how
        // many and how bright; twinkle is baked into each star's static alpha, so a still frame never shimmers.
        drawStars(ctx, atmosphere: atmosphere, width: w, height: h, color: color(environment.glow))
        drawMeteor(ctx, meteor: atmosphere.meteor, width: w, height: h)
        // The moon sits in the glow band, before the land: its azimuth places it across the sky, its altitude
        // lifts it, and its phase decides which side stays dark.
        drawMoon(ctx, moon: atmosphere.moon, width: w, height: h, color: color(environment.glow))
        // Sun / moon glow above the horizon.
        if environment.glowStrength > 0,
           let glow = CGGradient(colorsSpace: space,
                                 colors: [color(environment.glow, CGFloat(environment.glowStrength)),
                                          color(environment.glow, 0)] as CFArray, locations: [0, 1]) {
            let glowPosition = SolarGlowPosition.at(date, latitude: latitude, longitude: longitude)
            let center = CGPoint(x: w * glowPosition.x, y: h * glowPosition.y)
            ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: h * 0.45, options: [])
        }
        // DW-9 commit B: cloud bands sit above the horizon glow and behind the silhouettes, so a ridge can cover
        // the bottom of a bank exactly as it covers the stars.
        drawClouds(ctx, atmosphere: atmosphere, width: w, height: h, color: color(environment.glow))
        // Silhouette bands, farthest first.
        for (index, layer) in environment.layers.enumerated() {
            drawLayer(ctx, scene: environment.scene, index: index, of: environment.layers.count,
                      color: color(layer), width: w, height: h)
        }
        return ctx.makeImage()
    }

    /// DW-9 commit A: `starCount` stars at deterministic positions (index-seeded, not per-frame), each one's alpha
    /// `starOpacity` faded by its own share of `twinkleDepth` — static in the file, so no shimmer on a still frame.
    private static func drawStars(_ ctx: CGContext, atmosphere: SkyAtmosphere, width: CGFloat, height: CGFloat, color: CGColor) {
        guard atmosphere.starOpacity > 0, atmosphere.starCount > 0 else { return }
        let rgb = color.components ?? [1, 1, 1, 1]
        for index in 0..<atmosphere.starCount {
            var seed = UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ 0x5EED_1234
            func next() -> UInt64 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return seed
            }
            let x = CGFloat((next() >> 33) % 1_000) / 1_000 * width
            let y = height * (0.50 + CGFloat((next() >> 33) % 480) / 1_000)
            let r = 0.6 + CGFloat((next() >> 40) % 15) / 10
            let share = Double((next() >> 20) % 1_000) / 1_000
            let alpha = atmosphere.starOpacity * (1 - atmosphere.twinkleDepth * (0.35 + 0.65 * share))
            ctx.setFillColor(CGColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: CGFloat(max(alpha, 0))))
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
        }
    }

    /// One seeded streak for the night, never by day (`SkyAtmosphere` already returns `.none` then).
    private static func drawMeteor(_ ctx: CGContext, meteor: Meteor, width: CGFloat, height: CGFloat) {
        guard meteor != .none else { return }
        let bright = meteor == .bright
        let head = CGPoint(x: width * 0.27, y: height * 0.79)
        let tail = CGPoint(x: width * 0.19, y: height * 0.87)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: bright ? 0.85 : 0.45))
        ctx.setLineWidth(bright ? 2.4 : 1.2)
        ctx.move(to: tail); ctx.addLine(to: head)
        ctx.strokePath()
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: bright ? 0.95 : 0.55))
        ctx.fillEllipse(in: CGRect(x: head.x - 1.5, y: head.y - 1.5, width: 3, height: 3))
        ctx.restoreGState()
    }

    /// Two-circle phase: a faint full disc, the lit limb, then a lit core once the moon is more than half full.
    /// Halo and haze come straight from the plan, and the moon is skipped when it is below the horizon.
    private static func drawMoon(_ ctx: CGContext, moon: MoonAppearance, width: CGFloat, height: CGFloat, color: CGColor) {
        guard moon.visibility > 0.01 else { return }
        let radius = min(width, height) * 0.022
        let center = CGPoint(x: width * CGFloat(moon.azimuth / 360),
                             y: height * (0.62 + 0.26 * CGFloat(max(min(moon.altitude, 90), -10) / 90)))
        let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let rgb = color.components ?? [1, 1, 1, 1]
        func fill(_ alpha: Double) -> CGColor { CGColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: CGFloat(alpha)) }

        if moon.halo > 0.01, let halo = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                  colors: [fill(moon.halo * 0.28), fill(0)] as CFArray, locations: [0, 1]) {
            ctx.drawRadialGradient(halo, startCenter: center, startRadius: radius, endCenter: center,
                                   endRadius: radius * (2.4 + moon.haze * 1.6), options: [])
        }
        ctx.setFillColor(fill(moon.visibility * 0.18))
        ctx.fillEllipse(in: disc)
        ctx.saveGState()
        ctx.addEllipse(in: disc)
        ctx.clip()
        let waxing = moon.waxing
        let litHalf = CGRect(x: waxing ? center.x : center.x - radius, y: center.y - radius,
                             width: radius, height: radius * 2)
        ctx.clip(to: litHalf)
        ctx.setFillColor(fill(moon.visibility))
        ctx.fill(disc)
        ctx.restoreGState()
        if moon.illumination > 0.5 {
            let core = radius * 2 * CGFloat(2 * moon.illumination - 1)
            ctx.saveGState()
            ctx.addEllipse(in: disc)
            ctx.clip()
            ctx.setFillColor(fill(moon.visibility))
            ctx.fillEllipse(in: CGRect(x: center.x - core / 2, y: center.y - radius, width: core, height: radius * 2))
            ctx.restoreGState()
        }
    }

    /// DW-9 commit B: one band per plan entry — `cirrus` thin stretched blobs, `wisp` soft ellipses, `bank` stacked
    /// heavy ellipses — at the band's own opacity, drifting from `CloudBand.drift`. A four-bank storm adds a dark
    /// veil; fog's flattened bands already sit low and faint.
    private static func drawClouds(_ ctx: CGContext, atmosphere: SkyAtmosphere, width: CGFloat, height: CGFloat, color: CGColor) {
        guard !atmosphere.clouds.isEmpty else { return }
        let rgb = color.components ?? [1, 1, 1, 1]
        if atmosphere.clouds.count >= 4 {
            ctx.setFillColor(CGColor(red: 0.04, green: 0.05, blue: 0.08, alpha: 0.22))
            ctx.fill(CGRect(x: 0, y: height * 0.30, width: width, height: height * 0.70))
        }
        for (index, band) in atmosphere.clouds.enumerated() {
            let span = width * CGFloat(0.45 + 0.55 * band.coverage)
            let centerX = width * CGFloat(band.drift) + (index.isMultiple(of: 2) ? 0.18 : 0.62) * width
            let baseY = height * (0.44 + 0.05 * CGFloat(index) + 0.05 * CGFloat(band.thickness))
            let heightScale = height * CGFloat(0.010 + 0.030 * band.thickness)
            let alpha = CGFloat(band.opacity * 0.5)
            let tint = CGColor(red: min(rgb[0] * 1.1 + 0.08, 1), green: min(rgb[1] * 1.1 + 0.08, 1),
                               blue: min(rgb[2] * 1.1 + 0.08, 1), alpha: 1)
            ctx.setFillColor(tint.copy(alpha: alpha) ?? tint)
            switch band.family {
            case .cirrus:
                for lobe in 0..<3 {
                    let w = span * (0.75 - 0.16 * CGFloat(lobe))
                    let x = centerX - w / 2 + CGFloat(lobe) * width * 0.05
                    ctx.fillEllipse(in: CGRect(x: x, y: baseY + CGFloat(lobe) * heightScale * 0.35,
                                               width: w, height: heightScale * 0.55))
                }
            case .wisp:
                for lobe in 0..<3 {
                    let w = span * (0.30 + 0.10 * CGFloat(lobe % 2))
                    let x = centerX - span * 0.25 + CGFloat(lobe) * span * 0.22
                    ctx.fillEllipse(in: CGRect(x: x, y: baseY + CGFloat(lobe % 2) * heightScale * 0.4,
                                               width: w, height: heightScale))
                }
            case .bank:
                for lobe in 0..<5 {
                    let w = span * (0.55 - 0.06 * CGFloat(lobe % 3))
                    let x = centerX - span * 0.36 + CGFloat(lobe) * span * 0.17
                    ctx.fillEllipse(in: CGRect(x: x, y: baseY + CGFloat(lobe % 2) * heightScale * 0.5,
                                               width: w, height: heightScale * 1.5))
                }
            }
        }
    }

    /// Each scene draws the same three bands differently: skyline steps, rolling hills, jagged peaks, a cliff and
    /// the water below it.
    private static func drawLayer(_ ctx: CGContext, scene: WallpaperScene, index: Int, of count: Int,
                                  color: CGColor, width: CGFloat, height: CGFloat) {
        let base = height * (0.10 + 0.08 * CGFloat(count - index - 1))
        ctx.setFillColor(color)
        let path = CGMutablePath()
        switch scene {
        case .city:
            // Pseudo-random skyline: block widths and heights derived, never random per frame.
            let blocks = 14
            var x: CGFloat = 0
            for i in 0..<blocks {
                let seed = (i &* 73 &+ index &* 31) & 97
                let bw = width / CGFloat(blocks) * (0.7 + CGFloat(seed % 6) / 10)
                let bh = height * (0.10 + CGFloat(seed % 9) / 100) + base
                path.addRect(CGRect(x: x, y: 0, width: min(bw, width - x), height: bh))
                x += bw
                if x >= width { break }
            }
        default:
            path.move(to: CGPoint(x: 0, y: 0))
            let steps = 96
            for step in 0...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let ridge = SceneGeometry.ridge(x: Double(t), layer: index, peakX: scene == .coast ? 0.28 : 0.5)
                // Coast: the nearest band is the sea, kept low and flat so the cliff reads above it.
                let amplitude: CGFloat = scene == .alpine ? 0.55 : scene == .countryside ? 0.28 : 0.42
                let sea = scene == .coast && index == count - 1
                let y = sea ? height * (0.06 + 0.02 * CGFloat(index)) : base + height * amplitude * CGFloat(ridge)
                path.addLine(to: CGPoint(x: t * width, y: y))
            }
            path.addLine(to: CGPoint(x: width, y: 0))
            path.closeSubpath()
        }
        ctx.addPath(path)
        ctx.fillPath()
    }
}

/// DW-10 — Small Animation: a borderless, click-through, non-activating window one level above the desktop picture.
/// Clouds drift there, behind every normal window, so the desktop image is never rewritten and there is no swap
/// traffic: measured 0.03 % of one core for three layers, against 52.3 ms of CPU per image swap for the rejected
/// frame-swap design. `hide()` also removes the animations, so a paused overlay composites nothing at all.
@MainActor
final class WallpaperOverlay {
    static let shared = WallpaperOverlay()

    private var windows: [NSWindow] = []
    private var isShowing = false
    private var drawnPlan: SkyAtmosphere?
    private static let sprite: CGImage? = makeSprite()

    func hide() {
        guard isShowing || !windows.isEmpty else { return }
        for window in windows {
            window.contentView?.layer?.removeAllAnimations()
            window.contentView?.layer?.sublayers?.forEach { $0.removeAllAnimations() }
            window.orderOut(nil)
        }
        isShowing = false
    }

    func update(atmosphere: SkyAtmosphere, active: Bool) {
        guard active else { hide(); return }
        if windows.count != NSScreen.screens.count {
            windows.forEach { $0.orderOut(nil) }
            windows = NSScreen.screens.map { makeWindow(for: $0) }
            isShowing = false
        }
        for (index, window) in windows.enumerated() where index < NSScreen.screens.count {
            window.setFrame(NSScreen.screens[index].frame, display: false)
        }
        if drawnPlan != atmosphere { draw(atmosphere) }
        if !isShowing {
            windows.forEach { $0.orderFront(nil) }
            isShowing = true
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        window.contentView = view
        return window
    }

    private func draw(_ atmosphere: SkyAtmosphere) {
        drawnPlan = atmosphere
        for window in windows {
            guard let root = window.contentView?.layer else { continue }
            root.sublayers?.forEach { $0.removeFromSuperlayer() }
            let size = root.bounds.size
            for (index, band) in atmosphere.clouds.enumerated() {
                let layer = CALayer()
                let width = size.width * CGFloat(0.30 + 0.35 * band.coverage)
                let height = width * 0.30
                layer.frame = CGRect(x: -width, y: size.height * (0.58 + 0.06 * CGFloat(index)),
                                     width: width, height: height)
                layer.contents = Self.sprite
                layer.opacity = Float(min(band.opacity * 0.42, 1))
                root.addSublayer(layer)

                let drift = CABasicAnimation(keyPath: "position.x")
                drift.fromValue = -width * 0.5
                drift.toValue = size.width + width * 0.5
                drift.duration = 120 / max(band.speed, 0.2)
                drift.repeatCount = .infinity
                layer.add(drift, forKey: "drift")

                let shimmer = CABasicAnimation(keyPath: "opacity")
                shimmer.fromValue = layer.opacity
                shimmer.toValue = layer.opacity * 0.78
                shimmer.duration = 9 + Double(index) * 2
                shimmer.autoreverses = true
                shimmer.repeatCount = .infinity
                layer.add(shimmer, forKey: "shimmer")
            }
        }
    }

    /// A soft white blob, drawn once; the layers only move it, so the GPU does the work.
    private static func makeSprite() -> CGImage? {
        let size = 256
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: size, height: size / 2, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.85),
                                                 CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                                        locations: [0, 1]) else { return nil }
        let center = CGPoint(x: size / 2, y: size / 4)
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size / 2), options: [])
        return ctx.makeImage()
    }
}

/// §5.7 — one CoreImage downsample per artwork hash, then the pure `MusicArtworkPalette` maths. Cached so a
/// card, the lock screen and the wallpaper all read the same accent without recomputing anything.
final class MusicArtworkPaletteCache {
    static let shared = MusicArtworkPaletteCache()

    private let lock = NSLock()
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cache: [Int: MusicArtworkPalette] = [:]

    func palette(for data: Data?) -> MusicArtworkPalette {
        guard let data, !data.isEmpty else { return .fallback }
        let key = MusicArtworkSignature.of(data)
        if let cached = lock.withLock({ cache[key] }) { return cached }
        let palette = Self.extract(data) ?? .fallback
        lock.withLock {
            if cache.count >= 24 { cache.removeAll(keepingCapacity: true) }
            cache[key] = palette
        }
        return palette
    }

    private static func extract(_ data: Data) -> MusicArtworkPalette? {
        guard let source = CIImage(data: data), source.extent.width > 1, source.extent.height > 1 else { return nil }
        let side: CGFloat = 24
        let scale = side / max(source.extent.width, source.extent.height)
        let small = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        var pixels = [UInt8](repeating: 0, count: Int(side * side) * 4)
        ciContext.render(small, toBitmap: &pixels, rowBytes: Int(side) * 4, bounds: bounds,
                         format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        return MusicArtworkPalette(pixels: pixels)
    }
}

/// ML-5 — menu-bar synced lyrics. The status item lives in a file the test target also compiles, so it only
/// listens to this notification; the app-side bridge owns the Now Playing and lyrics reads.
@MainActor
final class MusicMenuBarLyricsBridge {
    static let shared = MusicMenuBarLyricsBridge()
    static let didChange = Notification.Name("com.katikati.music.menuBarLyric")
    static let enabledKey = "com.katikati.music.menuBarLyrics"

    private var cancellable: AnyCancellable?
    private var lastLine: String?

    func start(service: NowPlayingService) {
        guard cancellable == nil else { return }
        cancellable = service.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.update(state) }
        NotificationCenter.default.addObserver(
            forName: MusicSurfaceConfig.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.update(service.state) }
        }
    }

    private func update(_ state: NowPlayingState) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            publish(nil)
            return
        }
        guard let title = state.title, !title.isEmpty else {
            publish(nil)
            return
        }
        LyricsStore.shared.loadIfNeeded(title: title, artist: state.artist)
        let lines = LyricsStore.shared.lines(title: title, artist: state.artist)
        let elapsed = (state.elapsed ?? 0)
            + (state.isPlaying ? Date().timeIntervalSince(state.elapsedAsOf ?? Date()) : 0)
        publish(lines.last { $0.time <= elapsed + 0.1 }?.text)
    }

    private func publish(_ line: String?) {
        guard line != lastLine else { return }
        lastLine = line
        NotificationCenter.default.post(name: Self.didChange, object: line)
    }
}
