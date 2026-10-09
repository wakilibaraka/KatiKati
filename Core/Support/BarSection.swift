import Foundation

/// Logical content sections of the taskbar.
///
/// Canonical left-to-right order is always:
/// 1. `weather`
/// 2. `media` (now playing, live activities)
/// 3. `apps` (window chips and tungsten utilities: drawer, shelf, trash, pinned folders)
/// 4. `tray` (status cluster: battery, wifi, bluetooth, quick settings)
/// 5. `clock` (clock chip & calendar)
///
/// Across layout modes, this sequence is never rearranged; only the grouping into
/// discrete island slots varies.
enum BarSection: String, CaseIterable, Identifiable, Hashable, Codable, Sendable {
    case weather
    case media
    case apps
    case tray
    case clock

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weather: return "Weather"
        case .media: return "Media"
        case .apps: return "Apps"
        case .tray: return "Tray"
        case .clock: return "Clock"
        }
    }

    var placeholderEntryID: String {
        "sec-\(rawValue)"
    }

    /// Grouping of sections into island slots for each layout mode.
    ///
    /// - `.windows`: `[[.weather, .media, .apps, .tray, .clock]]` (1 full-width slot)
    /// - `.split3`: `[[.weather, .media], [.apps], [.tray, .clock]]` (3 slots)
    /// - `.split4`: `[[.weather, .media], [.apps], [.tray], [.clock]]` (4 slots)
    /// - `.centered`: `[[.weather, .media, .apps, .tray, .clock]]` (1 centered slot)
    static func islands(for mode: BarLayoutMode) -> [[BarSection]] {
        switch mode {
        case .windows, .centered:
            return [[.weather, .media, .apps, .tray, .clock]]
        case .split3:
            return [[.weather, .media], [.apps], [.tray, .clock]]
        case .split4:
            return [[.weather, .media], [.apps], [.tray], [.clock]]
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
