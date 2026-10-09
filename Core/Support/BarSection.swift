import CoreGraphics
import Foundation

/// Logical content sections of the taskbar.
///
/// Canonical left-to-right order is always:
/// 1. `weather`
/// 2. `apps` (window chips and tungsten utilities: drawer, shelf, trash, pinned folders)
/// 3. `media` (Now Playing mini icon and popup)
/// 4. `clock` (combined clock chip & calendar popup)
///
/// The `media` section is grouped with `.apps` in split modes, appearing at the
/// right end of the apps island (Phase 4U decision 2).
///
/// Across layout modes, this sequence is never rearranged; only the grouping into
/// discrete island slots varies.
enum BarSection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case weather
    case apps
    case media
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: return "Weather"
        case .apps: return "Apps"
        case .media: return "Now Playing"
        case .clock: return "Clock"
        }
    }

    var placeholderEntryID: String {
        "sec-\(rawValue)"
    }

    /// Fixed default width for the section's placeholder frame when no
    /// `widgetWidths` override is stored (edited via sliders in Settings —
    /// Phase 4U decision 3: order hardcoded, widths settings-only).
    var defaultWidgetWidth: CGFloat {
        switch self {
        case .weather: return 150
        case .apps: return 0
        case .media: return 140
        case .clock: return 160
        }
    }

    /// Grouping of sections into island slots for each layout mode.
    static func islands(for mode: BarLayoutMode, order: [BarSection] = [.weather, .apps, .media, .clock]) -> [[BarSection]] {
        switch mode {
        case .windows, .centered:
            return [order]
        case .split3, .split4:
            // Group .apps and .media together in the center island.
            guard let appsIndex = order.firstIndex(of: .apps) else {
                return [order]
            }
            var left = Array(order[..<appsIndex])
            var center: [BarSection] = [.apps]
            
            var rightStartIndex = appsIndex + 1
            if rightStartIndex < order.count && order[rightStartIndex] == .media {
                center.append(.media)
                rightStartIndex += 1
            }
            
            var right = Array(order[rightStartIndex...])
            
            if mode == .split4 && right.count > 1 {
                return [left, center, [right[0]], Array(right[1...])].filter { !$0.isEmpty }
            } else {
                return [left, center, right].filter { !$0.isEmpty }
            }
        }
    }

    /// The 0-based slot index that hosts this section in the given layout mode.
    func slotIndex(for mode: BarLayoutMode, order: [BarSection] = [.weather, .apps, .media, .clock]) -> Int {
        let islandGroups = Self.islands(for: mode, order: order)
        for (index, group) in islandGroups.enumerated() {
            if group.contains(self) {
                return index
            }
        }
        return 0
    }
}
