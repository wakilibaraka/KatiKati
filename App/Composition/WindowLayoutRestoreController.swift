import AppKit
import Combine
import OSLog

/// Phase 20c — puts windows back where they were after a sleep/wake or a display unplug/replug.
/// Cost model: one Combine subscription on the window snapshot (a dictionary write per publish) and five system
/// notifications; no timers except the one-shot settle delay after a wake or display change. Needs Accessibility
/// (already required by the strip); no new permission.
@MainActor
final class WindowLayoutRestoreController {
    static let enabledKey = "com.katikati.layoutRestore.enabled"

    private let runtime: AppRuntime
    private let displayTable: @MainActor () -> WindowDisplayAttribution.Table
    private var memory = WindowLayoutMemory()
    private var snapshotSink: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    /// While true the snapshot stream is not recorded: after a sleep or display change the system is
    /// rearranging windows and that arrangement must not overwrite the one worth restoring.
    private var isFrozen = false
    private var settleTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "layout-restore")

    init(runtime: AppRuntime, displayTable: @escaping @MainActor () -> WindowDisplayAttribution.Table) {
        self.runtime = runtime
        self.displayTable = displayTable
    }

    private var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    func start() {
        snapshotSink = runtime.$snapshot.sink { [weak self] snapshot in self?.record(snapshot) }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.freeze() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRestore() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRestore() }
        })
    }

    // MARK: - Recording

    private var topologyKey: String {
        WindowLayoutMemory.topologyKey(displayUUIDs: displayTable().displays.map(\.uuid))
    }

    private func layoutWindows(_ snapshot: DockSnapshot) -> [WindowLayoutMemory.Window] {
        snapshot.windows.values.compactMap { w in
            guard w.status == .active || w.status == .inactive, let frame = w.bounds,
                  let cg = w.cgWindowID, cg != 0, frame.width > 40, frame.height > 40 else { return nil }
            return WindowLayoutMemory.Window(pid: w.pid, cgWindowID: cg, frame: frame)
        }
    }

    private func record(_ snapshot: DockSnapshot) {
        guard !isFrozen, isEnabled else { return }
        memory.record(topology: topologyKey, windows: layoutWindows(snapshot))
    }

    // MARK: - Restoring

    private func freeze() { isFrozen = true; settleTask?.cancel() }

    /// Waits for the displays and windows to settle, then restores. Each new event restarts the wait.
    private func scheduleRestore() {
        isFrozen = true
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.restoreNow(force: false)
        }
    }

    /// Restores from the layout remembered for the current displays. `force` is the manual menu/button path:
    /// it works even when the automatic setting is off.
    func restoreNow(force: Bool = true) {
        defer {
            // Resume recording a moment after the moves land, so restored frames become the new memory.
            settleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard !Task.isCancelled else { return }
                self?.isFrozen = false
                self?.record(self?.runtime.snapshot ?? .empty)
            }
        }
        guard force || isEnabled else { return }
        let moves = memory.plan(topology: topologyKey, current: layoutWindows(runtime.snapshot))
        guard !moves.isEmpty else { return }
        log.info("restoring \(moves.count, privacy: .public) window(s)")
        DispatchQueue.global(qos: .userInitiated).async {
            let reader = AXWindowReader()
            for move in moves {
                guard let handle = reader.captureHandle(forPID: move.pid, cgWindowID: move.cgWindowID, messagingTimeout: 0.2) else { continue }
                _ = reader.setFrame(move.frame, for: handle.element, messagingTimeout: 0.2, verificationTolerance: 8)
            }
        }
    }
}
