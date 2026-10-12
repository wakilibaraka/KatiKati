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

    public init() {}

    public var body: some View {
        if settingsStore.dockIslandEnabled {
            LiveIslandDockCapsule()
        }
    }
}

/// The dock-side renderer. Reads the shared app-wide feed and holds it only while on screen.
struct LiveIslandDockCapsule: View {
    @ObservedObject private var feed = LiveActivityFeed.shared
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var isHovering = false
    @State private var showPopup = false
    
    var body: some View {
        let activity = feed.activity

        Group {
            if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    capsule(activity, showsLabel: true)
                    capsule(activity, showsLabel: false)
                }
            } else {
                capsule(activity, showsLabel: false)
            }
        }
        .padding(.horizontal, 8)
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

    private func glyph(for activity: LiveActivity) -> some View {
        Image(systemName: symbolName(for: activity.kind))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint(for: activity.kind))
            .frame(width: 16)
            .accessibilityHidden(true)
    }

    // MARK: - Kind mapping

    /// The kind's SF Symbol. All long-standing symbols (present since macOS 11) — an unknown name
    /// renders nothing at runtime with no compile-time warning, so validity is chosen deliberately.
    private func symbolName(for kind: LiveActivityKind) -> String {
        switch kind {
        case .music: return "music.note"
        case .focus: return "brain.head.profile"
        case .countdown: return "calendar"
        case .timer: return "timer"
        case .stopwatch: return "stopwatch"
        case .clock: return "clock"
        }
    }

    private func tint(for kind: LiveActivityKind) -> Color {
        switch kind {
        case .music: return .pink
        case .focus: return .orange
        case .countdown: return .blue
        case .timer: return .teal
        case .stopwatch: return .indigo
        case .clock: return .secondary
        }
    }

    /// Localized kind label. Whole literals so the localization gate sees them; every one already
    /// exists in the catalog (and is referenced elsewhere), so this adds no entry and orphans none.
    private func labelText(for kind: LiveActivityKind) -> Text {
        switch kind {
        case .music: return Text("Now Playing")
        case .focus: return Text("Focus")
        case .countdown: return Text("Countdown")
        case .timer: return Text("Timer")
        case .stopwatch: return Text("Stopwatch")
        case .clock: return Text("Clock")
        }
    }

    private func labelString(for kind: LiveActivityKind) -> String {
        switch kind {
        case .music: return String(localized: "Now Playing")
        case .focus: return String(localized: "Focus")
        case .countdown: return String(localized: "Countdown")
        case .timer: return String(localized: "Timer")
        case .stopwatch: return String(localized: "Stopwatch")
        case .clock: return String(localized: "Clock")
        }
    }

    // MARK: - Live value (data, never localized copy)

    private func valueText(for activity: LiveActivity) -> Text? {
        valueString(for: activity).map { Text(verbatim: $0) }
    }

    private func valueString(for activity: LiveActivity) -> String? {
        switch activity.content {
        case .music(let music):
            return music.title ?? music.artist
        case .focus(let focus):
            return LiveIslandFormat.clock(focus.remaining)
        case .countdown(let countdown):
            return countdownValue(countdown)
        case .timer(let timer):
            return LiveIslandFormat.clock(timer.remaining)
        case .stopwatch(let stopwatch):
            return LiveIslandFormat.stopwatch(stopwatch.elapsed)
        case .clock:
            return clockString()
        }
    }

    /// An event's "days away" in localized words via `RelativeDateTimeFormatter` (the OS supplies the
    /// translation), so no catalog key is invented. `0` days has no good relative phrasing ("now"),
    /// so the event's own label carries that case.
    private func countdownValue(_ content: CountdownContent) -> String {
        guard content.daysRemaining > 0 else { return content.label }
        let now = Date()
        guard let target = Calendar.current.date(byAdding: .day, value: content.daysRemaining, to: now) else {
            return content.label
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: target, relativeTo: now)
    }

    /// The wall clock in the locale's preferred 12/24-hour form (a template, not a hardcoded format).
    private func clockString() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter.string(from: Date())
    }

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
