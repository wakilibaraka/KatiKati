import Foundation

/// Logical content sections of the taskbar.
///
/// Canonical left-to-right order is always:
/// 1. `weather`
/// 2. `apps` (window chips and tungsten utilities: drawer, shelf, trash, pinned folders)
/// 3. `tray` (status cluster: battery, wifi, bluetooth, quick settings)
/// 4. `clock` (clock chip & calendar)
///
/// Across layout modes, this sequence is never rearranged; only the grouping into
/// discrete island slots varies.
enum BarSection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case weather
    case apps
    case tray
    case clock

    var id: String { rawValue }

    /// Grouping of sections into island slots for each layout mode.
    ///
    /// Per HYBRID_PLAN.md Appendix A:
    /// - `.windows`: `[[.weather, .apps, .tray, .clock]]` (1 full-width slot)
    /// - `.split3`: `[[.weather], [.apps], [.tray, .clock]]` (3 slots)
    /// - `.split4`: `[[.weather], [.apps], [.tray], [.clock]]` (4 slots)
    /// - `.centered`: `[[.weather, .apps, .tray, .clock]]` (1 centered slot)
    static func islands(for mode: BarLayoutMode) -> [[BarSection]] {
        switch mode {
        case .windows, .centered:
            return [[.weather, .apps, .tray, .clock]]
        case .split3:
            return [[.weather], [.apps], [.tray, .clock]]
        case .split4:
            return [[.weather], [.apps], [.tray], [.clock]]
        }
    }

    /// The 0-based slot index that hosts this section in the given layout mode.
    func slotIndex(for mode: BarLayoutMode) -> Int {
        let islandGroups = Self.islands(for: mode)
        for (index, group) in islandGroups.enumerated() {
            if group.contains(self) {
                return index
            }
        }
        return 0
    }
}
