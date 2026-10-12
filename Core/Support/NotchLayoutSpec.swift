import CoreGraphics
import Foundation

// Notch Live Island "boring" skin — the pure layout numbers and panel-selection rules.
//
// The numbers are the open-notch proportions of the reference design (a 640×190 black NotchShape with a
// header row, a music half and a calendar half). Keeping them here, away from SwiftUI, lets the sizes,
// the corner radii, the week strip and "which panels show" be unit-tested. Dual-compiled.

/// Which look the notch uses. `classic` is the original single-row panel.
enum LiveIslandSkin: String, CaseIterable, Sendable {
    case classic
    case boring
}

enum NotchTab: String, CaseIterable, Sendable {
    case home
    case shelf
}

enum NotchLayoutSpec {
    // MARK: sizes
    static let openSize = CGSize(width: 640, height: 190)
    static let closedCornerRadii = (top: CGFloat(6), bottom: CGFloat(14))
    static let openCornerRadii = (top: CGFloat(19), bottom: CGFloat(24))
    static let openPadding: CGFloat = 12
    static let homeSpacing: CGFloat = 12
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 12
    static let cardFillOpacity = 0.07
    static let headerSpacing: CGFloat = 8
    static let volumeSliderWidth: CGFloat = 56
    static let calendarColumnWidth: CGFloat = 215
    static let albumArtSize: CGFloat = 88
    static let albumArtCorner: CGFloat = 13
    static let headerButtonSize: CGFloat = 26
    static let progressHeight: CGFloat = 10

    // MARK: animation (response, damping)
    static let openSpring = (response: 0.42, damping: 0.8)
    static let closeSpring = (response: 0.45, damping: 1.0)

    /// Header is as tall as the closed notch (it flanks it) — never shorter than the buttons.
    static func headerHeight(closedHeight: CGFloat) -> CGFloat {
        max(closedHeight, headerButtonSize)
    }

    /// The open panel is never wider than the screen minus a small margin, and never narrower than
    /// the closed notch.
    static func openPanelSize(screenWidth: CGFloat, closedWidth: CGFloat) -> CGSize {
        let width = min(openSize.width, max(closedWidth, screenWidth - 24))
        return CGSize(width: width, height: openSize.height)
    }

    /// `size` clamped to the screen width (see `openPanelSize`); the height is kept.
    static func fit(_ size: CGSize, screenWidth: CGFloat, closedWidth: CGFloat) -> CGSize {
        CGSize(width: min(size.width, max(closedWidth, screenWidth - 24)), height: size.height)
    }

    // MARK: panels

    enum LeftPanel: Equatable { case music, activity }

    struct Panels: Equatable {
        var left: LeftPanel
        var showsCalendar: Bool
    }

    /// Music panel when music is the winning activity **or nothing is active** (the idle clock fallback
    /// is never shown on the notch — idle is the Now Playing player with quick actions); otherwise the
    /// running activity (timer, focus, stopwatch, countdown).
    static func panels(activityKind: LiveActivityKind, calendarEnabled: Bool) -> Panels {
        let showsPlayer = activityKind == .music || activityKind == .clock
        return Panels(left: showsPlayer ? .music : .activity, showsCalendar: calendarEnabled)
    }

    // MARK: week strip

    struct WeekDay: Equatable {
        var date: Date
        var dayNumber: Int
        var isToday: Bool
    }

    /// Seven consecutive days starting three days before `now` so today sits in the middle of the
    /// strip, like the reference ("Sat … Thu" with today fourth).
    static func weekStrip(now: Date, calendar: Calendar = .current) -> [WeekDay] {
        let today = calendar.startOfDay(for: now)
        return (-3...3).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return WeekDay(date: day, dayNumber: calendar.component(.day, from: day), isToday: offset == 0)
        }
    }

    /// "mm:ss" or "h:mm:ss"; clamps negatives to zero.
    static func clockText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
