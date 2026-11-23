import AppKit
import SwiftUI

/// Open state of the full notch skin: header row on top, flanked by the configurable Notch Page Roster,
/// then the active Bento Page (AI, Music, Calendar, Storage, Downloads, Teleprompter, Camera Check-in,
/// Studio Hub, Keep Awake). The page slide follows the paging direction;
/// reduced-motion falls back to a plain fade.
struct NotchHomeView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    let calendarEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let forward = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity))
    static let backward = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity))

    var body: some View {
        VStack(spacing: 0) {
            // 59d: the battery card hangs out of the header, so the header must draw above the page.
            NotchHeaderView(model: model, metrics: metrics)
                .zIndex(1)

            Group {
                switch model.activePage {
                case .aiTracker:
                    NotchAIPageView()
                case .audioDeck:
                    NotchMusicPageView(feed: feed)
                case .calendar:
                    NotchProductivityPageView(feed: feed)
                case .peripherals:
                    EmptyView()
                case .storage:
                    NotchStoragePageView()
                case .downloadDeck:
                    NotchDownloadsPageView(feed: feed)
                case .teleprompter:
                    NotchTeleprompterPageView()
                case .cameraMirror:
                    NotchMirrorPageView()
                case .studioHub:
                    NotchToolsView()
                case .keepAwake:
                    NotchKeepAwakePageView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 4)
            .transition(reduceMotion ? .opacity : (model.pageDirection >= 0 ? Self.forward : Self.backward))
            .id(model.activePage)
        }
        // Inset by flaring top ear radius and horizontal grid padding
        .padding(.horizontal, NotchDesignSpec.openCornerRadii.topFlaring + NotchDesignSpec.gridPadding.leading)
        .padding(.bottom, NotchDesignSpec.gridPadding.bottom)
    }
}

/// NP-2: the open notch's one card. Every page wears the same 0.10 white fill, 1 pt 0.08 rim and 18 pt
/// continuous radius, so no page can invent its own tint, border or radius. 0.10 is deliberate: 0.06 let
/// desktop text read through the cards (live-checked 2026-10-17).
struct NotchCardSurface: ViewModifier {
    var fillOpacity: Double = NotchDesignSpec.cardFillOpacity
    var strokeOpacity: Double = NotchDesignSpec.cardStrokeOpacity

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
        return content
            .background(
                shape.fill(Color.white.opacity(fillOpacity))
                    .overlay(shape.strokeBorder(Color.white.opacity(strokeOpacity),
                                                lineWidth: NotchDesignSpec.cardStrokeWidth))
            )
    }
}

extension View {
    /// The one card surface every notch page draws.
    func notchCard() -> some View { modifier(NotchCardSurface()) }
}
