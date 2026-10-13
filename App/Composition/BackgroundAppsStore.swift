import AppKit
import Combine

/// Phase 20a — running-process facts for the Background Apps drawer section. Lazy singleton: nothing observes
/// until the drawer first reads it; afterwards it reacts only to NSWorkspace launch / quit / hide / unhide
/// notifications (no timers). Classification itself is the pure `BackgroundAppClassifier`.
@MainActor
final class BackgroundAppsStore: ObservableObject {
    static let shared = BackgroundAppsStore()

    struct Fact: Equatable {
        let bundleID: String
        let policy: BackgroundAppClassifier.Policy
        let isHidden: Bool
        let isHelper: Bool
    }

    @Published private(set) var facts: [Fact] = []
    @Published private(set) var ignored: Set<String>
    static let showSystemHelpersKey = "com.katikati.drawer.showSystemHelpers"
    private static let ignoredKey = "com.katikati.drawer.backgroundIgnored"
    private let defaults = UserDefaults.standard
    private var observers: [NSObjectProtocol] = []

    private init() {
        ignored = Set(defaults.stringArray(forKey: Self.ignoredKey) ?? [])
        reload()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.reload() }
            })
        }
    }

    func ignore(_ id: String) {
        ignored.insert(id)
        defaults.set(Array(ignored).sorted(), forKey: Self.ignoredKey)
    }

    func unignoreAll() {
        ignored = []
        defaults.removeObject(forKey: Self.ignoredKey)
    }

    private func reload() {
        let list = NSWorkspace.shared.runningApplications.compactMap { app -> Fact? in
            guard let id = app.bundleIdentifier, !app.isTerminated else { return nil }
            let policy: BackgroundAppClassifier.Policy
            switch app.activationPolicy {
            case .regular: policy = .regular
            case .accessory: policy = .accessory
            default: policy = .prohibited
            }
            return Fact(bundleID: id, policy: policy, isHidden: app.isHidden,
                        isHelper: BackgroundAppClassifier.looksLikeHelper(bundlePath: app.bundleURL?.path, name: app.localizedName))
        }
        if list != facts { facts = list }
    }

    /// Background bundle ids for the drawer, given who currently has real windows and who is claimed elsewhere.
    func backgroundIDs(windowBacked: Set<String>, kept: Set<String>, messaging: Set<String>, stashed: Set<String>,
                       showSystemHelpers: Bool = false) -> [String] {
        let context = BackgroundAppClassifier.Context(
            selfBundleID: Bundle.main.bundleIdentifier ?? "", keptIDs: kept, messagingIDs: messaging,
            stashedIDs: stashed, ignoredIDs: ignored, showSystemHelpers: showSystemHelpers)
        return BackgroundAppClassifier.background(
            facts.map { .init(bundleID: $0.bundleID, policy: $0.policy, hasWindows: windowBacked.contains($0.bundleID), isHidden: $0.isHidden, isHelper: $0.isHelper) },
            context)
    }
}
