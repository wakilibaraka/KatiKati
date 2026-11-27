import CoreGraphics
import Foundation

/// Privacy detail level for the lock-screen calendar card (`L1`).
enum LockScreenDetailMode: String, CaseIterable, Identifiable, Sendable {
    case busyOnly
    case titles

    var id: String { rawValue }
}

/// Shared preference keys and decoders for Lock Screen surfaces (`L1`–`L4`).
enum LockScreenPrefs {
    static let calendarEnabledKey = "com.katikati.lockscreen.calendarEnabled"
    static let calendarDetailKey = "com.katikati.lockscreen.calendarDetail"
    static let fullArtBackdropKey = "com.katikati.lockscreen.fullArtBackdrop"
    static let glanceEnabledKey = "com.katikati.lockscreen.glanceEnabled"

    static func detailMode(from raw: String) -> LockScreenDetailMode {
        LockScreenDetailMode(rawValue: raw) ?? .busyOnly
    }
}

struct LockScreenEventRow: Identifiable, Equatable, Sendable {
    let id: String
    let displayTitle: String
    let timeLabel: String
    let countdownLabel: String?
    let isOngoing: Bool
    let colorRGB: [Double]
}

struct LockScreenGlanceItem: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let text: String
}

/// Pure event filtering, privacy redaction, glance formatting, and panel height budgeting for Lock Screen (`L1`, `L4`).
enum LockScreenSurfacePolicy {
    static func eventRows(
        from events: [DockEvent],
        now: Date,
        detailMode: LockScreenDetailMode,
        limit: Int = 3,
        busyPlaceholder: String = "Busy",
        timeFormatter: DateFormatter? = nil
    ) -> [LockScreenEventRow] {
        guard limit > 0 else { return [] }
        let selected = UpcomingEvents.select(events, now: now, limit: limit)
        let formatter = timeFormatter ?? defaultTimeFormatter()

        return selected.map { event in
            let status = EventTimeUntil.resolve(start: event.start, end: event.end, now: now)
            let isOngoing: Bool
            if case .inProgress = status {
                isOngoing = true
            } else {
                isOngoing = false
            }
            let title = detailMode == .busyOnly ? busyPlaceholder : event.title
            let timeLabel = event.isAllDay ? "" : formatter.string(from: event.start)
            return LockScreenEventRow(
                id: event.id,
                displayTitle: title,
                timeLabel: timeLabel,
                countdownLabel: status.label,
                isOngoing: isOngoing,
                colorRGB: event.colorRGB
            )
        }
    }

    static func glanceItems(
        focusRemaining: String?,
        temperatureCelsius: Double?,
        weatherSymbol: String?,
        nextEventCountdown: String?
    ) -> [LockScreenGlanceItem] {
        var items: [LockScreenGlanceItem] = []
        if let focusRemaining = nonEmpty(focusRemaining) {
            items.append(LockScreenGlanceItem(id: "focus", symbol: "moon.fill", text: focusRemaining))
        }
        if let temp = temperatureCelsius {
            let symbol = nonEmpty(weatherSymbol) ?? "cloud.fill"
            items.append(LockScreenGlanceItem(id: "weather", symbol: symbol, text: "\(Int(temp.rounded()))°"))
        }
        if let next = nonEmpty(nextEventCountdown) {
            items.append(LockScreenGlanceItem(id: "nextEvent", symbol: "calendar", text: next))
        }
        return items
    }

    static func stackHeight(
        musicHeight: CGFloat,
        showsCalendar: Bool,
        calendarRowCount: Int,
        showsGlance: Bool
    ) -> CGFloat {
        var height = musicHeight
        if showsGlance {
            height += 36
        }
        if showsCalendar {
            let rows = max(1, min(3, calendarRowCount))
            height += 54 + CGFloat(rows) * 26
        }
        return height
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func defaultTimeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }
}
