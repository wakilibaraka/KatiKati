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
    /// Driven by `NotchPanelController`'s hover state machine (not by SwiftUI hover, which fed back into
    /// the window resize and made the notch flicker).
    @Published var isOpen = false
    @Published var event: LiveEventPresentation?
    @Published var skin: LiveIslandSkin = .boring
    @Published var tab: NotchTab = .home
    @Published var activePage: NotchPage = .aiTracker
    var isExpanded: Bool { isOpen || event != nil }
    /// Shape sizes, set by the controller (closed width grows with the activity "sneak"). The window is
    /// as large as the larger of the two while a transition runs, so the shape animates inside it.
    @Published var closedSize = CGSize(width: NotchGeometry.fallbackNotchWidth, height: NotchGeometry.fallbackHeight)
    @Published var openSize = NotchGeometry.openSize
    /// Set by the controller: close the notch now (after an action such as opening Settings).
    var collapse: () -> Void = {}
    var openSettings: () -> Void = {}

    func stepPage(forward: Bool) {
        let tp = UserDefaults.standard.bool(forKey: TeleprompterModel.enabledKey)
        let mirror = UserDefaults.standard.bool(forKey: CameraMirrorService.enabledKey)
        let notifications = UserDefaults.standard.bool(forKey: NotificationMirrorService.enabledKey)
        activePage = forward
            ? activePage.next(wrap: true, teleprompter: tp, mirror: mirror, notifications: notifications)
            : activePage.previous(wrap: true, teleprompter: tp, mirror: mirror, notifications: notifications)
    }
}

struct NotchIslandView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var feed = LiveActivityFeed.shared
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notificationsPage = false
    @AppStorage(NotchEdgeStyle.sharpKey) private var sharpEdges = false
    /// `AppSettingsStore.Keys.themeMaterial`, which is file-private; the key itself is the contract.
    @AppStorage("com.katikati.theme.material") private var themeMaterialToken = DockThemeStyle.auto.token
    let metrics: NotchMetrics
    let theme: NowPlayingTheme

    /// Phase 12: the plate and content scheme, decided in `NotchTheme` (Core, tested). The island is a
    /// dark surface by design — this view pins `.colorScheme(.dark)` below — so the dark column is the
    /// one resolved.
    private var notchTheme: NotchTheme.Resolution {
        let style = DockThemeStyle(token: themeMaterialToken) ?? .auto
        return NotchTheme.resolve(
            hasHardwareNotch: metrics.hasHardwareNotch,
            tintsPlate: style.tintsPlate,
            tokens: DockThemeStyleTokens.resolve(style: style, appearance: .dark)
        )
    }

    var body: some View {
        let expanded = model.isExpanded
        let activity = feed.activity
        let boring = model.skin == .boring
        let edge = NotchEdgeStyle.mask(sharp: sharpEdges, expanded: expanded, hasHardwareNotch: metrics.hasHardwareNotch)
        let spring = expanded ? NotchMotionSpec.openSpring : NotchMotionSpec.closeSpring
        let size = expanded ? model.openSize : model.closedSize
        ZStack(alignment: .top) {
            NotchContinuousMaskShape(
                topCornerRadius: edge.top,
                bottomCornerRadius: edge.bottom,
                flaringTopEars: edge.flares
            )
            .fill(notchTheme.plate.color)
            if expanded { NotchSiriRim(top: edge.top, bottom: edge.bottom, flares: edge.flares).transition(.opacity) }
            Group {
                if !expanded {
                    closedContent(activity).padding(.horizontal, 14)
                } else if boring && model.event == nil {
                    VStack(spacing: 0) {
                        NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
                            .transition(.opacity)
                        Spacer(minLength: 0)
                        pageIndicatorDots
                    }
                } else {
                    openContent(activity).padding(.horizontal, 24)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .contextMenu {
            Section {
                ForEach(NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage,
                                          notifications: notificationsPage)) { page in
                    Button {
                        withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                            model.activePage = page
                        }
                    } label: {
                        HStack {
                            Text(page.title)
                            if model.activePage == page {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Divider()
            Button {
                model.collapse()
            } label: {
                Text(verbatim: "Collapse Notch")
            }
            Button {
                model.openSettings()
            } label: {
                Text(verbatim: "KatiKati Settings…")
            }
        }
        .animation(.spring(response: spring.response, dampingFraction: spring.dampingRatio), value: expanded)
        .animation(.spring(response: spring.response, dampingFraction: spring.dampingRatio), value: model.closedSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .colorScheme(notchTheme.prefersDarkContent ? .light : .dark)
    }

    private var pageIndicatorDots: some View {
        HStack(spacing: 6) {
            ForEach(NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage,
                                          notifications: notificationsPage)) { page in
                // A Button, not a capsule with a tap gesture: the gesture shape never surfaced as an
                // accessibility element, so VoiceOver saw nine nameless dots (live-checked 2026-10-17).
                Button {
                    withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                        model.activePage = page
                    }
                } label: {
                    Capsule()
                        .fill(model.activePage == page ? Color.white.opacity(0.9) : Color.white.opacity(0.25))
                        .frame(width: model.activePage == page ? 18 : 6, height: 4)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle().inset(by: -4))
                .accessibilityLabel(Text(page.title))
                .help(Text(page.title))
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: Closed — glyph left of the notch, value right of it

    private func closedContent(_ activity: LiveActivity) -> some View {
        if activity.kind == .clock { return AnyView(NotchDockChips(metrics: metrics)) }
        return AnyView(activityContent(activity))
    }

    private func activityContent(_ activity: LiveActivity) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                    .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                if let second = feed.secondaryActivity {
                    Image(systemName: LiveIslandStyle.symbolName(for: second.kind))
                        .foregroundStyle(LiveIslandStyle.tint(for: second.kind))
                }
            }
            .font(.system(size: 12, weight: .semibold))
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
                NotchEventCard(event: event, lifetime: NotchMotionSpec.eventLifetime) { model.event = nil }
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
                .accessibilityLabel(Text("Back"))
            Button { feed.togglePlayPause() } label: { Image(systemName: feed.nowPlayingState.isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(feed.nowPlayingState.isPlaying ? Text("Pause") : Text("Play"))
            Button { feed.nextTrack() } label: { Image(systemName: "forward.fill") }
                .accessibilityLabel(Text("Forward"))
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(.white)
    }
}
