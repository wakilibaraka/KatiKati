import SwiftUI
import UniformTypeIdentifiers

// Phase 8b-7 — the notch skin of the Live Island.
//
// Same data as the dock capsule (`LiveActivityFeed.shared`, `LiveActivityPolicy` winner, shared
// `LiveIslandStyle` glyphs/words) drawn inside boring.notch's vendored `NotchShape`. Closed: the black
// notch, growing a little on each side to show the live activity (only when something other than the
// clock is winning). Open (hover) or showing an event: a larger panel with the activity, music
// transport/progress, or the event headline. The window itself is sized by `NotchPanelController`; this
// view just fills it.

extension NotchOpenAnimation {
    var contentTransition: AnyTransition {
        switch self {
        case .boring:
            // Boring Notch's content transition at b7611bb, paired with its separate shell springs.
            return .scale(scale: 0.8, anchor: .top)
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.35))
        case .liquid:
            return .scale(scale: 0.94, anchor: .top).combined(with: .opacity)
        case .snap:
            return .opacity
        case .bounce:
            return .scale(scale: 0.92, anchor: .top).combined(with: .opacity)
        }
    }
}

@MainActor
final class NotchModel: ObservableObject {
    /// Driven by `NotchPanelController`'s hover state machine (not by SwiftUI hover, which fed back into
    /// the window resize and made the notch flicker).
    @Published var isOpen = false
    @Published var event: LiveEventPresentation?
    @Published var skin: LiveIslandSkin = .boring
    @Published var islandBridge: IslandLiveBridge?
    /// 0...1 lift of the music glow; the controller sets 1 on a track change and eases it back (50d).
    @Published var glowBoost = 0.0
    @Published var activePage: NotchPage = .home
    /// Last paging direction (+1 forward, -1 back); drives the slide edge in `NotchHomeView`.
    @Published var pageDirection = 1
    /// Slice DN-1/DN-2: Priority-ordered queue for transient hardware HUDs and live activities.
    @Published var activityQueue = NotchActivityQueue(maxItems: 8)
    @Published var isDropTargeted = false
    weak var shelfStore: ShelfStore?
    var activeHUDItem: NotchActivityItem? { activityQueue.items.first { $0.level != nil } }
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
    var requestShelf: () -> Void = {}
    var stageDraggedItems: () -> Bool = { false }

    func stepPage(forward: Bool) {
        pageDirection = forward ? 1 : -1
        let tp = NotchPage.isEnabled(TeleprompterModel.enabledKey)
        let mirror = NotchPage.isEnabled(CameraMirrorService.enabledKey)
        activePage = forward
            ? activePage.navigationPage.next(wrap: true, teleprompter: tp, mirror: mirror)
            : activePage.navigationPage.previous(wrap: true, teleprompter: tp, mirror: mirror)
    }

    /// Direct jumps (header icons, dots, context menu) animate toward the target page.
    func goToPage(_ page: NotchPage) {
        let tp = NotchPage.isEnabled(TeleprompterModel.enabledKey)
        let mirror = NotchPage.isEnabled(CameraMirrorService.enabledKey)
        pageDirection = NotchPageDirection.between(
            from: activePage.navigationPage, to: page.navigationPage,
            visible: NotchPage.visible(teleprompter: tp, mirror: mirror))
        activePage = page
    }
}

struct NotchIslandView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject private var feed = LiveActivityFeed.shared
    @AppStorage(TeleprompterModel.enabledKey) private var teleprompterPage = false
    @AppStorage(CameraMirrorService.enabledKey) private var cameraMirrorPage = true
    @AppStorage(NotchPageLayout.defaultsKey) private var pageLayoutRaw = ""   // re-renders the page pill's roster
    @AppStorage(NotchEdgeStyle.sharpKey) private var sharpEdges = false
    @AppStorage(NotchRestContent.defaultsKey) private var restContent = NotchRestContent.timeBattery.rawValue
    @AppStorage(NotchBehavior.musicBatteryKey) private var musicBattery = true
    @AppStorage(NotchOpenAnimation.defaultsKey) private var openAnimation = NotchOpenAnimation.boring.rawValue
    @AppStorage(NotchSizePreset.outlineKey) private var showOutline = false
    @AppStorage(NotchSizePreset.translucentKey) private var translucent = false
    @AppStorage(NotchHUDPresentation.showPercentageKey) private var showHUDPercentage = true
    @AppStorage(NotchMusicGlow.defaultsKey) private var glowStyle = NotchMusicGlow.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// NS-2: the stored plate look, read straight from defaults so Settings repaints the notch live.
    @AppStorage(NotchSurfaceAppearance.StorageKey.preset) private var surfacePresetRaw = NotchColorPreset.oledBlack.rawValue
    @AppStorage(NotchSurfaceAppearance.StorageKey.customHex) private var surfaceCustomHex = NotchSurfaceAppearance.defaultCustomHex
    @AppStorage(NotchSurfaceAppearance.StorageKey.transparency) private var surfaceTransparency = NotchSurfaceAppearance.defaultTransparency
    let metrics: NotchMetrics
    let theme: NowPlayingTheme
    /// 51h: external-display wide bar — the closed state shows `NotchWideBarView` instead of the ear chips.
    var wideBar = false

    /// NS-1/NS-2: the plate actually drawn this frame. Low Power Mode and the clamp live in the pure
    /// model; this view only reads the three stored values.
    private var surfaceAppearance: NotchSurfaceAppearance {
        NotchSurfaceAppearance(
            preset: NotchColorPreset(rawValue: surfacePresetRaw) ?? .oledBlack,
            customHex: surfaceCustomHex,
            transparency: surfaceTransparency
        )
    }

    private var detectedMeetingPlatform: MeetingCallPlatform? {
        feed.detectedMeetingPlatform
    }

    /// The closed chips only fade: blur or scale on a 32pt strip reads as a jump.
    private static let closedFade = AnyTransition.opacity

    /// The scheme the notch's own content is drawn in.
    ///
    /// Not the app's appearance: the notch paints its plate itself, and every stored preset is black
    /// or near-black (`NotchColorPreset.baseHex`), as is the liquid skin — so in Light appearance
    /// `.primary`/`.secondary` inside the open panel resolved to black on black (`NotchMusicPanel`,
    /// `NotchMeetingControlBar`, `NotchAIPageView`). The plate decides, with the same luminance test
    /// used elsewhere for artwork: only a pale custom plate flips the content back to dark ink.
    private var plateContentScheme: ColorScheme {
        guard model.skin != .liquid else { return .dark }
        let plate = surfaceAppearance.effectiveAppearance(
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled).baseColor
        let luminance = 0.2126 * plate.r + 0.7152 * plate.g + 0.0722 * plate.b
        return luminance > 0.55 ? .light : .dark
    }

    var body: some View {
        notchContent
            .environment(\.colorScheme, plateContentScheme)
            .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $model.isDropTargeted) { _ in
                model.stageDraggedItems()
            }
            .onChange(of: model.isDropTargeted) { _, targeted in
                let autoOpen = UserDefaults.standard.object(forKey: ShelfPolicy.notchAutoOpenOnDragKey) as? Bool ?? true
                if targeted, autoOpen { model.requestShelf() }
            }
    }

    @ViewBuilder
    private var notchContent: some View {
        if let bridge = model.islandBridge {
            let resolution = NotchTheme.resolve(
                hasHardwareNotch: metrics.hasHardwareNotch,
                tintsPlate: !metrics.hasHardwareNotch,
                tokens: DockThemeStyleTokens.resolve(style: .obsidianDark, appearance: .dark)
            )
            Color.clear.overlay(alignment: .top) {
                IslandSurfaceView(driver: bridge.driver, registry: bridge.registry, themeResolution: resolution) {
                    bentoSuiteView
                }
            }
        } else {
            legacyNotchBody
        }
    }

    @ViewBuilder
    private var bentoSuiteView: some View {
        let full = NotchGeometry.openSize
        let targetWidth = max(model.openSize.width, 320)
        let scale = model.skin == .classic ? (targetWidth / full.width) : 1.0
        if scale < 0.99 {
            NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
                .frame(width: full.width, height: full.height, alignment: .top)
                .scaleEffect(scale, anchor: .top)
                .frame(width: full.width * scale, height: full.height * scale, alignment: .top)
        } else {
            NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var legacyNotchBody: some View {
        let expanded = model.isExpanded
        let activity = feed.activity
        let style = NotchOpenAnimation(rawValue: openAnimation) ?? .boring
        let calculatedLayout = NotchGeometryCalculator.calculate(
            screenBounds: CGRect(origin: .zero, size: model.openSize),
            topInset: metrics.hasHardwareNotch ? metrics.closedSize.height : 0,
            menuBarHeight: metrics.closedSize.height,
            closedSize: model.closedSize,
            openSize: model.openSize,
            isExpanded: expanded,
            sharpEdges: sharpEdges
        )
        // boring.notch physics: open spring (0.42 / 0.80) for organic expansion,
        // close spring (0.45 / 1.0) for critically-damped snap back into bezel.
        let spring = expanded ? style.openSpring : style.closeSpring
        let motion: Animation = reduceMotion
            ? .easeInOut(duration: NotchMotionSpec.reducedMotionDuration)
            : .spring(response: spring.response, dampingFraction: spring.dampingRatio, blendDuration: 0)
        let size = expanded ? model.openSize : model.closedSize
        let reveal = reduceMotion ? AnyTransition.opacity : style.contentTransition
        let surface = surfaceAppearance.effectiveAppearance(
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
        let maskShape = NotchContinuousMaskShape(
            topCornerRadius: calculatedLayout.topCornerRadius,
            bottomCornerRadius: calculatedLayout.bottomCornerRadius,
            flaringTopEars: calculatedLayout.flaringTopEars,
            usesBoringOutline: model.skin == .boring
        )
        ZStack(alignment: .top) {
            // NS-2: vibrancy exists only while the plate is genuinely see-through. The default opaque
            // OLED black therefore spends no blur pass and has nothing to leak the desktop through.
            if surface.shouldRenderBlurMaterial {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .mask(maskShape)
            }
            maskShape
                .fill(surface.baseColor.color.opacity(surface.baseOpacity))
            // The 1 pt milled edge: the preset's own rim, subtle enough to read as hardware glass.
            maskShape
                .stroke(surface.rimColor.color.opacity(surface.rimOpacity), lineWidth: 1)
            if showOutline {
                maskShape.stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            Group {
                if !expanded {
                    closedContent(activity).padding(.horizontal, 14).transition(Self.closedFade)
                } else if model.event == nil {
                    // Compact skin: the same pages, laid out at full size and scaled to the smaller panel.
                    // NP-2: no dot strip under the page — the header's page pill is the only roster control,
                    // so the cards keep the height the dots used to take.
                    let full = NotchGeometry.openSize
                    let scale = model.openSize.width / full.width
                    NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
                        .frame(width: full.width, height: full.height, alignment: .top)
                        .scaleEffect(scale, anchor: .top)
                        .frame(width: full.width * scale, height: full.height * scale, alignment: .top)
                        .transition(reveal)
                } else {
                    openContent(activity).padding(.horizontal, 24).transition(reveal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(maskShape)
        .contentShape(Rectangle())
        .onTapGesture { if !expanded { model.requestOpen() } }
        .contextMenu {
            Section {
                ForEach(NotchPage.visible(teleprompter: teleprompterPage, mirror: cameraMirrorPage)) { page in
                    Button {
                        withAnimation(.spring(response: NotchMotionSpec.pageStepSpring.response, dampingFraction: NotchMotionSpec.pageStepSpring.dampingRatio)) {
                            model.goToPage(page)
                        }
                    } label: {
                        HStack {
                            Text(page.title)
                            if model.activePage.navigationPage == page {
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
        .shadow(
            color: metrics.hasHardwareNotch ? .clear : Color.black.opacity(0.32),
            radius: metrics.hasHardwareNotch ? 0 : 10,
            x: 0,
            y: metrics.hasHardwareNotch ? 0 : 4
        )
        .animation(motion, value: expanded)
        .animation(motion, value: model.closedSize)
        .animation(motion, value: model.activeHUDItem?.id)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .colorScheme(.dark)
    }

    // MARK: Closed — glyph left of the notch, value right of it

    private func closedContent(_ activity: LiveActivity) -> some View {
        if let hud = model.activeHUDItem {
            return AnyView(inlineHUDContent(hud))
        }
        if wideBar { return AnyView(NotchWideBarView(width: model.closedSize.width, height: model.closedSize.height)) }
        if let platform = detectedMeetingPlatform {
            return AnyView(
                HStack(spacing: 4) {
                    Image(systemName: platform.sfSymbol)
                        .foregroundColor(.green)
                        .font(.system(size: 11, weight: .bold))
                    Text(verbatim: platform.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "waveform")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                }
            )
        }
        if activity.kind == .clock {
            return restContent == NotchRestContent.nothing.rawValue ? AnyView(Color.clear) : AnyView(NotchDockChips(metrics: metrics))
        }
        return AnyView(activityContent(activity))
    }

    @ViewBuilder
    private func inlineHUDContent(_ hud: NotchActivityItem) -> some View {
        if hud.id.hasPrefix("clipboard|") || hud.icon == "doc.on.clipboard" || hud.icon == "doc.on.clipboard.fill" {
            clipboardToastContent(hud)
        } else {
            let level = hud.level ?? 0
            let tint: Color = hud.id == "hud.brightness" ? .yellow : (hud.id == "hud.keyboard" ? .orange : (level <= 0 ? .secondary : .cyan))
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: hud.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    if !metrics.hasHardwareNotch {
                        Text(verbatim: hud.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                }
                .frame(width: metrics.hasHardwareNotch ? NotchGeometry.sneakSide - 14 : nil, alignment: .leading)

                Spacer(minLength: metrics.hasHardwareNotch ? max(0, metrics.closedSize.width - 8) : 8)

                HStack(spacing: 5) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.18))
                            Capsule().fill(tint)
                                .frame(width: max(4, proxy.size.width * level))
                        }
                    }
                    .frame(width: 28, height: 4)
                    if showHUDPercentage {
                        Text(level, format: .percent.precision(.fractionLength(0)))
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    }
                }
                .frame(width: NotchGeometry.sneakSide - 6, alignment: .trailing)
            }
            .frame(maxHeight: metrics.closedSize.height)
        }
    }

    private func clipboardToastContent(_ hud: NotchActivityItem) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                if let appIcon = NSWorkspace.shared.frontmostApplication?.icon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 15, height: 15)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                } else {
                    Image(systemName: hud.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: hud.title)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                    if let glimpse = hud.subtitle, !glimpse.isEmpty {
                        Text(verbatim: glimpse)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
            }
            .frame(width: metrics.hasHardwareNotch ? NotchGeometry.sneakSide - 10 : nil, alignment: .leading)

            Spacer(minLength: metrics.hasHardwareNotch ? max(0, metrics.closedSize.width - 8) : 8)

            if let latest = ProductivityServices.shared.clipboard.history.displayOrder.first {
                Button {
                    ProductivityServices.shared.clipboard.pastePlain(latest)
                } label: {
                    Text("Paste Plain")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .frame(width: NotchGeometry.sneakSide - 8, alignment: .trailing)
            }
        }
        .frame(maxHeight: metrics.closedSize.height)
    }

    private func activityContent(_ activity: LiveActivity) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                if let art = musicArtwork(for: activity) {
                    art.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    MusicEqualizerBars(isActive: feed.nowPlayingState.isPlaying, tint: .white.opacity(0.85))
                        .frame(width: 16, height: 12)
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
            if case .music = activity.content {
                if musicBattery {
                    NotchLiveBattery().frame(width: NotchGeometry.sneakSide - 14, alignment: .trailing)   // battery stays put while music plays unless user opts out
                } else {
                    Color.clear.frame(width: NotchGeometry.sneakSide - 14)
                }
            } else if let value = LiveIslandStyle.valueText(for: activity) {
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
        .background(alignment: .leading) { musicGlow(for: activity) }
    }

    /// 50d: the artwork colour glowing behind the artwork on the left ear while music is the winning activity.
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
                            .frame(maxHeight: .infinity, alignment: .bottom).padding(.leading, 6)
                    } else {
                        Ellipse().fill(color).frame(width: 40, height: metrics.closedSize.height * 0.9)
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
            if let platform = detectedMeetingPlatform {
                NotchMeetingControlBar(call: MeetingCallState(platform: platform))
            }
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
            Button { feed.previousTrack() } label: { Image(systemName: "backward.end.fill") }
                .accessibilityLabel(Text("Back"))
            Button { feed.togglePlayPause() } label: { Image(systemName: feed.nowPlayingState.isPlaying ? "pause.fill" : "play.fill") }
                .accessibilityLabel(feed.nowPlayingState.isPlaying ? Text("Pause") : Text("Play"))
            Button { feed.nextTrack() } label: { Image(systemName: "forward.end.fill") }
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
