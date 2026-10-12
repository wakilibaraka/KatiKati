import AppKit
import SwiftUI

/// Open state of the full notch skin: header row on top, then music (or the winning activity) on the
/// left and the calendar on the right. The Shelf tab swaps the body for the parked files.
struct NotchHomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    let calendarEnabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView(model: model, metrics: metrics)
            Group {
                switch model.tab {
                case .home: home
                case .tools: NotchToolsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
        }
        // NotchShape's top corners flare outward, so the body is inset by the top radius per side.
        .padding(.horizontal, NotchLayoutSpec.openCornerRadii.top + NotchLayoutSpec.openPadding)
        .padding(.bottom, NotchLayoutSpec.openPadding)
    }

    /// Both halves sit on the same soft rounded card so they read as a matched pair.
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(NotchLayoutSpec.cardPadding)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
                .fill(Color.white.opacity(NotchLayoutSpec.cardFillOpacity)))
    }

    private var home: some View {
        let panels = NotchLayoutSpec.panels(activityKind: feed.activity.kind, calendarEnabled: calendarEnabled)
        return HStack(alignment: .top, spacing: NotchLayoutSpec.homeSpacing) {
            card {
                switch panels.left {
                case .music: NotchMusicPanel(feed: feed, isIdle: feed.activity.kind != .music)
                case .activity: NotchActivityPanel(activity: feed.activity)
                }
            }
            .frame(maxWidth: .infinity)
            if panels.showsCalendar {
                card { NotchCalendarPanel(calendar: ProductivityServices.shared.calendar) }
                    .frame(width: NotchLayoutSpec.calendarColumnWidth)
            }
        }
    }
}
