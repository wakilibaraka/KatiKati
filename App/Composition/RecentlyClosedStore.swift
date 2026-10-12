import AppKit

/// Phase 8a — remembers the regular apps the user quit (newest first) so the taskbar/drawer menu can offer
/// one-click restore. Event-driven off NSWorkspace launch/terminate notifications (no timer, no polling);
/// stores bundle IDs only, in UserDefaults. KatiKati itself and background (accessory/prohibited) apps are
/// never recorded.
@MainActor
final class RecentlyClosedStore: ObservableObject {
    static let shared = RecentlyClosedStore()
    private static let key = "com.katikati.recentlyClosed"

    @Published private(set) var list: RecentlyClosedList
    private var observers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard

    private init() {
        list = RecentlyClosedList(bundleIDs: defaults.stringArray(forKey: Self.key) ?? [])
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let ownID = Bundle.main.bundleIdentifier
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular, let id = app.bundleIdentifier, id != ownID else { return }
            MainActor.assumeIsolated { self?.update { $0.noteClosed(id) } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let id = app.bundleIdentifier else { return }
            MainActor.assumeIsolated { self?.update { $0.noteLaunched(id) } }
        })
    }

    private func update(_ change: (inout RecentlyClosedList) -> Void) {
        var next = list
        change(&next)
        guard next != list else { return }
        list = next
        defaults.set(next.bundleIDs, forKey: Self.key)
    }

    /// Entries still worth offering: not running now, and the app is still installed.
    func restorable() -> [(id: String, url: URL)] {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return list.visible(excluding: running).compactMap { id in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (id, $0) }
        }
    }

    func restore(_ url: URL) {
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }
}
