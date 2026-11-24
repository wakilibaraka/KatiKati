import CoreGraphics
import Foundation

// Phase 8b-6 — pure playback-progress maths for the Live Island's music surfaces.
//
// MediaRemote reports `elapsed` as of `timestamp`, not live; a surface that wants a moving bar must
// extrapolate `elapsed + rate * (now - timestamp)`. Kept pure (no MediaRemote, no clock reads — the
// caller passes `now`) so the clamps and the unknown-duration cases are unit-tested. Dual-compiled.

enum NowPlayingProgress {
    /// Seconds into the track right now, clamped to `0...duration` when a duration is known.
    static func elapsed(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> TimeInterval? {
        guard let elapsed, elapsed.isFinite, elapsed >= 0 else { return nil }
        var value = elapsed
        if rate > 0, let timestamp { value += rate * max(0, now.timeIntervalSince(timestamp)) }
        if let duration, duration.isFinite, duration > 0 { value = min(value, duration) }
        return value
    }

    /// 0...1, or `nil` when the duration is unknown / zero (a live stream) or the elapsed time is missing.
    static func fraction(at now: Date, elapsed: TimeInterval?, asOf timestamp: Date?, rate: Double, duration: TimeInterval?) -> Double? {
        guard let duration, duration.isFinite, duration > 0,
              let current = Self.elapsed(at: now, elapsed: elapsed, asOf: timestamp, rate: rate, duration: duration) else { return nil }
        return min(max(current / duration, 0), 1)
    }
}

// MARK: - Phase 50g: Opt-in Synced Lyrics (lrclib.net)

/// A word (or syllable, when the provider tags it that way) inside an enhanced-LRC line.
struct LyricsWord: Equatable, Sendable {
    var time: TimeInterval
    var text: String
}

struct LyricsLine: Equatable, Sendable {
    var time: TimeInterval
    var text: String
    /// Enhanced LRC only (`[00:12.50]<00:12.50>Hello <00:12.90>world`). Empty for plain LRC, so every
    /// existing surface keeps its line-by-line behaviour.
    var words: [LyricsWord] = []
}

enum LyricsTrack {
    static let enabledKey = "com.katikati.notch.lyrics"

    /// Parses standard `[mm:ss.xx]` or `[mm:ss]` LRC lines into sorted `LyricsLine` entries.
    static func parseLRC(_ raw: String) -> [LyricsLine] {
        var out: [LyricsLine] = []
        for rawLine in raw.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { continue }
            let tag = line[line.index(after: line.startIndex)..<close]
            let parts = tag.split(separator: ":")
            guard parts.count == 2,
                  let minutes = Double(parts[0]),
                  let seconds = Double(parts[1]),
                  minutes >= 0, seconds >= 0 else { continue }
            let body = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
            let (lyric, words) = splitWordTags(body)
            guard !lyric.isEmpty else { continue }
            out.append(LyricsLine(time: minutes * 60 + seconds, text: lyric, words: words))
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Splits enhanced-LRC inline tags: `Hello <00:12.90>world` -> text `Hello world`, words
    /// `[(12.9, "world")]`. A tag at the very start seeds the first word. Plain LRC returns no words, so
    /// the line-by-line path stays the only path.
    static func splitWordTags(_ body: String) -> (text: String, words: [LyricsWord]) {
        guard body.contains("<") else { return (body, []) }
        var words: [LyricsWord] = []
        var plain = ""
        var cursor = body.startIndex
        var pending: TimeInterval?
        while let open = body[cursor...].firstIndex(of: "<"),
              let close = body[open...].firstIndex(of: ">") {
            let chunk = body[cursor..<open]
            let text = chunk.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty, let time = pending {
                words.append(LyricsWord(time: time, text: text))
                plain += (plain.isEmpty ? "" : " ") + text
            } else if !text.isEmpty {
                plain += (plain.isEmpty ? "" : " ") + text
            }
            let tag = body[body.index(after: open)..<close]
            let parts = tag.split(separator: ":")
            if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]), m >= 0, s >= 0 {
                pending = m * 60 + s
            }
            cursor = body.index(after: close)
        }
        let tail = body[cursor...].trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            if let time = pending {
                words.append(LyricsWord(time: time, text: tail))
            }
            plain += (plain.isEmpty ? "" : " ") + tail
        }
        return (plain, words.sorted { $0.time < $1.time })
    }

    /// The word being sung at `elapsed`, or nil when the line carries no word tags.
    static func activeWord(in line: LyricsLine, at elapsed: TimeInterval) -> String? {
        guard !line.words.isEmpty else { return nil }
        var current: String?
        for word in line.words where word.time <= elapsed + 0.15 {
            current = word.text
        }
        return current ?? line.words.first?.text
    }

    /// Returns the most recent lyric line whose timestamp is `<= elapsed`.
    static func activeLine(in lines: [LyricsLine], at elapsed: TimeInterval) -> String? {
        guard !lines.isEmpty, elapsed >= 0 else { return nil }
        var current: String?
        for line in lines {
            if line.time <= elapsed + 0.15 {
                current = line.text
            } else {
                break
            }
        }
        return current ?? lines.first?.text
    }
}

// MARK: - Phase 60: Queue Reorder Intent & Multi-Line Timeline Matcher (Slice A-QueueLyrics)

/// Model representing a track in the playback queue.
struct NowPlayingQueueItem: Equatable, Sendable, Identifiable {
    let id: String
    var title: String
    var artist: String
    var duration: TimeInterval?

    init(id: String = UUID().uuidString, title: String, artist: String = "", duration: TimeInterval? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Pure queue manipulation logic.
enum NowPlayingQueueReorderPlan {
    /// Promotes the given track to the head of the upcoming queue (index 0).
    static func promoteTrackToTop(in queue: [NowPlayingQueueItem], id: String) -> [NowPlayingQueueItem] {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return queue }
        if index == 0 { return queue }
        var result = queue
        let item = result.remove(at: index)
        result.insert(item, at: 0)
        return result
    }

    /// Removes a track by identifier.
    static func removeTrack(in queue: [NowPlayingQueueItem], id: String) -> [NowPlayingQueueItem] {
        queue.filter { $0.id != id }
    }
}

/// Matcher that computes line windows and progress within the lyric timeline.
enum LyricTimelineMatcher {
    /// Finds the index of the active lyric line at the given elapsed time.
    static func activeIndex(in lines: [LyricsLine], at elapsed: TimeInterval) -> Int? {
        guard !lines.isEmpty, elapsed >= 0 else { return nil }
        var activeIdx: Int? = nil
        for (i, line) in lines.enumerated() {
            if line.time <= elapsed + 0.15 {
                activeIdx = i
            } else {
                break
            }
        }
        return activeIdx ?? 0
    }

    /// Returns a sliding window of lyric lines centered on or near the active line.
    static func window(in lines: [LyricsLine], at elapsed: TimeInterval, windowSize: Int = 3) -> [LyricsLine] {
        guard !lines.isEmpty else { return [] }
        guard let active = activeIndex(in: lines, at: elapsed) else { return Array(lines.prefix(windowSize)) }
        let half = windowSize / 2
        let start = max(0, min(lines.count - windowSize, active - half))
        let end = min(lines.count, start + windowSize)
        return Array(lines[start..<end])
    }

    /// Progress (0...1) from current line start time to next line start time.
    static func lineProgress(in lines: [LyricsLine], at elapsed: TimeInterval) -> Double {
        guard let activeIdx = activeIndex(in: lines, at: elapsed), lines.indices.contains(activeIdx) else { return 0.0 }
        let currentLine = lines[activeIdx]
        let nextTime = (activeIdx + 1 < lines.count) ? lines[activeIdx + 1].time : (currentLine.time + 4.0)
        let span = max(0.5, nextTime - currentLine.time)
        let prog = (elapsed - currentLine.time) / span
        return min(max(prog, 0.0), 1.0)
    }
}

/// Size profiles for detachable FloatingPlayerPanel.
enum FloatingPlayerSize: String, CaseIterable, Sendable {
    case mini
    case player
    case expanded

    var defaultDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .mini: return (180, 48)
        case .player: return (280, 120)
        case .expanded: return (340, 280)
        }
    }
}


// MARK: - ML-1: Music surfaces (pure, dual-compiled, no AppKit)

/// The three Canapé glass treatments, mapped onto the desktop canvas' existing material enum so there is
/// exactly one glass vocabulary in the app.
enum MusicGlassStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case clear
    case semi
    case tinted

    var id: String { rawValue }

    var material: DesktopBoxMaterialStyle {
        switch self {
        case .clear: return .clearMinimal
        case .semi: return .frostedGlass
        case .tinted: return .tintedGlass
        }
    }

    var title: String {
        switch self {
        case .clear: return String(localized: "Clear")
        case .semi: return String(localized: "Semi")
        case .tinted: return String(localized: "Tinted")
        }
    }
}

/// A colour in 0…1 components, so the palette can live in this AppKit-free file and be dual-compiled.
struct MusicRGB: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = min(max(r, 0), 1)
        self.g = min(max(g, 0), 1)
        self.b = min(max(b, 0), 1)
    }

    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Mix toward white (positive) or black (negative).
    func shifted(by amount: Double) -> MusicRGB {
        if amount >= 0 { return MusicRGB(r + (1 - r) * amount, g + (1 - g) * amount, b + (1 - b) * amount) }
        let k = 1 + amount
        return MusicRGB(r * k, g * k, b * k)
    }
}

/// One dominant/secondary pair per track, derived from a tiny downsampled buffer. Pure on purpose: the
/// CoreImage downsample lives in the renderer, the maths and the cache key live here and are testable.
struct MusicArtworkPalette: Equatable, Sendable {
    var accent: MusicRGB
    var secondary: MusicRGB
    var isDark: Bool

    static let fallback = MusicArtworkPalette(
        accent: MusicRGB(0.42, 0.46, 0.95),
        secondary: MusicRGB(0.62, 0.38, 0.88),
        isDark: true
    )

    init(accent: MusicRGB, secondary: MusicRGB, isDark: Bool) {
        self.accent = accent
        self.secondary = secondary
        self.isDark = isDark
    }

    /// `pixels` is RGBA8. Colours are bucketed into a 4×4×4 grid, the two most-populated buckets that are
    /// neither near-black nor near-white become accent and secondary. One pass, no k-means, no allocation
    /// per pixel beyond two small arrays.
    init(pixels: [UInt8]) {
        guard pixels.count >= 4 else { self = .fallback; return }
        var counts = [Int](repeating: 0, count: 64)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 64)
        var index = 0
        while index + 3 < pixels.count {
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            index += 4
            let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard lum > 0.06, lum < 0.94 else { continue }
            let bucket = (Int(r * 3.999) << 4) | (Int(g * 3.999) << 2) | Int(b * 3.999)
            counts[bucket] += 1
            sums[bucket].0 += r
            sums[bucket].1 += g
            sums[bucket].2 += b
        }
        let ranked = counts.indices.filter { counts[$0] > 0 }.sorted { counts[$0] > counts[$1] }
        guard let first = ranked.first else { self = .fallback; return }
        func colour(_ bucket: Int) -> MusicRGB {
            let n = Double(max(counts[bucket], 1))
            return MusicRGB(sums[bucket].0 / n, sums[bucket].1 / n, sums[bucket].2 / n)
        }
        let accent = colour(first)
        let secondary = ranked.dropFirst().first.map(colour) ?? accent.shifted(by: 0.25)
        self.init(accent: accent, secondary: secondary, isDark: accent.luminance < 0.62)
    }
}

/// Which of the three places a shared style is being resolved for.
enum MusicSurface: String, CaseIterable, Codable, Sendable, Identifiable {
    case wallpaper
    case lockScreen
    case desktop

    var id: String { rawValue }
}

/// §5.7 — one glass vocabulary for the card, the lock screen and the widget, mapped onto the canvas'
/// existing material enum so there is still exactly one glass implementation in the app.
enum MusicSurfaceTheme: String, CaseIterable, Codable, Sendable, Identifiable {
    case clearGlass
    case semiGlass
    case tintedGlass
    case oledBlack
    case crispLight

    var id: String { rawValue }

    init(legacy: MusicGlassStyle) {
        switch legacy {
        case .clear: self = .clearGlass
        case .semi: self = .semiGlass
        case .tinted: self = .tintedGlass
        }
    }

    var usesMaterial: Bool {
        switch self {
        case .semiGlass, .tintedGlass: return true
        case .clearGlass, .oledBlack, .crispLight: return false
        }
    }

    var material: DesktopBoxMaterialStyle {
        switch self {
        case .clearGlass: return .clearMinimal
        case .semiGlass: return .frostedGlass
        case .tintedGlass: return .tintedGlass
        case .oledBlack, .crispLight: return .clearMinimal
        }
    }

    /// Scrim painted over the material (or straight onto the desktop for the two solid presets).
    var scrimOpacity: Double {
        switch self {
        case .clearGlass: return 0.22
        case .semiGlass: return 0.16
        case .tintedGlass: return 0.22
        case .oledBlack: return 0.94
        case .crispLight: return 0.82
        }
    }

    var scrimIsLight: Bool { self == .crispLight }

    var isDark: Bool { self != .crispLight }

    var primaryTextOpacity: Double { isDark ? 1 : 0.9 }

    var secondaryTextOpacity: Double { isDark ? 0.55 : 0.48 }

    var rimOpacity: Double {
        switch self {
        case .clearGlass: return 0.38
        case .semiGlass: return 0.34
        case .tintedGlass: return 0.34
        case .oledBlack: return 0.22
        case .crispLight: return 0.5
        }
    }

    /// How much of the artwork accent is mixed into the surface.
    var accentMix: Double {
        switch self {
        case .clearGlass: return 0
        case .semiGlass: return 0.04
        case .tintedGlass: return 0.18
        case .oledBlack: return 0.06
        case .crispLight: return 0.10
        }
    }
}

/// §5.7 — the three card shapes. `.hero` is the Mooziac large-artwork card with the three lyric slots.
enum MusicCardLayout: String, CaseIterable, Codable, Sendable, Identifiable {
    case slim
    case full
    case hero

    var id: String { rawValue }

    var showsArtwork: Bool { self == .hero }

    var showsScrubber: Bool { self != .slim }

    var showsTransport: Bool { true }

    var lyricSlots: Int { self == .hero ? 3 : 1 }

    var artworkSide: CGFloat { self == .hero ? 92 : 0 }

    /// Height the desktop panel should ask for. Pure, so the panel callback and the lock card agree.
    func height(width: CGFloat) -> CGFloat {
        switch self {
        case .slim: return 96
        case .full: return 300
        case .hero: return max(320, artworkSide + 200)
        }
    }

    static func from(mode: MusicWidgetMode, heroEnabled: Bool) -> MusicCardLayout {
        switch mode {
        case .slim: return .slim
        case .full: return heroEnabled ? .hero : .full
        }
    }
}

/// §5.7 — scrubber shapes with deterministic, seeded bar heights: same track, same shape, no audio tap.
enum MusicScrubberStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case slim
    case pill
    case dotted
    case waveform

    var id: String { rawValue }

    var barCount: Int {
        switch self {
        case .slim, .pill: return 1
        case .dotted: return 24
        case .waveform: return 32
        }
    }

    /// Atmospheric draws a thick rounded pill (5 pt) rather than the 3 pt hairline.
    var trackHeight: CGFloat {
        switch self {
        case .pill: return 5
        case .slim: return 3
        case .dotted, .waveform: return 14
        }
    }

    /// FNV-1a over `title|artist` — the same hash family the wallpaper cache uses, so nothing here is random.
    static func seed(title: String?, artist: String?) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(title ?? "")|\(artist ?? "")".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// Deterministic heights in `minimum…1`, derived only from the seed and the index.
    static func barHeights(seed: UInt64, count: Int, minimum: CGFloat = 0.18) -> [CGFloat] {
        guard count > 0 else { return [] }
        var state = seed == 0 ? 0x9e3779b97f4a7c15 : seed
        return (0..<count).map { _ in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let unit = CGFloat(state % 1000) / 1000
            return minimum + (1 - minimum) * unit
        }
    }

    func heights(title: String?, artist: String?) -> [CGFloat] {
        Self.barHeights(seed: Self.seed(title: title, artist: artist), count: barCount)
    }
}

/// §5.7 — how the wallpaper paints the same theme full-bleed.
enum MusicWallpaperStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case atmosphericMesh
    case fullBleedFade
    case blurredAlbum
    case adaptiveTint
    case oledBlack
    case crispLight
    case heroArtwork

    var id: String { rawValue }

    var blurRadius: Double {
        switch self {
        case .atmosphericMesh: return 64
        case .fullBleedFade: return 58
        case .blurredAlbum: return 55
        case .heroArtwork: return 42
        case .adaptiveTint: return 30
        case .oledBlack: return 24
        case .crispLight: return 18
        }
    }

    /// The two Atmospheric styles paint their own artwork treatment in the renderer.
    var isAtmospheric: Bool { self == .atmosphericMesh || self == .fullBleedFade }

    /// Crisp-art styles keep the artwork readable; the others are washes.
    var keepsArtworkCrisp: Bool {
        switch self {
        case .oledBlack, .crispLight, .heroArtwork, .fullBleedFade: return true
        case .blurredAlbum, .adaptiveTint, .atmosphericMesh: return false
        }
    }

    var dim: Double {
        switch self {
        case .blurredAlbum: return 0
        case .adaptiveTint: return 0.08
        case .oledBlack: return 0.42
        case .crispLight: return 0
        case .heroArtwork: return 0.12
        case .atmosphericMesh: return 0.16
        case .fullBleedFade: return 0.10
        }
    }

    var brighten: Double { self == .crispLight ? 0.10 : 0 }

    var tintMix: Double {
        switch self {
        case .adaptiveTint: return 0.30
        case .atmosphericMesh: return 0.24
        default: return 0
        }
    }
}

/// A single shared style, optionally overridden per surface (§5.8).
struct MusicSurfaceStyle: Equatable, Codable, Sendable {
    var theme: MusicSurfaceTheme
    var scrubber: MusicScrubberStyle
    var layout: MusicCardLayout
    var wallpaperStyle: MusicWallpaperStyle

    /// Atmospheric (Full-Bleed) is the default on all four surfaces; every earlier style stays selectable.
    static let standard = MusicSurfaceStyle(theme: .semiGlass, scrubber: .pill, layout: .full,
                                            wallpaperStyle: .atmosphericMesh)
}

struct MusicStyleSelection: Equatable, Codable, Sendable {
    var base: MusicSurfaceStyle = .standard
    /// On by default: one picker group drives wallpaper, lock screen and widget.
    var matchesAcrossSurfaces: Bool = true
    var overrides: [String: MusicSurfaceStyle] = [:]

    func style(for surface: MusicSurface) -> MusicSurfaceStyle {
        guard !matchesAcrossSurfaces, let override = overrides[surface.rawValue] else { return base }
        return override
    }

    func theme(for surface: MusicSurface) -> MusicSurfaceTheme { style(for: surface).theme }
    func scrubber(for surface: MusicSurface) -> MusicScrubberStyle { style(for: surface).scrubber }
    func layout(for surface: MusicSurface) -> MusicCardLayout { style(for: surface).layout }
    func wallpaperStyle(for surface: MusicSurface) -> MusicWallpaperStyle { style(for: surface).wallpaperStyle }

    mutating func set(_ style: MusicSurfaceStyle, for surface: MusicSurface) {
        guard !matchesAcrossSurfaces else { base = style; return }
        overrides[surface.rawValue] = style
    }
}

/// The two configurable slots either side of the transport row.
enum MusicControlSlot: String, CaseIterable, Codable, Sendable, Identifiable {
    case lyrics
    case favorite
    case shuffle
    case repeatTrack = "repeat"
    case output
    case copy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lyrics: return String(localized: "Lyrics")
        case .favorite: return String(localized: "Favorite")
        case .shuffle: return String(localized: "Shuffle")
        case .repeatTrack: return String(localized: "Repeat")
        case .output: return String(localized: "Output")
        case .copy: return String(localized: "Copy")
        }
    }

    var symbolName: String {
        switch self {
        case .lyrics: return "text.quote"
        case .favorite: return "heart"
        case .shuffle: return "shuffle"
        case .repeatTrack: return "repeat"
        case .output: return "airplayaudio"
        case .copy: return "doc.on.doc"
        }
    }
}

/// What the current player can actually be asked to do. Slots the player cannot serve are hidden, never
/// rendered as dead buttons.
struct MusicControlCapabilities: Equatable, Sendable {
    var canLyrics = true
    var canFavorite = true
    /// `NowPlayingService` has no player-agnostic shuffle/repeat command: offer them only when a caller
    /// proves support.
    var canShuffle = false
    var canRepeat = false
    var canOutput = true
    var canCopy = true

    static let standard = MusicControlCapabilities()

    func offers(_ slot: MusicControlSlot) -> Bool {
        switch slot {
        case .lyrics: return canLyrics
        case .favorite: return canFavorite
        case .shuffle: return canShuffle
        case .repeatTrack: return canRepeat
        case .output: return canOutput
        case .copy: return canCopy
        }
    }
}

enum MusicControlSide: String, CaseIterable, Sendable {
    case left
    case right
}

/// Left/right slot pair. Always distinct: assignment normalises, so a stored duplicate can never hide a
/// control.
struct MusicControlAssignment: Equatable, Sendable {
    static let defaultLeft: MusicControlSlot = .lyrics
    static let defaultRight: MusicControlSlot = .output

    private(set) var left: MusicControlSlot
    private(set) var right: MusicControlSlot

    init(left: MusicControlSlot = MusicControlAssignment.defaultLeft,
         right: MusicControlSlot = MusicControlAssignment.defaultRight) {
        self.left = left
        self.right = right == left ? Self.alternative(to: left) : right
    }

    init(leftRaw: String?, rightRaw: String?) {
        let left = leftRaw.flatMap { MusicControlSlot(rawValue: $0) } ?? Self.defaultLeft
        let right = rightRaw.flatMap { MusicControlSlot(rawValue: $0) } ?? Self.defaultRight
        self.init(left: left, right: right)
    }

    /// The slot to draw on `side`, or nil when the player cannot serve it (the row then keeps the space
    /// empty instead of showing a dead control).
    func resolved(_ capabilities: MusicControlCapabilities) -> (left: MusicControlSlot?, right: MusicControlSlot?) {
        (capabilities.offers(left) ? left : nil, capabilities.offers(right) ? right : nil)
    }

    mutating func set(_ slot: MusicControlSlot, on side: MusicControlSide) {
        switch side {
        case .left:
            left = slot
            if right == slot { right = Self.alternative(to: slot) }
        case .right:
            right = slot
            if left == slot { left = Self.alternative(to: slot) }
        }
    }

    /// Deterministic replacement when a duplicate is picked.
    static func alternative(to slot: MusicControlSlot) -> MusicControlSlot {
        switch slot {
        case .lyrics: return .output
        case .output: return .lyrics
        case .favorite: return .copy
        case .copy: return .favorite
        case .shuffle: return .repeatTrack
        case .repeatTrack: return .shuffle
        }
    }
}

/// Slim bar vs full controls.
enum MusicWidgetMode: String, CaseIterable, Codable, Sendable {
    case slim
    case full
}

/// What a completed two-finger gesture asks the widget to do.
enum MusicSwipeOutcome: Equatable, Sendable {
    case resize(MusicWidgetMode)
    case skip(forward: Bool)
    case none
}

/// Which axis the gesture locked onto. Chosen once per gesture and never re-evaluated, so a diagonal can
/// never both resize and skip.
enum MusicSwipeAxis: String, Sendable {
    case horizontal
    case vertical
}

/// Two-finger gesture state machine: locks to one axis so a diagonal never both resizes and skips, fires
/// once per gesture, and rate-limits repeats with a cooldown.
struct MusicSwipeMachine: Sendable {
    var threshold: CGFloat = 42
    var velocityThreshold: CGFloat = 240
    var cooldown: TimeInterval = 0.28

    private(set) var axis: MusicSwipeAxis? = nil
    private var accumulated: CGFloat = 0
    private var lastFire: TimeInterval = -.infinity
    private var firedThisGesture = false

    init(threshold: CGFloat = 42, velocityThreshold: CGFloat = 240, cooldown: TimeInterval = 0.28) {
        self.threshold = threshold
        self.velocityThreshold = velocityThreshold
        self.cooldown = cooldown
    }

    /// New gesture began (`scrollWheel` phase `.began`).
    mutating func begin() {
        accumulated = 0
        axis = nil
        firedThisGesture = false
    }

    /// Ignore events until the dominant axis clears the lock threshold; return nothing while deciding.
    mutating func accumulate(deltaX: CGFloat, deltaY: CGFloat) {
        guard !firedThisGesture else { return }
        if axis == nil {
            // 6 pt of dominance before locking, so a shaky finger does not pick the wrong axis.
            if abs(deltaX) > abs(deltaY) + 6 { axis = .horizontal }
            else if abs(deltaY) > abs(deltaX) + 6 { axis = .vertical }
            else { return }
        }
        accumulated += (axis == .horizontal ? deltaX : deltaY)
    }

    /// Gesture ended (`scrollWheel` phase `.ended`). `mode` is the current size so a vertical swipe can
    /// toggle either way.
    mutating func end(velocity: CGFloat = 0, at now: TimeInterval, currentMode: MusicWidgetMode) -> MusicSwipeOutcome {
        defer { accumulated = 0; axis = nil; firedThisGesture = false }
        guard let axis, now - lastFire >= cooldown else { return .none }
        guard abs(accumulated) >= threshold || abs(velocity) >= velocityThreshold else { return .none }
        lastFire = now
        firedThisGesture = true
        switch axis {
        case .horizontal:
            // Natural scrolling inverts: a leftward two-finger move is a positive deltaX.
            let forward = accumulated < 0
            return .skip(forward: forward)
        case .vertical:
            let next: MusicWidgetMode
            if abs(accumulated) >= threshold {
                next = accumulated < 0 ? .full : .slim
            } else {
                next = currentMode == .full ? .slim : .full
            }
            return .resize(next)
        }
    }
}

/// Which display edge the widget tucks into.
enum MusicStashEdge: String, CaseIterable, Codable, Sendable {
    case left
    case right
}

/// Edge-stash geometry. Pure so the clamping is unit-tested instead of eyeballed.
enum MusicEdgeStash {
    /// How much of the card stays on screen while stashed.
    static let revealWidth: CGFloat = 16

    /// Frame for a stashed card: flush with the chosen edge, only `reveal` points visible.
    static func stashedFrame(_ frame: CGRect, in visible: CGRect, edge: MusicStashEdge,
                             reveal: CGFloat = revealWidth) -> CGRect {
        let clamped = frame.width > visible.width
            ? CGRect(x: visible.minX, y: frame.minY, width: visible.width, height: frame.height)
            : frame
        let x: CGFloat
        switch edge {
        case .left: x = visible.minX - clamped.width + min(reveal, clamped.width)
        case .right: x = visible.maxX - min(reveal, clamped.width)
        }
        return CGRect(x: x, y: clamped.minY, width: clamped.width, height: clamped.height)
    }

    /// Frame for a revealed card: fully back inside `visible`, never off the opposite edge.
    static func revealedFrame(_ frame: CGRect, in visible: CGRect, edge: MusicStashEdge) -> CGRect {
        let width = min(frame.width, visible.width)
        let x: CGFloat
        switch edge {
        case .left: x = visible.minX
        case .right: x = visible.maxX - width
        }
        return CGRect(x: x, y: frame.minY, width: width, height: frame.height)
    }

    /// How much of `frame` is actually on screen.
    static func visibleWidth(of frame: CGRect, in visible: CGRect) -> CGFloat {
        let clipped = frame.intersection(visible)
        return clipped.isNull ? 0 : max(0, clipped.width)
    }

    /// A stashed panel that is entirely off screen (reveal 0) cannot be hovered — the panel-level stash
    /// keeps at least `revealWidth` on screen for exactly this reason, and this predicate proves it.
    static func isFullyHidden(_ frame: CGRect, in visible: CGRect) -> Bool {
        visibleWidth(of: frame, in: visible) <= 0.5
    }

    /// Screen-space strip that reveals a stashed panel: from the screen edge to the sliver, over the
    /// panel's own vertical span. A cursor entering from that edge hits it before the panel does.
    static func revealZone(in frame: CGRect, edge: MusicStashEdge, visible: CGRect, reveal: CGFloat = revealWidth) -> CGRect {
        let height = min(frame.height, visible.height)
        let y = min(max(frame.minY, visible.minY), visible.maxY - height)
        switch edge {
        case .left:
            return CGRect(x: visible.minX, y: y, width: max(2, frame.maxX + 4 - visible.minX), height: height)
        case .right:
            return CGRect(x: frame.minX - 4, y: y, width: max(2, visible.maxX - frame.minX + 4), height: height)
        }
    }

    /// Hovering the visible sliver (or any part of a revealed card) reveals it. A left-stashed card sits
    /// off the left edge, so its sliver is at its *right* edge — and vice versa.
    static func isRevealed(mouseX: CGFloat, frame: CGRect, edge: MusicStashEdge,
                           reveal: CGFloat = revealWidth) -> Bool {
        switch edge {
        case .left: return mouseX <= frame.maxX + 2
        case .right: return mouseX >= frame.minX - 2
        }
    }
}

// MARK: - Wallpaper ownership

/// Which feature is currently painting the desktop picture. Exactly one capture of the user's original is
/// shared by all of them.
enum WallpaperSource: String, CaseIterable, Sendable {
    case weather
    case music
}

/// The fix for a real corruption path: `WallpaperEngine` captures the original only when no capture
/// exists and deletes it on restore, so a second writer used to make the *first* writer's next capture be
/// album art. The lease captures once per chain and restores only when the last holder releases.
struct WallpaperLease: Equatable, Sendable {
    private(set) var holders: Set<WallpaperSource> = []
    private(set) var isCaptured = false

    var isEmpty: Bool { holders.isEmpty }

    /// Returns true when the caller must capture the original now (first holder of a fresh chain).
    mutating func acquire(_ source: WallpaperSource) -> Bool {
        let needsCapture = holders.isEmpty && !isCaptured
        holders.insert(source)
        if needsCapture { isCaptured = true }
        return needsCapture
    }

    /// Returns true when the caller must restore the original (last holder released).
    mutating func release(_ source: WallpaperSource) -> Bool {
        holders.remove(source)
        guard holders.isEmpty, isCaptured else { return false }
        isCaptured = false
        return true
    }

    /// Adopt a capture left on disk by a previous run (crash recovery) without capturing again.
    mutating func adoptCapture() {
        isCaptured = true
    }

    /// Quit / "restore now": every holder drops and the capture is consumed.
    @discardableResult
    mutating func reset() -> Bool {
        holders.removeAll()
        guard isCaptured else { return false }
        isCaptured = false
        return true
    }
}

/// Pure backup/restore machine for the lock-screen card's own wallpaper swaps, with a persisted
/// `restorePending` marker so a crash mid-swap still restores on the next launch.
struct LockScreenWallpaperBackup: Equatable, Codable, Sendable {
    enum State: String, Codable, Sendable {
        case idle
        case held
        case restorePending
    }

    private(set) var state: State = .idle
    private(set) var originalURL: String?

    var isHolding: Bool { state != .idle }

    init() {}

    /// Returns false when a capture is already held (never overwrite the user's real wallpaper).
    mutating func capture(_ url: String) -> Bool {
        guard state == .idle, !url.isEmpty else { return false }
        originalURL = url
        state = .held
        return true
    }

    /// Called right before restoring, so a crash during the swap is still recoverable.
    mutating func markRestorePending() {
        guard state == .held else { return }
        state = .restorePending
    }

    /// Consumes the pending original and returns to idle.
    mutating func takeRestore() -> String? {
        guard state != .idle, let url = originalURL else { return nil }
        originalURL = nil
        state = .idle
        return url
    }

    mutating func cancel() {
        originalURL = nil
        state = .idle
    }
}


// MARK: - Atmospheric (Full-Bleed) — ML-7 pure core

/// The three interactive views every Atmospheric surface switches between.
enum MusicViewMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case nowPlaying
    case lyrics
    case queue

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .nowPlaying: return "play.square"
        case .lyrics: return "quote.bubble"
        case .queue: return "list.bullet"
        }
    }

    /// The three-mode bar walks the ring in this order.
    var next: MusicViewMode {
        switch self {
        case .nowPlaying: return .lyrics
        case .lyrics: return .queue
        case .queue: return .nowPlaying
        }
    }
}

/// Pear-desktop's exponential volume curve, kept pure so the card, the wings and the settings preview
/// agree on what "half way" means. 0 → silence, 1 → unity gain, three decades of usable travel.
enum MusicVolumeCurve {
    static let decades: Double = 3

    static func gain(forPosition position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        let span = pow(10, decades) - 1
        return (pow(10, decades * clamped) - 1) / span
    }

    static func position(forGain gain: Double) -> Double {
        let clamped = min(max(gain, 0), 1)
        let span = pow(10, decades) - 1
        return log10(1 + clamped * span) / decades
    }

    /// System volume is a 0…1 scalar gain, so the control maps it through the curve in both directions.
    static func percent(forPosition position: Double) -> Int {
        Int((gain(forPosition: position) * 100).rounded())
    }

    static func position(forPercent percent: Int) -> Double {
        position(forGain: Double(min(max(percent, 0), 100)) / 100)
    }
}

/// One row of the Queue / History drawer. The key is the same normalisation Favorites uses.
struct MusicQueueEntry: Identifiable, Equatable, Codable, Sendable {
    var title: String
    var artist: String?
    var artworkSignature: String?

    var key: String {
        "\(title.lowercased())|\(artist?.lowercased() ?? "")"
    }

    var id: String { key }
}

enum MusicQueueKind: String, CaseIterable, Sendable, Identifiable {
    case upcoming
    case history
    case favorites

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .upcoming: return "text.line.first.and.arrowtriangle.forward"
        case .history: return "clock.arrow.circlepath"
        case .favorites: return "star.fill"
        }
    }
}

struct MusicQueueSection: Identifiable, Equatable, Sendable {
    var kind: MusicQueueKind
    var entries: [MusicQueueEntry]

    var id: String { kind.rawValue }
}

/// Session history plus local favourites: the zero-permission fallback the plan promises. `upcoming` is
/// only ever filled by the opt-in AppleScript reader, so it stays empty when that is off or unsupported.
struct MusicQueueModel: Equatable, Codable, Sendable {
    var history: [MusicQueueEntry] = []
    var capacity: Int = 24
    var isShuffled: Bool = false
    var repeatsTrack: Bool = false
    var autoplay: Bool = true

    mutating func record(title: String?, artist: String?) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return }
        let entry = MusicQueueEntry(title: title, artist: artist)
        history.removeAll { $0.key == entry.key }
        history.insert(entry, at: 0)
        if history.count > capacity { history = Array(history.prefix(capacity)) }
    }

    func sections(upcoming: [MusicQueueEntry] = [], favorites: [MusicQueueEntry] = []) -> [MusicQueueSection] {
        var result: [MusicQueueSection] = []
        if !upcoming.isEmpty { result.append(MusicQueueSection(kind: .upcoming, entries: upcoming)) }
        if !history.isEmpty { result.append(MusicQueueSection(kind: .history, entries: history)) }
        if !favorites.isEmpty { result.append(MusicQueueSection(kind: .favorites, entries: favorites)) }
        return result
    }
}

/// One coloured stop of the Atmospheric mesh. Positions and radii are fractions of the painted surface, so
/// the renderer and any preview draw the same field at any size.
struct MusicMeshStop: Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var x: Double
    var y: Double
    var radius: Double

    init(color: MusicRGB, x: Double, y: Double, radius: Double) {
        self.r = color.r
        self.g = color.g
        self.b = color.b
        self.x = x
        self.y = y
        self.radius = radius
    }
}

/// Multi-stop adaptive mesh derived from the album palette in one pass — no per-frame sampling.
enum MusicMeshStops {
    static func stops(for palette: MusicArtworkPalette) -> [MusicMeshStop] {
        let base: MusicRGB = palette.isDark ? MusicRGB(0.05, 0.05, 0.08) : MusicRGB(0.97, 0.97, 0.99)
        func mix(_ a: MusicRGB, _ b: MusicRGB, _ t: Double) -> MusicRGB {
            MusicRGB(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
        }
        return [
            MusicMeshStop(color: palette.accent, x: 0.18, y: 0.18, radius: 0.95),
            MusicMeshStop(color: palette.secondary, x: 0.84, y: 0.28, radius: 0.85),
            MusicMeshStop(color: mix(palette.accent, base, 0.55), x: 0.50, y: 0.92, radius: 1.05),
            MusicMeshStop(color: mix(palette.secondary, base, 0.30), x: 0.10, y: 0.74, radius: 0.70),
            MusicMeshStop(color: base, x: 0.96, y: 0.96, radius: 1.10)
        ]
    }
}

/// Wing / card transport metrics. Small wings drop the volume row and the device label rather than shrinking
/// every glyph into illegibility.
struct MusicTransportLayout: Equatable, Sendable {
    var glyphSize: CGFloat
    var playDiameter: CGFloat
    var spacing: CGFloat
    var artworkSide: CGFloat
    var lyricLines: Int
    var showsScrubber: Bool
    var showsVolume: Bool
    var showsDeviceLabel: Bool

    init(size: WidgetSize) {
        switch size {
        case .small:
            glyphSize = 10
            playDiameter = 24
            spacing = 6
            artworkSide = 28
            lyricLines = 1
            showsScrubber = false
            showsVolume = false
            showsDeviceLabel = false
        case .medium:
            glyphSize = 13
            playDiameter = 30
            spacing = 10
            artworkSide = 36
            lyricLines = 2
            showsScrubber = true
            showsVolume = true
            showsDeviceLabel = true
        case .large:
            glyphSize = 16
            playDiameter = 38
            spacing = 14
            artworkSide = 52
            lyricLines = 3
            showsScrubber = true
            showsVolume = true
            showsDeviceLabel = true
        }
    }
}

/// Real romanization through ICU (`kCFStringTransformToLatin`): Japanese kana, Korean Hangul, Han and
/// Cyrillic all transliterate. A line in a script this cannot help with reports unsupported, so the 🌐 pill
/// is hidden instead of being shown inert.
enum MusicRomanizer {
    static func supports(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            let value = scalar.value
            return (0x3040...0x30FF).contains(value)      // kana
                || (0x3400...0x9FFF).contains(value)      // Han
                || (0xAC00...0xD7AF).contains(value)      // Hangul syllables
                || (0x1100...0x11FF).contains(value)      // Hangul jamo
                || (0x0400...0x04FF).contains(value)      // Cyrillic
        }
    }

    static func romanize(_ text: String) -> String? {
        guard supports(text) else { return nil }
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let latin = String(mutable)
        return latin == text ? nil : latin
    }
}

// MARK: - §10 Desktop music widget (pure policy)

/// §10 — the desktop music widget's four presets. `card` stays the default so an existing desktop widget
/// keeps its size; `poster`, `stage` and `strip` are additive.
enum MusicDesktopWidgetPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Full-screen art poster: below the Finder icons and click-through, so it behaves like a picture.
    case poster
    /// Half-screen stage panel: above the icons, below every app window.
    case stage
    /// The existing desktop card, unchanged in behaviour.
    case card
    /// A thin strip with title, scrubber and transport.
    case strip

    var id: String { rawValue }

    static let standard: MusicDesktopWidgetPreset = .card
}

extension MusicCardLayout {
    /// Single source of truth for the lock card (was 340 x 316/224/208 hard-coded in the overlay).
    static let lockWidth: CGFloat = 340

    func lockHeight(showsVolumeRow: Bool) -> CGFloat {
        self == .hero ? 316 : (showsVolumeRow ? 224 : 208)
    }

    var lockSize: CGSize { CGSize(width: Self.lockWidth, height: lockHeight(showsVolumeRow: true)) }
}

/// Which window level a preset may occupy. There are only two, and neither is above a normal window.
enum MusicDesktopWidgetLevel: String, Sendable, CaseIterable {
    /// `CGWindowLevelForKey(.desktopWindow) + 1` — below the desktop icons, above the desktop picture.
    case desktopPicture
    /// `CGWindowLevelForKey(.desktopIconWindow) + 1` — above the icons, below every app window.
    case desktopIcons
}

enum MusicDesktopWidgetPolicy {
    /// Poster sits behind the icons; everything else may sit above them but never above app windows.
    static func level(for preset: MusicDesktopWidgetPreset) -> MusicDesktopWidgetLevel {
        preset == .poster ? .desktopPicture : .desktopIcons
    }

    /// Numeric window level for a preset. Asserted in tests to stay below `normalWindowLevel`.
    static func windowLevel(for preset: MusicDesktopWidgetPreset) -> Int {
        switch level(for: preset) {
        case .desktopPicture: return Int(CGWindowLevelForKey(.desktopWindow)) + 1
        case .desktopIcons: return Int(CGWindowLevelForKey(.desktopIconWindow)) + 1
        }
    }

    /// The level of a normal app window: nothing here may reach or exceed it.
    static var normalWindowLevel: Int { Int(CGWindowLevelForKey(.normalWindow)) }

    /// Poster is a picture: it must never intercept a click, so icons, right-click and drag-select keep working.
    static func ignoresMouseEvents(for preset: MusicDesktopWidgetPreset) -> Bool {
        preset == .poster
    }

    /// Animations only run when the panel is visible, on screen and not covered by a window.
    static func pausesAnimations(isHidden: Bool, isOccluded: Bool) -> Bool {
        isHidden || isOccluded
    }
}

/// Menu-bar / Dock style insets for the surface the widget is placed in.
struct MusicDesktopWidgetInsets: Equatable, Sendable {
    var top: CGFloat = 0
    var bottom: CGFloat = 0
    var leading: CGFloat = 0
    var trailing: CGFloat = 0

    static let zero = MusicDesktopWidgetInsets()
}

enum MusicDesktopWidgetStageSide: String, Sendable, CaseIterable {
    case leading, trailing, top, bottom
}

/// Pure geometry: every rect the widget can take, clamped to the visible frame and snapped to its edges.
enum MusicDesktopWidgetGeometry {
    static let cardSize = CGSize(width: 300, height: 224)
    static let stripHeight: CGFloat = 44
    static let edgeMargin: CGFloat = 24
    static let snapThreshold: CGFloat = 32

    /// The rect a preset asks for inside `visibleFrame` (which already excludes the menu bar and the Dock;
    /// `insets` adds a user margin on top of that).
    static func rect(
        for preset: MusicDesktopWidgetPreset,
        in visibleFrame: CGRect,
        insets: MusicDesktopWidgetInsets = .zero,
        stageSide: MusicDesktopWidgetStageSide = .trailing
    ) -> CGRect {
        let bounds = clamp(CGRect(
            x: visibleFrame.minX + insets.leading,
            y: visibleFrame.minY + insets.bottom,
            width: max(0, visibleFrame.width - insets.leading - insets.trailing),
            height: max(0, visibleFrame.height - insets.top - insets.bottom)
        ), into: visibleFrame)
        return clamp(rawRect(for: preset, in: bounds, stageSide: stageSide), into: bounds)
    }

    private static func rawRect(
        for preset: MusicDesktopWidgetPreset,
        in bounds: CGRect,
        stageSide: MusicDesktopWidgetStageSide
    ) -> CGRect {
        switch preset {
        case .poster:
            return bounds
        case .stage:
            switch stageSide {
            case .leading:
                return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)
            case .trailing:
                return CGRect(x: bounds.midX, y: bounds.minY, width: bounds.width / 2, height: bounds.height)
            case .top:
                return CGRect(x: bounds.minX, y: bounds.midY, width: bounds.width, height: bounds.height / 2)
            case .bottom:
                return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height / 2)
            }
        case .card:
            return CGRect(
                x: bounds.maxX - cardSize.width - edgeMargin,
                y: bounds.minY + edgeMargin,
                width: cardSize.width,
                height: cardSize.height
            )
        case .strip:
            return CGRect(
                x: bounds.minX + edgeMargin,
                y: bounds.minY + edgeMargin,
                width: max(0, bounds.width - edgeMargin * 2),
                height: stripHeight
            )
        }
    }

    /// Keeps a dragged/resized rect inside the surface: shrinks it when it is larger than the surface.
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(max(0, rect.width), bounds.width)
        let height = min(max(0, rect.height), bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Snaps to the nearest edge on each axis when it is within `threshold`; otherwise leaves that axis alone.
    static func snap(
        _ rect: CGRect,
        into bounds: CGRect,
        threshold: CGFloat = snapThreshold
    ) -> CGRect {
        var result = clamp(rect, into: bounds)
        if abs(result.minX - bounds.minX) <= threshold {
            result.origin.x = bounds.minX
        } else if abs(bounds.maxX - result.maxX) <= threshold {
            result.origin.x = bounds.maxX - result.width
        }
        if abs(result.minY - bounds.minY) <= threshold {
            result.origin.y = bounds.minY
        } else if abs(bounds.maxY - result.maxY) <= threshold {
            result.origin.y = bounds.maxY - result.height
        }
        return result
    }

    /// Smallest a user-resized widget may become; a strip keeps its single-row height.
    static func minimumSize(for preset: MusicDesktopWidgetPreset) -> CGSize {
        switch preset {
        case .poster: return cardSize
        case .stage, .card: return CGSize(width: 240, height: 160)
        case .strip: return CGSize(width: 320, height: stripHeight)
        }
    }

    /// A live drag: the rect keeps its size and only its origin moves, held inside the surface.
    static func moved(_ rect: CGRect, by delta: CGSize, into bounds: CGRect) -> CGRect {
        clamp(rect.offsetBy(dx: delta.width, dy: delta.height), into: bounds)
    }

    /// A live resize from the bottom-trailing grip: the top-leading corner stays put and the size stays
    /// between the preset minimum and the surface. A strip only grows wider, never taller.
    static func resized(
        _ rect: CGRect,
        by delta: CGSize,
        preset: MusicDesktopWidgetPreset,
        into bounds: CGRect
    ) -> CGRect {
        let minimum = minimumSize(for: preset)
        let maxWidth = max(minimum.width, bounds.maxX - rect.minX)
        let width = min(max(minimum.width, rect.width + delta.width), maxWidth)
        let height: CGFloat
        if preset == .strip {
            height = stripHeight
        } else {
            let maxHeight = max(minimum.height, rect.maxY - bounds.minY)
            height = min(max(minimum.height, rect.height + delta.height), maxHeight)
        }
        return clamp(CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height), into: bounds)
    }

    /// Placement is remembered per display in the same normalized form `DesktopWidgetItem` already uses.
    static func normalized(_ rect: CGRect, in bounds: CGRect) -> NormalizedWidgetRect {
        guard bounds.width > 0, bounds.height > 0 else {
            return NormalizedWidgetRect(x: 0, y: 0, width: 0, height: 0)
        }
        return NormalizedWidgetRect(
            x: rect.minX / bounds.width,
            y: rect.minY / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height
        )
    }

    static func frame(from normalized: NormalizedWidgetRect, in bounds: CGRect) -> CGRect {
        clamp(CGRect(
            x: bounds.minX + normalized.x * bounds.width,
            y: bounds.minY + normalized.y * bounds.height,
            width: normalized.width * bounds.width,
            height: normalized.height * bounds.height
        ), into: bounds)
    }
}
