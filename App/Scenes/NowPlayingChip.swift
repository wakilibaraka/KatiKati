import Foundation
import SwiftUI

// Phase 8b-3 — the island's `.media` slot is now the **Live Island** capsule.
//
// Instead of a static play/pause dot, the slot renders whatever `LiveActivityPolicy` resolves as the
// winner — music / focus / event countdown / countdown timer / stopwatch / live clock — and
// re-renders on `LiveActivityFeed`'s 1 Hz tick, so the clock advances, focus/timer remaining counts
// down and the stopwatch climbs while the island is on screen. As the winner changes, the glyph,
// label and value morph in place (`.animation(value: activity.kind)`).
//
// Naming: the type keeps its original `NowPlayingChip` name and its `App/Scenes/NowPlayingChip.swift`
// home so the `.media` call site (`DockStripView`), the project file, and the section's settings
// label / hover title stay untouched — a deliberately minimal diff. The *surface* it draws is the
// Live Island.
//
// Layout: the `.media` slot is a fixed `targetWidth × 36pt` frame with `.clipped()` in
// `DockStripView`, so the capsule morphs strictly **inside** that box and can never overflow the
// island; `ViewThatFits` drops the kind label, then lets the value truncate, as the width slider
// narrows (the same technique `ClockChip`/`WeatherChip` use).
//
// Strings: the six kind labels are whole literals ("Now Playing"/"Focus"/"Countdown"/"Timer"/
// "Stopwatch"/"Clock") that already exist in the catalog and are referenced elsewhere, so this slice
// adds no catalog entry and orphans none. Kinetic numbers are *data*, so they go through
// `Text(verbatim:)` via the pure `LiveIslandFormat` — never an interpolated `Text` literal, which the
// localization gate would read as a missing key.
//
// Interaction (this slice): while a track is winning, tapping opens the existing music popup (theme /
// album art / transport — unchanged, which keeps the "Now Playing Theme" setting live). Every other
// kind is display-only here; its controls live in its own surface.

/// The `.media` slot. Honours the Live Island's per-surface switch (8b-5): with the dock island off
/// the slot renders nothing and holds no tick, so the notch can run alone.
public struct NowPlayingChip: View {
    @EnvironmentObject var settingsStore: AppSettingsStore
    @AppStorage("com.katikati.media.preset") private var mediaPreset: NowPlayingPreset = .expandedCard

    public init() {}

    public var body: some View {
        if settingsStore.dockIslandEnabled {
            if mediaPreset == .expandedCard {
                ExpandedMediaCardView()
            } else {
                LiveIslandDockCapsule()
            }
        }
    }
}

/// The dock-side renderer. Reads the shared app-wide feed and holds it only while on screen.
struct LiveIslandDockCapsule: View {
    @ObservedObject private var feed = LiveActivityFeed.shared
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var isHovering = false
    @State private var showPopup = false
    @Environment(\.widgetSize) private var widgetSize
    /// Phase 18 (owner 2026-10-13): on a side rail the chip has its own vertical layout instead of the
    /// bottom pill scaled down — idle actions stacked, an activity as ring over value.
    @Environment(\.liveIslandVertical) private var isVertical
    @EnvironmentObject var runtime: AppRuntime
    @State private var keepAwakeOn = false
    
    var body: some View {
        let activity = feed.activity

        Group {
            if isVertical {
                if LiveIdleAction.showsIdleActions(for: activity.kind) {
                    idleActions(vertical: true)
                } else {
                    verticalCapsule(activity)
                }
            } else if LiveIdleAction.showsIdleActions(for: activity.kind) {
                idleActions(vertical: false)
            } else if widgetSize == .small {
                capsule(activity, showsLabel: false)
            } else if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    capsule(activity, showsLabel: true)
                    capsule(activity, showsLabel: false)
                }
            } else {
                capsule(activity, showsLabel: false)
            }
        }
        .padding(isVertical ? .vertical : .horizontal, isVertical ? 6 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(isHovering ? 0.12 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { tap(for: activity) }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .help(helpText(for: activity))
        .animation(.easeInOut(duration: 0.18), value: activity.kind)
        .popover(isPresented: $showPopup, arrowEdge: .top) {
            NowPlayingPopup(
                state: feed.nowPlayingState,
                theme: settingsStore.nowPlayingTheme,
                onToggle: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onPrevious: { feed.previousTrack() }
            )
        }
    }

    // MARK: - Capsule content

    /// `[glyph] [label] [value]`; the label drops first as the slot narrows, then the value truncates
    /// (`ViewThatFits` + `minimumScaleFactor`), so the glyph never leaves the capsule.
    private func capsule(_ activity: LiveActivity, showsLabel: Bool) -> some View {
        HStack(spacing: 5) {
            glyph(for: activity)
            if showsLabel {
                labelText(for: activity.kind)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            if let value = valueText(for: activity) {
                value
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .layoutPriority(1)
            }
        }
    }

    /// Idle state (10c-1): no clock — the time capsule already shows the time. Three one-tap quick actions
    /// that match the notch's Focus / Timer / Keep Awake.
    private func idleActions(vertical: Bool) -> some View {
        let buttons = ForEach(LiveIdleAction.allCases, id: \.self) { action in
            Button { perform(action) } label: {
                Image(systemName: action == .keepAwake && keepAwakeOn ? "cup.and.saucer.fill" : action.symbolName)
                    .font(.system(size: vertical ? 15 : 13, weight: .semibold))
                    .foregroundStyle(idleTint(action))
                    .frame(width: vertical ? 30 : 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(idleTitle(action))
            .accessibilityLabel(idleTitle(action))
        }
        return Group {
            if vertical {
                VStack(spacing: 2) { buttons }
            } else {
                HStack(spacing: 4) { buttons }
            }
        }
        .onAppear { keepAwakeOn = runtime.isKeepAwakeOn?() ?? false }
    }

    /// Rail form of an active activity: the ring glyph, larger, over its short value ("4:58", "Live").
    private func verticalCapsule(_ activity: LiveActivity) -> some View {
        VStack(spacing: 4) {
            glyph(for: activity)
                .scaleEffect(1.3)
                .frame(width: 30, height: 30)
            if let value = valueText(for: activity) {
                value
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private func idleTitle(_ action: LiveIdleAction) -> String {
        switch action {
        case .focus: return String(localized: "Focus")
        case .timer: return String(localized: "Timer")
        case .keepAwake: return String(localized: "Keep Awake")
        }
    }

    private func idleTint(_ action: LiveIdleAction) -> Color {
        switch action {
        case .focus: return .orange
        case .timer: return .teal
        case .keepAwake: return keepAwakeOn ? .green : .secondary
        }
    }

    private func perform(_ action: LiveIdleAction) {
        let services = ProductivityServices.shared
        switch action {
        case .focus: services.focus.toggle()
        case .timer:
            services.timer.set(seconds: LiveIdleAction.quickTimerSeconds)
            services.timer.toggle()
        case .keepAwake: keepAwakeOn = runtime.onToggleKeepAwake?() ?? keepAwakeOn
        }
    }

    private func glyph(for activity: LiveActivity) -> some View {
        ZStack {
            if let progress = activity.ringProgress {
                Circle().stroke(tint(for: activity.kind).opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint(for: activity.kind), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbolName(for: activity.kind))
                .font(.system(size: activity.ringProgress == nil ? 13 : 10, weight: .semibold))
                .foregroundStyle(tint(for: activity.kind))
        }
        .frame(width: activity.ringProgress == nil ? 16 : 22, height: 22)
        .accessibilityHidden(true)
    }

    // MARK: - Kind mapping (shared with the notch surface via `LiveIslandStyle`)

    private func symbolName(for kind: LiveActivityKind) -> String { LiveIslandStyle.symbolName(for: kind) }
    private func tint(for kind: LiveActivityKind) -> Color { LiveIslandStyle.tint(for: kind) }
    private func labelText(for kind: LiveActivityKind) -> Text { LiveIslandStyle.labelText(for: kind) }
    private func labelString(for kind: LiveActivityKind) -> String { LiveIslandStyle.labelString(for: kind) }
    private func valueText(for activity: LiveActivity) -> Text? { LiveIslandStyle.valueText(for: activity) }
    private func valueString(for activity: LiveActivity) -> String? { LiveIslandStyle.valueString(for: activity) }

    // MARK: - Interaction

    /// The one affordance this slice ships: while a track is winning, tapping opens the music popup
    /// (theme / album art / transport — unchanged from the pre-8b chip). Every other kind is
    /// display-only; its controls live in its own surface.
    private func tap(for activity: LiveActivity) {
        if case .music = activity.content { showPopup.toggle() }
    }

    private func helpText(for activity: LiveActivity) -> String {
        let label = labelString(for: activity.kind)
        guard let value = valueString(for: activity), !value.isEmpty else { return label }
        return "\(label) — \(value)"
    }
}

struct NowPlayingPopup: View {
    let state: NowPlayingState
    let theme: NowPlayingTheme
    let onToggle: () -> Void
    var onNext: () -> Void = {}
    var onPrevious: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    
    private var isDarkMode: Bool {
        switch theme {
        case .light: return false
        case .dark: return true
        case .auto: return colorScheme == .dark
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Album art when MediaRemote provides it (8b-6), otherwise the turntable.
            ZStack {
                if let data = state.artworkData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.1))
                    TurntableView(isPlaying: state.isPlaying)
                        .padding(2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(width: 56, height: 56)
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.title ?? "Not Playing")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDarkMode ? .white : .black)
                            .lineLimit(1)
                        Text(state.artist ?? "Unknown Artist")
                            .font(.system(size: 12))
                            .foregroundColor(isDarkMode ? .gray : .secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    // AirPlay Icon
                    Button(action: {}) {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 12))
                            .foregroundColor(isDarkMode ? .white : .primary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
                
                // Playback Controls
                HStack(spacing: 24) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onToggle) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onNext) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(isDarkMode ? .white : .black)

                if let fraction = state.progress(at: Date()) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(.pink)
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(
            ZStack {
                if isDarkMode {
                    Color(white: 0.15)
                } else {
                    Color.white
                }
                
                // Subtle colorful blur
                LinearGradient(
                    colors: [Color.pink.opacity(0.15), Color.blue.opacity(0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 5)
        .colorScheme(isDarkMode ? .dark : .light)
    }
}


struct TurntableView: View {
    let isPlaying: Bool
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Base layer
            Circle()
                .fill(Color(white: 0.15))
            
            // Grooves
            ForEach(0..<4) { i in
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    .padding(CGFloat(i) * 3 + 2)
            }
            
            // Center label
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)
            
            // Spindle
            Circle()
                .fill(Color.black)
                .frame(width: 4, height: 4)
        }
        .rotationEffect(.degrees(rotation))
        .animation(
            isPlaying ? Animation.linear(duration: 3.0).repeatForever(autoreverses: false) : .default,
            value: isPlaying
        )
        .onChange(of: isPlaying) { playing in
            if playing {
                rotation += 360
            }
        }
        .onAppear {
            if isPlaying {
                rotation += 360
            }
        }
    }
}

private struct LiveIslandVerticalKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Phase 18: the Live Island chip renders its side-rail (vertical) layout.
    var liveIslandVertical: Bool {
        get { self[LiveIslandVerticalKey.self] }
        set { self[LiveIslandVerticalKey.self] = newValue }
    }
}

// MARK: - Expanded Media Player Card (Phase 32)

private struct ExpandedMediaCardView: View {
    @ObservedObject private var feed = LiveActivityFeed.shared
    @StateObject private var systemStatus = SystemStatusService()
    @State private var isHovered = false
    @State private var timelineNow = Date()
    @State private var currentPage: Int = 0
    @State private var scrollDirection: Int = 1
    @State private var showPopup = false
    @Environment(\.widgetSize) private var widgetSize
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let state = feed.nowPlayingState
        let progress = state.progress(at: timelineNow) ?? 0.35
        let title = (state.title?.isEmpty ?? true) ? "God's Plan" : (state.title ?? "God's Plan")
        let artist = (state.artist?.isEmpty ?? true) ? "Drake" : (state.artist ?? "Drake")

        HStack(spacing: 8) {
            // Paged Content area with vertical sliding animation
            ZStack {
                if currentPage == 0 {
                    trackPageView(state: state, progress: progress, title: title, artist: artist)
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else if currentPage == 1 {
                    volumePageView
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                } else {
                    spectrumPageView(state: state)
                        .transition(.asymmetric(
                            insertion: .move(edge: scrollDirection >= 0 ? .bottom : .top).combined(with: .opacity),
                            removal: .move(edge: scrollDirection >= 0 ? .top : .bottom).combined(with: .opacity)
                        ))
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()

            // Vertical Pagination Dots (Apple-style interactive indicator)
            VStack(spacing: 3) {
                ForEach(0..<3) { page in
                    Capsule(style: .continuous)
                        .fill(currentPage == page ? Color.white : Color.white.opacity(0.28))
                        .frame(width: 3, height: currentPage == page ? 8 : 3)
                        .scaleEffect(currentPage == page ? 1.1 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentPage)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            scrollDirection = page >= currentPage ? 1 : -1
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                                currentPage = page
                            }
                        }
                }
            }
            .padding(.trailing, 1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.88))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.32 : 0.16), radius: isHovered ? 6 : 3, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .onHover { isHovered = $0 }
        .overlay(
            VerticalWheelScrollNSViewRepresentable { direction in
                let target = min(max(currentPage + direction, 0), 2)
                guard target != currentPage else { return }
                scrollDirection = direction
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    currentPage = target
                }
            }
            .allowsHitTesting(true)
        )
        .onReceive(timer) { input in
            timelineNow = input
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .popover(isPresented: $showPopup, arrowEdge: .top) {
            NowPlayingPopup(
                state: state,
                theme: .auto,
                onToggle: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onPrevious: { feed.previousTrack() }
            )
        }
    }

    // MARK: - Page 0: Track Info & Transport

    private func trackPageView(state: NowPlayingState, progress: Double, title: String, artist: String) -> some View {
        HStack(spacing: 8) {
            // Album Artwork (never clipped)
            ZStack {
                if let data = state.artworkData, let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.25, blue: 0.75),
                                 Color(red: 0.15, green: 0.18, blue: 0.45)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    TurntableView(isPlaying: state.isPlaying)
                        .padding(2)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            // Track details + Scrubber Bar
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(artist)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // Scrubber Bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 3)

                        Capsule()
                            .fill(Color.white.opacity(0.88))
                            .frame(width: max(3, geo.size.width * CGFloat(progress)), height: 3)

                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                            .offset(x: max(0, min(geo.size.width - 6, geo.size.width * CGFloat(progress) - 3)))
                    }
                }
                .frame(height: 6)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Playback Transport Controls
            HStack(spacing: 5) {
                Button(action: { feed.previousTrack() }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: { feed.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 22, height: 22)
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                Button(action: { feed.nextTrack() }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Page 1: Volume & Audio Destination

    private var volumePageView: some View {
        let vol = systemStatus.status.volume
        return HStack(spacing: 8) {
            // Audio destination icon
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 32, height: 32)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                Image(systemName: "airplayaudio")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.38, green: 0.68, blue: 1.0))
            }

            // Volume level slider & device label
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Volume")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(vol.isMuted ? "Muted" : "\(vol.percent)%")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                // Interactive volume slider
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.18))
                            .frame(height: 4)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.38, green: 0.68, blue: 1.0),
                                             Color(red: 0.58, green: 0.45, blue: 0.95)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(3, geo.size.width * CGFloat(vol.isMuted ? 0 : vol.level)), height: 4)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { val in
                                let fraction = Float(min(max(val.location.x / geo.size.width, 0.0), 1.0))
                                systemStatus.setVolume(fraction)
                            }
                    )
                }
                .frame(height: 6)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Quick Mute / Unmute
            Button(action: {
                let current = systemStatus.status.volume.level
                if current > 0 {
                    systemStatus.setVolume(0)
                } else {
                    systemStatus.setVolume(0.5)
                }
            }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: vol.symbolName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Page 2: Audio Spectrum & Session Status

    private func spectrumPageView(state: NowPlayingState) -> some View {
        HStack(spacing: 8) {
            // Animated Equalizer Bars
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5) { bar in
                    EqualizerBar(index: bar, isPlaying: state.isPlaying)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            // Live session status / playback indicator
            VStack(alignment: .leading, spacing: 2) {
                Text("Now Playing")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isPlaying ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(state.isPlaying ? "Playing Live" : "Paused")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }

                Text(timeString(for: state))
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
            }
            .frame(minWidth: 55, maxWidth: .infinity, alignment: .leading)

            // Popup flyout opener
            Button(action: { showPopup.toggle() }) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 22, height: 22)
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func timeString(for state: NowPlayingState) -> String {
        let el = Int(state.elapsed ?? 84)
        let dur = Int(state.duration ?? 218)
        let elM = el / 60
        let elS = el % 60
        let durM = dur / 60
        let durS = dur % 60
        return String(format: "%d:%02d / %d:%02d", elM, elS, durM, durS)
    }
}

// MARK: - Equalizer Bar

private struct EqualizerBar: View {
    let index: Int
    let isPlaying: Bool
    @State private var barHeight: CGFloat = 5

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(
                LinearGradient(
                    colors: [Color(red: 0.38, green: 0.68, blue: 1.0), Color(red: 0.72, green: 0.45, blue: 1.0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 3, height: isPlaying ? barHeight : 4)
            .onAppear {
                syncAnimation()
            }
            .onChange(of: isPlaying) { _ in
                syncAnimation()
            }
    }

    private func syncAnimation() {
        if isPlaying {
            let heights: [CGFloat] = [16, 10, 20, 12, 18]
            let duration = 0.42 + Double(index) * 0.07
            withAnimation(Animation.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                barHeight = heights[index % heights.count]
            }
        } else {
            withAnimation(.default) {
                barHeight = 4
            }
        }
    }
}

// MARK: - Wheel Scroll Vertical Paging Interceptor

private struct VerticalWheelScrollNSViewRepresentable: NSViewRepresentable {
    var onStep: (Int) -> Void

    func makeNSView(context: Context) -> VerticalWheelNSView {
        let view = VerticalWheelNSView()
        view.onStep = onStep
        return view
    }

    func updateNSView(_ nsView: VerticalWheelNSView, context: Context) {
        nsView.onStep = onStep
    }
}

private final class VerticalWheelNSView: NSView {
    var onStep: ((Int) -> Void)?
    private var lastScrollTime: TimeInterval = 0
    private var accumulatedDelta: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only intercept scrollWheel events so standard mouse clicks pass directly to buttons beneath!
        if let event = NSApp.currentEvent, event.type == .scrollWheel {
            return self
        }
        return nil
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        let now = CACurrentMediaTime()

        accumulatedDelta += delta

        // Hysteresis cooldown (0.24s) prevents erratic multiple skips
        if now - lastScrollTime > 0.24 && abs(accumulatedDelta) > 1.2 {
            if accumulatedDelta > 0 {
                onStep?(-1) // scroll up -> previous page
            } else {
                onStep?(1)  // scroll down -> next page
            }
            lastScrollTime = now
            accumulatedDelta = 0
        }
    }
}



