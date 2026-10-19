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

/// Keeps a placed window inside the work area. Works in any space where the area and frame agree.
enum WindowFit {
    /// Shifts (never resizes) a frame fully inside the area; a frame wider/taller than the area is pinned to its leading edge.
    static func shifted(_ frame: CGRect, into area: CGRect) -> CGRect {
        var f = frame
        f.origin.x = max(area.minX, min(f.origin.x, area.maxX - f.width))
        f.origin.y = max(area.minY, min(f.origin.y, area.maxY - f.height))
        return f
    }

    /// True when a frame sits flush in the area as a half or quarter, the way macOS's own window tiling leaves it.
    static func isNativeTile(_ f: CGRect, in area: CGRect, tolerance: CGFloat = 24) -> Bool {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        let fullW = near(f.width, area.width), halfW = near(f.width, area.width / 2)
        let fullH = near(f.height, area.height), halfH = near(f.height, area.height / 2)
        guard (fullW || halfW) && (fullH || halfH) && !(fullW && fullH) else { return false }
        let flushX = near(f.minX, area.minX) || near(f.maxX, area.maxX)
        let flushY = near(f.minY, area.minY) || near(f.maxY, area.maxY)
        return flushX && flushY
    }

    /// Smallest tile an app can be expected to use; a layout with anything smaller leaves the extra windows floating.
    static let usableTile = CGSize(width: 360, height: 240)

    static func allUsable(_ frames: [CGRect]) -> Bool {
        frames.allSatisfy { $0.width >= usableTile.width - 0.5 && $0.height >= usableTile.height - 0.5 }
    }
}
