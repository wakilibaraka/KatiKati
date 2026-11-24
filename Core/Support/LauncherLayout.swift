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

/// How the launcher takes the screen. Windowed modes leave the desktop visible around a rounded card.
/// Raw values are stored in `com.katikati.launcher.presentation`; never rename them.
enum LauncherPresentation: String, CaseIterable, Sendable {
    case windowsStart
    case linuxMenu
    case drawer
    case centred
    case fullscreen

    static let `default`: LauncherPresentation = .windowsStart

    /// Legacy `"dock"` and `"popover"` stored strings auto-upgrade to `.windowsStart`.
    static func parse(_ stored: String?) -> LauncherPresentation {
        if stored == "dock" || stored == "popover" { return .windowsStart }
        return stored.flatMap(LauncherPresentation.init(rawValue:)) ?? .default
    }
}

/// Where anchored windowed launcher presets open. Raw values are stored in `LauncherPrefs`.
enum LauncherAnchorMode: String, CaseIterable, Codable, Sendable {
    case aboveIcon
    case screenCenter
    case followMouse

    static let `default`: LauncherAnchorMode = .aboveIcon
}

/// Item density for launcher grids and lists. Raw values are stored in `LauncherPrefs`.
enum LauncherDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case standard
    case spacious

    static let `default`: LauncherDensity = .standard
}

/// Content presentation inside category/list-capable launcher presets.
enum LauncherViewMode: String, CaseIterable, Codable, Sendable {
    case grid
    case list

    static let `default`: LauncherViewMode = .grid
}

/// Where the launcher panel sits. Pure, so all preset shapes can be checked without opening a window
/// (window and screen frames share the bottom-left origin, and every shape is pulled inside `visible`).
enum LauncherPanelFrame {
    static let centredMax = CGSize(width: 1200, height: 760)
    static let windowsStartSize = CGSize(width: 660, height: 620)
    static let linuxMenuSize = CGSize(width: 740, height: 560)
    static let drawerSize = CGSize(width: 440, height: 480)
    static let margin: CGFloat = 8

    /// `dockReserve` is the KatiKati bottom bar height; `leading` / `trailing` are side rail widths.
    static func rect(mode: LauncherPresentation, screen: CGRect, visible: CGRect,
                     dockReserve: CGFloat = 0, leading: CGFloat = 0, trailing: CGFloat = 0,
                     anchorX: CGFloat? = nil, anchorMode: LauncherAnchorMode = .aboveIcon) -> CGRect {
        switch mode {
        case .fullscreen: return screen
        case .centred: return centred(in: visible)
        case .windowsStart:
            return anchored(targetSize: windowsStartSize, in: visible, dockReserve: dockReserve,
                            leading: leading, trailing: trailing, anchorX: anchorX,
                            anchorMode: anchorMode, defaultCentered: true)
        case .linuxMenu:
            return anchored(targetSize: linuxMenuSize, in: visible, dockReserve: dockReserve,
                            leading: leading, trailing: trailing, anchorX: anchorX,
                            anchorMode: anchorMode, defaultCentered: false)
        case .drawer:
            if anchorMode == .screenCenter {
                return anchored(targetSize: drawerSize, in: visible, dockReserve: dockReserve,
                                leading: leading, trailing: trailing, anchorX: nil,
                                anchorMode: .screenCenter, defaultCentered: true)
            }
            return drawer(in: visible, dockReserve: dockReserve, leading: leading, trailing: trailing, anchorX: anchorX)
        }
    }

    /// Four fifths of the usable screen, never over `centredMax`.
    static func centred(in visible: CGRect) -> CGRect {
        let width = min(centredMax.width, visible.width * 0.8)
        let height = min(centredMax.height, visible.height * 0.8)
        return CGRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
    }

    /// Anchored or centered card inside the usable area above the bottom bar and between side rails.
    static func anchored(targetSize: CGSize, in visible: CGRect, dockReserve: CGFloat, leading: CGFloat,
                         trailing: CGFloat, anchorX: CGFloat?, anchorMode: LauncherAnchorMode,
                         defaultCentered: Bool) -> CGRect {
        let area = CGRect(x: visible.minX + leading, y: visible.minY + dockReserve,
                          width: max(0, visible.width - leading - trailing),
                          height: max(0, visible.height - dockReserve))
        let width = min(targetSize.width, max(0, area.width - 2 * margin), area.width * 0.88)
        let height = min(targetSize.height, max(0, area.height - 2 * margin), area.height * 0.88)
        let minX = min(area.minX + margin, max(area.minX, area.maxX - width))
        let maxX = max(minX, area.maxX - width - margin)
        let rawX: CGFloat
        if anchorMode == .screenCenter {
            rawX = area.midX - width / 2
        } else {
            rawX = anchorX.map { $0 - width / 2 } ?? (defaultCentered ? area.midX - width / 2 : minX)
        }
        let x = min(max(rawX, minX), maxX)
        let y: CGFloat
        if anchorMode == .screenCenter {
            y = min(max(area.midY - height / 2, area.minY + margin), max(area.minY, area.maxY - height - margin))
        } else {
            y = min(area.minY + margin, max(area.minY, area.maxY - height - margin))
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Compact vertical drawer anchored above the bottom bar (leading edge by default, or centered on `anchorX`),
    /// clamped between side rails inside `visible`.
    static func drawer(in visible: CGRect, dockReserve: CGFloat, leading: CGFloat, trailing: CGFloat,
                       anchorX: CGFloat? = nil) -> CGRect {
        let area = CGRect(x: visible.minX + leading, y: visible.minY + dockReserve,
                          width: max(0, visible.width - leading - trailing),
                          height: max(0, visible.height - dockReserve))
        let width = min(drawerSize.width, max(min(area.width, 280), area.width - 2 * margin), area.width)
        let height = min(drawerSize.height, area.height * 0.72)
        let minX = min(area.minX + margin, max(area.minX, area.maxX - width))
        let maxX = max(minX, area.maxX - width - margin)
        let rawX = anchorX.map { $0 - width / 2 } ?? minX
        let x = min(max(rawX, minX), maxX)
        let y = min(area.minY + margin, max(area.minY, visible.maxY - height - margin))
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

    static let `default`: LauncherScrollDirection = .vertical

    static func parse(_ stored: String?) -> LauncherScrollDirection {
        stored.flatMap(LauncherScrollDirection.init(rawValue:)) ?? .default
    }
}
