import AppKit
import Foundation

/// Foreground-app time tracking (Phase 7B-W1). Off until the user turns it on; while off nothing is observed and no
/// timer exists. While on it listens for app switches and sleep/lock notifications and wakes every 15 s to credit
/// time and check for idleness. It records only the frontmost regular app's bundle id and name — no Accessibility
/// access, no window titles, no screen capture.
@MainActor
final class ScreenTimeController: ObservableObject {
    static let enabledKey = "com.katikati.screentime.enabled"
    static let retentionDays = 90
    private static let ignored: Set<String> = ["com.apple.loginwindow", "com.apple.ScreenSaver.Engine"]

    @Published private(set) var ledger: ScreenTimeLedger
    @Published private(set) var enabled: Bool
    /// Bumped on every tick so views showing "now" refresh.
    @Published private(set) var tickCount = 0
    /// Called after each tick with the up-to-date ledger (limits, W3).
    var onTick: ((ScreenTimeLedger, _ currentBundleID: String?) -> Void)?

    private let store: ScreenTimeStore
    private let defaults: UserDefaults
    private var calendar = Calendar.current
    private var tracker = ScreenTimeTracker()
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var screenAsleep = false
    private var lastSave = Date.distantPast

    var currentBundleID: String? { tracker.current?.bundleID }

    init(store: ScreenTimeStore = ScreenTimeStore(url: ScreenTimeStore.defaultURL), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        ledger = store.load()
    }

    func startIfEnabled() { if enabled { start() } }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        on ? start() : stop()
    }

    /// Wipes every stored second and name.
    func deleteAllData() {
        ledger = ScreenTimeLedger()
        store.deleteAll()
    }

    private func start() {
        guard timer == nil else { return }
        calendar = Calendar.current
        ledger.prune(keepDays: Self.retentionDays, now: Date(), calendar: calendar)
        if let front = NSWorkspace.shared.frontmostApplication { activated(front) }
        let ws = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ handler: @escaping @MainActor (Notification) -> Void) {
            observers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { n in
                MainActor.assumeIsolated { handler(n) }
            }))
        }
        watch(NSWorkspace.didActivateApplicationNotification) { [weak self] n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.activated(app) }
        }
        watch(NSWorkspace.screensDidSleepNotification) { [weak self] _ in self?.screenAsleep = true; self?.tick() }
        watch(NSWorkspace.screensDidWakeNotification) { [weak self] _ in self?.screenAsleep = false; self?.tick() }
        watch(NSWorkspace.willSleepNotification) { [weak self] _ in self?.screenAsleep = true; self?.tick(); self?.save() }
        watch(NSWorkspace.didWakeNotification) { [weak self] _ in self?.screenAsleep = false; self?.tick() }
        watch(NSWorkspace.sessionDidResignActiveNotification) { [weak self] _ in self?.screenAsleep = true; self?.tick() }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] _ in self?.screenAsleep = false; self?.tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 5
        tick()
    }

    private func stop() {
        tracker.setCounting(false, at: Date(), ledger: &ledger, calendar: calendar)
        save()
        timer?.invalidate()
        timer = nil
        observers.forEach { $0.0.removeObserver($0.1) }
        observers = []
    }

    private func activated(_ app: NSRunningApplication) {
        let id = app.bundleIdentifier ?? ""
        let counts = app.activationPolicy == .regular && id != Bundle.main.bundleIdentifier && !Self.ignored.contains(id)
        tracker.appActivated(bundleID: counts ? id : "", name: app.localizedName ?? id, at: Date(), ledger: &ledger, calendar: calendar)
    }

    private func tick() {
        let now = Date()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let away = ScreenTimeTracker.isAway(idleSeconds: idle, screenAsleep: screenAsleep)
        tracker.setCounting(!away, at: now, ledger: &ledger, calendar: calendar)
        tickCount &+= 1
        if now.timeIntervalSince(lastSave) >= 60 { save() }
        onTick?(ledger, tracker.current?.bundleID)
    }

    func save() {
        lastSave = Date()
        try? store.save(ledger)
    }
}
