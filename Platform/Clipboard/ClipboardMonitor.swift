import AppKit

/// Records text copies into `ClipboardHistory` while the user has switched recording on (opt-in, default off —
/// the clipboard routinely holds secrets). One 0.7 s `changeCount` poll, running only while recording; nothing
/// is written to disk.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let enabledKey = "com.katikati.clipboard.enabled"

    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var isRecording: Bool
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
        history.remember(text)
    }

    deinit { timer?.invalidate() }
}
