import Foundation
import SwiftUI

// Shared presentation mapping for the Live Island: kind → SF Symbol / tint / label, activity → value.
// Extracted from the dock capsule (8b-3) so the notch surface (8b-7) renders the very same words and
// glyphs; neither surface owns its own copy. Labels are whole literals that already exist in the
// catalog (localization gate stays one-to-one); values are data (`Text(verbatim:)` / strings).

enum LiveIslandStyle {
    // MARK: - Kind mapping

    /// The kind's SF Symbol. All long-standing symbols (present since macOS 11) — an unknown name
    /// renders nothing at runtime with no compile-time warning, so validity is chosen deliberately.
    static func symbolName(for kind: LiveActivityKind) -> String {
        switch kind {
        case .music: return "music.note"
        case .focus: return "brain.head.profile"
        case .countdown: return "calendar"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .clock: return "clock"
        }
    }

    static func tint(for kind: LiveActivityKind) -> Color {
        switch kind {
        case .music: return .pink
        case .focus: return .orange
        case .countdown: return .blue
        case .timer: return .teal
        case .stopwatch: return .indigo
        case .clock: return .secondary
        }
    }

    /// Localized kind label. Whole literals so the localization gate sees them; every one already
    /// exists in the catalog (and is referenced elsewhere), so this adds no entry and orphans none.
    static func labelText(for kind: LiveActivityKind) -> Text {
        switch kind {
        case .music: return Text("Now Playing")
        case .focus: return Text("Focus")
        case .countdown: return Text("Countdown")
        case .timer: return Text("Timer")
        case .stopwatch: return Text("Stopwatch")
        case .clock: return Text("Clock")
        }
    }

    static func labelString(for kind: LiveActivityKind) -> String {
        switch kind {
        case .music: return String(localized: "Now Playing")
        case .focus: return String(localized: "Focus")
        case .countdown: return String(localized: "Countdown")
        case .timer: return String(localized: "Timer")
        case .stopwatch: return String(localized: "Stopwatch")
        case .clock: return String(localized: "Clock")
        }
    }

    // MARK: - Live value (data, never localized copy)

    static func valueText(for activity: LiveActivity) -> Text? {
        valueString(for: activity).map { Text(verbatim: $0) }
    }

    static func valueString(for activity: LiveActivity) -> String? {
        switch activity.content {
        case .music(let music):
            return music.title ?? music.artist
        case .focus(let focus):
            return LiveIslandFormat.clock(focus.remaining)
        case .countdown(let countdown):
            return countdownValue(countdown)
        case .timer(let timer):
            return LiveIslandFormat.clock(timer.remaining)
        case .stopwatch(let stopwatch):
            return LiveIslandFormat.stopwatch(stopwatch.elapsed)
        case .clock:
            return clockString()
        }
    }

    /// An event's "days away" in localized words via `RelativeDateTimeFormatter` (the OS supplies the
    /// translation), so no catalog key is invented. `0` days has no good relative phrasing ("now"),
    /// so the event's own label carries that case.
    static func countdownValue(_ content: CountdownContent) -> String {
        guard content.daysRemaining > 0 else { return content.label }
        let now = Date()
        guard let target = Calendar.current.date(byAdding: .day, value: content.daysRemaining, to: now) else {
            return content.label
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: target, relativeTo: now)
    }

    /// The wall clock in the locale's preferred 12/24-hour form (a template, not a hardcoded format).
    static func clockString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: Date())
    }

}
