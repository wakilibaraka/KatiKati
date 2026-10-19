import CoreGraphics

/// Configuration for spacing between and around tiled windows (Phase 26b).
struct TilingGaps: Equatable, Sendable, Codable {
    /// Inner gap between adjacent window tiles, in points.
    var inner: CGFloat
    /// Outer gap between window tiles and the screen/work area perimeter, in points.
    var outer: CGFloat

    /// Minimum allowable tile dimension to avoid unusable micro-windows.
    static let minTileSize = CGSize(width: 200, height: 150)

    /// Default spacing: 8pt inner, 8pt outer.
    static let `default` = TilingGaps(inner: 8, outer: 8)

    init(inner: CGFloat = 8, outer: CGFloat = 8) {
        self.inner = max(0, inner)
        self.outer = max(0, outer)
    }
}

/// Trims a screen's work area so windows stay clear of a solid KatiKati dock, the way the system Dock
/// shrinks `visibleFrame`. Cocoa (bottom-left) coordinates throughout.
enum DockReserve {
    /// Cuts `visible` on the screen edge nearest `dock`, up to the dock's inner edge. A dock that does not
    /// touch the work area (or nil) leaves it unchanged.
    static func workArea(visible: CGRect, screen: CGRect, dock: CGRect?) -> CGRect {
        guard let dock, !dock.isEmpty, dock.intersects(visible) else { return visible }
        let gaps: [(edge: Int, distance: CGFloat)] = [
            (0, abs(dock.minX - screen.minX)), (1, abs(screen.maxX - dock.maxX)),
            (2, abs(dock.minY - screen.minY)), (3, abs(screen.maxY - dock.maxY)),
        ]
        var r = visible
        switch gaps.min(by: { $0.distance < $1.distance })!.edge {
        case 0: r.size.width -= max(0, dock.maxX - r.minX); r.origin.x = max(r.minX, dock.maxX)
        case 1: r.size.width = max(0, min(r.maxX, dock.minX) - r.minX)
        case 2: r.size.height -= max(0, dock.maxY - r.minY); r.origin.y = max(r.minY, dock.maxY)
        default: r.size.height = max(0, min(r.maxY, dock.minY) - r.minY)
        }
        return r
    }
}
