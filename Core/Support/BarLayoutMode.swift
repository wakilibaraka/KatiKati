import Foundation

/// Layout modes supported by KatiKati.
///
/// KatiKati provides 4 distinct taskbar presentations:
/// - `.windows`: Traditional single full-width bar across the bottom of the screen.
/// - `.split3`: Three separate floating islands: Weather on the left, Apps centered, and Tray + Clock on the right.
/// - `.split4`: Four separate floating islands: Weather on the left, Apps centered, Tray, and Clock separated on the right.
/// - `.centered`: A single floating centered pill/island containing all elements.
enum BarLayoutMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case windows
    case split3
    case split4
    case centered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .split3: return "Split 3"
        case .split4: return "Split 4"
        case .centered: return "Centered"
        }
    }

    /// Whether this mode renders all sections inside a single continuous island/panel.
    var isSingleIsland: Bool {
        switch self {
        case .windows, .centered: return true
        case .split3, .split4: return false
        }
    }

    /// Whether this mode divides sections across multiple independent floating islands.
    var isSplit: Bool { !isSingleIsland }

    /// Number of panel slots required for this layout mode.
    var slotCount: Int {
        switch self {
        case .windows, .centered: return 1
        case .split3: return 3
        case .split4: return 4
        }
    }

    var detail: String {
        switch self {
        case .windows:
            return "Full-width bar with weather, centered apps, tray and clock"
        case .split3:
            return "Three islands: weather on left, apps centered, tray and clock on right"
        case .split4:
            return "Four islands: weather on left, apps centered, tray, and clock"
        case .centered:
            return "Single compact centered floating bar"
        }
    }
}
