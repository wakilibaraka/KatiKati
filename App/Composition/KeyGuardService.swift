import AppKit
import Carbon.HIToolbox
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
    static let visualizerKey = "com.katikati.keyguard.visualizer"
    static let capsProtectionKey = "com.katikati.keyguard.capsHold"
    static let finderKeysKey = "com.katikati.keyguard.finderKeys"
    static let passthroughAppsKey = "com.katikati.keyguard.passthroughApps"
    static let snippetExpansionKey = "com.katikati.snippets.expand"
    /// Phase 12: a cleaning lock's deadline, persisted so a crash mid-lock cannot leave the keyboard
    /// disabled until ⌃⌥⌘P (see `CleaningLock.launchDecision`).
    static let cleaningEndKey = "com.katikati.keyguard.cleaningEnd"

    @Published private(set) var isPaused = UserDefaults.standard.bool(forKey: KeyGuardService.pauseKey)
    @Published private(set) var isSlowQuitEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.slowQuitKey)
    /// Hold threshold in seconds; persisted, clamped to a sane range.
    @Published private(set) var slowQuitDuration: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.slowQuitDurationKey)
        return stored > 0 ? min(max(stored, 0.2), 5) : SlowQuitTiming().threshold
    }()
    /// Comma-separated bundle IDs that quit instantly instead of on hold.
    @Published private(set) var slowQuitExceptions = UserDefaults.standard.string(forKey: KeyGuardService.slowQuitExceptionsKey) ?? ""
    /// Phase 24d: the key visualizer. Off by default (owner override); keycaps are never logged or saved.
    @Published private(set) var isVisualizerEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.visualizerKey)
    /// 53a: a quick Caps Lock tap does nothing, a short hold toggles. Off by default like the other guards.
    @Published private(set) var isCapsProtectionEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.capsProtectionKey)
    /// 53b: ⌘X / ⌘V in Finder act like cut / move. Off by default.
    @Published private(set) var isFinderKeysEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.finderKeysKey)
    /// 53i: comma-separated apps whose ⌘Q stays native (remote desktops, virtual machines).
    @Published private(set) var passthroughApps = UserDefaults.standard.string(forKey: KeyGuardService.passthroughAppsKey)
        ?? SlowQuitPassthrough.defaults.joined(separator: ", ")
    /// 53c: type a snippet trigger plus a space anywhere to paste its text. Off by default.
    @Published private(set) var isSnippetExpansionEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.snippetExpansionKey)

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
    private var keyOverlay: KeyVisualizerController?
    private var visualizerTimer: Timer?

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    func setPaused(_ on: Bool) {
        guard on != isPaused else { return }
        isPaused = on
        UserDefaults.standard.set(on, forKey: Self.pauseKey)
        refresh()
    }

    func togglePause() { setPaused(!isPaused) }

    // MARK: Cleaning lock (Phase 36f)

    /// Seconds left on a timed cleaning lock, nil when none runs.
    @Published private(set) var cleaningRemaining: Int?
    private var cleaningTimer: Timer?
    private var cleaningEnd: Date?

    /// The lock's deadline is the only thing here that is reconciled at launch: the pause it uses is
    /// persisted, so a crash mid-lock used to come up locked. A window that has already passed
    /// releases it; a window still running resumes with the time left.
    init() {
        let stored = UserDefaults.standard.object(forKey: Self.cleaningEndKey) as? Date
        switch CleaningLock.launchDecision(deadline: stored, now: Date()) {
        case .resume(let seconds):
            cleaningEnd = stored
            cleaningRemaining = seconds
            startCleaningTimer()
        case .release:
            UserDefaults.standard.removeObject(forKey: Self.cleaningEndKey)
            // Only a deadline we just expired may unpause: with no deadline at all the pause is the
            // user's own (24b) and stays theirs. `stored == nil` is that case.
            if stored != nil {
                isPaused = false
                UserDefaults.standard.set(false, forKey: Self.pauseKey)
            }
        }
    }

    /// A timed pause for wiping the keyboard. Reuses the Phase 24b swallow-all + fixed ⌃⌥⌘P unlock, and
    /// frees itself when the time is up (fail-open). Asks for Input Monitoring first; false if not granted.
    @discardableResult
    func startCleaningLock(seconds: Double = CleaningLock.defaultSeconds) -> Bool {
        guard Self.hasPermission else { Self.requestPermission(); return false }
        let end = Date().addingTimeInterval(CleaningLock.clamped(seconds))
        cleaningEnd = end
        UserDefaults.standard.set(end, forKey: Self.cleaningEndKey)
        cleaningRemaining = Int(end.timeIntervalSinceNow.rounded(.up))
        setPaused(true)
        startCleaningTimer()
        return isPaused
    }

    func endCleaningLock() {
        guard cleaningEnd != nil else { return }
        cancelCleaningLock()
        setPaused(false)
    }

    private func startCleaningTimer() {
        cleaningTimer?.invalidate()
        cleaningTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cleaningTick() }
        }
    }

    /// Clears the countdown and its persisted deadline without touching the pause.
    private func cancelCleaningLock() {
        cleaningTimer?.invalidate(); cleaningTimer = nil
        cleaningEnd = nil
        cleaningRemaining = nil
        UserDefaults.standard.removeObject(forKey: Self.cleaningEndKey)
    }

    private func cleaningTick() {
        guard let end = cleaningEnd else { return }
        // Unlocked early by the chord: just clean up the countdown.
        if !isPaused { cancelCleaningLock(); return }
        let left = Int(end.timeIntervalSinceNow.rounded(.up))
        if left <= 0 { endCleaningLock() } else { cleaningRemaining = left }
    }

    func setSlowQuit(_ on: Bool) {
        guard on != isSlowQuitEnabled else { return }
        isSlowQuitEnabled = on
        UserDefaults.standard.set(on, forKey: Self.slowQuitKey)
        refresh()
    }

    func tearDown() {
        // Never leave the keyboard locked behind a quit: the paused flag is persisted.
        if cleaningEnd != nil { endCleaningLock() }
        stop()
    }

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

    func setVisualizer(_ on: Bool) {
        guard on != isVisualizerEnabled else { return }
        isVisualizerEnabled = on
        UserDefaults.standard.set(on, forKey: Self.visualizerKey)
        refresh()
    }

    func setCapsProtection(_ on: Bool) {
        guard on != isCapsProtectionEnabled else { return }
        isCapsProtectionEnabled = on
        UserDefaults.standard.set(on, forKey: Self.capsProtectionKey)
        refresh()
    }

    func setFinderKeys(_ on: Bool) {
        guard on != isFinderKeysEnabled else { return }
        isFinderKeysEnabled = on
        UserDefaults.standard.set(on, forKey: Self.finderKeysKey)
        refresh()
    }

    func setPassthroughApps(_ raw: String) {
        guard raw != passthroughApps else { return }
        passthroughApps = raw
        UserDefaults.standard.set(raw, forKey: Self.passthroughAppsKey)
        refresh()
    }

    func setSnippetExpansion(_ on: Bool) {
        guard on != isSnippetExpansionEnabled else { return }
        isSnippetExpansionEnabled = on
        UserDefaults.standard.set(on, forKey: Self.snippetExpansionKey)
        refresh()
    }

    /// The snippet editor writes through `@AppStorage`, so it calls this to re-read the triggers.
    func refreshSnippetTriggers() { refresh() }

    var passthroughPolicy: SlowQuitPassthrough { .parse(passthroughApps) }

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
        if isSlowQuitEnabled || isFinderKeysEnabled || isSnippetExpansionEnabled, frontmostObserver == nil {
            frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            frontmostObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.frontmostChanged(app) }
            }
        }
        shared.update(state: makeState())
        shared.setVisualizer(enabled: isVisualizerEnabled)
        // Toggling Caps Lock needs a posted key event; without that permission the guard must stay inert
        // rather than swallowing the key the user cannot toggle any other way.
        shared.setCapsProtection(enabled: isCapsProtectionEnabled && CGPreflightPostEventAccess())
        let triggers = SnippetExpander.triggers(from: CustomCommand.parseSnippets(
            UserDefaults.standard.string(forKey: CustomCommand.snippetsKey) ?? ""))
        shared.setSnippets(enabled: isSnippetExpansionEnabled, triggers: triggers)
        let anyOn = isPaused || isSlowQuitEnabled || isVisualizerEnabled || isCapsProtectionEnabled
            || isFinderKeysEnabled || isSnippetExpansionEnabled
        if anyOn, !started { start() } else if !anyOn, started { stop() }
        updateVisualizerTimer()
    }

    private func makeState() -> KeyGuardState {
        KeyGuardState(
            paused: isPaused,
            slowQuitEnabled: isSlowQuitEnabled,
            slowQuitApplies: slowQuitPolicy.applies(to: frontmostBundleID),
            slowQuitHolding: false,
            unlockKey: keyGuardUnlock,
            slowQuitPassthrough: passthroughPolicy.applies(to: frontmostBundleID),
            finderKeysActive: isFinderKeysEnabled && frontmostBundleID == "com.apple.finder",
            snippetsActive: isSnippetExpansionEnabled && !SnippetExpander.isIgnored(bundleID: frontmostBundleID)
        )
    }

    private func frontmostChanged(_ app: NSRunningApplication?) {
        frontmostBundleID = app?.bundleIdentifier
        guard isSlowQuitEnabled || isFinderKeysEnabled || isSnippetExpansionEnabled else { return }
        shared.update(state: makeState())
    }

    private func start() {
        guard Self.hasPermission else {
            log.warning("KeyGuard needs Input Monitoring; not starting")
            isPaused = false
            isSlowQuitEnabled = false
            isVisualizerEnabled = false
            isCapsProtectionEnabled = false
            isFinderKeysEnabled = false
            isSnippetExpansionEnabled = false
            UserDefaults.standard.set(false, forKey: Self.pauseKey)
            UserDefaults.standard.set(false, forKey: Self.slowQuitKey)
            UserDefaults.standard.set(false, forKey: Self.visualizerKey)
            UserDefaults.standard.set(false, forKey: Self.capsProtectionKey)
            UserDefaults.standard.set(false, forKey: Self.finderKeysKey)
            UserDefaults.standard.set(false, forKey: Self.snippetExpansionKey)
            shared.update(state: makeState())
            return
        }
        shared.onAction = { [weak self] action in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(action) } }
        }
        shared.onExpand = { [weak self] expansion in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.insertSnippet(expansion) } }
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
        visualizerTimer?.invalidate()
        visualizerTimer = nil
        keyOverlay?.hide()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop = tapRunLoop { CFRunLoopStop(loop) }
        tap = nil; tapRunLoop = nil; tapThread = nil; started = false
        shared.port = nil // a late tapDisabled callback must not revive a tap we stopped
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

    // MARK: - Snippet insertion (53c)

    /// Replaces the typed trigger with the expansion: the delimiter was swallowed, so the paste carries it.
    /// If another copy lands on the pasteboard before the paste goes out, the paste is cancelled.
    private func insertSnippet(_ expansion: SnippetExpander.Expansion) {
        guard isSnippetExpansionEnabled, CGPreflightPostEventAccess() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(expansion.replacement, forType: .string)
        let ours = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, pasteboard.changeCount == ours else { return }
                self.postKey(51, times: expansion.triggerCount)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, pasteboard.changeCount == ours else { return }
                        self.postCommandV()
                    }
                }
            }
        }
    }

    private func postKey(_ code: CGKeyCode, times: Int) {
        guard times > 0, let source = CGEventSource(stateID: .combinedSessionState) else { return }
        for _ in 0..<times {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return }
            postTagged(down); postTagged(up)
        }
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
        down.flags = .maskCommand; up.flags = .maskCommand
        postTagged(down); postTagged(up)
    }

    /// Our own events carry the tag, so the tap lets them through without feeding the guards again.
    private func postTagged(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: KeyGuardShared.syntheticTag)
        event.post(tap: .cghidEventTap)
    }

    // MARK: - Key visualizer (24d)

    /// The tap thread only appends to a bounded buffer; one 20 Hz main-actor read paints it, so typing
    /// never hops threads per keystroke and the overlay can never grow unbounded.
    private func updateVisualizerTimer() {
        if isVisualizerEnabled, started, visualizerTimer == nil {
            visualizerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshKeycaps() }
            }
        } else if (!isVisualizerEnabled || !started), let timer = visualizerTimer {
            timer.invalidate()
            visualizerTimer = nil
            keyOverlay?.hide()
        }
    }

    private func refreshKeycaps() {
        let symbols = shared.keycaps().map(\.symbol)
        if symbols.isEmpty {
            keyOverlay?.hide()
            return
        }
        let overlay = keyOverlay ?? KeyVisualizerController()
        keyOverlay = overlay
        overlay.show(symbols)
    }
}

/// State shared with the tap thread. Everything the callback touches is lock-protected and O(1).
/// `slowQuitHolding` is owned by the pipeline: `update` preserves it, so a settings/frontmost push
/// in the middle of a hold cannot cancel the keyUp that fires the quit. The keycaps the visualizer
/// paints live here too — bounded by `KeyVisualizerBuffer`, never logged, never persisted.
final class KeyGuardShared: @unchecked Sendable {
    private let lock = NSLock()
    private var state = KeyGuardState(unlockKey: keyGuardUnlock)
    private var caps = KeyVisualizerBuffer()
    private var capsPrunedAt = Date.distantPast
    private var visualizerOn = false
    private var capsProtectionOn = false
    private var capsGuard = CapsLockGuard()
    private var finderMap = FinderKeyMap()
    private var snippetsOn = false
    private var snippetExpander = SnippetExpander()
    var onExpand: ((SnippetExpander.Expansion) -> Void)?
    /// Marks the caps events we post ourselves so they pass back through this tap untouched.
    static let syntheticTag: Int64 = 0x4B41544931 // "KATI1"
    var port: CFMachPort?
    var onAction: (KeyGuardAction) -> Void = { _ in }

    func setVisualizer(enabled: Bool) {
        lock.lock()
        visualizerOn = enabled
        if !enabled { caps.clear() }
        lock.unlock()
    }

    /// Coalesces repeats and drops the oldest past the cap. Idle for >1.5 s clears it (the overlay hides).
    /// Under secure input (a password field has focus) nothing is kept and the strip is cleared; the
    /// probe is an autoclosure so it is read only while the visualizer is on. macOS has no change notification.
    func record(symbol: String, secureInput: @autoclosure () -> Bool = IsSecureEventInputEnabled()) {
        lock.lock(); defer { lock.unlock() }
        guard visualizerOn else { return }
        if secureInput() { caps.clear(); return }
        caps.push(symbol: symbol, at: Date())
        let now = Date()
        if now.timeIntervalSince(capsPrunedAt) > 0.5 {
            caps.prune(olderThan: 1.5, now: now)
            capsPrunedAt = now
        }
    }

    func keycaps() -> [KeycapVisual] { lock.lock(); defer { lock.unlock() }; return caps.items }
    func clearKeycaps() { lock.lock(); caps.clear(); lock.unlock() }

    // MARK: 53a Caps Lock protection

    func setCapsProtection(enabled: Bool) {
        lock.lock()
        capsProtectionOn = enabled
        if !enabled { capsGuard.reset() }
        lock.unlock()
    }

    /// True when the caps event is ours to handle (always swallowed while the guard is on).
    func handleCapsLock(isDown: Bool) -> Bool {
        lock.lock()
        // Re-checked per press: if posting was revoked at runtime, swallowing would kill the key.
        guard capsProtectionOn, CGPreflightPostEventAccess() else { lock.unlock(); return false }
        let schedule = isDown ? capsGuard.press() : false
        if !isDown { capsGuard.release() }
        let threshold = capsGuard.threshold
        lock.unlock()
        if schedule {
            DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + threshold) { [weak self] in
                self?.fireCapsLockIfHeld()
            }
        }
        return true
    }

    private func fireCapsLockIfHeld() {
        lock.lock()
        let fire = capsProtectionOn && capsGuard.fireIfStillHeld()
        lock.unlock()
        guard fire, let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CapsLockGuard.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CapsLockGuard.keyCode, keyDown: false) else { return }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticTag)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: 53c Snippet expansion

    func setSnippets(enabled: Bool, triggers: [String: String]) {
        lock.lock()
        snippetsOn = enabled
        snippetExpander.setTriggers(triggers)
        lock.unlock()
    }

    /// Feeds one typed character. Nil while off, in an ignored app, or under secure input — and then
    /// the word is dropped, so nothing typed in a password field can complete a trigger later.
    func feedSnippet(_ text: String, secureInput: @autoclosure () -> Bool = IsSecureEventInputEnabled())
        -> SnippetExpander.Expansion? {
        lock.lock(); defer { lock.unlock() }
        guard snippetsOn, state.snippetsActive else { snippetExpander.reset(); return nil }
        if secureInput() { snippetExpander.reset(); return nil }
        return snippetExpander.feed(text)
    }

    func snippetBackspace() {
        lock.lock(); snippetExpander.backspace(); lock.unlock()
    }

    func resetSnippetWord() {
        lock.lock(); snippetExpander.reset(); lock.unlock()
    }

    func update(state newState: KeyGuardState) {
        lock.lock()
        var merged = newState
        merged.slowQuitHolding = state.slowQuitHolding
        state = merged
        lock.unlock()
    }

    func reset() {
        lock.lock()
        state = KeyGuardState(unlockKey: keyGuardUnlock)
        caps.clear()
        capsGuard.reset()
        finderMap.reset()
        snippetExpander.reset()
        lock.unlock()
    }

    func decide(_ event: KeyGuardEvent) -> (decision: KeyGuardDecision, state: KeyGuardState) {
        lock.lock(); defer { lock.unlock() }
        let outcome = KeyGuardPipeline.reduce(event, state: state)
        state = outcome.state
        guard state.finderKeysActive else {
            finderMap.reset()
            return outcome
        }
        // Pause and SlowQuit win; the Finder map only sees what the pipeline lets through.
        guard case .passThrough = outcome.decision else { return outcome }
        return (finderMap.handle(event), state)
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
    // Our own posted Caps Lock toggle: let it through without feeding the pipeline.
    if event.getIntegerValueField(.eventSourceUserData) == KeyGuardShared.syntheticTag {
        return Unmanaged.passUnretained(event)
    }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    if shared.handleCapsLock(isDown: type == .keyDown) { return nil }
    if type == .keyDown {
        if code == 51 {
            shared.snippetBackspace()
        } else if let text = typedText(event) {
            if let expansion = shared.feedSnippet(text) {
                shared.onExpand?(expansion)
                return nil // the delimiter is part of the paste
            }
        } else {
            shared.resetSnippetWord()
        }
    }
    let modifiers = keyModifiers(event.flags)
    let keyEvent: KeyGuardEvent = type == .keyDown ? .keyDown(keyCode: code, modifiers: modifiers)
                                                  : .keyUp(keyCode: code, modifiers: modifiers)
    if type == .keyDown, let symbol = keycapSymbol(event) { shared.record(symbol: symbol) }
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
    case let .rewrite(code, extra):
        event.setIntegerValueField(.keyboardEventKeycode, value: Int64(code))
        event.flags = event.flags.union(cgFlags(extra))
        return Unmanaged.passUnretained(event)
    }
}

private func cgFlags(_ modifiers: KeyModifiers) -> CGEventFlags {
    var flags: CGEventFlags = []
    if modifiers.contains(.command) { flags.insert(.maskCommand) }
    if modifiers.contains(.option) { flags.insert(.maskAlternate) }
    if modifiers.contains(.control) { flags.insert(.maskControl) }
    if modifiers.contains(.shift) { flags.insert(.maskShift) }
    return flags
}

/// The plain character a keyDown produced, or nil when it was a shortcut or a non-typing key
/// (arrows, escape, function keys). Only used to build the snippet word, never logged.
private func typedText(_ event: CGEvent) -> String? {
    let flags = event.flags
    guard !flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate) else { return nil }
    var count = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &count, unicodeString: &buffer)
    guard count == 1 else { return nil }
    let text = String(utf16CodeUnits: buffer, count: 1)
    guard let scalar = text.unicodeScalars.first, scalar.value >= 0x20 else { return nil }
    return text
}

/// The character a keyDown produced ("a", "⌘A", "→"), or nil for a key that shows nothing worth
/// putting on a keycap. The visualizer only ever holds these — never a full keystroke log.
private func keycapSymbol(_ event: CGEvent) -> String? {
    var count = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &count, unicodeString: &buffer)
    guard count > 0 else { return nil }
    let text = String(utf16CodeUnits: buffer, count: count)
    let mods = keyModifiers(event.flags)
    var prefix = ""
    if mods.contains(.control) { prefix += "⌃" }
    if mods.contains(.option) { prefix += "⌥" }
    if mods.contains(.shift) { prefix += "⇧" }
    if mods.contains(.command) { prefix += "⌘" }
    return prefix.isEmpty ? text : prefix + text
}

private func keyModifiers(_ flags: CGEventFlags) -> KeyModifiers {
    var modifiers: KeyModifiers = []
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    return modifiers
}
