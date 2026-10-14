import AppKit
import CoreGraphics
import OSLog

/// The chord that unpauses while paused (⌃⌥⌘P). Fixed so the owner can always get out.
private let keyGuardUnlock = KeyChord(keyCode: 35, modifiers: [.control, .option, .command])

/// Phase 24b/24c: the single shared keyboard tap behind the input guards. Key events only, on its own
/// thread, alive only while a guard is on, off by default — the documented Hyperkey exception.
/// Swallowing needs Input Monitoring, requested with an explanation, never silently. 24c adds SlowQuit:
/// a held ⌘Q is eaten and replayed as a hold-to-quit with a center-screen progress panel.
@MainActor
final class KeyGuardService: ObservableObject {
    static let shared = KeyGuardService()
    static let pauseKey = "com.katikati.keyguard.pause"
    static let slowQuitKey = "com.katikati.keyguard.slowQuit"
    static let slowQuitDurationKey = "com.katikati.keyguard.slowQuitDuration"
    static let slowQuitExceptionsKey = "com.katikati.keyguard.slowQuitExceptions"

    @Published private(set) var isPaused = UserDefaults.standard.bool(forKey: KeyGuardService.pauseKey)
    @Published private(set) var isSlowQuitEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.slowQuitKey)
    /// Hold threshold in seconds; persisted, clamped to a sane range.
    @Published private(set) var slowQuitDuration: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.slowQuitDurationKey)
        return stored > 0 ? min(max(stored, 0.2), 5) : SlowQuitTiming().threshold
    }()
    /// Comma-separated bundle IDs that quit instantly instead of on hold.
    @Published private(set) var slowQuitExceptions = UserDefaults.standard.string(forKey: KeyGuardService.slowQuitExceptionsKey) ?? ""

    private let log = Logger(subsystem: "com.katikati.app", category: "keyguard")
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tap: CFMachPort?
    private let shared = KeyGuardShared()
    private var started = false
    private var frontmostObserver: NSObjectProtocol?
    private var frontmostBundleID: String?

    private var holdStartedAt: Date?
    private var holdTarget: NSRunningApplication?
    private var holdTimer: Timer?
    private var overlay: SlowQuitOverlayController?

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    func setPaused(_ on: Bool) {
        guard on != isPaused else { return }
        isPaused = on
        UserDefaults.standard.set(on, forKey: Self.pauseKey)
        refresh()
    }

    func togglePause() { setPaused(!isPaused) }

    func setSlowQuit(_ on: Bool) {
        guard on != isSlowQuitEnabled else { return }
        isSlowQuitEnabled = on
        UserDefaults.standard.set(on, forKey: Self.slowQuitKey)
        refresh()
    }

    func tearDown() { stop() }

    func setSlowQuitDuration(_ seconds: Double) {
        let clamped = min(max(seconds, 0.2), 5)
        guard clamped != slowQuitDuration else { return }
        slowQuitDuration = clamped
        UserDefaults.standard.set(clamped, forKey: Self.slowQuitDurationKey)
        refresh()
    }

    func setSlowQuitExceptions(_ raw: String) {
        guard raw != slowQuitExceptions else { return }
        slowQuitExceptions = raw
        UserDefaults.standard.set(raw, forKey: Self.slowQuitExceptionsKey)
        refresh()
    }

    /// The SlowQuit allow/deny view the pipeline sees. `deny` = quit instantly, no hold.
    var slowQuitPolicy: SlowQuitPolicy {
        let deny = slowQuitExceptions
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init)
        return SlowQuitPolicy(deny: Set(deny))
    }

    /// Start the tap when a guard is on, stop it when all are off, and push the current state.
    func refresh() {
        if DebugSwitch.keyGuardOff.isEnabled() {
            if started { stop() }
            return
        }
        if isSlowQuitEnabled, frontmostObserver == nil {
            frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.frontmostChanged(app) }
            }
        }
        shared.update(state: makeState())
        let anyOn = isPaused || isSlowQuitEnabled
        if anyOn, !started { start() } else if !anyOn, started { stop() }
    }

    private func makeState() -> KeyGuardState {
        KeyGuardState(
            paused: isPaused,
            slowQuitEnabled: isSlowQuitEnabled,
            slowQuitApplies: slowQuitPolicy.applies(to: frontmostBundleID),
            slowQuitHolding: false,
            unlockKey: keyGuardUnlock
        )
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        guard isSlowQuitEnabled else { return }
        shared.update(state: makeState())
    }

    private func start() {
        guard Self.hasPermission else {
            log.warning("KeyGuard needs Input Monitoring; not starting")
            isPaused = false
            isSlowQuitEnabled = false
            UserDefaults.standard.set(false, forKey: Self.pauseKey)
            UserDefaults.standard.set(false, forKey: Self.slowQuitKey)
            shared.update(state: makeState())
            return
        }
        shared.onAction = { [weak self] action in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(action) } }
        }
        let thread = Thread { [shared, weak self] in
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            let refcon = Unmanaged.passUnretained(shared).toOpaque()
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                               eventsOfInterest: mask, callback: keyGuardTapCallback, userInfo: refcon) else {
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.tapFailed() } }
                return
            }
            shared.port = port
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, source, .commonModes)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.tapRunLoop = loop; self?.tap = port } }
            CFRunLoopRun()
        }
        thread.name = "com.katikati.keyguard"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        started = true
        thread.start()
    }

    private func stop() {
        endHold()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop = tapRunLoop { CFRunLoopStop(loop) }
        tap = nil; tapRunLoop = nil; tapThread = nil; started = false
        if let frontmostObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(frontmostObserver)
            self.frontmostObserver = nil
        }
        frontmostBundleID = nil
        shared.reset()
    }

    private func tapFailed() { log.error("Could not create the key-guard tap"); started = false }

    private func handle(_ action: KeyGuardAction) {
        if DebugSwitch.keyGuardTrace.isEnabled() { log.debug("keyguard action \(String(describing: action))") }
        switch action {
        case .unlock: setPaused(false)
        case .slowQuitPressed: beginHold()
        case .slowQuitReleased: endHold()
        }
    }

    // MARK: - SlowQuit hold

    private func beginHold() {
        guard holdStartedAt == nil else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              slowQuitPolicy.applies(to: app.bundleIdentifier) else { return }
        holdStartedAt = Date()
        holdTarget = app
        let overlay = self.overlay ?? SlowQuitOverlayController()
        self.overlay = overlay
        overlay.show(app: app, progress: 0)
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let startedAt = holdStartedAt else { return }
        let elapsed = -startedAt.timeIntervalSinceNow
        if elapsed >= slowQuitDuration { fireHold() }
        else { overlay?.update(progress: SlowQuitTiming(threshold: slowQuitDuration).progress(heldFor: elapsed)) }
    }

    private func fireHold() {
        guard let app = holdTarget else { endHold(); return }
        endHold()
        if !app.terminate() { log.warning("SlowQuit could not terminate \(app.bundleIdentifier ?? "?")") }
    }

    private func endHold() {
        guard holdStartedAt != nil else { return }
        holdTimer?.invalidate()
        holdTimer = nil
        holdStartedAt = nil
        holdTarget = nil
        overlay?.hide()
    }
}

/// State shared with the tap thread. Everything the callback touches is lock-protected and O(1).
/// `slowQuitHolding` is owned by the pipeline: `update` preserves it, so a settings/frontmost push
/// in the middle of a hold cannot cancel the keyUp that fires the quit.
final class KeyGuardShared: @unchecked Sendable {
    private let lock = NSLock()
    private var state = KeyGuardState(unlockKey: keyGuardUnlock)
    var port: CFMachPort?
    var onAction: (KeyGuardAction) -> Void = { _ in }

    func update(state newState: KeyGuardState) {
        lock.lock()
        var merged = newState
        merged.slowQuitHolding = state.slowQuitHolding
        state = merged
        lock.unlock()
    }

    func reset() { lock.lock(); state = KeyGuardState(unlockKey: keyGuardUnlock); lock.unlock() }

    func decide(_ event: KeyGuardEvent) -> (decision: KeyGuardDecision, state: KeyGuardState) {
        lock.lock(); defer { lock.unlock() }
        let outcome = KeyGuardPipeline.reduce(event, state: state)
        state = outcome.state
        return outcome
    }
}

/// Per-key-event trace (opt-in via `DebugSwitch.keyGuardTrace`); one env lookup, no work when off.
private let keyGuardLog = Logger(subsystem: "com.katikati.app", category: "keyguard")

private func keyGuardTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<KeyGuardShared>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = shared.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let modifiers = keyModifiers(event.flags)
    let keyEvent: KeyGuardEvent = type == .keyDown ? .keyDown(keyCode: code, modifiers: modifiers)
                                                  : .keyUp(keyCode: code, modifiers: modifiers)
    let outcome = shared.decide(keyEvent)
    if DebugSwitch.keyGuardTrace.isEnabled() {
        keyGuardLog.debug("keyguard \(String(describing: keyEvent)) -> \(String(describing: outcome.decision))")
    }
    switch outcome.decision {
    case .passThrough: return Unmanaged.passUnretained(event)
    case .swallow: return nil
    case .consumeAndFire(let action):
        shared.onAction(action)
        return nil
    }
}

private func keyModifiers(_ flags: CGEventFlags) -> KeyModifiers {
    var modifiers: KeyModifiers = []
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    return modifiers
}
