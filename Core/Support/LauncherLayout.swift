import CoreGraphics
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

/// 57b: how the launcher takes the screen. Fullscreen is the pre-57b behaviour and stays the default; the windowed
/// modes leave the desktop visible around a rounded card. Raw values are stored in
/// `com.katikati.launcher.presentation`; never rename them.
enum LauncherPresentation: String, CaseIterable, Sendable {
    case fullscreen
    case centred
    case popover

    static let `default`: LauncherPresentation = .fullscreen

    static func parse(_ stored: String?) -> LauncherPresentation {
        stored.flatMap(LauncherPresentation.init(rawValue:)) ?? .default
    }
}

/// 57b: where that panel sits. Pure, so the three shapes can be checked without opening a window (window and screen
/// frames share the bottom-left origin, and every shape is pulled inside `visible`).
enum LauncherPanelFrame {
    static let centredMax = CGSize(width: 1200, height: 760)
    static let popoverSize = CGSize(width: 640, height: 520)
    static let margin: CGFloat = 8
    static let popoverGap: CGFloat = 12

    static func rect(mode: LauncherPresentation, screen: CGRect, visible: CGRect, anchor: CGPoint?) -> CGRect {
        switch mode {
        case .fullscreen: return screen
        case .centred: return centred(in: visible)
        case .popover: return popover(in: visible, anchor: anchor)
        }
    }

    /// Four fifths of the usable screen, never over `centredMax`.
    static func centred(in visible: CGRect) -> CGRect {
        let width = min(centredMax.width, visible.width * 0.8)
        let height = min(centredMax.height, visible.height * 0.8)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    /// Hangs under the summoning point (the pointer, or the FAB that was clicked), pulled back inside the screen.
    static func popover(in visible: CGRect, anchor: CGPoint?) -> CGRect {
        let width = min(popoverSize.width, visible.width - 2 * margin)
        let height = min(popoverSize.height, visible.height - 2 * margin)
        let point = anchor ?? CGPoint(x: visible.midX, y: visible.minY)
        let x = min(max(point.x - width / 2, visible.minX + margin), visible.maxX - width - margin)
        let y = min(max(point.y - height - popoverGap, visible.minY + margin), visible.maxY - height - margin)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// 57c: where the floating launcher orb sits and what counts as a click on it. Pure so the corner, the clamp against
/// another display's stored position and the drag slop can be tested without a window.
enum LauncherOrbPlacement {
    static let size: CGFloat = 56
    static let margin: CGFloat = 8
    /// Travel under this is a click, not a drag.
    static let clickSlop: CGFloat = 4

    /// Bottom-right of the usable screen, above the dock, on first run.
    static func defaultOrigin(in visible: CGRect) -> CGPoint {
        CGPoint(x: visible.maxX - size - margin, y: visible.minY + margin)
    }

    /// Keeps the whole orb on screen, so a position saved on a display that is now gone still lands somewhere.
    static func clamp(_ origin: CGPoint, in visible: CGRect) -> CGPoint {
        let maxX = max(visible.minX + margin, visible.maxX - size - margin)
        let maxY = max(visible.minY + margin, visible.maxY - size - margin)
        return CGPoint(x: min(max(origin.x, visible.minX + margin), maxX),
                       y: min(max(origin.y, visible.minY + margin), maxY))
    }

    static func isClick(travel: CGPoint) -> Bool {
        (travel.x * travel.x + travel.y * travel.y).squareRoot() <= clickSlop
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
