import Foundation

/// How the dock's widgets are drawn: one switch in Settings > Widgets, the same widgets in either look, on the
/// bottom bar and on a side rail alike.
enum WidgetLook: String, CaseIterable, Sendable {
    /// KatiKati's own pills: the shared dock plate at the legacy 10 pt radius.
    case classic
    /// Square graphite tiles at 14 pt, the rounder look of Docktor-style docks.
    case tiles

    static let storageKey = "com.katikati.widgets.look"
    static let `default`: WidgetLook = .classic

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .tiles: return "Tiles"
        }
    }

    var cornerRadius: CGFloat { self == .classic ? 10 : 14 }
}
