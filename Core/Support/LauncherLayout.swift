import Foundation

/// Where the launcher's search field sits (Phase 7B-L5). Always centred on its side; top is the default.
/// Raw values are stored in `com.katikati.launcher.searchPosition`; never rename them.
enum LauncherSearchPosition: String, CaseIterable, Sendable {
    case top
    case bottom
    case left
    case right

    static let `default`: LauncherSearchPosition = .top

    static func parse(_ stored: String?) -> LauncherSearchPosition {
        stored.flatMap(LauncherSearchPosition.init(rawValue:)) ?? .default
    }

    /// Width of the field on that side (a side field is narrower than a top/bottom one).
    var fieldWidth: Double { self == .left || self == .right ? 260 : 420 }

    /// Space the grid must leave for the field and, when the sheet is on the same side, for the sheet as well.
    /// Order: top, bottom, leading, trailing.
    func reservedInsets(sheetSide: EdgeSide, sheetWidth: Double = 328, field: Double = 56, side: Double = 300) -> (top: Double, bottom: Double, leading: Double, trailing: Double) {
        var i = (top: 0.0, bottom: 0.0, leading: 0.0, trailing: 0.0)
        switch self {
        case .top: i.top = field
        case .bottom: i.bottom = field
        case .left: i.leading = side
        case .right: i.trailing = side
        }
        if sheetSide == .left { i.leading += sheetWidth } else { i.trailing += sheetWidth }
        return i
    }
}

/// Space the launcher must keep clear on a screen so nothing sits under the notch, the menu bar, the Dock or a
/// KatiKati bar (Phase 7B). `frame` is the full screen, `visible` is what macOS leaves usable; `safeTop` is the notch
/// inset (`safeAreaInsets.top`). Insets are never negative and never exceed a third of the screen.
enum LauncherScreenInsets {
    /// `extraLeading` / `extraTrailing` keep the grid clear of a KatiKati side rail (Phase 18d).
    static func compute(frame: CGRect, visible: CGRect, safeTop: Double, extraBottom: Double = 0,
                        extraLeading: Double = 0, extraTrailing: Double = 0) -> (top: Double, bottom: Double, leading: Double, trailing: Double) {
        func clamp(_ v: Double, _ limit: Double) -> Double { min(max(0, v), limit / 3) }
        return (
            top: clamp(max(Double(frame.maxY - visible.maxY), safeTop), Double(frame.height)),
            bottom: clamp(Double(visible.minY - frame.minY) + extraBottom, Double(frame.height)),
            leading: clamp(Double(visible.minX - frame.minX) + extraLeading, Double(frame.width)),
            trailing: clamp(Double(frame.maxX - visible.maxX) + extraTrailing, Double(frame.width))
        )
    }
}

/// Which way the launcher grid scrolls (Phase 7B launcher redo). Raw values are stored in
/// `com.katikati.launcher.scroll`; never rename them.
enum LauncherScrollDirection: String, CaseIterable, Sendable {
    case vertical
    case horizontal

    static let `default`: LauncherScrollDirection = .horizontal

    static func parse(_ stored: String?) -> LauncherScrollDirection {
        stored.flatMap(LauncherScrollDirection.init(rawValue:)) ?? .default
    }
}
