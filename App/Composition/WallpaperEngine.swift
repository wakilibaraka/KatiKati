import AppKit
import Combine
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Phase 10b-2 — sets the real desktop wallpaper from the sun phase and the weather. Off by default; nothing
/// runs (no timer, no observers) until `com.katikati.wallpaper.enabled` is on. The user's original wallpaper
/// (per screen) is captured before the first change, persisted, and restored on disable / quit.
@MainActor
final class WallpaperEngine {
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
    private var observers: [NSObjectProtocol] = []
    private var boundaryTimer: Timer?
    private var lastApplied: [String: String] = [:]
    private(set) var isRunning = false

    private init() {}

    func configure(settings: AppSettingsStore, weather: WeatherService) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.weather = weather
        Publishers.CombineLatest3(settings.$wallpaperEnabled, settings.$wallpaperMode, settings.$wallpaperFolder)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, _, _ in
                guard let self else { return }
                if enabled { self.start() } else { self.stop() }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    private func start() {
        if !isRunning {
            isRunning = true
            captureOriginalIfNeeded()
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh(force: true) }
            })
            observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh(force: true) }
            })
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

    private var stateCancellables = Set<AnyCancellable>()

    /// Disable: put the original wallpaper back and stop everything.
    private func stop() {
        guard isRunning else { return }
        isRunning = false
        teardown()
        restoreOriginal()
    }

    /// App quit: restore, but leave the setting on so the next launch resumes.
    func restoreForQuit() {
        guard isRunning else { return }
        teardown()
        restoreOriginal()
    }

    /// Menu/Settings "Restore Wallpaper" without turning the feature off.
    func restoreNow() {
        restoreOriginal()
        lastApplied = [:]
    }

    private func teardown() {
        boundaryTimer?.invalidate(); boundaryTimer = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
        observers = []
        stateCancellables = []
    }

    // MARK: - Apply

    private func refresh(force: Bool) {
        guard isRunning, let settings else { return }
        let now = Date()
        let state = weather?.currentState ?? .empty
        let times = state.sunTimes(on: now) ?? SunTimes(sunrise: nil, sunset: nil, polar: state.isNight ? .night : .day)
        let forced = WallpaperDebugOverride.parse(DebugSwitch.wallpaperPhase.value())
        let phase = forced?.phase ?? SolarPhaseResolver.phase(at: now, times: times)
        let sky = forced?.sky ?? WallpaperSky(state.conditionFamily)
        let mode = WallpaperMode(rawValue: settings.wallpaperMode) ?? .both
        armTimer(after: now, times: times)

        let pack = Self.pack(folder: settings.wallpaperFolder)
        guard let key = WallpaperSelector.pick(phase: phase, sky: sky, mode: mode, available: Set(pack.keys)),
              let url = pack[key]?() else { return }
        for screen in NSScreen.screens {
            let id = Self.screenKey(screen)
            if !force, lastApplied[id] == key { continue }
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                lastApplied[id] = key
            } catch {
                NSLog("WallpaperEngine: setDesktopImageURL failed: \(error)")
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

    private static func screenKey(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    // MARK: - Packs

    /// key → lazily produced file URL. Custom folder when set and readable, otherwise the rendered Sky pack.
    private static func pack(folder: String) -> [String: () -> URL?] {
        if !folder.isEmpty, let files = try? FileManager.default.contentsOfDirectory(atPath: folder) {
            var result: [String: () -> URL?] = [:]
            for file in files where ["jpg", "jpeg", "png", "heic"].contains((file as NSString).pathExtension.lowercased()) {
                let key = ((file as NSString).deletingPathExtension).lowercased()
                result[key] = { URL(fileURLWithPath: folder).appendingPathComponent(file) }
            }
            if !result.isEmpty { return result }
        }
        var sky: [String: () -> URL?] = Dictionary(uniqueKeysWithValues: WallpaperSelector.allSkyKeys.map { key in (key, { SkyPackRenderer.fileURL(for: key) }) })
        for (alias, base) in WallpaperSelector.skyPackAliases { sky[alias] = { SkyPackRenderer.fileURL(for: base) } }
        return sky
    }
}

/// Renders the procedural Sky pack once per key into Application Support (PNG, vertical gradient + soft glow).
enum SkyPackRenderer {
    static func directory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("KatiKati/Wallpapers/sky", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func fileURL(for key: String) -> URL? {
        guard let dir = directory() else { return nil }
        let url = dir.appendingPathComponent("\(key).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let parts = key.split(separator: "-").map(String.init)
        guard parts.count == 2, let phase = SolarPhase(rawValue: parts[0]), let sky = WallpaperSky(rawValue: parts[1]),
              let image = render(phase: phase, sky: sky),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest) ? url : nil
    }

    static func render(phase: SolarPhase, sky: WallpaperSky, width: Int = 2560, height: Int = 1440) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let stops = SkyPalette.stops(phase: phase, sky: sky)
        func color(_ c: SkyRGB) -> CGColor { CGColor(red: c.r, green: c.g, blue: c.b, alpha: 1) }
        guard let gradient = CGGradient(colorsSpace: space, colors: [color(stops.top), color(stops.bottom)] as CFArray, locations: [0, 1]) else { return nil }
        // CoreGraphics origin is bottom-left: start at the top edge, end at the bottom.
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: .zero, options: [])
        if sky == .clear || sky == .cloudy {
            // Soft sun/moon glow near the horizon-side upper third.
            let glowColor = phase == .night ? CGColor(red: 0.85, green: 0.88, blue: 1, alpha: 0.28) : CGColor(red: 1, green: 0.95, blue: 0.8, alpha: sky == .clear ? 0.4 : 0.2)
            if let glow = CGGradient(colorsSpace: space, colors: [glowColor, glowColor.copy(alpha: 0)!] as CFArray, locations: [0, 1]) {
                let center = CGPoint(x: Double(width) * 0.72, y: Double(height) * (phase == .golden || phase == .dusk || phase == .dawn ? 0.35 : 0.7))
                ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: Double(height) * 0.45, options: [])
            }
        }
        return ctx.makeImage()
    }
}
