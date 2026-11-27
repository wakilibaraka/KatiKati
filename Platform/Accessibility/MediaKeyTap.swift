import AppKit
import ApplicationServices
import OSLog
import os.lock

/// F2: Opt-in session tap on `NX_SYSDEFINED` (`CGEventType` 14, subtype 8) for hardware media keys
/// (volume, mute, screen brightness, keyboard backlight). Fails open: if Accessibility is missing,
/// `DOCK_HUD_TAKEOVER=0`, or the tap disables itself past recovery, events pass straight to macOS.
@MainActor
final class MediaKeyTap {
    var onEvent: ((MediaKeyEvent) -> Void)?

    private let shared = MediaKeyTapShared()
    private let log = Logger(subsystem: "com.katikati.app", category: "hud-tap")
    private var thread: Thread?

    var isRunning: Bool { thread != nil }

    /// Thread-safe predicate checked synchronously inside the tap callback to decide whether to
    /// swallow a key. Returning `false` (e.g. HDMI output without volume control) passes the key
    /// back to macOS untouched.
    func setAvailability(_ canHandle: @escaping @Sendable (MediaKeyKind) -> Bool) {
        shared.setAvailability(canHandle)
    }

    func setEnabled(_ enabled: Bool) {
        let allowed = enabled && DebugSwitch.hudTakeover.isEnabled()
        if allowed { start() } else { stop() }
    }

    func tearDown() {
        stop()
    }

    private func start() {
        guard thread == nil else { return }
        guard AXIsProcessTrusted() else {
            log.info("MediaKeyTap requires Accessibility; leaving system OSD active")
            return
        }
        shared.prepare { [weak self] event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.onEvent?(event)
                }
            }
        }
        let worker = Thread { [shared, log] in shared.runTap(log: log) }
        worker.name = "com.katikati.mediakeytap"
        worker.qualityOfService = .userInteractive
        thread = worker
        worker.start()
    }

    private func stop() {
        thread = nil
        shared.stop()
    }
}

private final class MediaKeyTapShared: @unchecked Sendable {
    private var lock = os_unfair_lock_s()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var stopping = false
    private let recovery = EventTapRecoveryBox()
    private var onEvent: (@Sendable (MediaKeyEvent) -> Void)?
    private var canHandle: (@Sendable (MediaKeyKind) -> Bool)?

    func setAvailability(_ predicate: @escaping @Sendable (MediaKeyKind) -> Bool) {
        os_unfair_lock_lock(&lock)
        canHandle = predicate
        os_unfair_lock_unlock(&lock)
    }

    func prepare(onEvent: @escaping @Sendable (MediaKeyEvent) -> Void) {
        os_unfair_lock_lock(&lock)
        stopping = false
        self.onEvent = onEvent
        os_unfair_lock_unlock(&lock)
        recovery.reset()
    }

    func runTap(log: Logger) {
        autoreleasepool {
            let sysDefinedRaw = UInt32(14)
            let mask: CGEventMask = 1 << UInt64(sysDefinedRaw)
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            guard let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: mediaKeyTapCallback,
                userInfo: refcon
            ) else {
                log.error("Could not create NX_SYSDEFINED event tap; keeping native OSD")
                return
            }
            let loop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(nil, port, 0)
            os_unfair_lock_lock(&lock)
            let abort = stopping
            if !abort { tap = port; runLoop = loop }
            os_unfair_lock_unlock(&lock)
            guard !abort else { CFMachPortInvalidate(port); return }
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
    }

    func stop() {
        os_unfair_lock_lock(&lock)
        stopping = true
        let port = tap
        let loop = runLoop
        tap = nil
        runLoop = nil
        onEvent = nil
        os_unfair_lock_unlock(&lock)
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let loop { CFRunLoopStop(loop); CFRunLoopWakeUp(loop) }
        recovery.reset()
    }

    func handleDisable(log: Logger) {
        os_unfair_lock_lock(&lock)
        let port = tap
        os_unfair_lock_unlock(&lock)
        if !recovery.handleDisable(port: port) {
            log.fault("mediakey-tap-fused")
        }
    }

    func shouldHandle(_ kind: MediaKeyKind) -> Bool {
        os_unfair_lock_lock(&lock)
        let predicate = canHandle
        os_unfair_lock_unlock(&lock)
        return predicate?(kind) ?? true
    }

    func emit(_ event: MediaKeyEvent) {
        os_unfair_lock_lock(&lock)
        let handler = onEvent
        os_unfair_lock_unlock(&lock)
        handler?(event)
    }
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let shared = Unmanaged<MediaKeyTapShared>.fromOpaque(refcon).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        shared.handleDisable(log: Logger(subsystem: "com.katikati.app", category: "hud-tap"))
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == 14 else { return Unmanaged.passUnretained(event) }
    let decoded: MediaKeyEvent? = autoreleasepool {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        return MediaKeyDecode.decode(
            subtype: nsEvent.subtype.rawValue,
            data1: nsEvent.data1,
            modifierFlagsRaw: event.flags.rawValue
        )
    }
    guard let decoded, shared.shouldHandle(decoded.key) else {
        return Unmanaged.passUnretained(event)
    }
    if decoded.isKeyDown {
        shared.emit(decoded)
    }
    return nil
}
