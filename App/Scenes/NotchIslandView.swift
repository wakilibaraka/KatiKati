import SwiftUI

// Phase 8b-7 — the notch skin of the Live Island.
//
// Same data as the dock capsule (`LiveActivityFeed.shared`, `LiveActivityPolicy` winner, shared
// `LiveIslandStyle` glyphs/words) drawn inside boring.notch's vendored `NotchShape`. Closed: the black
// notch, growing a little on each side to show the live activity (only when something other than the
// clock is winning). Open (hover) or showing an event: a larger panel with the activity, music
// transport/progress, or the event headline. The window itself is sized by `NotchPanelController`; this
// view just fills it.

@MainActor
final class NotchModel: ObservableObject {
    @Published var isHovering = false
    @Published var event: LiveEventPresentation?
    var isExpanded: Bool { isHovering || event != nil }
}

struct NotchIslandView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var feed = LiveActivityFeed.shared
    let metrics: NotchMetrics
    let theme: NowPlayingTheme

    var body: some View {
        let expanded = model.isExpanded
        let activity = feed.activity
        ZStack(alignment: .top) {
            NotchShape(topCornerRadius: expanded ? 19 : 6, bottomCornerRadius: expanded ? 24 : 14)
                .fill(Color.black)
            Group {
                if expanded { openContent(activity) } else { closedContent(activity) }
            }
            .padding(.horizontal, expanded ? 24 : 14)
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeInOut(duration: 0.2)) { model.isHovering = hovering } }
        .animation(.easeInOut(duration: 0.2), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .colorScheme(.dark)
    }

    // MARK: Closed — glyph left of the notch, value right of it

    private func closedContent(_ activity: LiveActivity) -> some View {
        HStack(spacing: 0) {
            Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                .frame(width: NotchGeometry.sneakSide - 14, alignment: .leading)
            Spacer(minLength: metrics.closedSize.width - 8)
            if let value = LiveIslandStyle.valueText(for: activity) {
                value
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: NotchGeometry.sneakSide - 14, alignment: .trailing)
            }
        }
        .frame(maxHeight: metrics.closedSize.height)
    }

    // MARK: Open — event headline, or the activity with its controls

    @ViewBuilder
    private func openContent(_ activity: LiveActivity) -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: metrics.closedSize.height - 6)
            if let event = model.event {
                HStack(spacing: 10) {
                    Image(systemName: event.symbol).font(.system(size: 18, weight: .semibold))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: event.headline).font(.system(size: 14, weight: .semibold))
                        if let detail = event.detail, !detail.isEmpty {
                            Text(verbatim: detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    Spacer()
                }
                .foregroundStyle(.white)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                    VStack(alignment: .leading, spacing: 1) {
                        LiveIslandStyle.labelText(for: activity.kind)
                            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        if let value = LiveIslandStyle.valueText(for: activity) {
                            value.font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        }
                    }
                    Spacer()
                    if case .music = activity.content { transport }
                }
                if case .music = activity.content, let fraction = feed.nowPlayingState.progress(at: Date()) {
                    ProgressView(value: fraction).progressViewStyle(.linear).tint(.pink)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var transport: some View {
        HStack(spacing: 16) {
            Button { feed.previousTrack() } label: { Image(systemName: "backward.fill") }
            Button { feed.togglePlayPause() } label: { Image(systemName: feed.nowPlayingState.isPlaying ? "pause.fill" : "play.fill") }
            Button { feed.nextTrack() } label: { Image(systemName: "forward.fill") }
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(.white)
    }
}
