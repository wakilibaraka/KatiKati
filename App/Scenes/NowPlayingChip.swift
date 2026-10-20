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
    @Environment(\.liveIslandVertical) private var isVertical

    public init() {}

    public var body: some View {
        if settingsStore.dockIslandEnabled {
            if isVertical {
                RailMediaTile()
            } else if mediaPreset == .expandedCard {
                ExpandedMediaCardView()
            } else {
                LiveIslandDockCapsule()
            }
        }
    }
}

/// Runs the preset's action for a click on either Now Playing chip.
@MainActor
enum NowPlayingTapRunner {
    static func run(_ taps: Int, preset: NowPlayingTapPreset, state: NowPlayingState?, feed: LiveActivityFeed, popup: Binding<Bool>) {
        switch preset.action(forTaps: taps) {
        case .playPause: feed.togglePlayPause()
        case .openPlayer: popup.wrappedValue.toggle()
        case .openSourceApp:
            if let id = state?.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
        }
    }
}

/// Phase 49 (owner: "Compact vertical tile"): on a vertical rail the wide horizontal media card is
/// replaced by a 40 × 40 compact tile wearing the shared `DockTileChrome` — album artwork or turntable
/// disc with a subtle transport badge on hover, tapping to open `NowPlayingPopup`.
struct RailMediaTile: View {
    @ObservedObject private var feed = LiveActivityFeed.shared
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var isHovered = false
    @State private var showPopup = false

    private func handleTap(_ taps: Int, state: NowPlayingState?) {
        NowPlayingTapRunner.run(taps, preset: settingsStore.nowPlayingTapPreset, state: state, feed: feed, popup: $showPopup)
    }

    var body: some View {
        let state = feed.nowPlayingState
        let hasTrack = !(state.title?.isEmpty ?? true)
        let unreadable = hasTrack ? nil : feed.playerAccess.unreadableMessage
        let title = hasTrack ? (state.title ?? "") : (unreadable ?? String(localized: "Not Playing"))

        ZStack {
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
            .frame(width: 28, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
            )

            if isHovered || state.isPlaying {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 16, height: 16)
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 7.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 8, y: 8)
            }
        }
        .frame(width: BarSection.railTileSize, height: BarSection.railTileSize)
        .dockTileChrome(isHovered: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { handleTap(2, state: state) }
        .onTapGesture { handleTap(1, state: state) }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .help(Text(verbatim: title))
        .popover(isPresented: $showPopup, arrowEdge: .leading) {
            NowPlayingPopup(
                state: state,
                theme: settingsStore.nowPlayingTheme,
                access: feed.playerAccess,
                onToggle: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onPrevious: { feed.previousTrack() },
                onSeek: { feed.seek(to: $0) }
            )
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
            } else {
                ViewThatFits(in: .horizontal) {
                    capsule(activity, showsLabel: true)
                    capsule(activity, showsLabel: false)
                }
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
        .onTapGesture(count: 2) { tap(for: activity, taps: 2) }
        .onTapGesture { tap(for: activity, taps: 1) }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
        .help(helpText(for: activity))
        .animation(.easeInOut(duration: 0.18), value: activity.kind)
        .opacity(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: feed.isNotchExpanded) ? 0.0 : 1.0)
        .animation(.spring(response: NotchMotionSpec.wingSneakSpring.response, dampingFraction: NotchMotionSpec.wingSneakSpring.dampingRatio), value: feed.isNotchExpanded)
        .popover(isPresented: $showPopup, arrowEdge: .top) {
            NowPlayingPopup(
                state: feed.nowPlayingState,
                theme: settingsStore.nowPlayingTheme,
                access: feed.playerAccess,
                onToggle: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onPrevious: { feed.previousTrack() },
                onSeek: { feed.seek(to: $0) }
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
        let tint = glyphTint(for: activity)
        return ZStack {
            if let progress = activity.ringProgress {
                Circle().stroke(tint.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: symbolName(for: activity.kind))
                .font(.system(size: activity.ringProgress == nil ? 13 : 10, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: activity.ringProgress == nil ? 16 : 22, height: 22)
        .accessibilityHidden(true)
    }

    /// 50c: while music wins, the glyph and ring wear the (reduced) artwork colour; grey art falls back to the kind tint.
    private func glyphTint(for activity: LiveActivity) -> Color {
        guard case .music = activity.content, let accent = ArtworkAccentCache.accent(for: feed.nowPlayingState.artworkData) else {
            return tint(for: activity.kind)
        }
        return Color(red: accent.red, green: accent.green, blue: accent.blue)
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
    private func tap(for activity: LiveActivity, taps: Int) {
        if case .music = activity.content { handleTap(taps, state: feed.nowPlayingState) }
    }

    private func handleTap(_ taps: Int, state: NowPlayingState?) {
        NowPlayingTapRunner.run(taps, preset: settingsStore.nowPlayingTapPreset, state: state, feed: feed, popup: $showPopup)
    }

    private func helpText(for activity: LiveActivity) -> String {
        let label = labelString(for: activity.kind)
        guard let value = valueString(for: activity), !value.isEmpty else { return label }
        return "\(label) — \(value)"
    }
}

/// A progress bar you can scrub: press anywhere on it and the fill follows the pointer, release and the
/// player is sent there.
///
/// The vinyl notch page had a version of this of its own, and the dock card and the notch panel drew
/// display-only bars — which is why one surface could seek and the others could not (Phase 47). One
/// gesture, one look, four surfaces (notch panel, dock card, popup, vinyl deck).
struct MusicScrubBar: View {
    let progress: Double
    let duration: TimeInterval
    var trackHeight: CGFloat = 3
    var tint: Color = .white
    var knob: Bool = true
    let onSeek: (Double) -> Void

    /// Non-nil only while the pointer is down: the fill follows the drag instead of the player, which has
    /// not heard about it yet.
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = min(1, max(0, dragging ?? progress))
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.2)).frame(height: trackHeight)
                Capsule().fill(tint.opacity(0.9))
                    .frame(width: max(trackHeight, width * CGFloat(fraction)), height: trackHeight)
                if knob {
                    Circle().fill(tint)
                        .frame(width: trackHeight * 2, height: trackHeight * 2)
                        .offset(x: max(0, min(width - trackHeight * 2, width * CGFloat(fraction) - trackHeight)))
                }
            }
            .frame(width: width, height: max(trackHeight * 2, 8), alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragging = value.location.x / width }
                    .onEnded { value in
                        let target = min(1, max(0, value.location.x / width))
                        dragging = nil
                        onSeek(target * duration)
                    }
            )
        }
        .frame(height: max(trackHeight * 2, 8))
    }
}

/// Average artwork colour reduced through `ArtworkAccent`; one entry, because only one track plays at a time.
@MainActor
enum ArtworkAccentCache {
    private static var key: Data?
    private static var value: ArtworkAccent?

    static func accent(for data: Data?) -> ArtworkAccent? {
        guard let data else { return nil }
        if key == data { return value }
        key = data
        value = average(of: data).flatMap { ArtworkAccent.reduce(red: $0.0, green: $0.1, blue: $0.2) }
        return value
    }

    /// Draws the image into one RGBA pixel, which averages it.
    private static func average(of data: Data) -> (Double, Double, Double)? {
        guard let cg = NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let drawn = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        return drawn ? (Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255) : nil
    }
}
