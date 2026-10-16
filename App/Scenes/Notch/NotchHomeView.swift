import AppKit
import SwiftUI

/// Open state of the full notch skin: header row on top, flanked by the 5-page Bento Suite,
/// then the active Bento Page (AI Mission Control, Vinyl Audio Deck, Retro Flip Clock,
/// Productivity & Calendar, or Hardware HUD).
struct NotchHomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    let calendarEnabled: Bool

    var body: some View {
        VStack(spacing: 0) {
            NotchHeaderView(model: model, metrics: metrics)

            Group {
                switch model.activePage {
                case .aiTracker:
                    NotchAIPageView()
                case .audioDeck:
                    NotchVinylDeckPageView(feed: feed)
                case .retroClock:
                    NotchRetroClockPageView()
                case .downloadDeck:
                    NotchDownloadsPageView(feed: feed)
                case .calendarFocus:
                    NotchProductivityPageView()
                case .hardwareHud:
                    NotchHardwareHudPageView()
                case .teleprompter:
                    NotchTeleprompterPageView()
                case .cameraMirror:
                    NotchMirrorPageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
            .transition(.opacity)
            .id(model.activePage)
        }
        // Inset by flaring top ear radius and horizontal grid padding
        .padding(.horizontal, NotchDesignSpec.openCornerRadii.topFlaring + NotchDesignSpec.gridPadding.leading)
        .padding(.bottom, NotchDesignSpec.gridPadding.bottom)
    }
}
