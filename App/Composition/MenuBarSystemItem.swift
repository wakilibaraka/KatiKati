import AppKit
import Combine

/// Phase 20c — optional CPU / memory readout in the macOS menu bar (the DeskBar "menu-bar placement" gap);
/// clicking it opens Activity Monitor. Off by default. The status item and the 1 s sampler exist only while the
/// setting is on, so a user who never enables it pays nothing.
@MainActor
final class MenuBarSystemItem {
    static let enabledKey = "com.katikati.menuBarSystem.enabled"

    private let monitor = SystemMonitorController()
    private var item: NSStatusItem?
    private var sink: AnyCancellable?
    private var observer: NSObjectProtocol?

    func start() {
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.apply() }
        }
        apply()
    }

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private func apply() {
        if isEnabled, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.target = self
            item.button?.action = #selector(openActivityMonitor)
            item.button?.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            self.item = item
            monitor.acquire()
            sink = monitor.$snapshot.sink { [weak item] snapshot in
                item?.button?.title = SystemMonitorFormat.menuBarTitle(snapshot)
            }
        } else if !isEnabled, let existing = item {
            sink = nil
            monitor.release()
            NSStatusBar.system.removeStatusItem(existing)
            item = nil
        }
    }

    @objc private func openActivityMonitor() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
