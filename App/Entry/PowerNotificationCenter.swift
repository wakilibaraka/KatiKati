import AppKit
import Combine
import SwiftUI

/// Phase 59a — battery and peripheral notifications, delivered as the compact capsule the now-playing
/// chip uses instead of the notch island: the island takes the menu bar's width and a lot of the
/// screen, which is too much surface for "80 %".
///
/// The firing rules are `PowerNotificationPolicy` (pure, tested): transitions only, one alert per dip,
/// one per milestone per charge session. This type feeds it snapshots — the battery from
/// `SystemStatusService`, peripherals from `BluetoothDeviceReader` once a minute — records what fired,
/// and keeps the history the Notifications settings page lists.
@MainActor
final class PowerNotificationCenter: ObservableObject {
    static let shared = PowerNotificationCenter()

    @Published private(set) var rules: PowerNotificationRules
    @Published private(set) var history: [PowerNotification]

    private let status = SystemStatusService()
    private let presenter = PowerNotificationPillPresenter()
    private var cancellables = Set<AnyCancellable>()
    private var devices: [BluetoothDevice] = []
    private var previous: PowerNotificationPolicy.Snapshot?
    /// The first reading of each source seeds the baseline; a launch must not replay "connected" for
    /// every accessory already on the desk, or "charging" for a Mac that has been on power all day.
    private var seededStatus = false
    private var seededDevices = false
    private var fired = PowerNotificationPolicy.Fired()
    private var deviceTimer: Timer?
    private var started = false

    init(defaults: UserDefaults = .standard) {
        let loaded = PowerNotificationRules.load(defaults)
        rules = loaded
        history = PowerNotificationHistory.prune(PowerNotificationHistory.load(defaults),
                                                 retentionHours: loaded.retentionHours)
    }

    func start() {
        guard !started else { return }
        started = true
        status.acquire()
        status.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        refreshDevices()
        // One `system_profiler` a minute: a charge level does not move faster, and the read costs about
        // a second of a background core.
        deviceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDevices() }
        }
        // 59a live-check aid: `DOCK_NOTIFY_DEMO=<kind>` shows one pill at launch (not in the history).
        if let raw = DebugSwitch.powerNotificationDemo.value(), let kind = PowerNotificationKind(rawValue: raw) {
            let titles: [PowerNotificationKind: String] = [
                .lowBattery: String(localized: "Battery Low"), .charged: String(localized: "Battery Charged"),
                .charging: String(localized: "Charging"), .unplugged: String(localized: "Unplugged"),
                .peripheralConnected: String(localized: "Connected"),
                .peripheralDisconnected: String(localized: "Disconnected"),
                .peripheralLowBattery: String(localized: "Low Battery"),
            ]
            let demo = PowerNotification(kind: kind, title: titles[kind] ?? "", detail: "80%", date: Date())
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.presenter.show(demo) }
        }
    }

    func stop() {
        guard started else { return }
        started = false
        deviceTimer?.invalidate()
        deviceTimer = nil
        cancellables.removeAll()
        status.release()
    }

    // MARK: - Rules (the Notifications page)

    func updateRules(_ change: (inout PowerNotificationRules) -> Void) {
        var next = rules
        change(&next)
        next.save()
        rules = next
        history = PowerNotificationHistory.prune(history, retentionHours: next.retentionHours)
        PowerNotificationHistory.save(history)
    }

    func clearHistory() {
        history = []
        PowerNotificationHistory.save([])
    }

    // MARK: - Evaluation

    private func refreshDevices() {
        Task { [weak self] in
            let read = await BluetoothDeviceReader.read()
            guard let self else { return }
            self.devices = read.filter { $0.isConnected }
            self.evaluate()
        }
    }

    private func evaluate() {
        let battery = status.status.battery
        let snapshot = PowerNotificationPolicy.Snapshot(level: battery.level,
                                                        isCharging: battery.isCharging,
                                                        isPluggedIn: battery.isPluggedIn,
                                                        devices: devices)
        guard seededStatus else {
            seededStatus = true
            previous = snapshot
            seededDevices = devices.isEmpty == false
            return
        }
        guard var baseline = previous else {
            previous = snapshot
            return
        }
        // The first peripheral read establishes the baseline silently — arrivals after that are news.
        if !seededDevices, !devices.isEmpty {
            seededDevices = true
            baseline.devices = devices
            previous = snapshot
            return
        }
        previous = snapshot

        let events = PowerNotificationPolicy.events(from: baseline, to: snapshot, rules: rules, fired: &fired)
        guard !events.isEmpty else { return }
        for event in events {
            history = PowerNotificationHistory.appending(event, to: history,
                                                         retentionHours: rules.retentionHours)
        }
        PowerNotificationHistory.save(history)
        presenter.show(events.first)
    }
}

/// The compact capsule: same family as the now-playing chip — dark glass, one accent tile, one line of
/// title and one of detail — in the now-playing chip's band under the menu bar, but at the top **right**,
/// so a song starting at the same moment cannot sit on top of a "Battery Low". Click-through and
/// non-activating, so it never steals the pointer from what the user is doing.
@MainActor
final class PowerNotificationPillPresenter {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ notification: PowerNotification?) {
        guard let notification, let screen = NSScreen.main else { return }
        let host = NSHostingView(rootView: PowerNotificationPillView(notification: notification))
        let size = host.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.isReleasedWhenClosed = false
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            return p
        }()
        self.panel = panel
        panel.contentView = host
        let frame = screen.visibleFrame
        panel.setFrame(NSRect(x: frame.maxX - size.width - 12,
                              y: frame.maxY - size.height - 6,
                              width: size.width, height: size.height), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.22; panel?.animator().alphaValue = 0 },
                                                 completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }
}

private struct PowerNotificationPillView: View {
    let notification: PowerNotification

    private var accent: Color {
        switch notification.kind {
        case .lowBattery, .peripheralLowBattery: return Color(red: 0.98, green: 0.45, blue: 0.28)
        case .charged: return Color(red: 0.30, green: 0.80, blue: 0.48)
        case .charging: return Color(red: 0.34, green: 0.72, blue: 0.98)
        case .unplugged, .peripheralDisconnected: return Color(red: 0.62, green: 0.62, blue: 0.68)
        case .peripheralConnected: return Color(red: 0.42, green: 0.60, blue: 0.98)
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: notification.kind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(accent.opacity(0.9)))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: notification.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let detail = notification.detail {
                    Text(verbatim: detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
        .padding(6)
    }
}
