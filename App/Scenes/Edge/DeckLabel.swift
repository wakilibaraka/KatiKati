import AppKit
import SwiftUI

/// Tab-label typography (Phase 7A-D2): a setting picks the face (PostScript name, "" = system), the deck scale
/// resizes it, and one cached measurement feeds both layout and drawing so the strip always fits the text.
struct DeckFont {
    let postScript: String
    let scale: CGFloat

    private var size: CGFloat { 11 * scale }
    var tracking: CGFloat { 0.1 * scale }

    var nsFont: NSFont {
        if !postScript.isEmpty, let f = NSFont(name: postScript, size: size) { return f }
        return NSFont.systemFont(ofSize: size, weight: .bold)
    }

    var font: Font { Font(nsFont as CTFont) }

    /// Measures rotated runs with this exact face; widths are cached per face + text (layout asks often).
    var measure: VerticalLabelMeasure {
        let ns = nsFont
        let tracking = self.tracking
        let advance = max(1, ceil(ns.ascender - ns.descender + ns.leading))
        return VerticalLabelMeasure(rotatedWidth: { text in
            DeckLabelWidthCache.width(of: text, font: ns, tracking: tracking)
        }, uprightAdvance: advance)
    }

    /// Faces offered in Settings (those installed), after noty's `Ink.allFaces`.
    static let faces: [(name: String, postScript: String)] = [
        ("System", ""), ("Noteworthy", "Noteworthy-Bold"), ("Bradley Hand", "BradleyHandITCTT-Bold"),
        ("Marker Felt", "MarkerFelt-Wide"), ("Chalkboard", "ChalkboardSE-Bold"), ("Avenir Next", "AvenirNext-DemiBold"),
        ("New York", "NewYork-Semibold"), ("Georgia", "Georgia-Bold"), ("Menlo", "Menlo-Bold"),
    ].filter { $0.1.isEmpty || NSFont(name: $0.1, size: 12) != nil }
}

private enum DeckLabelWidthCache {
    private static var cache: [String: CGFloat] = [:]

    static func width(of text: String, font: NSFont, tracking: CGFloat) -> CGFloat {
        let key = "\(font.fontName)|\(font.pointSize)|\(text)"
        if let hit = cache[key] { return hit }
        let w = (text as NSString).size(withAttributes: [.font: font]).width + tracking * CGFloat(text.count)
        if cache.count > 400 { cache.removeAll(keepingCapacity: true) }
        cache[key] = w
        return w
    }
}

/// A tab title turned on its side. CJK/emoji stay upright; Latin stays one rotated run (noty's
/// `VerticalTabLabel` treatment).
struct VerticalTabLabel: View {
    let title: String
    let strip: CGFloat
    let onRight: Bool
    let ink: Color
    let metrics: DeckMetrics
    let deckFont: DeckFont

    private var text: String { title.uppercased() }
    private var availableAdvance: CGFloat { max(20, strip - metrics.labelInset) }
    private var usesUpright: Bool { VerticalLabelLayout.runs(for: text).contains { $0.orientation == .upright } }

    var body: some View {
        if usesUpright {
            let fitted = VerticalLabelLayout.fittingRuns(for: text, maxAdvance: availableAdvance, measure: deckFont.measure)
            let ordered = onRight ? fitted : Array(fitted.reversed())
            VStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, run in
                    runView(run)
                }
            }
            .frame(width: metrics.tabWidth, height: strip, alignment: .center)
        } else {
            rotated(text, height: strip)
        }
    }

    @ViewBuilder private func runView(_ run: VerticalLabelRun) -> some View {
        switch run.orientation {
        case .upright:
            Text(verbatim: run.text)
                .font(deckFont.font)
                .foregroundColor(ink.opacity(0.85))
                .frame(width: max(20, metrics.tabWidth - metrics.labelInset), height: deckFont.measure.uprightAdvance)
        case .rotated:
            rotated(run.text, height: deckFont.measure.rotatedWidth(run.text))
        }
    }

    private func rotated(_ s: String, height: CGFloat) -> some View {
        Text(verbatim: s)
            .font(deckFont.font)
            .kerning(deckFont.tracking)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundColor(ink.opacity(0.85))
            .frame(width: availableAdvance, height: metrics.tabWidth)
            .rotationEffect(.degrees(onRight ? 90 : -90))
            .frame(width: metrics.tabWidth, height: height)
    }
}
