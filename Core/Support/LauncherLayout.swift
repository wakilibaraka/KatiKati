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
