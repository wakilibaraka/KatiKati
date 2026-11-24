import AppKit
import AVFoundation
import Carbon.HIToolbox
import OSLog
import Speech

/// Turns the shortcut bindings (Phase 7B-V4) into live triggers: Carbon hot keys for Space chords, and an event
/// monitor for modifier double-taps. The monitors exist only for the bindings that are on; `apply` is idempotent.
@MainActor
final class ShortcutService {
    var onAction: (ShortcutAction) -> Void = { _ in }
    private var hotKeys: [ShortcutAction: GlobalHotKeyMonitor] = [:]
    private var tapActions: [ShortcutTapKey: [ShortcutAction]] = [:]
    private var holdActions: [ShortcutTapKey: [ShortcutAction]] = [:]
    private var holdTimer: Timer?
    private var activeHoldKey: ShortcutTapKey?
    private var policy = ShortcutMonitorPolicy()
    private var flagsMonitors: (global: Any?, local: Any?) = (nil, nil)
    private var cancelMonitors: (global: Any?, local: Any?) = (nil, nil)
    private var cancelDisarmWork: DispatchWorkItem?
    private var menuObservers: [NSObjectProtocol] = []
    private var applied: [ShortcutAction: ShortcutTrigger]?
    private let log = Logger(subsystem: "com.katikati.app", category: "hotkey")

    func apply(_ bindings: [ShortcutAction: ShortcutTrigger]) {
        guard bindings != applied else { return }
        applied = bindings
        var failed: [ShortcutAction: String] = [:]
        hotKeys.values.forEach { $0.stop() }
        hotKeys = [:]
        removeEventMonitors()
        tapActions = [:]
        holdActions = [:]
        cancelHold()
        policy.detector.reset()
        for action in ShortcutAction.allCases where action != .windowSwitcher {
            switch bindings[action] ?? .off {
            case .off: break
            case .chord(let chord):
                let monitor = GlobalHotKeyMonitor(shortcut: Self.shortcut(for: action, chord: chord)) { [weak self] in self?.onAction(action) }
                if monitor.start() == .registered { hotKeys[action] = monitor } else {
                    failed[action] = String(format: String(localized: "%@ is taken by macOS or another app, so it is not active."), chord.glyphs)
                    log.warning("Shortcut \(chord.glyphs, privacy: .public) for \(action.rawValue, privacy: .public) could not be registered")
                }
            case .doubleTap(let key):
                tapActions[key, default: []].append(action)
            case .key(let key):
                let monitor = GlobalHotKeyMonitor(shortcut: Self.shortcut(for: action, key: key)) { [weak self] in self?.onAction(action) }
                if monitor.start() == .registered { hotKeys[action] = monitor } else {
                    failed[action] = String(format: String(localized: "%@ is taken by macOS or another app, so it is not active."), key.glyphs)
                    log.warning("Shortcut \(key.glyphs, privacy: .public) for \(action.rawValue, privacy: .public) could not be registered")
                }
            case .hold(let key):
                holdActions[key, default: []].append(action)
            case .hyper:
                // The Hyperkey service owns the primary trigger. Option+Shift+V is a clash-free
                // fallback while Hyper Key is off.
                if action == .clipboardMenu {
                    let fallback = ShortcutKey(
                        keyCode: 9,
                        modifiers: ShortcutKey.option | ShortcutKey.shift
                    )
                    let monitor = GlobalHotKeyMonitor(shortcut: Self.shortcut(for: action, key: fallback)) { [weak self] in
                        self?.onAction(action)
                    }
                    if monitor.start() == .registered { hotKeys[action] = monitor } else {
                        failed[action] = String(format: String(localized: "%@ is taken by macOS or another app, so it is not active."), fallback.glyphs)
                    }
                }
            }
        }
        ShortcutRegistrationState.shared.failures = failed
        policy.hasBindings = !tapActions.isEmpty || !holdActions.isEmpty
        if policy.hasBindings {
            installMenuObservers()
            if policy.wantsFlagsMonitor { flagsMonitors = installMonitorPair(matching: [.flagsChanged]) }
        }
    }

    func tearDown() {
        hotKeys.values.forEach { $0.stop() }
        hotKeys = [:]
        removeEventMonitors()
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        policy = ShortcutMonitorPolicy()
        cancelHold()
        applied = nil
    }

    private static func shortcut(for action: ShortcutAction, key: ShortcutKey) -> GlobalHotKeyShortcut {
        var mods: UInt32 = 0
        if key.modifiers & ShortcutKey.control != 0 { mods |= UInt32(controlKey) }
        if key.modifiers & ShortcutKey.option != 0 { mods |= UInt32(optionKey) }
        if key.modifiers & ShortcutKey.shift != 0 { mods |= UInt32(shiftKey) }
        if key.modifiers & ShortcutKey.command != 0 { mods |= UInt32(cmdKey) }
        return GlobalHotKeyShortcut(keyCode: UInt32(key.keyCode), carbonModifiers: mods, displayGlyphs: key.glyphs,
                                    signature: 0x5467_4567, id: action.hotKeyID)
    }

    private static func shortcut(for action: ShortcutAction, chord: ShortcutChord) -> GlobalHotKeyShortcut {
        var mods: UInt32 = 0
        if chord.usesControl { mods |= UInt32(controlKey) }
        if chord.usesOption { mods |= UInt32(optionKey) }
        if chord.usesShift { mods |= UInt32(shiftKey) }
        if chord.usesCommand { mods |= UInt32(cmdKey) }
        return GlobalHotKeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: mods, displayGlyphs: chord.glyphs,
                                    signature: 0x5467_4567, id: action.hotKeyID)
    }

    private func installMonitorPair(matching mask: NSEvent.EventTypeMask) -> (Any?, Any?) {
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let kind = event.type, code = event.keyCode, flags = event.modifierFlags, time = event.timestamp
            Task { @MainActor in self?.handle(kind: kind, keyCode: code, flags: flags, time: time) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(kind: event.type, keyCode: event.keyCode, flags: event.modifierFlags, time: event.timestamp)
            return event
        }
        return (global, local)
    }

    private func removeMonitorPair(_ pair: inout (global: Any?, local: Any?)) {
        if let m = pair.global { NSEvent.removeMonitor(m) }
        if let m = pair.local { NSEvent.removeMonitor(m) }
        pair = (nil, nil)
    }

    private func removeEventMonitors() {
        cancelDisarmWork?.cancel(); cancelDisarmWork = nil
        removeMonitorPair(&cancelMonitors)
        removeMonitorPair(&flagsMonitors)
    }

    private func installMenuObservers() {
        guard menuObservers.isEmpty else { return }
        menuObservers = [(NSMenu.didBeginTrackingNotification, true), (NSMenu.didEndTrackingNotification, false)].map { name, tracking in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.policy.isMenuTracking = tracking
                    if tracking { self.policy.detector.reset(); self.cancelHold(); self.removeEventMonitors() }
                    else if self.policy.wantsFlagsMonitor, self.flagsMonitors.global == nil {
                        self.flagsMonitors = self.installMonitorPair(matching: [.flagsChanged])
                    }
                }
            }
        }
    }

    private func syncCancelMonitors(at time: TimeInterval) {
        cancelDisarmWork?.cancel(); cancelDisarmWork = nil
        policy.isHolding = holdTimer != nil || activeHoldKey != nil
        guard let window = policy.cancelWindow(at: time) else { removeMonitorPair(&cancelMonitors); return }
        if cancelMonitors.global == nil {
            cancelMonitors = installMonitorPair(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged])
        }
        guard window.isFinite else { return }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cancelDisarmWork = nil; self.policy.detector.reset(); self.removeMonitorPair(&self.cancelMonitors)
            }
        }
        cancelDisarmWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + window + 0.02, execute: work)
    }

    private func handle(kind: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags, time: TimeInterval) {
        defer { syncCancelMonitors(at: time) }
        guard policy.wantsFlagsMonitor else { return }
        guard kind == .flagsChanged else { policy.detector.pointerActivity(); cancelHold(); return }
        guard let key = ShortcutTapKey(keyCode: keyCode) else { policy.detector.reset(); cancelHold(); return }
        let family: NSEvent.ModifierFlags = {
            switch key {
            case .leftCommand, .rightCommand: return .command
            case .leftControl, .rightControl: return .control
            case .leftOption, .rightOption: return .option
            case .fn: return .function
            }
        }()
        let active = flags.intersection([.command, .control, .option, .shift, .function])
        let isDown = active.contains(family)
        // A chord such as ⌘⇧ is neither a tap nor a hold.
        if isDown, active != family { policy.detector.reset(); cancelHold(); return }
        if isDown, holdActions[key] != nil { startHold(key) } else { cancelHold() }
        guard let fired = policy.detector.modifierChanged(keyCode: keyCode, isDown: isDown, time: time),
              let actions = tapActions[fired] else { return }
        actions.forEach(onAction)
    }

    private func startHold(_ key: ShortcutTapKey) {
        cancelHold()
        holdTimer = Timer.scheduledTimer(withTimeInterval: ShortcutHold.threshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.holdTimer = nil
                self.activeHoldKey = key
                self.holdActions[key]?.forEach(self.onAction)
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if let held = activeHoldKey {
            activeHoldKey = nil
            if holdActions[held]?.contains(.dictate) == true {
                DictationController.shared.stopAndPaste()
            }
            if holdActions[held]?.contains(where: { $0 == .radialDial || $0 == .radialDialSnap || $0 == .radialDialTools }) == true {
                RadialDialPanelController.shared.hotkeyReleased()
            }
        }
    }
}

/// Port plan #14: on-device Speech + AVAudioEngine dictation into the frontmost app.
@MainActor
final class DictationController {
    static let shared = DictationController()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latestTranscript = ""
    private(set) var isRecording = false

    func toggle() {
        if isRecording {
            stopAndPaste()
        } else {
            start()
        }
    }

    func start() {
        guard !isRecording else { return }
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else { return }
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                Task { @MainActor in
                    self.beginSession()
                }
            }
        }
    }

    private func beginSession() {
        guard !isRecording, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return }
        latestTranscript = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        request = req
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }
        engine.prepare()
        guard (try? engine.start()) != nil else {
            inputNode.removeTap(onBus: 0)
            request = nil
            return
        }
        isRecording = true
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                self?.latestTranscript = text
            }
        }
    }

    func stopAndPaste() {
        guard isRecording else { return }
        isRecording = false
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        let text = DictationTranscript.cleaned(latestTranscript)
        latestTranscript = ""
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        guard AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand; up.flags = .maskCommand
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        }
    }
}
