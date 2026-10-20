import AppKit
import CoreGraphics
import OSLog

/// Phase 9e — Caps Lock as Hyper (⌃⌥⇧⌘). **Off by default.**
///
/// How it works: while on, `hidutil` remaps Caps Lock → F18 (restoring the user's own remaps on turn-off
/// and on quit), and a key-events-only `CGEventTap` on its own thread feeds `HyperkeyEngine`; a bound
/// Hyper+key is consumed and fired on the main thread. This is the one deliberate exception to the
/// "no resident global event monitors" rule (documented in HYBRID_PLAN): it listens to **keyboard**
/// events only — never mouse — exists only while the feature is on, and its callback is O(1).
/// Needs the Input Monitoring permission, requested with an explanation, never silently.
@MainActor
final class HyperkeyService {
    var onAction: (ShortcutAction) -> Void = { _ in }
    private let log = Logger(subsystem: "com.caye.macosdockcc.v2", category: "hyperkey")

    private var enabled = false
    private var bindings: [UInt16: ShortcutAction] = [:]
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var tap: CFMachPort?
    private let shared = HyperkeyShared()
    private var remapApplied = false

    static var hasPermission: Bool { CGPreflightListenEventAccess() }
    @discardableResult static func requestPermission() -> Bool { CGRequestListenEventAccess() }

    func configure(enabled: Bool, bindings: [UInt16: ShortcutAction]) {
        self.bindings = bindings
        shared.setBindings(bindings)
        if !enabled, !checkedStaleRemap { clearStaleRemap() }
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        if enabled { start() } else { stop() }
    }

    /// `kill -9` skips `restoreRemap`, and `hidutil` keeps the Caps Lock → F18 entry until logout; with Hyperkey
    /// off nothing would handle F18, so Caps Lock would stay dead. Checked once per launch, only while off.
    private var checkedStaleRemap = false
    private func clearStaleRemap() {
        checkedStaleRemap = true
        let current = Self.currentMapping()
        guard current.contains(HyperkeyRemap.ours) else { return }
        _ = Self.setMapping(HyperkeyRemap.removing(from: current))
    }

    func tearDown() { enabled = false; stop() }

    // MARK: start / stop

    private func start() {
        guard Self.hasPermission else {
            log.warning("Hyperkey needs Input Monitoring; not starting")
            enabled = false
            return
        }
        applyRemap()
        shared.onFire = { [weak self] code in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.fire(code) } }
        }
        let thread = Thread { [shared, weak self] in
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            let refcon = Unmanaged.passUnretained(shared).toOpaque()
            guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                               options: .defaultTap, eventsOfInterest: mask,
                                               callback: hyperkeyTapCallback, userInfo: refcon) else {
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
        thread.name = "com.katikati.hyperkey"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
    }

    private func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let loop = tapRunLoop { CFRunLoopStop(loop) }
        tap = nil; tapRunLoop = nil; tapThread = nil
        shared.port = nil // a late tapDisabled callback must not revive a tap we stopped
        shared.reset()
        restoreRemap()
    }

    private func tapFailed() {
        log.error("Could not create the keyboard event tap")
        enabled = false
        restoreRemap()
    }

    private func fire(_ code: UInt16) {
        guard enabled, let action = bindings[code] else { return }
        onAction(action)
    }

    // MARK: Caps Lock → F18 (`hidutil`), reversible

    private var originalMapping: [HyperkeyRemap.Mapping] = []

    private func applyRemap() {
        guard !remapApplied else { return }
        originalMapping = Self.currentMapping()
        remapApplied = Self.setMapping(HyperkeyRemap.adding(to: originalMapping))
    }

    /// Puts back exactly what was there before (minus our entry). Safe to call repeatedly.
    func restoreRemap() {
        guard remapApplied else { return }
        remapApplied = false
        _ = Self.setMapping(HyperkeyRemap.removing(from: Self.currentMapping()))
    }

    private static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private static func currentMapping() -> [HyperkeyRemap.Mapping] {
        run(["property", "--get", "UserKeyMapping"]).map(HyperkeyRemap.parse) ?? []
    }

    private static func setMapping(_ mappings: [HyperkeyRemap.Mapping]) -> Bool {
        run(["property", "--set", HyperkeyRemap.json(mappings)]) != nil
    }
}

/// State shared with the tap thread. Everything the callback touches is lock-protected and O(1).
final class HyperkeyShared: @unchecked Sendable {
    private let lock = NSLock()
    private var engine = HyperkeyEngine()
    private var boundKeys = Set<UInt16>()
    var port: CFMachPort?
    var onFire: (UInt16) -> Void = { _ in }

    func setBindings(_ b: [UInt16: ShortcutAction]) {
        lock.lock(); boundKeys = Set(b.keys); lock.unlock()
    }
    func reset() { lock.lock(); engine.reset(); lock.unlock() }

    func decide(keyCode: UInt16, isDown: Bool, isRepeat: Bool) -> HyperkeyEngine.Decision {
        lock.lock(); defer { lock.unlock() }
        let keys = boundKeys
        return engine.handle(keyCode: keyCode, isDown: isDown, isRepeat: isRepeat) { keys.contains($0) }
    }
}

private func hyperkeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<HyperkeyShared>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let port = shared.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else { return Unmanaged.passUnretained(event) }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    switch shared.decide(keyCode: code, isDown: type == .keyDown, isRepeat: isRepeat) {
    case .passThrough: return Unmanaged.passUnretained(event)
    case .swallow: return nil
    case let .fire(key):
        shared.onFire(key)
        return nil
    }
}
