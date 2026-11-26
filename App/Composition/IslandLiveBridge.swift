import AppKit
import Combine
import Foundation
import SwiftUI

/// Reactive bridge synchronizing KatiKati live subsystems into the `IslandStore` priority/split
/// queue (`Now Playing`, `Timer`/`Focus`, `Downloads`, `Shelf`, `Battery`, `Camera/Recording`,
/// `AI Agent`, and transient `LiveEvent` alerts).
@MainActor
final class IslandLiveBridge: ObservableObject, LiveEventSink {
    let driver: IslandSurfaceDriver
    let registry: IslandPresetRegistry

    private let liveActivityFeed: LiveActivityFeed
    private let downloadService: DownloadManagerService
    private let agentService: AgentUsageService
    private let cameraService: CameraMirrorService
    private let weatherService: WeatherService
    private let alarmStore: AlarmStore
    private let systemStatus = SystemStatusService()

    private weak var shelfStore: ShelfStore?
    private var cancellables = Set<AnyCancellable>()
    private var shelfCancellables = Set<AnyCancellable>()
    private var transientWorkItems: [String: DispatchWorkItem] = [:]
    private var activeHardwareHUDKey: String?
    private var isStarted = false

    var onOpenAudioDeck: (() -> Void)?

    private enum ActivityID {
        static let music = "katikati.music"
        static let timer = "katikati.timer"
        static let download = "katikati.download"
        static let camera = "katikati.camera"
        static let shelf = "katikati.shelf"
        static let agent = "katikati.agent"
        static let battery = "katikati.battery"
        static let bluetooth = "katikati.bluetooth"
        static let hud = "katikati.hud"
        static let hardwareHUD = "katikati.hardwareHUD"
        static let playgroundA = "katikati.playground.a"
        static let playgroundB = "katikati.playground.b"
    }

    init(
        driver: IslandSurfaceDriver? = nil,
        registry: IslandPresetRegistry? = nil,
        liveActivityFeed: LiveActivityFeed = .shared,
        downloadService: DownloadManagerService = .shared,
        agentService: AgentUsageService = .shared,
        cameraService: CameraMirrorService = .shared,
        weatherService: WeatherService? = nil,
        alarmStore: AlarmStore? = nil
    ) {
        self.driver = driver ?? IslandSurfaceDriver()
        self.registry = registry ?? IslandPresetRegistry()
        self.liveActivityFeed = liveActivityFeed
        self.downloadService = downloadService
        self.agentService = agentService
        self.cameraService = cameraService
        self.weatherService = weatherService ?? .shared
        self.alarmStore = alarmStore ?? ProductivityServices.shared.alarms
    }

    func bindShelfStore(_ store: ShelfStore) {
        shelfStore = store
        shelfCancellables.removeAll()
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncShelf()
            }
            .store(in: &shelfCancellables)
        store.$shakePulse
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncShelf(alertOnDrop: true)
            }
            .store(in: &shelfCancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        systemStatus.acquire()

        liveActivityFeed.$activity
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncMediaAndProductivity() }
            .store(in: &cancellables)

        liveActivityFeed.$secondaryActivity
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncMediaAndProductivity() }
            .store(in: &cancellables)

        downloadService.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncDownloads() }
            .store(in: &cancellables)

        agentService.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncAgent() }
            .store(in: &cancellables)

        cameraService.$isMirrored
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncCamera() }
            .store(in: &cancellables)

        weatherService.$currentState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.syncWeather(state) }
            .store(in: &cancellables)

        alarmStore.$alarms
            .receive(on: RunLoop.main)
            .sink { [weak self] alarms in self?.syncAlarm(alarms) }
            .store(in: &cancellables)

        systemStatus.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.syncBattery(status.battery) }
            .store(in: &cancellables)

        syncMediaAndProductivity()
        syncDownloads()
        syncAgent()
        syncCamera()
        syncWeather(weatherService.currentState)
        syncAlarm(alarmStore.alarms)
        syncShelf()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        cancellables.removeAll()
        shelfCancellables.removeAll()
        transientWorkItems.values.forEach { $0.cancel() }
        transientWorkItems.removeAll()
        systemStatus.release()
    }

    // MARK: - LiveEventSink (transient alert expansion)

    func show(_ event: LiveEvent) { show(event, onOpen: nil) }

    func show(_ event: LiveEvent, onOpen: (() -> Void)?) {
        guard let spec = IslandHUDRouteSpec.event(event) else {
            syncMediaAndProductivity()
            return
        }
        let presentation = LiveEventPresentation(event)
        let id = spec.activityID
        let views: IslandActivityViews

        switch event {
        case .trackChanged:
            return

        case let .clipboardCopied(preview, linkCleaned):
            views = IslandPresets.clipboardHUD(
                title: presentation.headline,
                preview: preview,
                isPaste: false,
                linkCleaned: linkCleaned,
                appIcon: NSWorkspace.shared.frontmostApplication?.icon,
                onPastePlain: {
                    if let latest = ProductivityServices.shared.clipboard.history.displayOrder.first {
                        ProductivityServices.shared.clipboard.pastePlain(latest)
                    }
                },
                onOpenHistory: onOpen
            )

        case let .clipboardPasted(preview):
            views = IslandPresets.clipboardHUD(
                title: presentation.headline,
                preview: preview,
                isPaste: true,
                linkCleaned: false,
                appIcon: NSWorkspace.shared.frontmostApplication?.icon,
                onPastePlain: nil,
                onOpenHistory: onOpen
            )

        case let .focusPhaseChanged(phase):
            let symbol = phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill"
            views = IslandPresets.focusHUD(
                title: presentation.headline,
                subtitle: String(localized: "Focus Timer"),
                systemImage: symbol,
                accent: phase == .focus ? IslandTheme.Accent.purple : IslandTheme.Accent.lagoon,
                onOpen: onOpen
            )

        case let .focusCycleCompleted(count):
            views = IslandPresets.focusHUD(
                title: presentation.headline,
                subtitle: "\(count) completed",
                systemImage: "checkmark.circle.fill",
                accent: IslandTheme.Accent.green,
                onOpen: onOpen
            )

        case let .notice(kind, detail):
            switch kind {
            case .capsLockOn, .capsLockOff:
                views = IslandPresets.systemHUD(
                    title: presentation.headline,
                    subtitle: nil,
                    systemImage: presentation.symbol,
                    progress: nil,
                    accent: kind == .capsLockOn ? IslandTheme.Accent.yellow : IslandTheme.Ink.secondary,
                    onOpen: nil
                )
            case .batteryHigh, .batteryFull:
                views = IslandPresets.battery(
                    level: kind == .batteryFull ? 1.0 : 0.8,
                    charging: true,
                    deviceName: "MacBook",
                    detail: detail ?? presentation.headline
                )
            case .hydrate, .pause:
                views = IslandPresets.systemHUD(
                    title: presentation.headline,
                    subtitle: detail,
                    systemImage: presentation.symbol,
                    progress: nil,
                    accent: IslandTheme.Accent.lagoon,
                    onOpen: onOpen
                )
            }

        case .downloadFinished:
            views = IslandPresets.systemHUD(
                title: presentation.headline,
                subtitle: presentation.detail,
                systemImage: presentation.symbol,
                progress: 1.0,
                accent: IslandTheme.Accent.green,
                onOpen: onOpen
            )

        case .timerFinished, .alarmDue:
            views = IslandPresets.systemHUD(
                title: presentation.headline,
                subtitle: presentation.detail,
                systemImage: presentation.symbol,
                progress: nil,
                accent: IslandTheme.Accent.orange,
                onOpen: onOpen
            )

        case .severeWeather:
            views = IslandPresets.systemHUD(
                title: presentation.headline,
                subtitle: presentation.detail,
                systemImage: presentation.symbol,
                progress: nil,
                accent: IslandTheme.Accent.red,
                onOpen: onOpen
            )

        case .stopwatchStopped, .countdownReachedToday:
            views = IslandPresets.systemHUD(
                title: presentation.headline,
                subtitle: presentation.detail,
                systemImage: presentation.symbol,
                progress: nil,
                accent: IslandTheme.Accent.sky,
                onOpen: onOpen
            )
        }

        registry.register(id: id, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: id,
                label: presentation.headline,
                priority: spec.priority,
                alert: spec.alert
            )
        )
        scheduleEnd(id: id, afterSeconds: spec.lifetime)
    }

    func showHardwareHUD(
        id: String,
        icon: String,
        title: String,
        level: Double,
        onScrub: ((Double) -> Void)? = nil
    ) {
        activeHardwareHUDKey = id
        let spec = IslandHUDRouteSpec.hardwareHUD()
        let showsPercentage = UserDefaults.standard.object(forKey: NotchHUDPresentation.showPercentageKey) as? Bool ?? true
        let accent: Color = {
            if id == "hud.brightness" { return IslandTheme.Accent.yellow }
            if id == "hud.keyboard" { return IslandTheme.Accent.orange }
            return level <= 0 ? IslandTheme.Ink.secondary : IslandTheme.Accent.sky
        }()
        registry.register(
            id: spec.activityID,
            views: IslandPresets.hardwareLevelHUD(
                title: title,
                subtitle: nil,
                systemImage: icon,
                level: level,
                accent: accent,
                showsPercentage: showsPercentage,
                onScrub: onScrub
            )
        )
        driver.store.start(IslandActivitySpec(id: spec.activityID, label: title, priority: spec.priority, alert: spec.alert))
        scheduleEnd(id: spec.activityID, afterSeconds: spec.lifetime)
    }

    func showBluetoothAccessoryHUD(device: BluetoothDevice, isLowBattery: Bool) {
        let spec = IslandHUDRouteSpec.bluetoothAccessory(isLowBattery: isLowBattery)
        let level = Double(device.lowestBattery ?? 0) / 100.0
        let detail = isLowBattery
            ? String(localized: "Low Battery")
            : (device.batteryBreakdown ?? String(localized: "Connected"))
        let views = IslandPresets.battery(
            level: level,
            charging: false,
            deviceName: device.name,
            detail: detail
        )
        registry.register(id: spec.activityID, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: spec.activityID,
                label: device.name,
                priority: spec.priority,
                alert: spec.alert
            )
        )
        scheduleEnd(id: spec.activityID, afterSeconds: spec.lifetime)
    }

    private static let pagesPlaceholderID = "katikati.pages"

    func openPages() {
        if driver.snapshot.expanded == nil {
            if driver.snapshot.activities.isEmpty {
                let id = Self.pagesPlaceholderID
                let title = String(localized: "Notch Pages")
                registry.register(id: id, views: IslandPresets.systemHUD(title: title, subtitle: nil, systemImage: "square.grid.2x2"))
                driver.store.start(IslandActivitySpec(id: id, label: title, priority: 0))
                driver.store.expand(id)
            } else {
                driver.store.expand()
            }
        }
        driver.isShowingBentoSuite = true
    }

    func removePagesPlaceholder() {
        let id = Self.pagesPlaceholderID
        guard driver.snapshot.expanded == nil, driver.snapshot.activities.contains(where: { $0.id == id }) else { return }
        driver.store.end(id)
        registry.unregister(id: id)
    }

    // MARK: - Reactive Sync Handlers

    private func syncMediaAndProductivity() {
        let primary = liveActivityFeed.activity
        let secondary = liveActivityFeed.secondaryActivity
        let nowState = liveActivityFeed.nowPlayingState

        let isMusicActive = primary.kind == .music || secondary?.kind == .music || nowState.isPlaying
        if isMusicActive {
            let now = Date()
            let art = nowState.artworkData.flatMap { NSImage(data: $0) }
            let accentRGBA = ArtworkAccentCache.accent(for: nowState.artworkData)
            let accent = accentRGBA.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? IslandTheme.Accent.pink
            driver.artworkAuraLab = accentRGBA.map { LiquidOKLab.fromSRGB(SIMD3($0.red, $0.green, $0.blue)) }

            let elapsed = NowPlayingProgress.elapsed(
                at: now,
                elapsed: nowState.elapsed,
                asOf: nowState.elapsedAsOf,
                rate: nowState.rate,
                duration: nowState.duration
            )
            let lyricLine: String? = {
                guard UserDefaults.standard.bool(forKey: LyricsTrack.enabledKey), let elapsed else { return nil }
                LyricsStore.shared.loadIfNeeded(title: nowState.title, artist: nowState.artist)
                let lines = LyricsStore.shared.lines(title: nowState.title, artist: nowState.artist)
                return LyricsTrack.activeLine(in: lines, at: elapsed)
            }()

            let views = IslandPresets.nowPlaying(
                title: nowState.title ?? "Now Playing",
                artist: nowState.artist ?? nowState.appName ?? "",
                artwork: art,
                progress: nowState.progress(at: now),
                elapsed: elapsed,
                duration: nowState.duration,
                lyricsLine: lyricLine,
                isPlaying: nowState.isPlaying,
                accent: accent,
                onTogglePlayPause: { [weak self] in self?.liveActivityFeed.togglePlayPause() },
                onPrevious: { [weak self] in self?.liveActivityFeed.previousTrack() },
                onNext: { [weak self] in self?.liveActivityFeed.nextTrack() },
                onSeek: { [weak self] seconds in self?.liveActivityFeed.seek(to: seconds) },
                onOpenAudioDeck: onOpenAudioDeck
            )
            registry.register(id: ActivityID.music, views: views)
            driver.store.start(
                IslandActivitySpec(
                    id: ActivityID.music,
                    label: nowState.title ?? "Now Playing",
                    priority: 5
                )
            )
        } else {
            driver.artworkAuraLab = nil
            driver.store.end(ActivityID.music)
            registry.unregister(id: ActivityID.music)
        }

        if let timerPayload = timerPayload(from: primary, secondary: secondary) {
            let views = IslandPresets.timer(
                label: timerPayload.label,
                source: timerPayload.source,
                progressRemaining: timerPayload.progressRemaining,
                isPaused: timerPayload.isPaused,
                onToggle: {
                    ProductivityServices.shared.timer.toggle()
                },
                onCancel: {
                    ProductivityServices.shared.timer.reset()
                }
            )
            registry.register(id: ActivityID.timer, views: views)
            driver.store.start(
                IslandActivitySpec(
                    id: ActivityID.timer,
                    label: timerPayload.label,
                    priority: 6
                )
            )
        } else {
            driver.store.end(ActivityID.timer)
            registry.unregister(id: ActivityID.timer)
        }
    }

    private func timerPayload(
        from primary: LiveActivity,
        secondary: LiveActivity?
    ) -> (label: String, source: IslandTimeSource, progressRemaining: Double, isPaused: Bool)? {
        let candidates = [primary.content, secondary?.content].compactMap { $0 }
        for content in candidates {
            switch content {
            case let .timer(t):
                return (
                    "Timer",
                    .remaining(until: Date().addingTimeInterval(TimeInterval(t.remaining))),
                    max(0, min(1, 1.0 - t.progress)),
                    false
                )
            case let .focus(f):
                return (
                    f.phase == .focus ? "Focus" : "Break",
                    .remaining(until: Date().addingTimeInterval(TimeInterval(f.remaining))),
                    max(0, min(1, 1.0 - f.progress)),
                    false
                )
            case let .stopwatch(s):
                return (
                    "Stopwatch",
                    .fixed(ms: s.elapsed * 1000.0),
                    0.5,
                    false
                )
            default:
                continue
            }
        }
        return nil
    }

    private func syncDownloads() {
        let active = downloadService.items.filter { $0.state == .active }
        guard let item = active.first else {
            driver.store.end(ActivityID.download)
            registry.unregister(id: ActivityID.download)
            return
        }
        let progress = item.totalBytes > 0
            ? Double(item.bytesDownloaded) / Double(item.totalBytes)
            : 0.0
        let speedMB = Double(item.downloadSpeedBps) / 1_000_000.0
        let detail = speedMB > 0.01 ? String(format: "%.1f MB/s", speedMB) : "\(active.count) active"
        let views = IslandPresets.download(
            fileName: item.name,
            progress: progress,
            detail: detail,
            isDone: progress >= 1.0
        )
        registry.register(id: ActivityID.download, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: ActivityID.download,
                label: item.name,
                priority: 7
            )
        )
    }

    private func syncAgent() {
        guard let activeTurn = agentService.snapshot.activeTurn, activeTurn.isActive else {
            driver.store.end(ActivityID.agent)
            registry.unregister(id: ActivityID.agent)
            return
        }
        let total = activeTurn.tokens.total
        let tokenStr = total >= 1000 ? String(format: "%.1fk", Double(total) / 1000.0) : "\(total)"
        let views = IslandPresets.aiAgent(
            providerName: activeTurn.provider.displayName,
            model: activeTurn.model,
            toolName: activeTurn.activeTool?.toolName,
            tokenSummary: tokenStr,
            sparklineValues: agentService.snapshot.weeklyHeatmap
        )
        registry.register(id: ActivityID.agent, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: ActivityID.agent,
                label: activeTurn.provider.displayName,
                priority: 8
            )
        )
    }

    private func syncCamera() {
        guard cameraService.isMirrored else {
            driver.store.end(ActivityID.camera)
            registry.unregister(id: ActivityID.camera)
            return
        }
        registry.register(
            id: ActivityID.camera,
            views: IslandPresets.recording(title: "Camera Mirror", since: Date())
        )
        driver.store.start(IslandActivitySpec(id: ActivityID.camera, label: "Camera Mirror", priority: 6))
    }

    private func syncWeather(_ state: WeatherState) {
        guard let detail = state.detail,
              let warning = WeatherWarningEngine.warnings(for: detail, thresholds: WeatherPrefs.thresholds())
                .first(where: { $0.severity == .severe }) else { return }
        LiveEventCenter.shared.deliver(.severeWeather(kind: warning.kind.rawValue), now: Date())
    }

    private func syncAlarm(_ alarms: [AlarmItem]) {
        let now = Date()
        guard let (alarm, fire) = AlarmList.next(in: alarms, after: now),
              fire.timeIntervalSince(now) <= 60 else { return }
        LiveEventCenter.shared.deliver(.alarmDue(label: alarm.label), now: now)
    }

    private func syncShelf(alertOnDrop: Bool = false) {
        guard let store = shelfStore, !store.items.isEmpty else {
            driver.store.end(ActivityID.shelf)
            registry.unregister(id: ActivityID.shelf)
            return
        }
        guard alertOnDrop || store.items.count > 0 else { return }
        if !alertOnDrop && !driver.snapshot.activities.contains(where: { $0.id == ActivityID.shelf }) {
            return
        }
        let latestName = URL(fileURLWithPath: store.items[0].path).lastPathComponent
        let views = IslandPresets.shelfTransfer(
            itemCount: store.items.count,
            latestName: latestName,
            onOpenShelf: { [weak self] in
                self?.driver.isShowingBentoSuite = true
                self?.driver.store.expand(ActivityID.shelf)
            }
        )
        registry.register(id: ActivityID.shelf, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: ActivityID.shelf,
                label: latestName,
                priority: 4,
                alert: alertOnDrop
            )
        )
        if alertOnDrop {
            scheduleEnd(id: ActivityID.shelf, afterSeconds: 4.0)
        }
    }

    private func syncBattery(_ battery: BatteryStatus) {
        guard let level = battery.level, battery.isCharging else { return }
        let isPlugTransition = !driver.snapshot.activities.contains(where: { $0.id == ActivityID.battery })
        guard isPlugTransition || battery.isCharging else { return }

        let timeDetail: String
        if let remaining = battery.facts.secondsRemaining {
            let mins = max(1, remaining / 60)
            timeDetail = "Full in \(mins)m"
        } else {
            timeDetail = "\(level)%"
        }
        let views = IslandPresets.battery(
            level: Double(level) / 100.0,
            charging: battery.isCharging,
            deviceName: "MacBook",
            detail: timeDetail
        )
        registry.register(id: ActivityID.battery, views: views)
        driver.store.start(
            IslandActivitySpec(
                id: ActivityID.battery,
                label: "Charging \(level)%",
                priority: 8
            )
        )
        if isPlugTransition {
            scheduleEnd(id: ActivityID.battery, afterSeconds: 3.3)
        }
    }

    private func scheduleEnd(id: String, afterSeconds: Double) {
        transientWorkItems[id]?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.driver.store.end(id)
                self.registry.unregister(id: id)
                self.transientWorkItems.removeValue(forKey: id)
            }
        }
        transientWorkItems[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + afterSeconds, execute: item)
    }

    // MARK: - Settings Interactive Playground Support

    enum PlaygroundScenario: String, CaseIterable {
        case singleTimer
        case splitMusicAndTimer
        case downloadAlert
        case aiAgentAndCall
        case etaDelivery
    }

    func runPlayground(_ scenario: PlaygroundScenario) {
        clearPlayground()
        switch scenario {
        case .singleTimer:
            let views = IslandPresets.timer(
                label: "Focus Sprint",
                source: .remaining(until: Date().addingTimeInterval(258)),
                progressRemaining: 0.72,
                isPaused: false
            )
            registry.register(id: ActivityID.playgroundA, views: views)
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundA, label: "Focus Sprint", priority: 10))

        case .splitMusicAndTimer:
            let music = IslandPresets.nowPlaying(
                title: "Midnight City",
                artist: "M83",
                artwork: nil,
                progress: 0.62,
                isPlaying: true,
                onTogglePlayPause: {},
                onPrevious: {},
                onNext: {}
            )
            let timer = IslandPresets.timer(
                label: "Timer",
                source: .remaining(until: Date().addingTimeInterval(185)),
                progressRemaining: 0.65,
                isPaused: false
            )
            registry.register(id: ActivityID.playgroundA, views: music)
            registry.register(id: ActivityID.playgroundB, views: timer)
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundA, label: "Now Playing", priority: 10))
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundB, label: "Timer", priority: 9))

        case .downloadAlert:
            let dl = IslandPresets.download(
                fileName: "macOS-SDK-27.xip",
                progress: 0.68,
                detail: "28.4 MB/s · 12s left",
                isDone: false
            )
            registry.register(id: ActivityID.playgroundA, views: dl)
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundA, label: "macOS-SDK-27.xip", priority: 10, alert: true))

        case .aiAgentAndCall:
            let agent = IslandPresets.aiAgent(
                providerName: "Claude",
                model: "Sonnet 4.6",
                toolName: "IslandChoreography.swift",
                tokenSummary: "4.8k",
                sparklineValues: [0.2, 0.35, 0.55, 0.42, 0.85, 0.92]
            )
            let call = IslandPresets.call(
                caller: "Design Sync",
                subtitle: "FaceTime Audio",
                since: Date().addingTimeInterval(-142),
                isMuted: false
            )
            registry.register(id: ActivityID.playgroundA, views: call)
            registry.register(id: ActivityID.playgroundB, views: agent)
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundA, label: "Design Sync", priority: 10))
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundB, label: "Claude", priority: 9))

        case .etaDelivery:
            let eta = IslandPresets.etaTemplate(
                title: "Courier En Route",
                subtitle: "2 stops away",
                etaMinutes: "4m",
                stepsDone: 2,
                totalSteps: 4
            )
            registry.register(id: ActivityID.playgroundA, views: eta)
            driver.store.start(IslandActivitySpec(id: ActivityID.playgroundA, label: "Courier En Route", priority: 10, alert: true))
        }
    }

    func clearPlayground() {
        driver.store.end(ActivityID.playgroundA)
        driver.store.end(ActivityID.playgroundB)
        registry.unregister(id: ActivityID.playgroundA)
        registry.unregister(id: ActivityID.playgroundB)
    }
}
