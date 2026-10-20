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
    /// Focus & timers, clipboard + quick note, system HUD (the file shelf lives on the dock).
    case tools

    var localizedTitle: String {
        switch self {
        case .home: return String(localized: "Home")
        case .tools: return String(localized: "Tools")
        }
    }
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

    // MARK: ear zones

    /// What may sit left and right of the camera cutout on the collapsed notch, in the capsule's own
    /// coordinates (origin top-left). Both are `.zero` without hardware: a fake pill has no cutout to flank.
    struct EarZones: Equatable {
        var left: CGRect
        var right: CGRect
    }

    /// The capsule grows by `sneakSide` on each side while an activity shows, which pushes the keepout
    /// inward from the capsule edges by the same amount.
    static func earZones(metrics: NotchMetrics, showsActivity: Bool) -> EarZones {
        guard metrics.hasHardwareNotch, !metrics.cameraKeepoutBox.isEmpty else { return EarZones(left: .zero, right: .zero) }
        let sneak = showsActivity ? NotchGeometry.sneakSide : 0
        let keepout = metrics.cameraKeepoutBox
        let total = metrics.closedSize.width + 2 * sneak
        let height = metrics.closedSize.height
        let leftWidth = keepout.minX + sneak
        let rightX = keepout.maxX + sneak
        return EarZones(left: CGRect(x: 0, y: 0, width: leftWidth, height: height),
                        right: CGRect(x: rightX, y: 0, width: total - rightX, height: height))
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

    // MARK: page body

    /// The 4 pt gap the page group adds under the header row (`NotchHomeView`).
    static let pageTopPadding: CGFloat = 4

    /// Height left for a Bento page's cards: the open panel minus the header row that flanks the notch,
    /// the page gap, and the grid's bottom padding. A card that asks for more than this is clipped by the
    /// panel with no warning, so the cards' own budgets are asserted against it in the tests.
    static func pageBodyHeight(headerHeight: CGFloat) -> CGFloat {
        openSize.height - headerHeight - pageTopPadding - NotchDesignSpec.gridPadding.bottom
    }
}

/// Row budget of the Productivity page's two cards (48a). Named constants rather than literals inside the
/// view, so "does it still fit?" is a unit test instead of an eyeball on a notched display.
enum NotchProductivityLayout {
    static let cardHeader: CGFloat = 18
    static let weekStrip: CGFloat = 26
    static let agendaRow: CGFloat = 14
    static let agendaRowCount = 3
    static let focusTimer: CGFloat = 22
    static let progress: CGFloat = 6
    static let controls: CGFloat = 22
    static let reminderRow: CGFloat = 13
    static let rowSpacing: CGFloat = 3

    /// Card A: header, the week strip, then the agenda rows.
    static func cardAContent(rows: Int = agendaRowCount) -> CGFloat {
        cardHeader + weekStrip + CGFloat(rows) * agendaRow + 2 * rowSpacing
    }

    /// Card B: header, timer + cycle dots, progress, controls, and a reminder row when one exists.
    static func cardBContent(hasReminder: Bool) -> CGFloat {
        let rows: CGFloat = hasReminder ? 5 : 4
        return cardHeader + focusTimer + progress + controls + (hasReminder ? reminderRow : 0)
            + (rows - 1) * rowSpacing
    }

    /// Both cards share one height; the taller one must fit the page body minus the cards' own padding.
    static func fits(headerHeight: CGFloat, hasReminder: Bool, cardPadding: CGFloat) -> Bool {
        let budget = NotchLayoutSpec.pageBodyHeight(headerHeight: headerHeight) - 2 * cardPadding
        return max(cardAContent(), cardBContent(hasReminder: hasReminder)) <= budget
    }
}
