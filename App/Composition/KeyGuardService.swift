import AppKit
import AudioToolbox
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
    static let slowQuitModeKey = "com.katikati.keyguard.slowQuitMode"
    static let slowQuitListModeKey = "com.katikati.keyguard.slowQuitListMode"
    static let slowQuitShowOverlayKey = "com.katikati.keyguard.slowQuitShowOverlay"
    static let slowQuitOverlayStyleKey = "com.katikati.keyguard.slowQuitOverlayStyle"
    static let visualizerKey = "com.katikati.keyguard.visualizer"
    static let visualizerFilterKey = "com.katikati.keyguard.visualizerFilter"
    static let visualizerStyleKey = "com.katikati.keyguard.visualizerStyle"
    static let visualizerLingerKey = "com.katikati.keyguard.visualizerLinger"
    static let visualizerFontSizeKey = "com.katikati.keyguard.visualizerFontSize"
    static let visualizerMouseClicksKey = "com.katikati.keyguard.visualizerMouseClicks"
    static let capsProtectionKey = "com.katikati.keyguard.capsHold"
    static let capsProtectionModeKey = "com.katikati.keyguard.capsMode"
    static let capsProtectionThresholdKey = "com.katikati.keyguard.capsThreshold"
    static let finderKeysKey = "com.katikati.keyguard.finderKeys"
    static let passthroughAppsKey = "com.katikati.keyguard.passthroughApps"
    static let snippetExpansionKey = "com.katikati.snippets.expand"
    /// Phase 12: a cleaning lock's deadline, persisted so a crash mid-lock cannot leave the keyboard
    /// disabled until ⌃⌥⌘P (see `CleaningLock.launchDecision`).
    static let cleaningEndKey = "com.katikati.keyguard.cleaningEnd"

    @Published private(set) var isPaused = UserDefaults.standard.bool(forKey: KeyGuardService.pauseKey)
    var onCommandBarToggle: (() -> Void)?
    @Published private(set) var isSlowQuitEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.slowQuitKey)
    /// Hold threshold in seconds; persisted, clamped to a sane range.
    @Published private(set) var slowQuitDuration: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.slowQuitDurationKey)
        return stored > 0 ? min(max(stored, 0.2), 5) : SlowQuitTiming().threshold
    }()
    /// Comma-separated bundle IDs that quit instantly instead of on hold (or only protected apps when inverted).
    @Published private(set) var slowQuitExceptions = UserDefaults.standard.string(forKey: KeyGuardService.slowQuitExceptionsKey) ?? ""
    @Published private(set) var slowQuitMode: SlowQuitMode = {
        SlowQuitMode(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.slowQuitModeKey) ?? "") ?? .hold
    }()
    @Published private(set) var slowQuitListMode: SlowQuitListMode = {
        SlowQuitListMode(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.slowQuitListModeKey) ?? "") ?? .allExceptListed
    }()
    @Published private(set) var slowQuitShowOverlay: Bool = {
        if UserDefaults.standard.object(forKey: KeyGuardService.slowQuitShowOverlayKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: KeyGuardService.slowQuitShowOverlayKey)
    }()
    @Published private(set) var slowQuitOverlayStyle: SlowQuitOverlayStyle = {
        SlowQuitOverlayStyle(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.slowQuitOverlayStyleKey) ?? "") ?? .ring
    }()
    /// Phase 24d: the key visualizer. Off by default (owner override); keycaps are never logged or saved.
    @Published private(set) var isVisualizerEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.visualizerKey)
    @Published private(set) var visualizerFilter: KeyVisualizerFilter = {
        KeyVisualizerFilter(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.visualizerFilterKey) ?? "") ?? .allKeys
    }()
    @Published private(set) var visualizerStyle: KeyVisualizerStyle = {
        KeyVisualizerStyle(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.visualizerStyleKey) ?? "") ?? .glassCapsule
    }()
    @Published private(set) var visualizerLinger: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.visualizerLingerKey)
        return stored > 0 ? min(max(stored, 0.5), 4.0) : 1.5
    }()
    @Published private(set) var visualizerFontSize: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.visualizerFontSizeKey)
        return stored > 0 ? min(max(stored, 12), 28) : 15
    }()
    @Published private(set) var visualizerMouseClicks = UserDefaults.standard.bool(forKey: KeyGuardService.visualizerMouseClicksKey)
    @Published var visualizerPositionUnlocked = false
    /// 53a: a quick Caps Lock tap does nothing, a short hold (or double-tap) toggles. Off by default.
    @Published private(set) var isCapsProtectionEnabled = UserDefaults.standard.bool(forKey: KeyGuardService.capsProtectionKey)
    @Published private(set) var capsProtectionMode: CapsLockProtectionMode = {
        CapsLockProtectionMode(rawValue: UserDefaults.standard.string(forKey: KeyGuardService.capsProtectionModeKey) ?? "") ?? .hold
    }()
    @Published private(set) var capsProtectionThreshold: Double = {
        let stored = UserDefaults.standard.double(forKey: KeyGuardService.capsProtectionThresholdKey)
        return stored > 0 ? min(max(stored, 0.10), 0.50) : 0.15
    }()
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
    private var doubleTapTiming = SlowQuitDoubleTapTiming()
    private var doubleTapTimeoutWork: DispatchWorkItem?
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

    func setSlowQuitMode(_ mode: SlowQuitMode) {
        guard mode != slowQuitMode else { return }
        endHold()
        doubleTapTiming.reset()
        doubleTapTimeoutWork?.cancel()
        doubleTapTimeoutWork = nil
        slowQuitMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.slowQuitModeKey)
        refresh()
    }

    func setSlowQuitListMode(_ mode: SlowQuitListMode) {
        guard mode != slowQuitListMode else { return }
        slowQuitListMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.slowQuitListModeKey)
        refresh()
    }

    func setSlowQuitShowOverlay(_ show: Bool) {
        guard show != slowQuitShowOverlay else { return }
        slowQuitShowOverlay = show
        UserDefaults.standard.set(show, forKey: Self.slowQuitShowOverlayKey)
        if !show { overlay?.hide() }
    }

    func setSlowQuitOverlayStyle(_ style: SlowQuitOverlayStyle) {
        guard style != slowQuitOverlayStyle else { return }
        slowQuitOverlayStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.slowQuitOverlayStyleKey)
    }

    func setVisualizer(_ on: Bool) {
        guard on != isVisualizerEnabled else { return }
        isVisualizerEnabled = on
        UserDefaults.standard.set(on, forKey: Self.visualizerKey)
        refresh()
    }

    func setVisualizerFilter(_ filter: KeyVisualizerFilter) {
        guard filter != visualizerFilter else { return }
        visualizerFilter = filter
        UserDefaults.standard.set(filter.rawValue, forKey: Self.visualizerFilterKey)
        refresh()
    }

    func setVisualizerStyle(_ style: KeyVisualizerStyle) {
        guard style != visualizerStyle else { return }
        visualizerStyle = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.visualizerStyleKey)
        refreshKeycaps()
    }

    func setVisualizerLinger(_ seconds: Double) {
        let clamped = min(max(seconds, 0.5), 4.0)
        guard abs(visualizerLinger - clamped) > 0.01 else { return }
        visualizerLinger = clamped
        UserDefaults.standard.set(clamped, forKey: Self.visualizerLingerKey)
        refresh()
    }

    func setVisualizerFontSize(_ size: Double) {
        let clamped = min(max(size, 12), 28)
        guard abs(visualizerFontSize - clamped) > 0.1 else { return }
        visualizerFontSize = clamped
        UserDefaults.standard.set(clamped, forKey: Self.visualizerFontSizeKey)
        refreshKeycaps()
    }

    func setVisualizerMouseClicks(_ on: Bool) {
        guard on != visualizerMouseClicks else { return }
        visualizerMouseClicks = on
        UserDefaults.standard.set(on, forKey: Self.visualizerMouseClicksKey)
        refresh()
    }

    func setVisualizerPositionUnlocked(_ unlocked: Bool) {
        visualizerPositionUnlocked = unlocked
        let overlay = keyOverlay ?? KeyVisualizerController()
        keyOverlay = overlay
        overlay.setPositionUnlocked(unlocked, config: currentVisualizerConfig())
    }

    func resetVisualizerPosition() {
        keyOverlay?.resetPosition()
    }

    private func currentVisualizerConfig() -> KeyVisualizerConfig {
        KeyVisualizerConfig(
            filter: visualizerFilter,
            style: visualizerStyle,
            lingerDuration: visualizerLinger,
            fontSize: visualizerFontSize,
            showMouseClicks: visualizerMouseClicks,
            isPositionUnlocked: visualizerPositionUnlocked
        )
    }

    func setCapsProtection(_ on: Bool) {
        guard on != isCapsProtectionEnabled else { return }
        isCapsProtectionEnabled = on
        UserDefaults.standard.set(on, forKey: Self.capsProtectionKey)
        refresh()
    }

    func setCapsProtectionMode(_ mode: CapsLockProtectionMode) {
        guard mode != capsProtectionMode else { return }
        capsProtectionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.capsProtectionModeKey)
        refresh()
    }

    func setCapsProtectionThreshold(_ seconds: Double) {
        let clamped = min(max(seconds, 0.10), 0.50)
        guard abs(capsProtectionThreshold - clamped) > 0.005 else { return }
        capsProtectionThreshold = clamped
        UserDefaults.standard.set(clamped, forKey: Self.capsProtectionThresholdKey)
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

    /// The SlowQuit allow/deny view the pipeline sees.
    var slowQuitPolicy: SlowQuitPolicy {
        let listed = Set(slowQuitExceptions
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init))
        switch slowQuitListMode {
        case .allExceptListed:
            return SlowQuitPolicy(deny: listed)
        case .onlyListedApps:
            return SlowQuitPolicy(allow: listed)
        }
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
        shared.setVisualizer(enabled: isVisualizerEnabled, filter: visualizerFilter, linger: visualizerLinger)
        // Toggling Caps Lock needs a posted key event; without that permission the guard must stay inert
        // rather than swallowing the key the user cannot toggle any other way.
        shared.setCapsProtection(
            enabled: isCapsProtectionEnabled && CGPreflightPostEventAccess(),
            mode: capsProtectionMode,
            threshold: capsProtectionThreshold
        )
        let snippetItems = TextSnippetStore.parse(UserDefaults.standard.string(forKey: CustomCommand.snippetsKey) ?? "")
        shared.setSnippets(enabled: isSnippetExpansionEnabled, items: snippetItems)
        let keyAudioOn = UserDefaults.standard.bool(forKey: KeyAudioSoundpack.enabledKey)
        let doubleTapCmdOn = UserDefaults.standard.bool(forKey: "com.katikati.keyguard.doubleTapCmd")
        shared.keyAudioEnabled = keyAudioOn
        shared.keyAudioSoundpack = KeyAudioSoundpack.current()
        let anyOn = isPaused || isSlowQuitEnabled || isVisualizerEnabled || isCapsProtectionEnabled
            || isFinderKeysEnabled || isSnippetExpansionEnabled || keyAudioOn || doubleTapCmdOn
        if anyOn, !started { start() } else if !anyOn, started { stop() }
        updateVisualizerTimer()
    }

    private func makeState() -> KeyGuardState {
        let excluded = TextSnippetStore.parseExcludedApps(UserDefaults.standard.string(forKey: TextSnippetStore.excludedAppsKey) ?? "")
        return KeyGuardState(
            paused: isPaused,
            slowQuitEnabled: isSlowQuitEnabled,
            slowQuitApplies: slowQuitPolicy.applies(to: frontmostBundleID),
            slowQuitHolding: false,
            unlockKey: keyGuardUnlock,
            slowQuitPassthrough: passthroughPolicy.applies(to: frontmostBundleID),
            finderKeysActive: isFinderKeysEnabled && frontmostBundleID == "com.apple.finder",
            snippetsActive: isSnippetExpansionEnabled && !SnippetExpander.isIgnored(bundleID: frontmostBundleID, extraExcluded: excluded)
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
        shared.onModifierDoubleTap = { [weak self] mod in
            DispatchQueue.main.async {
                if mod == .command {
                    self?.onCommandBarToggle?()
                }
            }
        }
        let thread = Thread { [shared, weak self] in
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                   (1 << CGEventType.keyUp.rawValue) |
                                   (1 << CGEventType.flagsChanged.rawValue)
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
        doubleTapTimeoutWork?.cancel()
        doubleTapTimeoutWork = nil
        doubleTapTiming.reset()
        overlay?.hide()
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
        guard let app = NSWorkspace.shared.frontmostApplication,
              slowQuitPolicy.applies(to: app.bundleIdentifier) else { return }

        if slowQuitMode == .doubleTap {
            doubleTapTimeoutWork?.cancel()
            doubleTapTimeoutWork = nil
            switch doubleTapTiming.registerTap() {
            case .fire:
                overlay?.hide()
                if !app.terminate() { log.warning("SlowQuit could not terminate \(app.bundleIdentifier ?? "?")") }
            case .armed:
                if slowQuitShowOverlay {
                    let overlay = self.overlay ?? SlowQuitOverlayController()
                    self.overlay = overlay
                    overlay.show(app: app, progress: 0.5, style: slowQuitOverlayStyle, mode: .doubleTap)
                }
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        self?.doubleTapTiming.reset()
                        self?.doubleTapTimeoutWork = nil
                        self?.overlay?.hide()
                    }
                }
                doubleTapTimeoutWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapTiming.window, execute: work)
            }
            return
        }

        guard holdStartedAt == nil else { return }
        holdStartedAt = Date()
        holdTarget = app
        if slowQuitShowOverlay {
            let overlay = self.overlay ?? SlowQuitOverlayController()
            self.overlay = overlay
            overlay.show(app: app, progress: 0, style: slowQuitOverlayStyle, mode: .hold)
        }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let startedAt = holdStartedAt else { return }
        let elapsed = -startedAt.timeIntervalSinceNow
        if elapsed >= slowQuitDuration { fireHold() }
        else if slowQuitShowOverlay {
            overlay?.update(progress: SlowQuitTiming(threshold: slowQuitDuration).progress(heldFor: elapsed))
        }
    }

    private func fireHold() {
        guard let app = holdTarget else { endHold(); return }
        endHold()
        if !app.terminate() { log.warning("SlowQuit could not terminate \(app.bundleIdentifier ?? "?")") }
    }

    private func endHold() {
        if slowQuitMode == .doubleTap { return }
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
        guard isSnippetExpansionEnabled, !IsSecureEventInputEnabled(), CGPreflightPostEventAccess() else { return }
        let pasteboard = NSPasteboard.general
        let priorClipboard = pasteboard.string(forType: .string) ?? ""
        let expanded = SnippetVariableExpander.expand(expansion.replacement, clipboard: priorClipboard)
        pasteboard.clearContents()
        pasteboard.setString(expanded.text, forType: .string)
        let ours = pasteboard.changeCount
        let deleteCount = expansion.swallowedDelimiter ? expansion.triggerCount : max(0, expansion.triggerCount - 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, pasteboard.changeCount == ours else { return }
                self.postKey(51, times: deleteCount)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self, pasteboard.changeCount == ours else { return }
                        self.postCommandV()
                        if expanded.cursorLeftArrows > 0 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) { [weak self] in
                                MainActor.assumeIsolated {
                                    self?.postKey(123, times: expanded.cursorLeftArrows)
                                }
                            }
                        }
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
        if symbols.isEmpty && !visualizerPositionUnlocked {
            keyOverlay?.hide()
            return
        }
        let overlay = keyOverlay ?? KeyVisualizerController()
        keyOverlay = overlay
        overlay.show(symbols, config: currentVisualizerConfig())
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
    private var visualizerFilter: KeyVisualizerFilter = .allKeys
    private var visualizerLinger: TimeInterval = 1.5
    private var capsProtectionOn = false
    private var capsProtectionMode: CapsLockProtectionMode = .hold
    private var capsGuard = CapsLockGuard()
    private var finderMap = FinderKeyMap()
    private var snippetsOn = false
    private var snippetExpander = SnippetExpander()
    var onExpand: ((SnippetExpander.Expansion) -> Void)?
    private var lastFlags: CGEventFlags = []
    private var doubleTapDetector = KeyModifierDoubleTapDetector()
    var onModifierDoubleTap: ((ModifierKey) -> Void)?
    var keyAudioEnabled: Bool = false
    var keyAudioSoundpack: KeyAudioSoundpack = .mechanicalClick
    var isCallActive: Bool = false
    /// Marks the caps events we post ourselves so they pass back through this tap untouched.
    static let syntheticTag: Int64 = 0x4B41544931 // "KATI1"
    var port: CFMachPort?
    var onAction: (KeyGuardAction) -> Void = { _ in }

    func setVisualizer(enabled: Bool, filter: KeyVisualizerFilter = .allKeys, linger: TimeInterval = 1.5) {
        lock.lock()
        visualizerOn = enabled
        visualizerFilter = filter
        visualizerLinger = linger
        if !enabled { caps.clear() }
        lock.unlock()
    }

    func currentVisualizerFilter() -> KeyVisualizerFilter {
        lock.lock(); defer { lock.unlock() }
        return visualizerFilter
    }

    /// Coalesces repeats and drops the oldest past the cap. Idle for >`visualizerLinger` clears it.
    /// Under secure input (a password field has focus) nothing is kept and the strip is cleared; the
    /// probe is an autoclosure so it is read only while the visualizer is on. macOS has no change notification.
    func record(symbol: String, secureInput: @autoclosure () -> Bool = IsSecureEventInputEnabled()) {
        lock.lock(); defer { lock.unlock() }
        guard visualizerOn else { return }
        if secureInput() { caps.clear(); return }
        caps.push(symbol: symbol, at: Date())
        let now = Date()
        if now.timeIntervalSince(capsPrunedAt) > 0.25 {
            caps.prune(olderThan: visualizerLinger, now: now)
            capsPrunedAt = now
        }
    }

    func keycaps() -> [KeycapVisual] {
        lock.lock(); defer { lock.unlock() }
        if visualizerOn {
            caps.prune(olderThan: visualizerLinger, now: Date())
        }
        return caps.items
    }
    func clearKeycaps() { lock.lock(); caps.clear(); lock.unlock() }

    // MARK: 53a Caps Lock protection

    func setCapsProtection(enabled: Bool, mode: CapsLockProtectionMode = .hold, threshold: TimeInterval = 0.15) {
        lock.lock()
        capsProtectionOn = enabled
        capsProtectionMode = mode
        capsGuard.threshold = threshold
        if !enabled { capsGuard.reset() }
        lock.unlock()
    }

    /// Handles physical Caps Lock (`keyCode == 57`) from `.flagsChanged` or `.keyDown`/`.keyUp`.
    /// Returns true when the event was swallowed by the guard.
    func handleCapsLock(isDown: Bool) -> Bool {
        lock.lock()
        guard capsProtectionOn, CGPreflightPostEventAccess() else { lock.unlock(); return false }
        let mode = capsProtectionMode
        if mode == .doubleTap {
            let shouldFire = isDown ? capsGuard.registerDoubleTap() : false
            lock.unlock()
            if shouldFire { postSyntheticCapsLock() }
            return true
        }
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
        guard fire else { return }
        postSyntheticCapsLock()
    }

    private func postSyntheticCapsLock() {
        guard let source = CGEventSource(stateID: .combinedSessionState),
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

    func setSnippets(enabled: Bool, items: [TextSnippetItem]) {
        lock.lock()
        snippetsOn = enabled
        snippetExpander.setSnippets(items)
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

    func decide(_ event: KeyGuardEvent, isRepeat: Bool = false) -> (decision: KeyGuardDecision, state: KeyGuardState) {
        lock.lock(); defer { lock.unlock() }
        var effectiveState = state
        effectiveState.secureInputActive = IsSecureEventInputEnabled()
        let outcome = KeyGuardPipeline.reduce(event, state: effectiveState, isRepeat: isRepeat)
        state = outcome.state
        guard state.finderKeysActive else {
            finderMap.reset()
            return outcome
        }
        // Pause and SlowQuit win; the Finder map only sees what the pipeline lets through.
        guard case .passThrough = outcome.decision else { return outcome }
        return (finderMap.handle(event), state)
    }

    func handleFlagsChanged(flags: CGEventFlags, at date: Date = Date()) {
        lock.lock()
        let diff = flags.symmetricDifference(lastFlags)
        lastFlags = flags
        let handler = onModifierDoubleTap
        lock.unlock()

        let mod: ModifierKey? = {
            if diff.contains(.maskCommand) { return .command }
            if diff.contains(.maskAlternate) { return .option }
            if diff.contains(.maskControl) { return .control }
            if diff.contains(.maskShift) { return .shift }
            return nil
        }()

        guard let mod else { return }
        let isDown: Bool = {
            switch mod {
            case .command: return flags.contains(.maskCommand)
            case .option: return flags.contains(.maskAlternate)
            case .control: return flags.contains(.maskControl)
            case .shift: return flags.contains(.maskShift)
            }
        }()

        lock.lock()
        let step = doubleTapDetector.registerModifier(modifier: mod, isDown: isDown, at: date)
        lock.unlock()

        if case .doubleTap(let tapped) = step {
            handler?(tapped)
        }
    }

    func registerInterveningKey() {
        lock.lock(); defer { lock.unlock() }
        doubleTapDetector.registerInterveningKey()
    }

    func handleKeyAudio(event: KeyGuardEvent) {
        lock.lock()
        let enabled = keyAudioEnabled
        let callActive = isCallActive
        let paused = state.paused
        lock.unlock()

        guard KeyAudioPolicy.shouldTrigger(
            event: event,
            enabled: enabled,
            isSecureInput: IsSecureEventInputEnabled(),
            isCallActive: callActive,
            isPaused: paused
        ) else { return }

        AudioServicesPlaySystemSound(1104)
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
    if type == .flagsChanged {
        if event.getIntegerValueField(.eventSourceUserData) == KeyGuardShared.syntheticTag {
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        if code == CapsLockGuard.keyCode {
            let isDown = event.flags.contains(.maskAlphaShift)
            if shared.handleCapsLock(isDown: isDown) { return nil }
        }
        shared.handleFlagsChanged(flags: event.flags)
        let outcome = shared.decide(.flagsChanged(modifiers: keyModifiers(event.flags)))
        if case .consumeAndFire(let action) = outcome.decision {
            shared.onAction(action)
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
    // Our own posted Caps Lock toggle: let it through without feeding the pipeline.
    if event.getIntegerValueField(.eventSourceUserData) == KeyGuardShared.syntheticTag {
        return Unmanaged.passUnretained(event)
    }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    if code == CapsLockGuard.keyCode, shared.handleCapsLock(isDown: type == .keyDown) { return nil }
    let modifiers = keyModifiers(event.flags)
    let keyEvent: KeyGuardEvent = type == .keyDown ? .keyDown(keyCode: code, modifiers: modifiers)
                                                  : .keyUp(keyCode: code, modifiers: modifiers)
    if type == .keyDown {
        shared.registerInterveningKey()
        shared.handleKeyAudio(event: keyEvent)
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
    if type == .keyDown, let symbol = keycapSymbol(event, code: code, filter: shared.currentVisualizerFilter()) {
        shared.record(symbol: symbol)
    }
    let isRepeat = type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let outcome = shared.decide(keyEvent, isRepeat: isRepeat)
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

/// The character a keyDown produced ("a", "⌘A", "→"), or nil when filtered out or non-printable.
/// The visualizer only ever holds these — never a full keystroke log.
private func keycapSymbol(_ event: CGEvent, code: UInt16, filter: KeyVisualizerFilter) -> String? {
    var count = 0
    var buffer = [UniChar](repeating: 0, count: 4)
    event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &count, unicodeString: &buffer)
    let text = count > 0 ? String(utf16CodeUnits: buffer, count: count) : nil
    return KeyVisualizerSymbol.format(
        keyCode: code,
        modifiers: keyModifiers(event.flags),
        characters: text,
        filter: filter
    )
}

private func keyModifiers(_ flags: CGEventFlags) -> KeyModifiers {
    var modifiers: KeyModifiers = []
    if flags.contains(.maskCommand) { modifiers.insert(.command) }
    if flags.contains(.maskAlternate) { modifiers.insert(.option) }
    if flags.contains(.maskControl) { modifiers.insert(.control) }
    if flags.contains(.maskShift) { modifiers.insert(.shift) }
    return modifiers
}
