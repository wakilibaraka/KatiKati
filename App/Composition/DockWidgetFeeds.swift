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
    private var timer: Timer?
    private var holders = 0

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
    }

    private func refresh() {
        Task { [weak self] in
            let all = await BluetoothDeviceReader.read()
            self?.devices = all.filter(\.isConnected)
        }
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
