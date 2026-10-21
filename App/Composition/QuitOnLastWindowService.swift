import AppKit
import ApplicationServices
import OSLog

/// 53d: quit an opted-in app after its last window closes. Off by default and list-driven, because leaving
/// an app running is the safe default and quitting one can raise its own unsaved-changes prompt.
///
/// The AX observer watches `kAXWindowCreatedNotification` on the app and `kAXUIElementDestroyedNotification`
/// on each window. A quit needs a *successful* read that went from at least one window to zero; an AX read
/// failure is treated as unknown and never quits. `terminate()` is the graceful path, so the app's save
/// prompt still runs. Needs Accessibility; without it every AX call fails and the service does nothing.
@MainActor
final class QuitOnLastWindowService {
    static let shared = QuitOnLastWindowService()
    static let key = "com.katikati.windows.quitOnClose"

    private let log = Logger(subsystem: "com.katikati.app", category: "quitOnClose")
    private var policy = QuitOnLastWindowPolicy()
    private var observers: [pid_t: AXObserver] = [:]
    private var sawWindow: Set<pid_t> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingChecks: [pid_t: DispatchWorkItem] = [:]

    var apps: String { UserDefaults.standard.string(forKey: Self.key) ?? "" }
    var isEnabled: Bool { !policy.bundleIDs.isEmpty }

    // MARK: lifecycle

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.track(app) }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.forget(app?.processIdentifier) }
        })
        refresh()
    }

    func tearDown() {
        for work in pendingChecks.values { work.cancel() }
        pendingChecks.removeAll()
        for observer in observers.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        sawWindow.removeAll()
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers.removeAll()
    }

    /// Re-read the opt-in list. Called at launch and whenever Settings edits it.
    func refresh() {
        policy = QuitOnLastWindowPolicy.parse(apps)
        guard isEnabled, AXIsProcessTrusted() else {
            dropAllObservers()
            return
        }
        for pid in Array(observers.keys) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  policy.applies(to: app.bundleIdentifier) else {
                dropObserver(pid)
                continue
            }
        }
        for app in NSWorkspace.shared.runningApplications where policy.applies(to: app.bundleIdentifier) {
            track(app)
        }
    }

    func setApps(_ raw: String) {
        guard raw != apps else { return }
        UserDefaults.standard.set(raw, forKey: Self.key)
        refresh()
    }

    // MARK: observation

    private func track(_ app: NSRunningApplication?) {
        guard let app, policy.applies(to: app.bundleIdentifier), AXIsProcessTrusted() else { return }
        let pid = app.processIdentifier
        if let observer = observers[pid] {
            watchWindows(of: pid, observer: observer)
            return
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, quitOnLastWindowCallback, &observer) == .success, let observer else { return }
        let appElement = AXUIElementCreateApplication(pid)
        _ = AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString,
                                      Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
        watchWindows(of: pid, observer: observer)
    }

    /// Registers the destroyed notification on every window that exists now. Re-registering a window is a
    /// harmless no-op, so this runs after every event instead of trying to diff window sets.
    private func watchWindows(of pid: pid_t, observer: AXObserver) {
        let windows = Self.windows(of: pid) ?? []
        if !windows.isEmpty { sawWindow.insert(pid) }
        for window in windows {
            _ = AXObserverAddNotification(observer, window, kAXUIElementDestroyedNotification as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
        }
    }

    fileprivate func handleAXEvent(pid: pid_t) {
        guard observers[pid] != nil, let app = NSRunningApplication(processIdentifier: pid),
              policy.applies(to: app.bundleIdentifier) else { return }
        let windows = Self.windows(of: pid)
        if let windows, !windows.isEmpty {
            sawWindow.insert(pid)
            if let observer = observers[pid] { watchWindows(of: pid, observer: observer) }
            return
        }
        guard QuitOnLastWindowPolicy.shouldQuit(hadWindow: sawWindow.contains(pid), windowCount: windows?.count) else { return }
        // A closed window is often replaced at once (tab drag, reopening). Wait a beat, then re-count.
        pendingChecks[pid]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.quitIfStillWindowless(pid) }
        }
        pendingChecks[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func quitIfStillWindowless(_ pid: pid_t) {
        pendingChecks[pid] = nil
        guard let app = NSRunningApplication(processIdentifier: pid),
              policy.applies(to: app.bundleIdentifier),
              Self.windows(of: pid).map({ $0.isEmpty }) == true else { return }
        sawWindow.remove(pid)
        log.info("Quitting \(app.bundleIdentifier ?? "?", privacy: .public): last window closed")
        app.terminate()
    }

    private func forget(_ pid: pid_t?) {
        guard let pid else { return }
        pendingChecks[pid]?.cancel()
        pendingChecks[pid] = nil
        dropObserver(pid)
    }

    private func dropObserver(_ pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        sawWindow.remove(pid)
    }

    private func dropAllObservers() {
        for pid in Array(observers.keys) { dropObserver(pid) }
    }

    // MARK: AX reads

    /// `nil` means the read failed (no Accessibility, app gone, AX not ready) — never treated as zero.
    nonisolated static func windows(of pid: pid_t) -> [AXUIElement]? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        return (value as? [AXUIElement]) ?? []
    }
}

/// AXObserver callbacks arrive on the main run loop (the source is added there), so the main-actor hop is
/// direct. The element's pid is enough: the window count is re-read rather than trusted from the event.
private func quitOnLastWindowCallback(observer: AXObserver, element: AXUIElement, notification: CFString,
                                      refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let service = Unmanaged<QuitOnLastWindowService>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    guard AXUIElementGetPid(element, &pid) == .success else { return }
    MainActor.assumeIsolated { service.handleAXEvent(pid: pid) }
}
