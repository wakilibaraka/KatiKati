import Foundation

/// Layout modes supported by KatiKati.
///
/// KatiKati provides 4 distinct taskbar presentations:
/// - `.windows`: Traditional single full-width bar across the bottom of the screen.
/// - `.split3`: Three separate floating islands: Weather on the left, Apps centered, and Clock on the right.
/// - `.split4`: Four-island grouping rule (left / apps / first right / rest right). With the
///   canonical `weather → apps → clock` order (Phase 4U decision 8b removed `tray`) it
///   produces the same 3 islands as `.split3`.
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
            return "Full-width bar with weather, centered apps and clock"
        case .split3:
            return "Three islands: weather on left, apps centered, clock on right"
        case .split4:
            return "Three islands (split-4 rule): weather on left, apps centered, clock"
        case .centered:
            return "Single compact centered floating bar"
        }
    }
}
