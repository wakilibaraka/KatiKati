import AppKit

// Phase 36 — the small daily helpers. One owner, one `UserDefaults` change observer: every helper is a
// default-OFF key, started only while on and torn down when off, so a disabled helper costs nothing.
// Pure rules live in `Core/Support/DailyHelpersRules.swift`.

@MainActor
final class DailyHelpersService {
    static let shared = DailyHelpersService()
    static let hideFromCaptureKey = "com.katikati.helpers.hideFromCapture"

    private var defaultsObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?
    /// Windows this service hid, so turning the switch off restores exactly those (and no others).
    private var hidden = Set<Int>()

    func start() {
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        applyCaptureHiding(UserDefaults.standard.bool(forKey: Self.hideFromCaptureKey))
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
}
