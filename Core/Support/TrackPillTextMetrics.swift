import AppKit

/// How wide the track pill's text column is: the longer of its two lines, capped so a long title scrolls
/// instead of stretching the pill, and floored so a one-word title still leaves the equalizer in from the
/// edge. `MarqueeText` takes whatever width it is offered, so the pill has to offer one — a bare
/// `maxWidth` collapsed the column and rendered both lines as slivers (owner screenshot 2026-10-21).
enum TrackPillTextMetrics {
    static let cap: CGFloat = 170
    static let floor: CGFloat = 40

    /// Two points of slack for glyph overhang; the faces are the ones the view draws.
    static func columnWidth(title: String, artist: String) -> CGFloat {
        let titleWidth = (title as NSString).size(withAttributes: [.font: rounded(12, weight: .bold)]).width
        let artistWidth = (artist as NSString).size(withAttributes: [.font: rounded(11, weight: .regular)]).width
        return min(cap, max(floor, ceil(max(titleWidth, artistWidth)) + 2))
    }

    private static func rounded(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }
}
