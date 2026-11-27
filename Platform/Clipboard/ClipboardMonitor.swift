import AppKit
import Carbon

/// Records text copies into `ClipboardHistory` while the user has switched recording on (opt-in, default off —
/// the clipboard routinely holds secrets). One 0.7 s `changeCount` poll, running only while recording; nothing
/// is written to disk.
@MainActor
final class ClipboardMonitor: ObservableObject {
    static let enabledKey = "com.katikati.clipboard.enabled"
    static let linkCleanerKey = "com.katikati.linkCleaner"
    static let soundsKey = "com.katikati.clipboard.sounds"
    static let notchToastKey = "com.katikati.clipboard.notchToast"
    static let ignorePatternsKey = "com.katikati.clipboard.ignorePatterns"
    /// 55g: unpinned entries older than this many days are dropped; 0 (the default) keeps everything.
    static let keepDaysKey = "com.katikati.clipboard.keepDays"

    @Published private(set) var history = ClipboardHistory()
    @Published private(set) var isRecording: Bool
    @Published private(set) var linkCleanerEnabled = false
    /// Fired for every external copy that gets recorded (never for `copy(_:)` from the flyout). The app
    /// layer decides whether that earns a toast; the monitor stays free of presentation.
    var onRecorded: ((String) -> Void)?
    /// T1.2: carries whether URL tracking parameters were stripped before recording/toasting.
    var onRecordedWithCleaning: ((String, Bool) -> Void)?
    /// Fired whenever content is pasted (via `pastePlain(_:)` or global ⌘V).
    var onPasted: ((String) -> Void)?
    private static let syntheticKeyTag: Int64 = 0x4B41544931
    private let defaults: UserDefaults
    private let pasteboard: NSPasteboard
    private var lastChange: Int
    private var timer: Timer?
    /// MC-1/MC-3: one-shot "ignore the next copy" latch, set from the Clipboard page.
    @Published private var skipNextCopy = false
    private var lastCopiedOriginBundleID: String?
    private var lastCopyWasBlocked = false
    private var rawChangeObservers: [UUID: @MainActor () -> Void] = [:]

    init(defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        lastChange = pasteboard.changeCount
        isRecording = defaults.bool(forKey: Self.enabledKey)
        linkCleanerEnabled = defaults.bool(forKey: Self.linkCleanerKey)
        syncTimer()
    }

    func setRecording(_ on: Bool) {
        guard on != isRecording else { return }
        isRecording = on
        defaults.set(on, forKey: Self.enabledKey)
        if on {
            lastChange = pasteboard.changeCount   // what was copied before recording started is not ours to take
        }
        syncTimer()
    }

    func setLinkCleanerEnabled(_ on: Bool) {
        guard on != linkCleanerEnabled else { return }
        linkCleanerEnabled = on
        if on {
            lastChange = pasteboard.changeCount
        }
        syncTimer()
    }

    /// Puts an entry back on the pasteboard (and moves it to the top).
    func copy(_ entry: ClipEntry, playSound: Bool = true) {
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastChange = pasteboard.changeCount
        history.remember(entry.text, originBundleID: entry.originBundleID)
        if playSound { playCue(.copy) }
    }

    /// Copies the entry, then sends ⌘V to the still-frontmost app (the flyout is non-activating). Only
    /// text is written, so nothing rich pastes. Needs Accessibility for the keystroke; silent if denied.
    func pastePlain(_ entry: ClipEntry) {
        copy(entry, playSound: false)
        playCue(.paste)
        onPasted?(entry.text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticKeyTag)
            up.setIntegerValueField(.eventSourceUserData, value: Self.syntheticKeyTag)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Invoked on global ⌘V detection (Input Monitoring): plays subtle paste sound & notifies toast if enabled.
    func handleExternalPaste() {
        guard !IsSecureEventInputEnabled() else { return }
        let changeCount = pasteboard.changeCount
        if changeCount == lastChange, lastCopyWasBlocked { return }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let sourceBundleID = changeCount == lastChange ? lastCopiedOriginBundleID : nil
        let ignoreRules = ClipboardIgnoreRules.parseLines(defaults.string(forKey: Self.ignorePatternsKey) ?? "")
        guard let raw = pasteboard.string(forType: .string),
              MaccyPasteboardFilter.shouldRecord(types: types, sourceBundleID: sourceBundleID, text: raw, rules: filterRules),
              !ClipboardIgnoreRules.matches(raw, rules: ignoreRules) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playCue(.paste)
        onPasted?(trimmed)
    }

    private func playCue(_ event: ClipboardAudioEvent) {
        guard let name = ClipboardAudioPolicy.soundName(for: event, defaults: defaults),
              let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = ClipboardAudioPolicy.volume(defaults: defaults)
        sound.play()
    }

    /// 55g: applies the retention setting to what is already in memory and to every later copy.
    func setRetention(days: Int) {
        defaults.set(max(0, days), forKey: Self.keepDaysKey)
        history.prune(olderThanDays: max(0, days))
    }

    /// MC-3: the page's capture state, read by the flyout's header pill.
    var captureMode: ClipboardCaptureMode {
        if !isRecording { return .paused }
        return skipNextCopy ? .skipNextCopy : .active
    }

    /// MC-1: the next external copy is dropped and the latch clears itself.
    func ignoreNextCopy() { skipNextCopy = true }

    var isSkippingNextCopy: Bool { captureMode.isSkippingNextCopy }

    func togglePin(_ id: UUID) { history.togglePin(id) }
    func remove(_ id: UUID) { history.remove(id) }
    func clear() { history.clear() }

    /// MC-3: ⌥⌘⌫ keeps pins, ⇧⌥⌘⌫ drops everything.
    func clearAll(keepingPinned: Bool) { history.clear(keepingPinned: keepingPinned) }

    /// Registers a listener fired whenever `pasteboard.changeCount` advances (before text/privacy filters),
    /// keeping the shared pasteboard poll active without spawning a second timer.
    @discardableResult
    func addRawChangeObserver(_ handler: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        let wasIdle = rawChangeObservers.isEmpty && !isRecording && !linkCleanerEnabled
        rawChangeObservers[id] = handler
        if wasIdle { lastChange = pasteboard.changeCount }
        syncTimer()
        return id
    }

    func removeRawChangeObserver(_ id: UUID) {
        guard rawChangeObservers.removeValue(forKey: id) != nil else { return }
        syncTimer()
    }

    private func syncTimer() {
        if isRecording || linkCleanerEnabled || !rawChangeObservers.isEmpty {
            startTimer()
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func refreshPollingInterval() {
        if isRecording || linkCleanerEnabled || !rawChangeObservers.isEmpty {
            startTimer()
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let scheduled = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        scheduled.tolerance = min(0.3, pollInterval / 2)
        RunLoop.main.add(scheduled, forMode: .common)
        timer = scheduled
    }

    /// MC-3: the Clipboard page's Polling Interval (100/250/500 ms), 0.7 s when unset.
    private var pollInterval: TimeInterval {
        let ms = defaults.integer(forKey: ClipboardSettingsKeys.pollingIntervalMS)
        return ms > 0 ? Double(ms) / 1000 : 0.7
    }

    /// MC-3: the Privacy toggles and ignore patterns, built fresh for every copy so a switch applies immediately.
    private var filterRules: MaccyPasteboardFilter.Rules {
        let ignoreConcealed = defaults.object(forKey: ClipboardSettingsKeys.ignoreConcealed) as? Bool ?? true
        let ignoreAutoGenerated = defaults.object(forKey: ClipboardSettingsKeys.ignoreAutoGenerated) as? Bool ?? true
        let ignoreUniversal = defaults.object(forKey: ClipboardSettingsKeys.ignoreUniversal) as? Bool ?? false
        let substrings = ClipboardIgnoreRules
            .parseLines(defaults.string(forKey: Self.ignorePatternsKey) ?? "")
            .compactMap { rule -> String? in
                if case .substring(let needle) = rule { return needle }
                return nil
            }
        return MaccyPasteboardFilter.Rules(
            ignoreConcealed: ignoreConcealed,
            ignoreAutoGenerated: ignoreAutoGenerated,
            ignoreUniversal: ignoreUniversal,
            ignoredPatterns: substrings
        )
    }

    private func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        for observer in rawChangeObservers.values {
            observer()
        }
        guard isRecording || linkCleanerEnabled else { return }
        let types = (pasteboard.types ?? []).map(\.rawValue)
        let originBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        lastCopiedOriginBundleID = originBundleID
        lastCopyWasBlocked = false

        guard ClipboardHistory.shouldRecord(types: types),
              let rawText = pasteboard.string(forType: .string) else {
            lastCopyWasBlocked = true
            return
        }
        let rules = ClipboardIgnoreRules.parseLines(defaults.string(forKey: Self.ignorePatternsKey) ?? "")
        guard MaccyPasteboardFilter.shouldRecord(
            types: types, sourceBundleID: originBundleID, text: rawText, rules: filterRules
        ), !ClipboardIgnoreRules.matches(rawText, rules: rules) else {
            lastCopyWasBlocked = true
            return
        }

        let outcome = captureMode.shouldRecordCopy()
        if isRecording {
            skipNextCopy = outcome.nextMode.isSkippingNextCopy
            guard outcome.record else {
                lastCopyWasBlocked = true
                return
            }
        } else if skipNextCopy {
            skipNextCopy = false
            lastCopyWasBlocked = true
            return
        }

        let resolution = ClipboardPasteboardProcessor.process(
            text: rawText,
            isRecording: isRecording,
            cleanLinks: linkCleanerEnabled
        )
        if resolution.shouldRewritePasteboard {
            pasteboard.clearContents()
            pasteboard.setString(resolution.finalText, forType: .string)
            lastChange = pasteboard.changeCount
        }

        var recorded = false
        if resolution.shouldRecordHistory {
            let limit = defaults.integer(forKey: ClipboardSettingsKeys.historyLimit)
            history.limit = limit > 0 ? limit : ClipboardHistory.maxUnpinned
            history.remember(resolution.finalText, originBundleID: originBundleID)
            history.prune(olderThanDays: defaults.integer(forKey: Self.keepDaysKey))
            recorded = true
        }

        guard recorded || resolution.didCleanLink else { return }
        if let cue = resolution.audioEvent { playCue(cue) }
        onRecordedWithCleaning?(resolution.finalText, resolution.didCleanLink)
        onRecorded?(resolution.finalText)
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
