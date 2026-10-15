import AppKit

// Phase 36 — the small daily helpers. One owner, one `UserDefaults` change observer: every helper is a
// default-OFF key, started only while on and torn down when off, so a disabled helper costs nothing.
// Pure rules live in `Core/Support/DailyHelpersRules.swift`.

@MainActor
final class DailyHelpersService {
    static let shared = DailyHelpersService()
    static let hideFromCaptureKey = "com.katikati.helpers.hideFromCapture"
    static let capsLockKey = "com.katikati.helpers.capsLock"

    /// Set by `AppDelegate` to `liveEventCenter.deliver`.
    var deliver: (LiveEvent) -> Void = { _ in }

    private var defaultsObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    /// Windows this service hid, so turning the switch off restores exactly those (and no others).
    private var hidden = Set<Int>()
    private var capsMonitor: Any?
    private var caps = CapsLockTracker()

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
}
