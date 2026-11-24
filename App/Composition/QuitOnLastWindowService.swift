import AppKit
import ApplicationServices
import Combine
import OSLog

/// 53d: quit an opted-in app after its last window closes. Off by default and list-driven, because leaving
/// an app running is the safe default and quitting one can raise its own unsaved-changes prompt.
///
/// The AX observer watches `kAXWindowCreatedNotification` on the app and `kAXUIElementDestroyedNotification`
/// on each window. A quit needs a *successful* read that went from at least one window to zero; an AX read
/// failure is treated as unknown and never quits. `terminate()` is the graceful path, so the app's save
/// prompt still runs. Needs Accessibility; without it every AX call fails and the service does nothing.
///
/// The list is `@Published` because the app-rules table in Settings edits it and draws one switch per
/// app outside this service's own writes; without that, a row added in Settings would not redraw.
@MainActor
final class QuitOnLastWindowService: ObservableObject {
    static let shared = QuitOnLastWindowService()
    static let key = "com.katikati.windows.quitOnClose"
    static let modeKey = "com.katikati.windows.quitOnCloseMode"
    static let excludedKey = "com.katikati.windows.quitOnCloseExcluded"
    static let delayKey = "com.katikati.windows.quitOnCloseDelay"

    private let log = Logger(subsystem: "com.katikati.app", category: "quitOnClose")
    private var policy = QuitOnLastWindowPolicy()
    private var idlePolicy = IdleAppAutoQuitPolicy()
    private var lastActiveTimes: [String: Date] = [:]
    private var lastNotifiedAt: [String: Date] = [:]
    private var idleTimer: Timer?
    private var observers: [pid_t: AXObserver] = [:]
    private var sawWindow: Set<pid_t> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pendingChecks: [pid_t: DispatchWorkItem] = [:]

    /// Comma/whitespace separated bundle IDs, the same form the key-guard lists use.
    @Published private(set) var apps: String = UserDefaults.standard.string(forKey: QuitOnLastWindowService.key) ?? ""
    @Published private(set) var mode: QuitOnCloseMode = {
        QuitOnCloseMode(rawValue: UserDefaults.standard.string(forKey: QuitOnLastWindowService.modeKey) ?? "") ?? .selectedOnly
    }()
    @Published private(set) var excludedApps: String = UserDefaults.standard.string(forKey: QuitOnLastWindowService.excludedKey) ?? ""
    @Published private(set) var quitDelay: Double = {
        let stored = UserDefaults.standard.double(forKey: QuitOnLastWindowService.delayKey)
        return stored > 0 ? QuitOnLastWindowPolicy.clampDelay(stored) : 0.5
    }()

    // Leaf / Quitter Idle & Heavy App settings
    @Published private(set) var idleThresholdSeconds: TimeInterval = UserDefaults.standard.double(forKey: IdleAppAutoQuitPolicy.defaultsKey)
    @Published private(set) var idleAction: IdleAppAction = {
        IdleAppAction(rawValue: UserDefaults.standard.string(forKey: IdleAppAutoQuitPolicy.actionKey) ?? "") ?? .notify
    }()
    @Published private(set) var idleMinMemoryMB: Int = UserDefaults.standard.integer(forKey: IdleAppAutoQuitPolicy.minMemoryMBKey)
    @Published private(set) var idlePerAppRaw: String = UserDefaults.standard.string(forKey: IdleAppAutoQuitPolicy.perAppActionsKey) ?? ""

    var isIdleTimerRunning: Bool { idleTimer != nil }

    var isEnabled: Bool {
        switch mode {
        case .off: return false
        case .selectedOnly: return !policy.bundleIDs.isEmpty
        case .allExceptExcluded: return true
        }
    }

    // MARK: lifecycle

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let id = app?.bundleIdentifier {
                    self?.lastActiveTimes[id] = Date()
                }
                self?.track(app)
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.forget(app?.processIdentifier) }
        })
        refresh()
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        guard !workspaceObservers.isEmpty, idleThresholdSeconds > 0 else {
            idleTimer?.invalidate()
            idleTimer = nil
            return
        }
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluateIdleApps() }
        }
    }

    func tearDown() {
        idleTimer?.invalidate()
        idleTimer = nil
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
        policy = QuitOnLastWindowPolicy.parse(apps, mode: mode, excludedRaw: excludedApps)
        guard isEnabled, AXIsProcessTrusted() else {
            dropAllObservers()
            return
        }
        for pid in Array(observers.keys) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular,
                  policy.applies(to: app.bundleIdentifier) else {
                dropObserver(pid)
                continue
            }
        }
        for app in NSWorkspace.shared.runningApplications
            where app.activationPolicy == .regular && policy.applies(to: app.bundleIdentifier) {
            track(app)
        }
    }

    func setApps(_ raw: String) {
        guard raw != apps else { return }
        apps = raw
        UserDefaults.standard.set(raw, forKey: Self.key)
        refresh()
    }

    func setMode(_ newMode: QuitOnCloseMode) {
        guard newMode != mode else { return }
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        refresh()
    }

    func setExcludedApps(_ raw: String) {
        guard raw != excludedApps else { return }
        excludedApps = raw
        UserDefaults.standard.set(raw, forKey: Self.excludedKey)
        refresh()
    }

    func setQuitDelay(_ seconds: Double) {
        let clamped = QuitOnLastWindowPolicy.clampDelay(seconds)
        guard clamped != quitDelay else { return }
        quitDelay = clamped
        UserDefaults.standard.set(clamped, forKey: Self.delayKey)
    }

    func setIdleThresholdSeconds(_ seconds: TimeInterval) {
        guard seconds != idleThresholdSeconds else { return }
        idleThresholdSeconds = seconds
        UserDefaults.standard.set(seconds, forKey: IdleAppAutoQuitPolicy.defaultsKey)
        updateIdleTimer()
    }

    func setIdleAction(_ action: IdleAppAction) {
        guard action != idleAction else { return }
        idleAction = action
        UserDefaults.standard.set(action.rawValue, forKey: IdleAppAutoQuitPolicy.actionKey)
        if action == .notify { IdleAppNotifier.shared.registerCategoryIfNeeded() }
    }

    func setIdleMinMemoryMB(_ mb: Int) {
        guard mb != idleMinMemoryMB else { return }
        idleMinMemoryMB = mb
        UserDefaults.standard.set(mb, forKey: IdleAppAutoQuitPolicy.minMemoryMBKey)
    }

    func idleAction(for bundleID: String) -> IdleAppAction? {
        IdleAppAutoQuitPolicy.parsePerAppActions(idlePerAppRaw)[bundleID]
    }

    func setIdleAction(_ action: IdleAppAction?, for bundleID: String) {
        var map = IdleAppAutoQuitPolicy.parsePerAppActions(idlePerAppRaw)
        if let action, action != .off {
            map[bundleID] = action
        } else {
            map.removeValue(forKey: bundleID)
        }
        let serialized = IdleAppAutoQuitPolicy.serializePerAppActions(map)
        guard serialized != idlePerAppRaw else { return }
        idlePerAppRaw = serialized
        UserDefaults.standard.set(serialized, forKey: IdleAppAutoQuitPolicy.perAppActionsKey)
    }

    // MARK: idle & heavy app management (Leaf + Quitter)

    func evaluateIdleApps(now: Date = Date(), isPlayingMedia: Bool? = nil, isAgentWorking: Bool? = nil) {
        let threshold = idleThresholdSeconds
        let minBytes = UInt64(max(0, idleMinMemoryMB)) * 1024 * 1024
        let perApp = IdleAppAutoQuitPolicy.parsePerAppActions(idlePerAppRaw)
        idlePolicy = IdleAppAutoQuitPolicy(
            idleThresholdSeconds: threshold,
            defaultAction: idleAction,
            minMemoryBytes: minBytes,
            perAppActions: perApp
        )
        guard threshold > 0 else { return }

        let mediaOrCallActive = isPlayingMedia ?? (PrivacyUseProbe.microphoneInUse() || PrivacyUseProbe.cameraInUse())
        let agentWorking = isAgentWorking ?? (AgentUsageService.shared.snapshot.activeTurn?.isActive == true)

        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier,
                  !app.isActive else { continue }
            let lastActive = lastActiveTimes[bundleID] ?? app.launchDate ?? now
            let idleDuration = now.timeIntervalSince(lastActive)
            let memoryBytes = AppMemorySampler.physicalFootprintBytes(for: app.processIdentifier)

            guard let resolved = idlePolicy.resolvedAction(
                bundleID: bundleID,
                idleDuration: idleDuration,
                memoryBytes: memoryBytes,
                isPlayingMedia: mediaOrCallActive,
                isAgentWorking: agentWorking
            ) else { continue }

            switch resolved {
            case .quit:
                log.info("Auto-quitting idle application: \(bundleID, privacy: .public)")
                app.terminate()
            case .hide:
                guard !app.isHidden else { continue }
                log.info("Auto-hiding idle application: \(bundleID, privacy: .public)")
                app.hide()
            case .notify:
                if let last = lastNotifiedAt[bundleID], now.timeIntervalSince(last) < 1800 { continue }
                lastNotifiedAt[bundleID] = now
                let name = app.localizedName ?? bundleID
                IdleAppNotifier.shared.post(
                    appName: name,
                    bundleID: bundleID,
                    pid: app.processIdentifier,
                    idleMinutes: max(1, Int(idleDuration / 60)),
                    memoryBytes: memoryBytes
                )
            case .off, .keep:
                break
            }
        }
    }

    // MARK: observation

    private func track(_ app: NSRunningApplication?) {
        guard let app, app.activationPolicy == .regular, policy.applies(to: app.bundleIdentifier), AXIsProcessTrusted() else { return }
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
              app.activationPolicy == .regular,
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
        DispatchQueue.main.asyncAfter(deadline: .now() + quitDelay, execute: work)
    }

    private func quitIfStillWindowless(_ pid: pid_t) {
        pendingChecks[pid] = nil
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.activationPolicy == .regular,
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
        let app = AXMessagingPolicy.applyTimeout(AXUIElementCreateApplication(pid))
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return nil }
        let raw = (value as? [AXUIElement]) ?? []
        return raw.filter { window in
            AXMessagingPolicy.applyTimeout(window)
            var subroleRef: CFTypeRef?
            let subrole = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef) == .success
                ? (subroleRef as? String)
                : nil
            var sizeRef: CFTypeRef?
            var size = CGSize(width: 100, height: 100)
            if AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
               let axValue = sizeRef, CFGetTypeID(axValue) == AXValueGetTypeID() {
                AXValueGetValue(axValue as! AXValue, .cgSize, &size)
            }
            return QuitOnLastWindowPolicy.isCountableWindow(subrole: subrole, size: size)
        }
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
