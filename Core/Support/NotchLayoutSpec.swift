import CoreGraphics
import Foundation
import simd

// Notch Live Island "boring" skin — the pure layout numbers and panel-selection rules.
//
// The numbers are the open-notch proportions of the reference design (a 640×190 black NotchShape with a
// header row, a music half and a calendar half). Keeping them here, away from SwiftUI, lets the sizes,
// the corner radii, the week strip and "which panels show" be unit-tested. Dual-compiled.

/// Which look the notch uses. `liquid` is the Liquid Notch metaball shell (default);
/// `boring` (Full), `classic` (Compact), and `dynamicIsland` are preserved as selectable presets.
enum LiveIslandSkin: String, CaseIterable, Sendable {
    case liquid
    case classic
    case boring
    case dynamicIsland
}

typealias NotchShellPreset = LiveIslandSkin

enum NotchTab: String, CaseIterable, Sendable {
    case home
    /// Focus & timers, clipboard + quick note, system HUD (the file shelf lives on the dock).
    case tools

    var localizedTitle: String {
        switch self {
        case .home: return String(localized: "Home")
        case .tools: return String(localized: "Tools")
        }
    }
}

enum NotchLayoutSpec {
    // MARK: sizes
    static let openSize = CGSize(width: 640, height: 190)
    static let closedCornerRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openCornerRadii = (top: CGFloat(19), bottom: CGFloat(24))
    static let openPadding: CGFloat = 12
    static let homeSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 12
    static let cardFillOpacity = 0.07
    static let headerSpacing: CGFloat = 8
    static let volumeSliderWidth: CGFloat = 56
    static let calendarColumnWidth: CGFloat = 215
    static let albumArtSize: CGFloat = 88
    static let albumArtCorner: CGFloat = 13
    static let headerButtonSize: CGFloat = 26
    static let progressHeight: CGFloat = 10

    // MARK: animation
    // The springs live in `NotchMotionSpec` only (51e): the pair that used to sit here (0.42/0.8 open,
    // 0.45/1.0 close) had no reference anywhere and disagreed with the 0.38/1.0 and 0.32/1.0 the views
    // actually run, so it was a second source of truth for the feel.

    /// Header is as tall as the closed notch (it flanks it) — never shorter than the buttons.
    static func headerHeight(closedHeight: CGFloat) -> CGFloat {
        max(closedHeight, headerButtonSize)
    }

    /// The open panel is never wider than the screen minus a small margin, and never narrower than
    /// the closed notch.
    static func openPanelSize(screenWidth: CGFloat, closedWidth: CGFloat) -> CGSize {
        let width = min(openSize.width, max(closedWidth, screenWidth - 24))
        return CGSize(width: width, height: openSize.height)
    }

    /// `size` clamped to the screen width (see `openPanelSize`); the height is kept.
    static func fit(_ size: CGSize, screenWidth: CGFloat, closedWidth: CGFloat) -> CGSize {
        CGSize(width: min(size.width, max(closedWidth, screenWidth - 24)), height: size.height)
    }

    // MARK: ear zones

    /// What may sit left and right of the camera cutout on the collapsed notch, in the capsule's own
    /// coordinates (origin top-left). Both are `.zero` without hardware: a fake pill has no cutout to flank.
    struct EarZones: Equatable {
        var left: CGRect
        var right: CGRect
    }

    /// The capsule grows by `sneakSide` on each side while an activity shows, which pushes the keepout
    /// inward from the capsule edges by the same amount.
    static func earZones(metrics: NotchMetrics, showsActivity: Bool) -> EarZones {
        guard metrics.hasHardwareNotch, !metrics.cameraKeepoutBox.isEmpty else { return EarZones(left: .zero, right: .zero) }
        let sneak = showsActivity ? NotchGeometry.sneakSide : 0
        let keepout = metrics.cameraKeepoutBox
        let total = metrics.closedSize.width + 2 * sneak
        let height = metrics.closedSize.height
        let leftWidth = keepout.minX + sneak
        let rightX = keepout.maxX + sneak
        return EarZones(left: CGRect(x: 0, y: 0, width: leftWidth, height: height),
                        right: CGRect(x: rightX, y: 0, width: total - rightX, height: height))
    }

    // MARK: panels

    enum LeftPanel: Equatable { case music, activity }

    struct Panels: Equatable {
        var left: LeftPanel
        var showsCalendar: Bool
    }

    /// Music panel when music is the winning activity **or nothing is active** (the idle clock fallback
    /// is never shown on the notch — idle is the Now Playing player with quick actions); otherwise the
    /// running activity (timer, focus, stopwatch, countdown).
    static func panels(activityKind: LiveActivityKind, calendarEnabled: Bool) -> Panels {
        let showsPlayer = activityKind == .music || activityKind == .clock
        return Panels(left: showsPlayer ? .music : .activity, showsCalendar: calendarEnabled)
    }

    // MARK: week strip

    struct WeekDay: Equatable {
        var date: Date
        var dayNumber: Int
        var isToday: Bool
    }

    /// Seven consecutive days starting three days before `now` so today sits in the middle of the
    /// strip, like the reference ("Sat … Thu" with today fourth).
    static func weekStrip(now: Date, calendar: Calendar = .current) -> [WeekDay] {
        let today = calendar.startOfDay(for: now)
        return (-3...3).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return WeekDay(date: day, dayNumber: calendar.component(.day, from: day), isToday: offset == 0)
        }
    }

    /// "mm:ss" or "h:mm:ss"; clamps negatives to zero.
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: page body

    /// The 4 pt gap the page group adds under the header row (`NotchHomeView`).
    static let pageTopPadding: CGFloat = 4

    /// Height left for a Bento page's cards: the open panel minus the header row that flanks the notch,
    /// the page gap, and the grid's bottom padding. A card that asks for more than this is clipped by the
    /// panel with no warning, so the cards' own budgets are asserted against it in the tests.
    static func pageBodyHeight(headerHeight: CGFloat) -> CGFloat {
        openSize.height - headerHeight - pageTopPadding - NotchDesignSpec.gridPadding.bottom
    }
}

/// NP-2: the one top bar the open notch wears. The old header drew nine 19 pt buttons with 10 pt glyphs
/// left of the cutout; the replacement is a single capsule that names the page it is on and opens the
/// same roster. The numbers live here so "does the pill still fit beside the camera?" is a test.
enum NotchPageChrome {
    static let pillHeight: CGFloat = 22
    static let pillHorizontalPadding: CGFloat = 9
    static let pillSpacing: CGFloat = 5
    static let pillIcon: CGFloat = 10
    static let pillChevron: CGFloat = 7
    static let pillTitleSize: CGFloat = 10.5
    /// A title never takes the whole ear; the volume, battery and settings still need the other side.
    static let pillMaxTitleWidth: CGFloat = 118
    /// Volume (65) + battery chip (≈50) + gear (22) + two 6 pt gaps, rounded up.
    static let rightClusterWidth: CGFloat = 150

    /// The room left of the camera cutout in the open panel, minus the panel's own 4 pt inset.
    static func leftEarWidth(openWidth: CGFloat, closedWidth: CGFloat) -> CGFloat {
        max(0, (openWidth - closedWidth) / 2 - 4)
    }

    /// The pill at its widest title.
    static func pillWidth(titleWidth: CGFloat = pillMaxTitleWidth) -> CGFloat {
        2 * pillHorizontalPadding + pillIcon + pillChevron + 2 * pillSpacing + titleWidth
    }

    /// Both sides fit beside the cutout without touching it.
    static func fits(openWidth: CGFloat, closedWidth: CGFloat) -> Bool {
        let ear = leftEarWidth(openWidth: openWidth, closedWidth: closedWidth)
        return pillWidth() <= ear && rightClusterWidth <= ear
    }
}

/// Row budget of the Productivity page's two cards (48a). Named constants rather than literals inside the
/// view, so "does it still fit?" is a unit test instead of an eyeball on a notched display.
enum NotchProductivityLayout {
    static let cardHeader: CGFloat = 18
    static let weekStrip: CGFloat = 26
    static let agendaRow: CGFloat = 14
    static let agendaRowCount = 3
    static let focusTimer: CGFloat = 22
    static let progress: CGFloat = 6
    static let controls: CGFloat = 22
    static let reminderRow: CGFloat = 13
    static let rowSpacing: CGFloat = 3

    /// Card A: header, the week strip, then the agenda rows.
    static func cardAContent(rows: Int = agendaRowCount) -> CGFloat {
        cardHeader + weekStrip + CGFloat(rows) * agendaRow + 2 * rowSpacing
    }

    /// Card B: header, timer + cycle dots, progress, controls, and a reminder row when one exists.
    static func cardBContent(hasReminder: Bool) -> CGFloat {
        let rows: CGFloat = hasReminder ? 5 : 4
        return cardHeader + focusTimer + progress + controls + (hasReminder ? reminderRow : 0)
            + (rows - 1) * rowSpacing
    }

    /// Both cards share one height; the taller one must fit the page body minus the cards' own padding.
    static func fits(headerHeight: CGFloat, hasReminder: Bool, cardPadding: CGFloat) -> Bool {
        let budget = NotchLayoutSpec.pageBodyHeight(headerHeight: headerHeight) - 2 * cardPadding
        return max(cardAContent(), cardBContent(hasReminder: hasReminder)) <= budget
    }
}

// MARK: - Liquid Notch Core Engine (MIT: fellipegoncalvesleite/liquid-notch)

/// Presentation mode for the Liquid Notch shell.
enum LiquidPresentationMode: String, CaseIterable, Sendable {
    case idle, compact, peek, duo, hud, split, card
}

/// OKLab <-> sRGB perceptual color conversion for album-art ambient glow.
enum LiquidOKLab {
    static func fromSRGB(_ c: SIMD3<Double>) -> SIMD3<Double> {
        let r = toLinear(c.x), g = toLinear(c.y), b = toLinear(c.z)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    static func toSRGB(L: Double, a: Double, b: Double) -> SIMD3<Double> {
        let l = pow3(L + 0.3963377774 * a + 0.2158037573 * b)
        let m = pow3(L - 0.1055613458 * a - 0.0638541728 * b)
        let s = pow3(L - 0.0894841775 * a - 1.2914855480 * b)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return SIMD3(toGamma(r), toGamma(g), toGamma(bl))
    }

    private static func pow3(_ x: Double) -> Double { x * x * x }
    private static func toLinear(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
    private static func toGamma(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}

/// Every parameter of the liquid surface at one instant, in points.
struct LiquidShapeState: Equatable, Sendable {
    var mainHalfWidth: Double
    var mainHeight: Double
    var mainRadius: Double
    var dropX: Double = 0
    var dropY: Double = 0
    var dropRadius: Double = 0
    var e1X: Double = 0
    var e1R: Double = 0
    var e2X: Double = 0
    var e2R: Double = 0
    var cardHalfWidth: Double = 0
    var cardTop: Double = 0
    var cardHeight: Double = 0
    var cardRadius: Double = 0
    var cardX: Double = 0
    var mainX: Double = 0
    var kBezel: Double = 0
    var glowIntensity: Double = 0
    var glowFalloff: Double = 12
    var auraL: Double = 0.7
    var auraA: Double = 0.1
    var auraB: Double = -0.1
}

/// Byte-for-byte mirror of `Uniforms` in the embedded LiquidShape Metal shader.
struct LiquidShapeUniforms: Sendable {
    var view: SIMD4<Float> = .zero
    var notch: SIMD4<Float> = .zero
    var main: SIMD4<Float> = .zero
    var drop: SIMD4<Float> = .zero
    var merge: SIMD4<Float> = .zero
    var glow: SIMD4<Float> = .zero
    var aura: SIMD4<Float> = .zero
    var fill: SIMD4<Float> = .zero
    var card: SIMD4<Float> = .zero
    var card2: SIMD4<Float> = .zero
    var pulse: SIMD4<Float> = .zero
    var hair: SIMD4<Float> = .zero
    var extra1: SIMD4<Float> = .zero
    var extra2: SIMD4<Float> = .zero

    init(
        state s: LiquidShapeState,
        neckRadius: Double = 0,
        dropRadii: SIMD2<Double>? = nil,
        viewSize: SIMD2<Double>,
        scale: Double,
        notchHalfWidth: Double,
        notchHeight: Double,
        notchRadius: Double = 10,
        cornerExponent: Double = 4.2,
        kNotch: Double = 10,
        kDrop: Double = 18,
        edgeFeather: Double = 1.1,
        cardNeck: Double = 0,
        earGlowOffset: Double = 0,
        hairline: Double = 0.14
    ) {
        let dr = dropRadii ?? SIMD2(s.dropRadius, s.dropRadius)
        let auraRGB = LiquidOKLab.toSRGB(L: s.auraL, a: s.auraA, b: s.auraB)
        view = SIMD4(Float(viewSize.x), Float(viewSize.y), Float(scale), Float(edgeFeather))
        notch = SIMD4(Float(notchHalfWidth), Float(notchHeight), Float(notchRadius), 0)
        main = SIMD4(Float(max(s.mainHalfWidth, 0)), Float(max(s.mainHeight, 0)), Float(max(s.mainRadius, 0)), Float(cornerExponent))
        drop = SIMD4(Float(viewSize.x / 2 + s.dropX), Float(s.dropY), Float(max(dr.x, 0)), Float(max(dr.y, 0)))
        merge = SIMD4(Float(kNotch), Float(kDrop), Float(max(s.kBezel, 0)), Float(max(neckRadius, 0)))
        glow = SIMD4(Float(max(s.glowIntensity, 0)), Float(max(s.glowFalloff, 0.1)), Float(1.0 / 255.0), 0)
        aura = SIMD4(Float(auraRGB.x), Float(auraRGB.y), Float(auraRGB.z), 0)
        fill = .zero
        card = SIMD4(Float(max(s.cardHalfWidth, 0)), Float(s.cardTop), Float(max(s.cardHeight, 0)), Float(max(s.cardRadius, 0)))
        card2 = SIMD4(Float(max(cardNeck, 0)), Float(earGlowOffset), Float(s.cardX), Float(s.mainX))
        pulse = .zero
        hair = SIMD4(Float(hairline), Float(0.5 * scale), 0, 0)
        let ball = { (x: Double, r: Double, nx: Double, nr: Double) -> SIMD4<Float> in
            let gap = abs(x - nx) - max(r, 0) - nr
            let k = r > 0.05 ? kDrop * min(max(1 - gap / 10, 0), 1) : 0
            return SIMD4(Float(viewSize.x / 2 + x), Float(s.dropY), Float(max(r, 0)), Float(k))
        }
        extra1 = ball(s.e1X, s.e1R, -s.mainHalfWidth, 0)
        extra2 = ball(s.e2X, s.e2R, s.dropX, s.dropRadius)
    }
}

/// CPU mirror of the LiquidShape Metal distance field for hit-testing.
enum LiquidShapeSDF {
    enum HitRegion: Equatable, Sendable { case ears, card, bubble(Int) }
    private static let topExtension = 64.0

    static func hit(_ p: SIMD2<Double>, _ u: LiquidShapeUniforms, earPad: Double = 6, cardPad: Double = 2) -> HitRegion? {
        guard p.y >= 0 else { return nil }
        if let d = card(p, u), d < cardPad { return .card }
        let dr = SIMD2(Double(u.drop.z), Double(u.drop.w))
        let dropR = min(dr.x, dr.y)
        if dropR > 1, simd_length(p - SIMD2(Double(u.drop.x), Double(u.drop.y))) < dropR + earPad { return .bubble(0) }
        for (i, e) in [u.extra1, u.extra2].enumerated() where e.z > 1 {
            if simd_length(p - SIMD2(Double(e.x), Double(e.y))) < Double(e.z) + earPad { return .bubble(i + 1) }
        }
        let cx = Double(u.view.x) / 2
        let mh = Double(u.main.y)
        let dMain = roundBox(p - SIMD2(cx + Double(u.card2.w), (mh - topExtension) / 2),
                             SIMD2(Double(u.main.x), (mh + topExtension) / 2), Double(u.main.z), Double(u.main.w))
        return dMain < earPad ? .ears : nil
    }

    private static func card(_ p: SIMD2<Double>, _ u: LiquidShapeUniforms) -> Double? {
        let hw = Double(u.card.x), h = Double(u.card.z)
        guard hw > 0.5, h > 0.5 else { return nil }
        let cx = Double(u.view.x) / 2 + Double(u.card2.z)
        return roundBox(p - SIMD2(cx, Double(u.card.y) + h / 2), SIMD2(hw, h / 2), Double(u.card.w), Double(u.main.w))
    }

    static func roundBox(_ p: SIMD2<Double>, _ b: SIMD2<Double>, _ r0: Double, _ n: Double) -> Double {
        let r = min(r0, min(b.x, b.y))
        let q = abs(p) - b + SIMD2(repeating: r)
        let m = simd_max(q, .zero)
        let outside = n == 2 ? simd_length(m) : pow(pow(m.x, n) + pow(m.y, n), 1 / n)
        return outside + min(max(q.x, q.y), 0) - r
    }
}

/// Computes target LiquidShapeState per mode, including non-notch external-display floating pill fallback.
enum LiquidShapeTargets {
    static func resting(
        mode: LiquidPresentationMode,
        notchHalfWidth: Double,
        notchHeight: Double,
        hasHardwareNotch: Bool,
        idleHover: Bool = false,
        earExtent: Double = 64,
        cardSize: CGSize = NotchGeometry.liquidOpenSize
    ) -> LiquidShapeState {
        let baseHalf = hasHardwareNotch ? notchHalfWidth : 74.0
        let baseHeight = hasHardwareNotch ? notchHeight : 28.0
        let bezelK = hasHardwareNotch ? 6.0 : 0.0
        var s = LiquidShapeState(
            mainHalfWidth: baseHalf,
            mainHeight: baseHeight,
            mainRadius: hasHardwareNotch ? 10 : 14,
            kBezel: bezelK
        )
        switch mode {
        case .idle:
            if idleHover {
                s.mainHalfWidth = baseHalf + 6
                s.mainHeight = baseHeight + 4
                s.mainRadius += 2
            }
        case .compact, .peek, .hud:
            s.mainHalfWidth = baseHalf + earExtent
            s.mainHeight = mode == .peek ? baseHeight + 10 : baseHeight
            s.mainRadius = min(14, s.mainHeight / 2)
            s.glowIntensity = 0.35
        case .duo, .split:
            s.mainHalfWidth = baseHalf + earExtent
            s.mainRadius = min(14, baseHeight / 2)
            s.dropRadius = min(14, baseHeight / 2 - 2)
            s.dropX = s.mainHalfWidth + 10 + s.dropRadius
            s.dropY = baseHeight / 2
            s.glowIntensity = 0.35
        case .card:
            s.mainHalfWidth = baseHalf + 18
            s.mainRadius = 10
            s.cardHalfWidth = Double(cardSize.width) / 2
            s.cardTop = baseHeight + (hasHardwareNotch ? 8 : 10)
            s.cardHeight = Double(cardSize.height)
            s.cardRadius = 24
            s.glowIntensity = 0.45
        }
        return s
    }
}

// MARK: - Liquid Synced Lyrics (LRCLIB, on-demand only)

struct LiquidLyricLine: Equatable, Sendable {
    let time: Double
    let text: String
}

struct LiquidLyrics: Equatable, Sendable {
    let key: String
    let lines: [LiquidLyricLine]
    let plain: [String]
    static let lead = 0.1

    func current(at elapsed: Double) -> Int? {
        lines.lastIndex { $0.time <= elapsed + Self.lead }
    }

    /// Prevents brief flicker backward when a player's clock steps back <= 1.5s right after a seek.
    func line(from shown: Int?, at elapsed: Double) -> Int? {
        let now = current(at: elapsed)
        if let shown, shown < lines.count, (now ?? -1) < shown, lines[shown].time - (elapsed + Self.lead) <= 1.5 {
            return shown
        }
        return now
    }
}

struct LiquidLyricsEntry: Equatable, Sendable {
    let duration: Double?
    let lines: [LiquidLyricLine]
    let plain: [String]
}

enum LiquidLyricsSource {
    static func key(title: String, artist: String) -> String { "\(artist)|\(title)" }

    /// Fetches from LRCLIB only when explicitly requested by opening the lyrics view.
    static func fetch(title: String, artist: String, album: String, duration: Double?) async -> LiquidLyrics? {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var c = URLComponents(string: "https://lrclib.net/api/get")!
        c.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            + (album.isEmpty ? [] : [URLQueryItem(name: "album_name", value: album)])
            + (duration.map { [URLQueryItem(name: "duration", value: String(Int($0.rounded())))] } ?? [])
        var s = URLComponents(string: "https://lrclib.net/api/search")!
        s.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        async let exact = json(c.url)
        async let found = json(s.url)
        let entries = ((await exact as? [String: Any]).map { [$0] } ?? []) + ((await found as? [[String: Any]]) ?? [])
        guard let e = best(entries.map(entry), duration: duration) else { return nil }
        return LiquidLyrics(key: key(title: title, artist: artist), lines: e.lines, plain: e.lines.isEmpty ? e.plain : [])
    }

    private static func json(_ url: URL?) async -> Any? {
        guard let url, let (data, r) = try? await URLSession.shared.data(from: url),
              (r as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func entry(_ j: [String: Any]) -> LiquidLyricsEntry {
        let plain = (j["plainLyrics"] as? String ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return LiquidLyricsEntry(
            duration: (j["duration"] as? NSNumber)?.doubleValue,
            lines: parse(j["syncedLyrics"] as? String ?? ""),
            plain: plain == [""] ? [] : plain
        )
    }

    static func best(_ entries: [LiquidLyricsEntry], duration: Double?) -> LiquidLyricsEntry? {
        let fits = entries.filter { e in duration.map { d in e.duration.map { abs($0 - d) <= 2 } ?? true } ?? true }
        var distinct: [(entry: LiquidLyricsEntry, copies: Int)] = []
        for e in fits where !e.lines.isEmpty {
            if let i = distinct.firstIndex(where: { $0.entry.lines == e.lines }) {
                distinct[i].copies += 1
            } else {
                distinct.append((e, 1))
            }
        }
        guard !distinct.isEmpty else {
            guard let e = fits.first(where: { !$0.plain.isEmpty }) ?? entries.first(where: { !$0.plain.isEmpty || !$0.lines.isEmpty }) else { return nil }
            return LiquidLyricsEntry(duration: e.duration, lines: [], plain: e.plain.isEmpty ? e.lines.map(\.text) : e.plain)
        }
        let scored = distinct.indices.map { i -> (Int, Double) in
            let others = distinct.indices.filter { $0 != i }.map { distance(distinct[i].entry.lines, distinct[$0].entry.lines) }
            return (i, others.isEmpty ? 0 : others.reduce(0, +) / Double(others.count))
        }
        let pick = scored.min { a, b in
            abs(a.1 - b.1) > 0.01 ? a.1 < b.1 : (distinct[a.0].copies != distinct[b.0].copies ? distinct[a.0].copies > distinct[b.0].copies : a.0 < b.0)
        }!
        return distinct[pick.0].entry
    }

    static func distance(_ a: [LiquidLyricLine], _ b: [LiquidLyricLine]) -> Double {
        func words(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var gaps: [Double] = [], from = 0
        for line in a where !words(line.text).isEmpty {
            guard let j = b[from...].firstIndex(where: { words($0.text) == words(line.text) }) else { continue }
            gaps.append(abs(line.time - b[j].time))
            from = j + 1
        }
        guard gaps.count >= 3 else { return 10 }
        gaps.sort()
        return gaps[gaps.count / 2]
    }

    static func parse(_ lrc: String) -> [LiquidLyricLine] {
        var out: [LiquidLyricLine] = []
        for raw in lrc.split(separator: "\n") {
            var line = Substring(raw), stamps: [Double] = []
            while line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let stamp = line[line.index(after: line.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
                    stamps.append(m * 60 + s)
                }
                line = line[line.index(after: close)...]
            }
            let text = line.trimmingCharacters(in: .whitespaces)
            for t in stamps { out.append(LiquidLyricLine(time: t, text: text)) }
        }
        return out.sorted { $0.time < $1.time }
    }
}

// MARK: - Liquid Opt-In Extras (LQ-5: Sports, Video-in-Island, Lock Screen, Notifications — all off by default)

enum LiquidExtrasKeys {
    static let sportsEnabled = "com.katikati.liquid.sportsEnabled"
    static let videoInIslandEnabled = "com.katikati.liquid.videoInIslandEnabled"
    static let lockScreenEnabled = "com.katikati.liquid.lockScreenEnabled"
    static let notificationsEnabled = "com.katikati.liquid.notificationsEnabled"
}

enum LiquidSportLeague: String, CaseIterable, Identifiable, Sendable {
    case football, nfl, nba, mlb, nhl
    var id: String { rawValue }
    var espnPath: String {
        switch self {
        case .football: return "soccer/eng.1"
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .mlb: return "baseball/mlb"
        case .nhl: return "hockey/nhl"
        }
    }
}

struct LiquidSportsScore: Equatable, Identifiable, Sendable {
    let id: String
    let league: LiquidSportLeague
    let homeAbbrev: String
    let awayAbbrev: String
    let homeScore: String
    let awayScore: String
    let statusText: String
    let isLive: Bool
}

enum LiquidESPNParser {
    static func parseScoreboard(_ data: Data, league: LiquidSportLeague) -> [LiquidSportsScore] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { ev in
            guard let id = ev["id"] as? String,
                  let comp = (ev["competitions"] as? [[String: Any]])?.first,
                  let competitors = comp["competitors"] as? [[String: Any]], competitors.count >= 2 else { return nil }
            let home = competitors.first { ($0["homeAway"] as? String) == "home" } ?? competitors[0]
            let away = competitors.first { ($0["homeAway"] as? String) == "away" } ?? competitors[1]
            let homeAbbrev = ((home["team"] as? [String: Any])?["abbreviation"] as? String) ?? "HOM"
            let awayAbbrev = ((away["team"] as? [String: Any])?["abbreviation"] as? String) ?? "AWY"
            let homeScore = (home["score"] as? String) ?? "0"
            let awayScore = (away["score"] as? String) ?? "0"
            let statusType = ((ev["status"] as? [String: Any])?["type"] as? [String: Any]) ?? [:]
            let state = (statusType["state"] as? String) ?? ""
            let detail = (statusType["shortDetail"] as? String) ?? (statusType["description"] as? String) ?? ""
            return LiquidSportsScore(
                id: id, league: league, homeAbbrev: homeAbbrev, awayAbbrev: awayAbbrev,
                homeScore: homeScore, awayScore: awayScore, statusText: detail, isLive: state == "in"
            )
        }
    }
}

enum LiquidWallpaperBackup {
    static func backupURL(in dir: URL) -> URL {
        dir.appendingPathComponent("lock-wallpaper-backup.path")
    }

    static func saveOriginalPath(_ path: String, in dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = backupURL(in: dir)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try path.write(to: file, atomically: true, encoding: .utf8)
    }

    static func consumeOriginalPath(in dir: URL) -> String? {
        let file = backupURL(in: dir)
        guard let path = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: file)
        return path
    }
}
