import CoreGraphics
import Foundation

/// Logical content sections of the taskbar.
///
/// Canonical left-to-right order is always:
/// 1. `weather`
/// 2. `apps` (window chips and tungsten utilities: drawer, shelf, trash, pinned folders)
/// 3. `clock` (combined clock chip & calendar popup)
///
/// The former `media` section (now playing) was removed owner 2026-10-09 (Phase 4U
/// decision 2): Now Playing returns in the 4f rework as a play/pause mini icon
/// at the apps island's right end plus a popup — not as a section of its own.
///
/// The former `tray` section (status cluster) was removed owner 2026-10-09 (Phase 4U
/// decision 8b): Wi-Fi, battery, the tray popup, quick settings and the merged ring
/// icon are Phase 7 edge-bar scope (decision 8c); the bar's right end is the combined
/// clock chip alone.
///
/// Across layout modes, this sequence is never rearranged; only the grouping into
/// discrete island slots varies.
enum BarSection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case weather
    case apps
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: return "Weather"
        case .apps: return "Apps"
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
        case .weather: return 120
        case .apps: return 0
        case .clock: return 160
        }
    }

    /// Grouping of sections into island slots for each layout mode.
    ///
    /// - `.windows`: `[[.weather, .apps, .clock]]` (1 full-width slot)
    /// - `.windows`, `.centered`: `[order]` (1 slot)
    /// - `.split3`: Everything before `.apps` (slot 0), `[.apps]` (slot 1), everything after `.apps` (slot 2)
    /// - `.split4`: Left group, `[.apps]`, first right item, remaining right items.
    ///   With only three canonical sections, the "remaining right items" group is
    ///   empty, so `.split4` yields the same 3 groups as `.split3` (Phase 4U decision
    ///   8b removed `tray`); `BarLayoutMode.slotCount` derives from this, so no
    ///   fourth panel is allocated to duplicate the apps strip.
    static func islands(for mode: BarLayoutMode, order: [BarSection] = [.weather, .apps, .clock]) -> [[BarSection]] {
        switch mode {
        case .windows, .centered:
            return [order]
        case .split3:
            guard let appsIndex = order.firstIndex(of: .apps) else {
                return [order]
            }
            let left = Array(order[..<appsIndex])
            let right = Array(order[(appsIndex + 1)...])
            return [left, [.apps], right].filter { !$0.isEmpty }
        case .split4:
            guard let appsIndex = order.firstIndex(of: .apps) else {
                return [order]
            }
            let left = Array(order[..<appsIndex])
            let right = Array(order[(appsIndex + 1)...])
            if right.count > 1 {
                return [left, [.apps], [right[0]], Array(right[1...])].filter { !$0.isEmpty }
            } else {
                return [left, [.apps], right].filter { !$0.isEmpty }
            }
        }
    }

    /// The 0-based slot index that hosts this section in the given layout mode.
    func slotIndex(for mode: BarLayoutMode, order: [BarSection] = [.weather, .apps, .clock]) -> Int {
        let islandGroups = Self.islands(for: mode, order: order)
        for (index, group) in islandGroups.enumerated() {
            if group.contains(self) {
                return index
            }
        }
        return 0
    }
}
