import AppKit

/// Records text copies into `ClipboardHistory` while the user has switched recording on (opt-in, default off —
/// the clipboard routinely holds secrets). One 0.7 s `changeCount` poll, running only while recording; nothing
/// is written to disk.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let enabledKey = "com.katikati.clipboard.enabled"
    static let soundsKey = "com.katikati.clipboard.sounds"
    static let notchToastKey = "com.katikati.clipboard.notchToast"
    static let ignorePatternsKey = "com.katikati.clipboard.ignorePatterns"
    /// 55g: unpinned entries older than this many days are dropped; 0 (the default) keeps everything.
    static let keepDaysKey = "com.katikati.clipboard.keepDays"

    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var isRecording: Bool
    /// Fired for every external copy that gets recorded (never for `copy(_:)` from the flyout). The app
    /// layer decides whether that earns a toast; the monitor stays free of presentation.
    var onRecorded: ((String) -> Void)?
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Timer?

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        lastChange = pasteboard.changeCount
        isRecording = defaults.bool(forKey: Self.enabledKey)
        if isRecording { startTimer() }
    }

    func setRecording(_ on: Bool) {
        guard on != isRecording else { return }
        isRecording = on
        defaults.set(on, forKey: Self.enabledKey)
        if on {
            lastChange = pasteboard.changeCount   // what was copied before recording started is not ours to take
            startTimer()
        } else {
            timer?.invalidate(); timer = nil
        }
    }

    /// Puts an entry back on the pasteboard (and moves it to the top).
    func copy(_ entry: ClipEntry) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChange = pasteboard.changeCount
        history.remember(entry.text)
    }

    /// Copies the entry, then sends ⌘V to the still-frontmost app (the flyout is non-activating). Only
    /// text is written, so nothing rich pastes. Needs Accessibility for the keystroke; silent if denied.
    func pastePlain(_ entry: ClipEntry) {
        copy(entry)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// 55g: applies the retention setting to what is already in memory and to every later copy.
    func setRetention(days: Int) {
        defaults.set(max(0, days), forKey: Self.keepDaysKey)
        history.prune(olderThanDays: max(0, days))
    }

    func togglePin(_ id: UUID) { history.togglePin(id) }
    func remove(_ id: UUID) { history.remove(id) }
    func clear() { history.clear() }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 0.3
    }

    private func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard ClipboardHistory.shouldRecord(types: types), let text = pasteboard.string(forType: .string) else { return }
        let rules = ClipboardIgnoreRules.parseLines(defaults.string(forKey: Self.ignorePatternsKey) ?? "")
        guard !ClipboardIgnoreRules.matches(text, rules: rules) else { return }
        history.remember(text)
        history.prune(olderThanDays: defaults.integer(forKey: Self.keepDaysKey))
        if defaults.bool(forKey: Self.soundsKey) { NSSound(named: "Tink")?.play() }
        onRecorded?(text)
    }

    deinit { timer?.invalidate() }
}
