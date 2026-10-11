import Foundation

/// Layout modes supported by KatiKati.
///
/// KatiKati provides 5 distinct taskbar presentations:
/// - `.windows`: Traditional single full-width bar across the bottom of the screen.
/// - `.split3`: Three islands: launcher·weather / apps·media / clock·widgets (Phase 4U-A).
/// - `.split4`: Four islands: launcher·weather / apps / media / clock·widgets (Phase 4U-A).
/// - `.split5`: Five islands: launcher / weather / apps·media / clock / widgets (Phase 4U-A).
/// - `.centered`: A single floating centered pill/island containing all elements.
enum BarLayoutMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case windows
    case split3
    case split4
    case split5
    case centered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Windows"
        case .split3: return "Split 3"
        case .split4: return "Split 4"
        case .split5: return "Split 5"
        case .centered: return "Centered"
        }
    }

    /// Whether this mode renders all sections inside a single continuous island/panel.
    var isSingleIsland: Bool {
        switch self {
        case .windows, .centered: return true
        case .split3, .split4, .split5: return false
        }
    }

    /// Whether this mode divides sections across multiple independent floating islands.
    var isSplit: Bool { !isSingleIsland }

    /// Number of panel slots required for this layout mode.
    ///
    /// Derived from the island groups the canonical order actually produces rather than
    /// a hand-kept constant: after the Phase 4U `.tray` removal (decision 8b) `.split4`
    /// yields 3 groups, and allocating a 4th panel would land in the projection's
    /// orphan-slot `[.apps]` fallback and duplicate the whole apps strip.
    var slotCount: Int {
        BarSection.islands(for: self).count
    }

    var detail: String {
        switch self {
        case .windows:
            return "Full-width bar with every section in one strip"
        case .split3:
            return "Three islands: launcher and weather, apps and now playing, clock and widgets"
        case .split4:
            return "Four islands: launcher and weather, apps, now playing, clock and widgets"
        case .split5:
            return "Five islands: launcher, weather, apps + now playing, clock, widgets"
        case .centered:
            return "Single compact centered floating bar"
        }
    }
}
