import Foundation
import Combine

public enum ClockPreset: String, CaseIterable, Equatable {
    case modernMac = "modern"
    case pixelRetro = "pixel"
    case flipTiles = "flip"
}

public struct ClockContent: Equatable {
    public let primaryText: String
    public let secondaryText: String?
    
    public init(primaryText: String, secondaryText: String? = nil) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

public protocol ClockDataProvider {
    func currentContent(for date: Date) -> ClockContent
}

/// 4e: the tick a minute-resolution clock waits for.
public enum ClockTick {
    /// The first whole-minute boundary strictly after `date` — the instant `TimelineView` must
    /// start on so a minute-aligned chip never shows a reading that is up to 59s stale. Exactly
    /// on a boundary returns the *next* one, never the same instant.
    public static func nextMinute(after date: Date, calendar: Calendar = .current) -> Date {
        guard let minute = calendar.dateInterval(of: .minute, for: date) else { return date }
        return minute.end
    }
}

/// 8d: the chip's hue axis — warm by day, indigo at night.
///
/// The exact RGB stops live in `ClockArt` (App) next to the weather samples they are a
/// matched pair against; this is the day/night split itself, kept in Core as the testable
/// seam. Boundaries picked at build time: 07:00–18:59 local reads warm, 19:00–06:59 indigo.
public enum ClockChipDaylight {
    public static func isNight(_ date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour < 7 || hour >= 19
    }
}

public final class StandardClockProvider: ClockDataProvider {
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    
    public init() {
        timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        dateFormatter = DateFormatter()
        // Example: "Wed, Jun 17"
        dateFormatter.dateFormat = "E, MMM d"
    }
    
    public func currentContent(for date: Date) -> ClockContent {
        return ClockContent(
            primaryText: timeFormatter.string(from: date),
            secondaryText: dateFormatter.string(from: date)
        )
    }
}
