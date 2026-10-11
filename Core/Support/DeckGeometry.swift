import Foundation

// Pure deck geometry for the edge bars (Phase 7A-D1). The model — a pill at rest, a fan of shingled tabs on
// hover, one `scale` that multiplies every length and rounds to whole points so lapped tabs never land on half
// pixels — follows noty's `DeckGeom` / `DeckLayout` (aimen08/noty, MIT, see NOTICE §5). Re-derived for KatiKati:
// no global settings (the scale is an input), label measurement is injected so Core stays AppKit-free, and the
// panel-frame helpers are new (our panels are content-sized rather than full height).

struct DeckMetrics: Equatable, Sendable {
    let scale: CGFloat

    init(scale: CGFloat = 1) { self.scale = min(max(scale, 0.5), 2) }

    private func s(_ v: CGFloat) -> CGFloat { (v * scale).rounded() }

    // Rest: a narrow pill of colour dashes.
    var pillWidth: CGFloat { s(12) }
    var pillTouchWidth: CGFloat { s(14) }
    var dashHeight: CGFloat { s(14) }
    var dashWidth: CGFloat { s(7) }
    var dashGap: CGFloat { s(5) }
    var pillPad: CGFloat { s(7) }
    // Fan.
    var tabWidth: CGFloat { s(30) }
    var tabGap: CGFloat { s(7) }
    /// How far the next tab laps over the one before it.
    var tabLap: CGFloat { s(40) }
    var pitchMin: CGFloat { s(56) }
    var pitchMax: CGFloat { s(124) }
    var pitchFloor: CGFloat { s(36) }
    var labelPad: CGFloat { s(20) }
    var labelInset: CGFloat { s(12) }
    /// Tabs are drawn this far past the screen edge so their lean opens no wedge against it.
    var bleed: CGFloat { s(14) }
    var chipWidth: CGFloat { s(30) }
    var chipHeight: CGFloat { s(24) }
    var chipGap: CGFloat { s(6) }
    var buttonSize: CGFloat { s(28) }
    var buttonGap: CGFloat { s(12) }
    var moreTabHeight: CGFloat { s(34) }
    /// Transparent room around the stack for shadows (never part of the hit area).
    var shadowRoom: CGFloat { s(24) }
}

enum DeckGeometry {
    static let maxDashes = 14
    /// The deck may claim at most this much of the screen height before tabs start shrinking.
    static let heightBudget: CGFloat = 0.68
    static let leanDegrees: Double = 3
    static let fanLimit = 5

    /// Everything leans the same way — matching angles read as deliberate.
    static func lean(onRight: Bool) -> Double { onRight ? -leanDegrees : leanDegrees }

    static func pillHeight(_ m: DeckMetrics, itemCount: Int) -> CGFloat {
        let shown = min(itemCount, maxDashes)
        let n = max(1, shown + (itemCount > maxDashes ? 1 : 0))
        return m.pillPad * 2 + CGFloat(n) * m.dashHeight + CGFloat(n - 1) * m.dashGap
    }

    /// Tab stack metrics. `longestLabel` is the rendered advance of the longest tab title; the uncovered
    /// strip of each tab is sized to it (clamped), and shrinks on short screens (`heightBudget`).
    static func layout(_ m: DeckMetrics, panelHeight: CGFloat, count: Int, hasMore: Bool,
                       longestLabel: CGFloat = 0, buttons: Int = 0) -> DeckLayout {
        let n = max(1, count)    // pitch is solved for at least one tab; `count` stays the real number
        var pitch = min(m.pitchMax, max(m.pitchMin, longestLabel + m.labelPad))
        let reserved = hasMore ? m.moreTabHeight + m.tabGap : 0
        let budget = panelHeight * heightBudget - reserved
        if CGFloat(n) * pitch + m.tabLap > budget {
            pitch = max(m.pitchFloor, (budget - m.tabLap) / CGFloat(n))
        }
        return DeckLayout(metrics: m, itemHeight: pitch + m.tabLap, pitch: pitch, count: max(0, count),
                          hasMore: hasMore, panelHeight: panelHeight, buttons: buttons)
    }

    // MARK: Panel frames (bottom-left origin, ⊆ visibleFrame)

    /// The dormant detection strip: pill height, hugging the screen edge, vertically placed by `yRatio`
    /// (0 = bottom, 1 = top of the visible area).
    static func restFrame(_ m: DeckMetrics, side: EdgeSide, visible: CGRect, itemCount: Int, yRatio: CGFloat,
                          edgeWidth: CGFloat = 14) -> CGRect {
        let h = min(pillHeight(m, itemCount: itemCount), visible.height)
        let w = max(m.pillWidth + 2, edgeWidth)
        let y = visible.minY + max(0, visible.height - h) * clamp01(yRatio)
        let x = side == .right ? visible.maxX - w : visible.minX
        return CGRect(x: x, y: y.rounded(), width: w, height: h)
    }

    /// The fan: as tall as the stack, centred on the pill's centre, kept `margin` inside the visible area.
    static func fanFrame(_ m: DeckMetrics, side: EdgeSide, visible: CGRect, stackHeight: CGFloat, itemCount: Int,
                         yRatio: CGFloat, margin: CGFloat = 12) -> CGRect {
        let rest = restFrame(m, side: side, visible: visible, itemCount: itemCount, yRatio: yRatio)
        let h = max(0, min(stackHeight + m.shadowRoom, visible.height - 2 * margin))
        let ideal = rest.midY - h / 2
        let y = min(max(visible.minY + margin, ideal), max(visible.minY + margin, visible.maxY - h - margin))
        let w = fanWidth(m)
        let x = side == .right ? visible.maxX - w : visible.minX
        return CGRect(x: x, y: y.rounded(), width: w, height: h)
    }

    /// Width of the fanned panel: the room other panels (the weather stack) keep clear of a deck.
    static func fanWidth(_ m: DeckMetrics) -> CGFloat { m.tabWidth + m.bleed + m.shadowRoom }

    /// New yRatio when the pill is dragged so its centre sits at `pointerY`.
    static func yRatio(forPointerY pointerY: CGFloat, pillHeight: CGFloat, visible: CGRect) -> CGFloat {
        let available = max(1, visible.height - pillHeight)
        let y = min(max(visible.minY, pointerY - pillHeight / 2), visible.maxY - pillHeight)
        return clamp01((y - visible.minY) / available)
    }

    /// Which screen side a dragged pill snaps to.
    static func snapSide(pointerX: CGFloat, screenFrame: CGRect) -> EdgeSide {
        pointerX < screenFrame.midX ? .left : .right
    }

    private static func clamp01(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }

    // MARK: Drag reorder

    /// Slot a dragged tab would drop into. It must travel 60 % of a slot (not 50 %) before the target
    /// moves — at the halfway mark pointer jitter flips the answer every frame and each flip animates a row.
    static func dragTarget(from: Int, dy: CGFloat, pitch: CGFloat, count: Int) -> Int {
        let raw = dy / max(1, pitch)
        let slots = raw > 0 ? Int(floor(raw + 0.4)) : Int(ceil(raw - 0.4))
        return min(max(0, from + slots), max(0, count - 1))
    }

    /// Vertical offset of tab `index` while `from` is dragged toward `to` (the others step aside).
    static func dragShift(index: Int, from: Int, to: Int, pitch: CGFloat) -> CGFloat {
        guard index != from else { return 0 }
        if from < to, index > from, index <= to { return -pitch }
        if from > to, index < from, index >= to { return pitch }
        return 0
    }

    /// Past this much vertical travel a press is a reorder, not a tap.
    static let dragSlop: CGFloat = 5
}

struct DeckLayout: Equatable, Sendable {
    let metrics: DeckMetrics
    /// Full height of one tab.
    let itemHeight: CGFloat
    /// Top-to-top spacing; < itemHeight means overlap.
    let pitch: CGFloat
    let count: Int
    let hasMore: Bool
    let panelHeight: CGFloat
    /// Round buttons stacked under the tabs (`+`, settings, status, widgets).
    let buttons: Int

    /// Negative for shingled tabs — the VStack spacing that produces the overlap.
    var spacing: CGFloat { pitch - itemHeight }

    var stackHeight: CGFloat {
        var h: CGFloat = count > 0 ? CGFloat(count - 1) * pitch + itemHeight : 0
        if hasMore { h += metrics.tabGap + metrics.moreTabHeight }
        if buttons > 0 {
            // A gap precedes every button except the first one of a buttons-only stack.
            let gaps = (count > 0 || hasMore) ? buttons : buttons - 1
            h += CGFloat(buttons) * metrics.buttonSize + CGFloat(gaps) * metrics.buttonGap
        }
        return h
    }

    /// Centre of the uncovered strip of tab `index` (relative to the stack top).
    func center(_ index: Int) -> CGFloat {
        let strip = index == count - 1 ? itemHeight : pitch
        return CGFloat(index) * pitch + strip / 2
    }

    var cap: CGFloat { max(140, panelHeight - 76) }
    var overflows: Bool { stackHeight > cap }
}

// MARK: - Vertical tab labels

enum VerticalLabelOrientation: Equatable, Sendable { case upright, rotated }

struct VerticalLabelRun: Equatable, Sendable {
    let text: String
    let orientation: VerticalLabelOrientation
}

/// How wide text renders — injected so Core needs no AppKit (the App layer measures with the tab font).
struct VerticalLabelMeasure {
    /// Width of a rotated (horizontal-then-turned) run.
    let rotatedWidth: (String) -> CGFloat
    /// Vertical advance of one upright glyph.
    let uprightAdvance: CGFloat

    func advance(of run: VerticalLabelRun) -> CGFloat {
        run.orientation == .upright ? uprightAdvance : rotatedWidth(run.text)
    }

    func total(_ runs: [VerticalLabelRun]) -> CGFloat { runs.reduce(0) { $0 + advance(of: $1) } }
}

/// Unicode-aware layout model for tab titles: CJK, kana, hangul, full-width punctuation and emoji keep their
/// upright vertical-writing presentation (one glyph per run); Latin, digits and other scripts stay one rotated
/// run so words remain readable. Behaviour follows noty's `VerticalLabelLayout` (MIT).
enum VerticalLabelLayout {
    static func runs(for title: String) -> [VerticalLabelRun] {
        var result: [VerticalLabelRun] = []
        var rotated = ""
        func flushRotated() {
            guard !rotated.isEmpty else { return }
            result.append(VerticalLabelRun(text: rotated, orientation: .rotated))
            rotated.removeAll(keepingCapacity: true)
        }
        let characters = Array(title)
        for (index, character) in characters.enumerated() {
            let upright = isUpright(character) && (!isSpace(character) || spaceIsBetweenUprightGlyphs(in: characters, at: index))
            if upright {
                flushRotated()
                result.append(VerticalLabelRun(text: String(character), orientation: .upright))
            } else {
                rotated.append(character)
            }
        }
        flushRotated()
        return result
    }

    /// Truncates from the end with an upright ellipsis when the strip is too short for the full title.
    static func fittingRuns(for title: String, maxAdvance: CGFloat, measure: VerticalLabelMeasure) -> [VerticalLabelRun] {
        let text = title.uppercased()
        let all = runs(for: text)
        guard measure.total(all) > maxAdvance else { return all }
        let ellipsis = VerticalLabelRun(text: "…", orientation: .upright)
        let room = maxAdvance - measure.advance(of: ellipsis)
        var prefix = ""
        for character in text {
            let candidate = prefix + String(character)
            guard measure.total(runs(for: candidate)) <= room else { break }
            prefix = candidate
        }
        return runs(for: prefix) + [ellipsis]
    }

    private static func isSpace(_ c: Character) -> Bool {
        c.unicodeScalars.allSatisfy { $0.value == 0x20 || $0.value == 0x3000 || $0.value == 0x00A0 }
    }

    private static func spaceIsBetweenUprightGlyphs(in characters: [Character], at index: Int) -> Bool {
        let previous = index > 0 ? characters[index - 1] : nil
        let next = index + 1 < characters.count ? characters[index + 1] : nil
        return (previous.map(isUpright) ?? true) && (next.map(isUpright) ?? true)
    }

    static func isUpright(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x2E80...0x2FFF, 0x3000...0x30FF, 0x3100...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                 0xA960...0xA97F, 0xAC00...0xD7FF, 0xF900...0xFAFF, 0xFE10...0xFE6F, 0xFF00...0xFFEF,
                 0x1F000...0x1FAFF, 0x20000...0x2FA1F:
                return true
            case 0x20, 0x3000, 0x00A0:
                return true       // spaces stay eligible; `runs` attaches mixed-script spaces to rotated text
            default:
                return false
            }
        }
    }
}
