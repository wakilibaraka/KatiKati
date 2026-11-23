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
    private let fileURL: URL
    private var memory = WindowLayoutMemory()
    private var snapshotSink: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    /// While true the snapshot stream is not recorded: after a sleep or display change the system is
    /// rearranging windows and that arrangement must not overwrite the one worth restoring.
    private var isFrozen = false
    private var settleTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.katikati.app", category: "layout-restore")

    nonisolated static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent(WindowLayoutMemory.fileName)
    }

    init(runtime: AppRuntime,
         displayTable: @escaping @MainActor () -> WindowDisplayAttribution.Table,
         fileURL: URL = WindowLayoutRestoreController.defaultURL) {
        self.runtime = runtime
        self.displayTable = displayTable
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(WindowLayoutMemory.self, from: data) {
            self.memory = decoded
        }
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
        let previous = memory
        memory.record(topology: topologyKey, windows: layoutWindows(snapshot))
        if memory != previous { scheduleSave() }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        let snapshot = memory
        let url = fileURL
        Task.detached(priority: .utility) {
            try? Self.write(snapshot, to: url)
        }
    }

    nonisolated private static func write(_ memory: WindowLayoutMemory, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(memory).write(to: url, options: .atomic)
    }

    // MARK: - Restoring

    private func freeze() {
        isFrozen = true
        settleTask?.cancel()
        saveTask?.cancel()
        persistNow()
    }

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
        // WM revamp §4: a remembered frame must land in the work area tiling would use today — the
        // layout may have been saved on a bigger display or behind a Dock that has since grown.
        let clamped = moves.map(fitToWorkArea)
        log.info("restoring \(clamped.count, privacy: .public) window(s)")
        DispatchQueue.global(qos: .userInitiated).async {
            let reader = AXWindowReader()
            for move in clamped {
                guard let handle = reader.captureHandle(forPID: move.pid, cgWindowID: move.cgWindowID, messagingTimeout: 0.2) else { continue }
                _ = reader.setFrame(move.frame, for: handle.element, messagingTimeout: 0.2, verificationTolerance: 8)
            }
        }
    }

    /// Fits a remembered frame into the work area tiling computes for the screen it belongs to.
    /// Remembered frames are Quartz (top-left origin), so the Cocoa work area is converted first;
    /// a frame whose screen is gone is left alone rather than guessed onto another display.
    private func fitToWorkArea(_ move: WindowLayoutMemory.Move) -> WindowLayoutMemory.Move {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return move }
        let center = WindowFit.cocoaCenter(ofQuartzFrame: move.frame, primaryMaxY: primary.frame.maxY)
        guard let screen = screens.first(where: { $0.frame.contains(center) }) else { return move }
        let area = TilingEngine.shared.workArea(of: screen)
        let quartzArea = CGRect(
            origin: SnapPosition.accessibilityOrigin(of: area, primaryMaxY: primary.frame.maxY),
            size: area.size
        )
        let fitted = WindowFit.fitted(move.frame, into: quartzArea)
        guard fitted != move.frame else { return move }
        return WindowLayoutMemory.Move(pid: move.pid, cgWindowID: move.cgWindowID, frame: fitted)
    }
}
