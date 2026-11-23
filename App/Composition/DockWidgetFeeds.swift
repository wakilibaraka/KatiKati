import Combine
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
    private let monitor = SystemMonitorController()
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

    func retain() { monitor.acquire() }
    func release() { monitor.release() }
}

/// Connected Bluetooth peripherals with their battery levels (polled; `system_profiler` is not free).
@MainActor
final class DockDevicesFeed: ObservableObject {
    static let shared = DockDevicesFeed()

    @Published private(set) var devices: [BluetoothDevice] = []
    @Published private(set) var isRefreshing = false
    private var timer: Timer?
    private var holders = 0
    private var refreshTask: Task<Void, Never>?

    func retain() {
        holders += 1
        guard timer == nil else { return }
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
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            defer {
                self?.isRefreshing = false
                self?.refreshTask = nil
            }
            let all = await BluetoothDeviceReader.read()
            guard !Task.isCancelled else { return }
            self?.devices = all.filter(\.isConnected)
        }
    }

    private func refresh() {
        refreshNow()
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
