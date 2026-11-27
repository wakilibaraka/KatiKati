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

    /// Fits a frame into `area`: shrink it when the area is smaller, then shift it inside, so the
    /// result is fully visible instead of merely pinned at its leading edge. Restored layouts carry
    /// frames from the display they were saved on — a smaller screen, a bigger Dock or a retired
    /// work-area reserve can leave them hanging off an edge.
    static func fitted(_ frame: CGRect, into area: CGRect) -> CGRect {
        guard area.width > 0, area.height > 0 else { return frame }
        var f = frame
        f.size.width = min(f.width, area.width)
        f.size.height = min(f.height, area.height)
        return shifted(f, into: area)
    }

    /// True when two frames in the same coordinate space match within `tolerance` on origin and size.
    static func isNearlyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// Converts a Quartz (top-left origin) frame's center to Cocoa (bottom-left origin) coordinates.
    static func cocoaCenter(ofQuartzFrame frame: CGRect, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: frame.midX, y: primaryMaxY - frame.midY)
    }
}

/// The ribbon's camera: the smallest scroll offset that shows the focused column whole (RT-2).
/// Offsets are points from the strip's first column; `0` shows the left edge, and the maximum is
/// `contentWidth - viewportWidth`, so the last column can sit flush at the right edge.
enum StripCamera {
    static func offset(
        focused: CGRect,
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        current: CGFloat
    ) -> CGFloat {
        guard viewportWidth > 0, contentWidth > viewportWidth else { return 0 }
        var offset = current
        if focused.minX < offset {
            offset = focused.minX
        } else if focused.maxX > offset + viewportWidth {
            offset = focused.maxX - viewportWidth
        }
        return min(max(0, offset), contentWidth - viewportWidth)
    }
}

/// Where the ribbon keeps a column that is outside the viewport (RT-2). macOS keeps a sliver of
/// any window on screen — ~1 pt at an edge; asking for more snaps back to ~40 pt and never above
/// the menu bar — so the strip asks for that clamp and reads back what it was granted.
enum StripParking {
    enum Side: Sendable, Hashable { case left, right, bottom }

    /// The sliver macOS leaves visible. Larger asks are clamped by the WindowServer, so the solver
    /// requests this value to keep the requested and granted frames in agreement.
    static let peek: CGFloat = 1

    static func parked(_ frame: CGRect, in area: CGRect, side: Side) -> CGRect {
        var f = frame
        switch side {
        case .left: f.origin.x = area.minX - frame.width + peek
        case .right: f.origin.x = area.maxX - peek
        case .bottom: f.origin.y = area.minY - frame.height + peek
        }
        return f
    }

    /// The side to park on: the viewport-relative side, unless another display sits that way, in
    /// which case the column parks at the bottom edge and cannot leak onto the neighbour.
    static func side(forEdge edge: Side, neighbourOnEdge: Bool) -> Side {
        switch edge {
        case .left, .right: return neighbourOnEdge ? .bottom : edge
        case .bottom: return .bottom
        }
    }
}

/// Where a workspace keeps the windows that are not in the active workspace (W-3).
///
/// Same mechanism the ribbon already uses — macOS keeps a sliver of any window it is asked to move
/// past an edge, and pulls back an ask that goes further — but a workspace parks a whole set at once
/// and remembers the frame each window had so a switch (or a quit) can put it back. Cocoa
/// coordinates (bottom-left origin), like the rest of this file.
///
/// The recovery frame is the load-bearing part: it is written *before* a window is parked and only
/// discarded once the window has been restored and that removal has been persisted. A crash between
/// the two leaves a window parked with a frame to return to, which is recoverable; the reverse order
/// would leave it off screen with nothing recorded (spaceman's parking invariant).
enum WorkspaceParking {
    /// One parked window's recovery record, as persisted.
    struct Record: Codable, Equatable, Sendable {
        /// `WindowID.rawValue`.
        var windowID: String
        /// The display the window belongs to (`TilingEngine.screenKey(for:)`).
        var displayKey: String
        /// `WorkspaceID.token` the window belongs to.
        var workspace: String
        /// The Cocoa frame the window had before it was parked.
        var recoveryFrame: CGRect
        /// `"left"`, `"right"` or `"bottom"`.
        var side: String
        /// The owning process and window id, so a crash-recovery pass can write the frame back
        /// without a live snapshot. Optional: an older record may not carry them.
        var pid: Int32?
        var cgWindowID: UInt32?

        init(
            windowID: String,
            displayKey: String,
            workspace: String,
            recoveryFrame: CGRect,
            side: StripParking.Side,
            pid: Int32? = nil,
            cgWindowID: UInt32? = nil
        ) {
            self.windowID = windowID
            self.displayKey = displayKey
            self.workspace = workspace
            self.recoveryFrame = recoveryFrame
            self.side = Self.token(for: side)
            self.pid = pid
            self.cgWindowID = cgWindowID
        }

        var parkingSide: StripParking.Side {
            switch side {
            case "left": return .left
            case "bottom": return .bottom
            default: return .right
            }
        }

        static func token(for side: StripParking.Side) -> String {
            switch side {
            case .left: return "left"
            case .right: return "right"
            case .bottom: return "bottom"
            }
        }
    }

    /// The edge to park on. The right edge by default: the bottom edge is where the system Dock
    /// usually is, and where the ribbon already parks when a display sits beside this one. A display
    /// with another display to its right parks at the bottom for the same reason the ribbon does —
    /// a window hanging past the right edge would show up on the neighbour.
    static func side(neighbourOnRight: Bool) -> StripParking.Side {
        neighbourOnRight ? .bottom : .right
    }

    /// The frame that puts `frame` just past `side` of `area`, keeping its size. macOS grants only a
    /// sliver of an off-screen ask, so callers must read back what the window actually took.
    static func parked(_ frame: CGRect, in area: CGRect, side: StripParking.Side) -> CGRect {
        StripParking.parked(frame, in: area, side: side)
    }

    /// Where a parked window goes when it is revealed: its recovery frame, shrunk and shifted into
    /// the current work area if the display has changed since it was parked (the same rule
    /// `WindowLayoutRestoreController.fitToWorkArea` applies to a remembered layout).
    static func revealFrame(_ recovery: CGRect, in area: CGRect) -> CGRect {
        WindowFit.fitted(recovery, into: area)
    }

    /// The workspace a transition plan says to park, without duplicates.
    static func parkingSet(_ plan: WorkspaceTransitionPlan) -> [WindowID] {
        var seen = Set<WindowID>()
        return plan.park.filter { seen.insert($0).inserted }
    }
}
