import AppKit
import Combine

// Phase 36 — the small daily helpers. One owner, one `UserDefaults` change observer: every helper is a
// default-OFF key, started only while on and torn down when off, so a disabled helper costs nothing.
// Pure rules live in `Core/Support/DailyHelpersRules.swift`.

@MainActor
final class DailyHelpersService {
    static let shared = DailyHelpersService()
    static let hideFromCaptureKey = "com.katikati.helpers.hideFromCapture"
    static let capsLockKey = "com.katikati.helpers.capsLock"
    static let batteryKey = "com.katikati.helpers.batteryNudge"
    static let ejectKey = "com.katikati.helpers.usbEject"
    static let privacyKey = "com.katikati.helpers.privacyDot"
    static let hydrateKey = "com.katikati.helpers.hydrate"
    static let pauseKey = "com.katikati.helpers.pause"

    /// Set by `AppDelegate` to `liveEventCenter.deliver`.
    var deliver: (LiveEvent) -> Void = { _ in }

    private var defaultsObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    /// Windows this service hid, so turning the switch off restores exactly those (and no others).
    private var hidden = Set<Int>()
    private var capsMonitor: Any?
    private var caps = CapsLockTracker()
    private var batteryStatus: SystemStatusService?
    private var batterySub: AnyCancellable?
    private var batteryRule = BatteryNoticeRule()
    private var mountObserver: NSObjectProtocol?
    private let ejectPill = USBEjectPillController()
    private var privacyTimer: Timer?
    private let privacyDots = PrivacyDotController()
    private var reminderTimers: [LiveNoticeKind: Timer] = [:]
    /// PHN-2: the Smart Pause probe — camera/mic/focus state, only while Smart Pause is on.
    private var wellnessTimer: Timer?
    /// The focus timer lives in the Edge layer, which is not part of the test target's compile list;
    /// `AppDelegate` hands the read in so this file stays buildable in both targets.
    var focusActiveProvider: () -> Bool = { false }

    func start() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        applyCaptureHiding(UserDefaults.standard.bool(forKey: Self.hideFromCaptureKey))
        applyCapsLock(UserDefaults.standard.bool(forKey: Self.capsLockKey))
        applyBattery(UserDefaults.standard.bool(forKey: Self.batteryKey))
        applyEject(UserDefaults.standard.bool(forKey: Self.ejectKey))
        applyPrivacy(UserDefaults.standard.bool(forKey: Self.privacyKey))
        // PHN: every wellness helper ships on, so an unset key means on (`bool(forKey:)` would read off).
        applyReminder(.hydrate, WellnessDefaults.isEnabled(.waterReminder))
        applyReminder(.pause, WellnessDefaults.isEnabled(.pauseReminder))
        applyWellnessProbe()
        automationPolicy.settings = SmartDockAutomationSettings.current()
    }

    // MARK: 56e — water and break reminders

    /// One repeating timer per reminder while on; the first notice comes a full interval after switching on.
    private func applyReminder(_ kind: LiveNoticeKind, _ on: Bool) {
        guard let interval = kind.reminderInterval else { return }
        if on, reminderTimers[kind] == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.deliverReminder(kind) }
            }
            timer.tolerance = 30
            reminderTimers[kind] = timer
        } else if !on, let timer = reminderTimers.removeValue(forKey: kind) {
            timer.invalidate()
        }
    }

    /// PHN-2 — a reminder arrives only when it will not interrupt: water holds during any blocker
    /// (Smart Pause), a break holds only during a call/camera/mic, and a snooze silences either one.
    /// The pause line is the current prompt, so the toast is a real nudge instead of a generic headline.
    private func deliverReminder(_ kind: LiveNoticeKind) {
        let hydro = HydrationController.shared
        let blockers = hydro.blockers
        if hydro.pauseSnoozed { return }
        switch kind {
        case .hydrate where blockers.any, .pause where blockers.inMeeting:
            return
        default:
            break
        }
        var detail: String?
        if kind == .pause {
            hydro.refreshPausePrompt()
            detail = hydro.currentPause?.text
        }
        deliver(.notice(kind, detail: detail))
    }

    /// PHN-2 — Smart Pause's inputs. Two property reads every 2 s while the switch is on; the timer is
    /// released the moment it is off, so a disabled helper costs nothing.
    private func applyWellnessProbe() {
        guard WellnessDefaults.isEnabled(.smartPause) else {
            wellnessTimer?.invalidate()
            wellnessTimer = nil
            HydrationController.shared.setExternalBlockers(focusActive: false, cameraInUse: false,
                                                           microphoneInUse: false, callActive: false)
            return
        }
        probeWellness()
        guard wellnessTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.probeWellness() }
        }
        timer.tolerance = 0.5
        wellnessTimer = timer
    }

    private func probeWellness() {
        HydrationController.shared.setExternalBlockers(
            focusActive: focusActiveProvider(),
            cameraInUse: PrivacyUseProbe.cameraInUse(),
            microphoneInUse: PrivacyUseProbe.microphoneInUse(),
            callActive: false
        )
    }

    // MARK: 36d — hide from screen capture

    /// `sharingType = .none` keeps our windows out of screenshots, recordings and screen shares. New
    /// panels (toasts, flyouts) appear later, so while on we also re-apply when a window becomes visible.
    private func applyCaptureHiding(_ on: Bool) {
        if on {
            if occlusionObserver == nil {
                occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyCaptureHiding(true) }
                }
            }
            for window in NSApp.windows where window.sharingType != .none {
                window.sharingType = .none
                hidden.insert(window.windowNumber)
            }
        } else {
            if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
            occlusionObserver = nil
            for window in NSApp.windows where hidden.contains(window.windowNumber) { window.sharingType = .readOnly }
            hidden.removeAll()
        }
    }

    // MARK: 36a — Caps Lock HUD

    /// A global `flagsChanged` monitor that exists only while the switch is on. It needs Input Monitoring
    /// (same gate as the key guards); without it the helper stays off rather than prompting from here.
    private func applyCapsLock(_ on: Bool) {
        if on, capsMonitor == nil, KeyGuardService.hasPermission {
            caps = CapsLockTracker()
            _ = caps.update(isOn: CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift))
            capsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isOn = event.modifierFlags.contains(.capsLock)
                MainActor.assumeIsolated {
                    guard let self, let kind = self.caps.update(isOn: isOn) else { return }
                    self.deliver(.notice(kind, detail: nil))
                }
            }
        } else if !on, let monitor = capsMonitor {
            NSEvent.removeMonitor(monitor)
            capsMonitor = nil
        }
    }

    // MARK: 36b — charge / unplug island

    /// Rides `SystemStatusService` (IOKit power-source notification — event-driven, no polling) only while on.
    private func applyBattery(_ on: Bool) {
        if on, batteryStatus == nil {
            let service = SystemStatusService()
            batteryRule = BatteryNoticeRule()
            batteryStatus = service
            service.acquire()
            batterySub = service.$status.map(\.battery).removeDuplicates().sink { [weak self] battery in
                guard let self, let kind = self.batteryRule.update(battery) else { return }
                self.deliver(.notice(kind, detail: battery.level.map { "\($0)%" }))
            }
        } else if !on, let service = batteryStatus {
            batterySub = nil
            service.release()
            batteryStatus = nil
        }
    }

    // MARK: 36c — USB eject pill

    /// `NSWorkspace.didMountNotification` (event-driven, only while on).
    private func applyEject(_ on: Bool) {
        if on, mountObserver == nil {
            mountObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
                guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                MainActor.assumeIsolated { self?.offerEject(url) }
            }
        } else if !on, let observer = mountObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            mountObserver = nil
            ejectPill.hide()
        }
    }

    private func offerEject(_ url: URL) {
        let keys: Set<URLResourceKey> = [.volumeIsEjectableKey, .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsLocalKey, .volumeNameKey]
        guard let values = try? url.resourceValues(forKeys: keys),
              EjectPolicy.isOffered(isEjectable: (values.volumeIsEjectable ?? false) || (values.volumeIsRemovable ?? false),
                                    isInternal: values.volumeIsInternal ?? false,
                                    isLocal: values.volumeIsLocal ?? true,
                                    isRoot: url.path == "/") else { return }
        ejectPill.show(volumeURL: url, name: values.volumeName ?? url.lastPathComponent)
    }

    // MARK: 36h — privacy dot

    /// shortcut: two property reads every 2 s while on, instead of per-device property listeners (which need
    /// re-registering as cameras come and go); move to listeners if the wakeups ever show in Activity Monitor.
    private func applyPrivacy(_ on: Bool) {
        if on, privacyTimer == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.pollPrivacy() }
            }
            timer.tolerance = 0.5
            privacyTimer = timer
            pollPrivacy()
        } else if !on, privacyTimer != nil {
            privacyTimer?.invalidate(); privacyTimer = nil
            privacyDots.hide()
        }
    }

    private func pollPrivacy() {
        privacyDots.update(PrivacyDots(camera: PrivacyUseProbe.cameraInUse(), microphone: PrivacyUseProbe.microphoneInUse()))
    }

    // MARK: - Slice 4.2: SmartDockAutomations

    var automationPolicy = SmartDockAutomationPolicy()
    private var lastAIPercentByProvider: [String: Double] = [:]
    var onDockHiddenChange: ((Bool) -> Void)?
    var onPauseMediaRequest: (() -> Void)?

    func evaluateMeetingApproaching(secondsUntilMeeting: TimeInterval, hasMeetingLink: Bool, isMediaPlaying: Bool) {
        if let action = automationPolicy.evaluateMeetingMediaPause(
            secondsUntilMeeting: secondsUntilMeeting,
            hasMeetingLink: hasMeetingLink,
            isMediaPlaying: isMediaPlaying
        ), action == .pauseMedia {
            onPauseMediaRequest?()
        }
    }

    func evaluateAIProviderUsage(provider: String, sessionPercent: Double, weeklyPercent: Double) {
        let prev = lastAIPercentByProvider[provider] ?? 0
        if let action = automationPolicy.evaluateAILimitThreshold(
            provider: provider,
            sessionPercent: sessionPercent,
            weeklyPercent: weeklyPercent,
            previousMaxPercent: prev
        ) {
            lastAIPercentByProvider[provider] = max(sessionPercent, weeklyPercent)
            switch action {
            case .warnAILimit, .notifyAILimitReset:
                break
            default: break
            }
        }
    }

    func evaluateFullscreenChange(isFullscreen: Bool, isDockHidden: Bool) {
        if let action = automationPolicy.evaluateFullscreenStepAside(
            isFullscreen: isFullscreen,
            isDockCurrentlyHidden: isDockHidden
        ) {
            if case .setDockHidden(let hide) = action {
                onDockHiddenChange?(hide)
            }
        }
    }
}
