import AppKit

// Phase 37b — the teleprompter's live state, shared by the floating window and the notch page. The 30 Hz
// timer exists only while playing; paused or closed it does nothing. No camera, no permission.

@MainActor
final class TeleprompterModel: ObservableObject {
    static let shared = TeleprompterModel()
    static let enabledKey = "com.katikati.teleprompter.enabled"
    private static let scriptKey = "com.katikati.teleprompter.script"
    private static let wpmKey = "com.katikati.teleprompter.wpm"
    private static let fontKey = "com.katikati.teleprompter.font"
    private static let mirrorKey = "com.katikati.teleprompter.mirror"

    @Published var script: String { didSet { UserDefaults.standard.set(script, forKey: Self.scriptKey) } }
    @Published var wpm: Double { didSet { UserDefaults.standard.set(wpm, forKey: Self.wpmKey) } }
    @Published var fontSize: Double { didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontKey) } }
    @Published var mirrored: Bool { didSet { UserDefaults.standard.set(mirrored, forKey: Self.mirrorKey) } }
    @Published private(set) var scroll = TeleprompterScroll()
    @Published private(set) var isPlaying = false
    /// Laid-out height of the script, reported by the view.
    var contentHeight = 0.0

    private var timer: Timer?
    private var last = Date()

    private init() {
        let d = UserDefaults.standard
        script = d.string(forKey: Self.scriptKey) ?? ""
        wpm = (d.object(forKey: Self.wpmKey) as? Double).map { min(max($0, TeleprompterSpeed.wpmRange.lowerBound), TeleprompterSpeed.wpmRange.upperBound) } ?? TeleprompterSpeed.defaultWPM
        fontSize = (d.object(forKey: Self.fontKey) as? Double).map { min(max($0, TeleprompterSpeed.fontRange.lowerBound), TeleprompterSpeed.fontRange.upperBound) } ?? TeleprompterSpeed.defaultFont
        mirrored = d.bool(forKey: Self.mirrorKey)
    }

    var links: [URL] { ScriptLinks.urls(in: script) }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard !isPlaying, !script.isEmpty else { return }
        if scroll.offset >= contentHeight, contentHeight > 0 { scroll.reset() }
        isPlaying = true
        last = Date()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        isPlaying = false
        timer?.invalidate(); timer = nil
    }

    func restart() { scroll.reset(); objectWillChange.send() }

    func nudge(_ points: Double) { scroll.nudge(points, contentHeight: contentHeight) }

    private func tick() {
        let now = Date()
        let more = scroll.advance(dt: now.timeIntervalSince(last), wpm: wpm, fontSize: fontSize, contentHeight: contentHeight)
        last = now
        if !more { pause() }
    }
}
