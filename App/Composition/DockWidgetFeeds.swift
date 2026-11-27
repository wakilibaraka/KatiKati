import Combine
import CoreAudio
import Foundation

// Shared, ref-counted data behind the dock's Calendar / System / Devices widgets. Each feed runs its timer only
// while a widget is on screen (the Dock strip, a rail tile or a hover preview), like `SystemMonitorController`.

/// Next meetings. Reuses `CalendarService` for access handling (never re-prompts a decided status).
@MainActor
final class DockCalendarFeed: ObservableObject {
    static let shared = DockCalendarFeed()

    @Published private(set) var upcoming: [DockEvent] = []
    @Published private(set) var access: CalendarAccess = .unknown
    private let service = CalendarService()
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var holders = 0

    private init() {
        service.$upcoming.sink { [weak self] in self?.upcoming = $0 }.store(in: &cancellables)
        service.$eventsAccess.sink { [weak self] in self?.access = $0 }.store(in: &cancellables)
    }

    func retain() {
        holders += 1
        guard timer == nil else { return }
        service.startEvents()
        // Event ends and the 36 h window both move with time, so re-query now and then.
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.service.refreshUpcoming() }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// CPU / memory / disk throughput with a 30-second history each.
@MainActor
final class DockSystemFeed: ObservableObject {
    static let shared = DockSystemFeed()

    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpu = SampleHistory()
    @Published private(set) var memory = SampleHistory()
    @Published private(set) var diskRead = SampleHistory()
    @Published private(set) var diskWrite = SampleHistory()
    private let monitor = SystemMonitorController.shared
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = monitor.$snapshot.dropFirst().sink { [weak self] snap in
            guard let self else { return }
            snapshot = snap
            cpu.append(snap.cpu)
            memory.append(snap.memory.fraction)
            diskRead.append(snap.diskRead)
            diskWrite.append(snap.diskWrite)
        }
    }

    func retain() {
        monitor.acquire()
        snapshot = monitor.snapshot
    }
    func release() { monitor.release() }
}

/// Shared connected Bluetooth peripheral feed (polled every 60 s + CoreAudio device-list listener
/// while retained, so AirPods/audio accessories notify near-instantly with zero extra processes).
@MainActor
final class DockDevicesFeed: ObservableObject {
    static let shared = DockDevicesFeed()

    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var allDevices: [BluetoothDevice] = []
    @Published private(set) var isRefreshing = false
    let events = PassthroughSubject<PeripheralEvent, Never>()

    private var timer: Timer?
    private var holders = 0
    private var refreshTask: Task<Void, Never>?
    private var debounceWork: DispatchWorkItem?
    private var followUpWork: DispatchWorkItem?
    private var audioListenerBlock: AudioObjectPropertyListenerBlock?
    private var hasSeeded = false
    private var previousConnected: [BluetoothDevice] = []
    private var lowDeviceIDs: Set<String> = []
    private var lastReadAt: Date = .distantPast

    func retain() {
        holders += 1
        guard timer == nil else { return }
        installAudioListener()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
        debounceWork?.cancel()
        debounceWork = nil
        followUpWork?.cancel()
        followUpWork = nil
        removeAudioListener()
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Reads immediately unless a shared read completed within `maxAge` seconds.
    func refreshIfStale(maxAge: TimeInterval = 5) async {
        if hasSeeded && Date().timeIntervalSince(lastReadAt) <= maxAge {
            return
        }
        await performRead()
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        refreshTask = Task { [weak self] in
            await self?.performRead()
        }
    }

    private func performRead() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer {
            isRefreshing = false
            refreshTask = nil
        }
        let all = await BluetoothDeviceReader.read()
        guard !Task.isCancelled else { return }
        lastReadAt = Date()
        allDevices = all
        let connected = all.filter(\.isConnected)
        devices = connected

        if !hasSeeded {
            hasSeeded = true
            previousConnected = connected
            lowDeviceIDs = Set(PowerNotificationPolicy.lowDevices(connected).map { PeripheralDiff.canonicalID(of: $0) })
            return
        }

        let diffResult = PeripheralDiff.diff(old: previousConnected, new: connected, alreadyLow: lowDeviceIDs)
        previousConnected = connected
        lowDeviceIDs = diffResult.low
        for event in diffResult.events {
            events.send(event)
        }
        if PeripheralDiff.needsBatteryFollowUp(in: diffResult.events) {
            scheduleBatteryFollowUp()
        }
    }

    private func refresh() {
        refreshNow()
    }

    private func scheduleDebouncedAudioRefresh() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.debounceWork = nil
                self?.refreshNow()
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func scheduleBatteryFollowUp() {
        followUpWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.followUpWork = nil
                self?.refreshNow()
            }
        }
        followUpWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: work)
    }

    private func installAudioListener() {
        guard audioListenerBlock == nil else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.scheduleDebouncedAudioRefresh() }
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        if status == noErr {
            audioListenerBlock = block
        }
    }

    private func removeAudioListener() {
        guard let block = audioListenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        audioListenerBlock = nil
    }
}

/// Mounted drives with their free space. Reading the mount table is a handful of syscalls, so the
/// 10 s poll only runs while a Drives widget or rail tile is on screen.
@MainActor
final class DockDrivesFeed: ObservableObject {
    static let shared = DockDrivesFeed()

    @Published private(set) var volumes: [DriveVolume] = []
    private var timer: Timer?
    private var holders = 0

    func retain() {
        holders += 1
        guard timer == nil else { return }
        volumes = DriveInventory.volumes()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.volumes = DriveInventory.volumes() }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// OW-5b: the opt-in ticker. Three keyless feeds (CoinGecko, open.er-api, goldprice) are read together, every
/// successful set is written to `ticker.json`, and a cold start with no network draws that copy under the
/// offline badge instead of an empty pane.
@MainActor
final class TickerFeed: ObservableObject {
    static let shared = TickerFeed()

    @Published private(set) var snapshot: TickerSnapshot?
    @Published private(set) var freshness: TickerFreshness = .offline
    @Published private(set) var isRefreshing = false

    private static let refreshInterval: TimeInterval = 5 * 60
    private var lastAttemptFailed = true
    private var timer: Timer?
    private var holders = 0
    private let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati")
    }

    private init() {
        directory = Self.defaultDirectory
        snapshot = TickerCache.load(from: directory).flatMap { cached in
            TickerCachePolicy.isStale(fetchedAt: cached.fetchedAt, now: Date()) ? nil : cached
        }
        // No attempt has been made yet: a disk copy is cached, and nothing on disk is offline.
        lastAttemptFailed = false
        freshness = TickerCachePolicy.freshness(fetchedAt: snapshot?.fetchedAt, lastAttemptFailed: false, now: Date())
        if snapshot == nil { freshness = .cached }
    }

    /// Runs the refresh timer only while a pane is on screen, like the other dock feeds.
    func retain() {
        holders += 1
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func release() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing,
              UserDefaults.standard.bool(forKey: TickerCachePolicy.enabledKey) else {
            freshness = TickerCachePolicy.freshness(fetchedAt: lastSuccess, lastAttemptFailed: lastAttemptFailed, now: Date())
            return
        }
        isRefreshing = true
        Task { [weak self] in
            let quotes = await Self.fetchAll()
            guard let self else { return }
            self.isRefreshing = false
            if quotes.isEmpty {
                self.lastAttemptFailed = true
                self.freshness = .offline
                return
            }
            let snapshot = TickerSnapshot(quotes: quotes, fetchedAt: Date())
            self.snapshot = snapshot
            self.lastAttemptFailed = false
            self.freshness = .live
            TickerCache.save(snapshot, to: self.directory)
        }
    }

    private var lastSuccess: Date? { snapshot?.fetchedAt }

    static let cryptoURL = URL(string: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true")!
    static let fxURL = URL(string: "https://open.er-api.com/v6/latest/USD")!
    static let goldURL = URL(string: "https://data-asg.goldprice.org/dbXRates/USD")!

    /// One failed feed does not sink the others: gold alone still gives a price to show.
    static func fetchAll() async -> [TickerQuote] {
        async let crypto = data(from: cryptoURL)
        async let fx = data(from: fxURL)
        async let gold = data(from: goldURL)
        var quotes: [TickerQuote] = []
        quotes += TickerFeedParser.crypto(from: await crypto ?? Data())
        quotes += TickerFeedParser.fx(from: await fx ?? Data())
        quotes += TickerFeedParser.gold(from: await gold ?? Data())
        return quotes
    }

    private static func data(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        return try? await URLSession.shared.data(for: request).0
    }
}
