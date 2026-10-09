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
    /// - `.windows`, `.centered`: `[order]` (1 slot)
    /// - `.split3`: Everything before `.apps` (slot 0), `[.apps]` (slot 1), everything after `.apps` (slot 2)
    /// - `.split4`: Left group, `[.apps]`, first right item, remaining right items.
    static func islands(for mode: BarLayoutMode, order: [BarSection] = [.weather, .media, .apps, .tray, .clock]) -> [[BarSection]] {
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
    func slotIndex(for mode: BarLayoutMode, order: [BarSection] = [.weather, .media, .apps, .tray, .clock]) -> Int {
        let islandGroups = Self.islands(for: mode, order: order)
        for (index, group) in islandGroups.enumerated() {
            if group.contains(self) {
                return index
            }
        }
        return 0
    }
}
