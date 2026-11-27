import AppKit
import SwiftUI

/// Left card of the full notch skin when music is the winning activity or nothing is active: album art,
/// title / artist, a thin progress bar (no time readout), and the transport row. Idle shows
/// "Not Playing" with a quick-actions row instead of the progress bar.
struct NotchMusicPanel: View {
    @ObservedObject var feed: LiveActivityFeed
    @ObservedObject private var lyricsStore = LyricsStore.shared
    @AppStorage(LyricsTrack.enabledKey) private var showLyrics = false
    @State private var showQueuePopover = false
    @State private var upcomingQueue: [NowPlayingQueueItem] = []
    @AppStorage(NotchTransportControl.defaultsKey) private var transportRaw = NotchTransportControl.initialRaw
    var isIdle = false
    var compact = false
    var onExpand: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var artworkSize: CGFloat { compact ? 82 : NotchLayoutSpec.albumArtSize }

    /// The artwork's reduced colour, white when the art is grey or missing.
    private func accent(_ state: NowPlayingState) -> Color {
        ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white
    }

    var body: some View {
        let state = feed.nowPlayingState
        // A player we may not read says so, instead of the card claiming nothing is playing (Phase 45).
        let unreadable = isIdle ? feed.playerAccess.unreadableMessage : nil
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                art(isIdle ? nil : state.artworkData, isPlaying: !isIdle && state.isPlaying)
                if let onExpand {
                    Button(action: onExpand) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 26, height: 18)
                            .background(Capsule().fill(.white.opacity(0.10)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Music"))
                    .help(Text("Open Details"))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if isIdle {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(unreadable ?? "Not Playing").font(.system(size: 14, weight: .bold, design: .rounded)).lineLimit(1)
                        if unreadable == nil {
                            Text("Play something to see it here").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                        } else {
                            Button("Open System Settings") {
                                if let url = PlayerAccess.automationSettingsURL { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    transport(state)
                    NotchQuickActions()
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !compact {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(state.isPlaying ? accent(state) : Color.orange)
                                        .frame(width: 5, height: 5)
                                    Text(verbatim: state.isPlaying ? "PLAYING" : "PAUSED")
                                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                        .foregroundStyle(state.isPlaying ? accent(state) : Color.orange)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill((state.isPlaying ? accent(state) : Color.orange).opacity(0.16)))
                            }
                            // NP-3: a still title that shrinks before it truncates. The marquee started
                            // scrolling after 1.2 s, so every capture clipped the title on both edges.
                            Text(verbatim: state.title ?? "")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(compact ? 2 : 1)
                                .minimumScaleFactor(0.8)
                            Text(verbatim: state.artist ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
                        }
                        .opensSourceApp(state.bundleIdentifier)
                        Spacer(minLength: 0)
                        MusicEqualizerBars(isActive: state.isPlaying && !reduceMotion, tint: accent(state))
                            .frame(width: 22, height: 18)
                    }
                    Spacer(minLength: 0)
                    progress(state)
                    transport(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: compact ? 104 : NotchLayoutSpec.albumArtSize)
        .foregroundStyle(.white)
        .background {
            if !isIdle {
                // Artwork wash: the accent fades out left to right behind the card.
                LinearGradient(
                    colors: [accent(state).opacity(compact ? 0.38 : 0.30), .clear],
                    startPoint: compact ? .topLeading : .leading,
                    endPoint: compact ? .bottomTrailing : .trailing
                )
                    .padding(-10).blur(radius: 14).allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.6), value: state.artworkData?.count)
            }
        }
    }

    /// The player's own artwork when it hands one over; the vinyl otherwise, spinning only while the
    /// track is playing (Phase 43 — it used to be a static note glyph either way).
    private func art(_ data: Data?, isPlaying: Bool) -> some View {
        let glow = ArtworkAccentCache.accent(for: data).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.black
        let size = artworkSize
        return Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(TurntableView(isPlaying: isPlaying).padding(2))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous))
        .shadow(color: glow.opacity(0.55), radius: 12, y: 3)
        .opensSourceApp(isIdle ? nil : feed.nowPlayingState.bundleIdentifier)
    }

    @ViewBuilder
    private func progress(_ state: NowPlayingState) -> some View {
        // TimelineView only ticks while music is showing; the bar moves without the feed's own tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = state.progress(at: context.date) ?? 0
            let duration = state.duration ?? 0
            let elapsed = fraction * duration
            let lyricLines = showLyrics && !compact ? lyricsStore.lines(title: state.title, artist: state.artist) : []
            VStack(alignment: .leading, spacing: 3) {
                if showLyrics && !compact {
                    let window = LyricTimelineMatcher.window(in: lyricLines, at: elapsed, windowSize: 2)
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(window.enumerated()), id: \.offset) { _, line in
                            let isActive = (line.text == LyricsTrack.activeLine(in: lyricLines, at: elapsed))
                            Text(verbatim: line.text)
                                .font(.system(size: isActive ? 10.5 : 9, weight: isActive ? .semibold : .regular, design: .rounded))
                                .foregroundStyle(isActive ? .white : .white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                }
                HStack(spacing: 8) {
                    Text(verbatim: Self.clock(elapsed)).frame(minWidth: 30, alignment: .trailing)
                    MusicScrubBar(progress: fraction, duration: duration, trackHeight: 4, tint: accent(state),
                                  onSeek: { feed.seek(to: $0) })
                    Text(verbatim: duration > 0 ? "-" + Self.clock(max(0, duration - elapsed)) : "–:––").frame(minWidth: 30, alignment: .leading)
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
            }
            .onAppear {
                if showLyrics && !compact { lyricsStore.loadIfNeeded(title: state.title, artist: state.artist) }
            }
            .onChange(of: state.title) { _, _ in
                if showLyrics && !compact { lyricsStore.loadIfNeeded(title: state.title, artist: state.artist) }
            }
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transport(_ state: NowPlayingState) -> some View {
        HStack(spacing: compact ? 12 : 16) {
            ForEach(NotchTransportControl.decode(transportRaw)) { control in
                transportButton(control, state: state)
            }
            if !compact {
                Button { showQueuePopover.toggle() } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(showQueuePopover ? 1.0 : 0.6))
                }
                .popover(isPresented: $showQueuePopover) {
                    NotchQueuePopoverView(queue: $upcomingQueue)
                }
                Button { showLyrics.toggle() } label: {
                    Image(systemName: "quote.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(showLyrics ? accent(state) : .white.opacity(0.55))
                }
                AudioOutputMenu {
                    Image(systemName: "airplayaudio")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ control: NotchTransportControl, state: NowPlayingState) -> some View {
        let isPrimary = control == .playPause
        let isPlaying = state.isPlaying && !isIdle
        return Button {
            switch control {
            case .previous: feed.previousTrack()
            case .playPause: feed.togglePlayPause()
            case .next: feed.nextTrack()
            case .backward, .forward:
                guard let duration = state.duration, let progress = state.progress(at: Date()) else { return }
                let offset: Double = control == .backward ? -15 : 15
                feed.seek(to: min(duration, max(0, progress * duration + offset)))
            }
        } label: {
            Image(systemName: isPrimary && isPlaying ? "pause.fill" : control.symbol)
                .font(.system(size: isPrimary ? 14 : 13, weight: isPrimary ? .bold : .medium))
                .frame(width: isPrimary ? 30 : 16, height: 30)
                .background {
                    if isPrimary {
                        Circle().fill(Color.white.opacity(0.16))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    }
                }
        }
        .disabled((control == .backward || control == .forward) && state.progress(at: Date()) == nil)
        .accessibilityLabel(Text(verbatim: isPrimary ? (isPlaying ? String(localized: "Pause") : String(localized: "Play")) : control.title))
    }

}

/// Dedicated full-width Music page (split from Calendar): full-width player card with optional
/// synchronized LRC lyrics & audio output companion panel.
struct NotchMusicPageView: View {
    @ObservedObject var feed: LiveActivityFeed

    var body: some View {
        let state = feed.nowPlayingState
        let isIdle = (state.title ?? "").isEmpty
        // NP-3: one full-width player. The 175 pt companion squeezed the title and, when only the
        // output picker filled it, drew an almost-empty card; the output menu already lives in transport.
        NotchMusicPanel(feed: feed, isIdle: isIdle)
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .notchCard()
    }
}

/// Left half when something other than music is winning (timer, focus, stopwatch, countdown, clock):
/// the activity's glyph, label and value, large.
struct NotchActivityPanel: View {
    let activity: LiveActivity
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                .frame(width: NotchLayoutSpec.albumArtSize, height: NotchLayoutSpec.albumArtSize)
                .background(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                LiveIslandStyle.labelText(for: activity.kind).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                if let value = LiveIslandStyle.valueText(for: activity) {
                    value.font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                }
                controls
            }
            Spacer(minLength: 0)
        }
        .frame(height: NotchLayoutSpec.albumArtSize)
    }
}

extension NotchActivityPanel {
    /// Pause/resume and stop for the activities KatiKati owns; the event countdown has nothing to control.
    @ViewBuilder fileprivate var controls: some View {
        switch activity.kind {
        case .focus: controlRow(toggle: { services.focus.toggle() }, stop: { services.focus.reset() })
        case .timer: controlRow(toggle: { services.timer.toggle() }, stop: { services.timer.reset() })
        case .stopwatch: controlRow(toggle: { services.stopwatch.toggle() }, stop: { services.stopwatch.reset() })
        default: EmptyView()
        }
    }

    private func controlRow(toggle: @escaping () -> Void, stop: @escaping () -> Void) -> some View {
        HStack(spacing: 18) {
            Button(action: toggle) { Image(systemName: "playpause.fill").font(.system(size: 16)) }
            Button(action: stop) { Image(systemName: "stop.fill").font(.system(size: 16)) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.top, 4)
    }
}

/// Idle extras under the Now Playing placeholder (instead of a clock): start a Pomodoro or a 5-minute
/// timer. (Volume lives in the header's right cluster.)
struct NotchQuickActions: View {
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 8) {
            chip("timer", Text("Timer")) { services.timer.set(seconds: 300); services.timer.toggle() }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }

    private func chip(_ symbol: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                title.font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Queue Popover & Detachable Floating Player (Slice 2.4)

struct NotchQueuePopoverView: View {
    @Binding var queue: [NowPlayingQueueItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "Playing Next")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            if queue.isEmpty {
                Text(verbatim: "No upcoming tracks")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(queue) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: item.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            if !item.artist.isEmpty {
                                Text(verbatim: item.artist)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                queue = NowPlayingQueueReorderPlan.promoteTrackToTop(in: queue, id: item.id)
                            }
                        } label: {
                            Image(systemName: "arrow.up.to.line")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                        .help("Promote to top of queue")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(10)
        .frame(width: 180)
    }
}
