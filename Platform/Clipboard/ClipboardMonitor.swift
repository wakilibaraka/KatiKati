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

/// 53g — paste the clipboard image into the front Finder window as a `.png`. Finder's target folder
/// comes over Apple Events, so the first paste asks for the Automation grant; the write never
/// overwrites (see `PasteImageNaming`), and the caller only has to report what failed.
enum ClipboardImagePaster {
    enum Failure: Error, Equatable {
        case noImage
        case noFinderWindow
        case automationRefused
        case writeFailed

        /// One plain sentence: this is shown as a shortcut toast, not in a dialog.
        var message: String {
            switch self {
            case .noImage: return String(localized: "The clipboard has no image.")
            case .noFinderWindow: return String(localized: "No Finder window is in front.")
            case .automationRefused: return String(localized: "Allow KatiKati to control Finder in System Settings.")
            case .writeFailed: return String(localized: "The image could not be written.")
            }
        }
    }

    /// Main thread: `NSAppleScript` blocks while Finder answers, and this is a user-initiated action.
    static func paste() -> Result<URL, Failure> {
        guard let png = pngData() else { return .failure(.noImage) }
        let folder: URL
        switch frontFolder() {
        case .success(let url): folder = url
        case .failure(let failure): return .failure(failure)
        }
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let name = PasteImageNaming.uniqueName(base: String(localized: "Clipboard Image"),
                                               fileExtension: "png",
                                               existing: Set(existing))
        let url = folder.appendingPathComponent(name)
        do {
            try png.write(to: url, options: [.atomic, .withoutOverwriting])
            return .success(url)
        } catch {
            return .failure(.writeFailed)
        }
    }

    /// PNG straight off the pasteboard; a TIFF-only copy (most screenshots and Safari images) is
    /// re-encoded once instead of being refused.
    private static func pngData() -> Data? {
        let board = NSPasteboard.general
        if let png = board.data(forType: .png) { return png }
        guard let tiff = board.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// The front Finder window's target folder, over Apple Events. Finder closed, no window open and
    /// a refused grant are three different answers, and the toast says which.
    private static func frontFolder() -> Result<URL, Failure> {
        let source = "tell application \"Finder\" to if (count of windows) > 0 then POSIX path of (target of front window as alias)"
        guard let script = NSAppleScript(source: source) else { return .failure(.noFinderWindow) }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            // -1743: the user said no to "KatiKati wants to control Finder".
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            return .failure(code == -1743 ? .automationRefused : .noFinderWindow)
        }
        guard let path = result.stringValue, !path.isEmpty else { return .failure(.noFinderWindow) }
        return .success(URL(fileURLWithPath: path, isDirectory: true))
    }
}
