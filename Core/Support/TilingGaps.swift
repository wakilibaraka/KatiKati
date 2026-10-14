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
