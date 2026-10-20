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
    /// 0...1 lift of the music glow; the controller sets 1 on a track change and eases it back (50d).
    @Published var glowBoost = 0.0
    @Published var tab: NotchTab = .home
    @Published var activePage: NotchPage = .downloadDeck
    /// Last paging direction (+1 forward, -1 back); drives the slide edge in `NotchHomeView`.
    @Published var pageDirection = 1
    var isExpanded: Bool { isOpen || event != nil }
    /// Shape sizes, set by the controller (closed width grows with the activity "sneak"). The window is
    /// as large as the larger of the two while a transition runs, so the shape animates inside it.
    @Published var closedSize = CGSize(width: NotchGeometry.fallbackNotchWidth, height: NotchGeometry.fallbackHeight)
    @Published var openSize = NotchGeometry.openSize
    /// Set by the controller: close the notch now (after an action such as opening Settings).
    var collapse: () -> Void = {}
    var openSettings: () -> Void = {}
    /// Set by the controller: open the notch now (the click-to-open mode).
    var requestOpen: () -> Void = {}

    func stepPage(forward: Bool) {
        pageDirection = forward ? 1 : -1
        let tp = UserDefaults.standard.bool(forKey: TeleprompterModel.enabledKey)
        let mirror = UserDefaults.standard.bool(forKey: CameraMirrorService.enabledKey)
        let notifications = UserDefaults.standard.bool(forKey: NotificationMirrorService.enabledKey)
        activePage = forward
            ? activePage.next(wrap: true, teleprompter: tp, mirror: mirror, notifications: notifications)
            : activePage.previous(wrap: true, teleprompter: tp, mirror: mirror, notifications: notifications)
    }

    /// Direct jumps (header icons, dots, context menu) animate toward the target page.
    func goToPage(_ page: NotchPage) {
        let tp = UserDefaults.standard.bool(forKey: TeleprompterModel.enabledKey)
        let mirror = UserDefaults.standard.bool(forKey: CameraMirrorService.enabledKey)
        let notifications = UserDefaults.standard.bool(forKey: NotificationMirrorService.enabledKey)
        pageDirection = NotchPageDirection.between(
            from: activePage, to: page,
            visible: NotchPage.visible(teleprompter: tp, mirror: mirror, notifications: notifications))
        activePage = page
    }
}

struct NotchIslandView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var feed = LiveActivityFeed.shared
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = false
    @AppStorage(NotificationMirrorService.enabledKey) private var notificationsPage = false
    @AppStorage(NotchPageLayout.defaultsKey) private var pageLayoutRaw = ""   // re-renders the page strip
    @AppStorage(NotchEdgeStyle.sharpKey) private var sharpEdges = false
    @AppStorage(NotchRestContent.defaultsKey) private var restContent = NotchRestContent.dockChips.rawValue
    @AppStorage(NotchOpenAnimation.defaultsKey) private var openAnimation = NotchOpenAnimation.boring.rawValue
    @AppStorage(NotchSizePreset.outlineKey) private var showOutline = false
    @AppStorage(NotchSizePreset.translucentKey) private var translucent = false
    @AppStorage(NotchMusicGlow.defaultsKey) private var glowStyle = NotchMusicGlow.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// `AppSettingsStore.Keys.themeMaterial`, which is file-private; the key itself is the contract.
    @AppStorage("com.katikati.theme.material") private var themeMaterialToken = DockThemeStyle.auto.token
    let metrics: NotchMetrics
    let theme: NowPlayingTheme
    /// 51h: external-display wide bar — the closed state shows `NotchWideBarView` instead of the ear chips.
    var wideBar = false

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

    private func openTransition(_ style: NotchOpenAnimation) -> AnyTransition {
        switch style.reveal {
        case .fade: return .opacity
        case .pour:
            return AnyTransition.modifier(active: LiquidBlur(amount: 8), identity: LiquidBlur(amount: 0))
                .combined(with: .scale(scale: 0.92, anchor: .top)).combined(with: .opacity)
        case .drop: return .opacity.combined(with: .offset(y: -6))
        case .pop: return .scale(scale: 0.85, anchor: .top).combined(with: .opacity)
        }
    }

    /// The closed chips only fade: blur or scale on a 32pt strip reads as a jump.
    private static let closedFade = AnyTransition.opacity

    var body: some View {
        let expanded = model.isExpanded
        let activity = feed.activity
        let boring = model.skin == .boring
        let edge = NotchEdgeStyle.mask(sharp: sharpEdges, expanded: expanded, hasHardwareNotch: metrics.hasHardwareNotch)
        let style = NotchOpenAnimation(rawValue: openAnimation) ?? .boring
        let spring = expanded ? style.openSpring : style.closeSpring
        let motion: Animation = reduceMotion
            ? .easeInOut(duration: NotchMotionSpec.reducedMotionDuration)
            : .spring(response: spring.response, dampingFraction: spring.dampingRatio)
        let size = expanded ? model.openSize : model.closedSize
        ZStack(alignment: .top) {
            NotchContinuousMaskShape(
                topCornerRadius: edge.top,
                bottomCornerRadius: edge.bottom,
                flaringTopEars: edge.flares
            )
            .fill(notchTheme.plate.color.opacity(translucent && expanded ? 0.82 : 1))
            if showOutline {
                NotchContinuousMaskShape(
                    topCornerRadius: edge.top,
                    bottomCornerRadius: edge.bottom,
                    flaringTopEars: edge.flares
                )
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            Group {
                if !expanded {
                    closedContent(activity).padding(.horizontal, 14).transition(Self.closedFade)
                } else if model.event == nil {
                    // Compact skin: the same pages, laid out at full size and scaled to the smaller panel.
                    let full = NotchGeometry.openSize
                    let scale = model.openSize.width / full.width
                    VStack(spacing: 0) {
                        NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
                            .transition(openTransition(style))
                        Spacer(minLength: 0)
                        pageIndicatorDots
                    }
                    .frame(width: full.width, height: full.height, alignment: .top)
                    .scaleEffect(scale, anchor: .top)
                    .frame(width: full.width * scale, height: full.height * scale, alignment: .top)
                } else {
                    openContent(activity).padding(.horizontal, 24).transition(openTransition(style))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { model.requestOpen() } }
        .contextMenu {
            Section {
                ForEach(NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage,
                                          notifications: notificationsPage)) { page in
                    Button {
                        withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                            model.goToPage(page)
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
        .animation(motion, value: expanded)
        .animation(motion, value: model.closedSize)
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
                        model.goToPage(page)
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
        if wideBar { return AnyView(NotchWideBarView(width: model.closedSize.width, height: model.closedSize.height)) }
        if activity.kind == .clock {
            return restContent == NotchRestContent.nothing.rawValue ? AnyView(Color.clear) : AnyView(NotchDockChips(metrics: metrics))
        }
        return AnyView(activityContent(activity))
    }

    private func activityContent(_ activity: LiveActivity) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let art = musicArtwork(for: activity) {
                    art.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                        .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                }
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
                    .minimumScaleFactor(0.5)
                    .truncationMode(.tail)
                    .frame(width: NotchGeometry.sneakSide - 8, alignment: .trailing)
            }
        }
        .frame(maxHeight: metrics.closedSize.height)
        .background(alignment: .trailing) { musicGlow(for: activity) }
    }

    /// 50d: the artwork colour glowing behind the right ear while music is the winning activity.
    @ViewBuilder
    private func musicGlow(for activity: LiveActivity) -> some View {
        if case .music = activity.content, let accent = ArtworkAccentCache.accent(for: feed.nowPlayingState.artworkData) {
            let style = NotchMusicGlow(rawValue: glowStyle) ?? .default
            let color = Color(red: accent.red, green: accent.green, blue: accent.blue)
            TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !style.isAnimated(reduceMotion: reduceMotion))) { context in
                let level = style.level(at: context.date.timeIntervalSinceReferenceDate, boost: model.glowBoost, reduceMotion: reduceMotion)
                Group {
                    if style == .edge {
                        Capsule().fill(color).frame(width: NotchGeometry.sneakSide - 12, height: 2)
                            .frame(maxHeight: .infinity, alignment: .bottom).padding(.trailing, 6)
                    } else {
                        Ellipse().fill(color).frame(width: NotchGeometry.sneakSide, height: metrics.closedSize.height * 0.9)
                            .blur(radius: 10)
                    }
                }
                .opacity(level)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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
                    if let art = musicArtwork(for: activity) {
                        art.resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                    }
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
                if case .music = activity.content {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let fraction = feed.nowPlayingState.progress(at: context.date) {
                            ProgressView(value: fraction).progressViewStyle(.linear).tint(.pink)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The playing app's own artwork, when the activity is music and the player handed one over.
    private func musicArtwork(for activity: LiveActivity) -> Image? {
        guard case .music = activity.content, let data = feed.nowPlayingState.artworkData, let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
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

private struct LiquidBlur: ViewModifier {
    let amount: CGFloat
    func body(content: Content) -> some View { content.blur(radius: amount) }
}
