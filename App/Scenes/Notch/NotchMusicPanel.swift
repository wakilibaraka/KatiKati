import AppKit
import SwiftUI

/// Left card of the full notch skin when music is the winning activity or nothing is active: album art,
/// title / artist, a thin progress bar (no time readout), and the transport row. Idle shows
/// "Not Playing" with a quick-actions row instead of the progress bar.
struct NotchMusicPanel: View {
    @ObservedObject var feed: LiveActivityFeed
    var isIdle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The artwork's reduced colour, white when the art is grey or missing.
    private func accent(_ state: NowPlayingState) -> Color {
        ArtworkAccentCache.accent(for: state.artworkData).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? .white
    }

    var body: some View {
        let state = feed.nowPlayingState
        // A player we may not read says so, instead of the card claiming nothing is playing (Phase 45).
        let unreadable = isIdle ? feed.playerAccess.unreadableMessage : nil
        HStack(alignment: .top, spacing: 12) {
            art(isIdle ? nil : state.artworkData, isPlaying: !isIdle && state.isPlaying)
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
                        VStack(alignment: .leading, spacing: 1) {
                            MarqueeText(text: state.title ?? "", font: .system(size: 15, weight: .bold, design: .rounded), nearEnd: (state.progress(at: Date()) ?? 0) > 0.88)
                            MarqueeText(text: state.artist ?? "", font: .system(size: 12)).foregroundStyle(.white.opacity(0.6))
                        }
                        .opensSourceApp(state.bundleIdentifier)
                        Spacer(minLength: 0)
                        MusicEqualizerBars(isActive: state.isPlaying && !reduceMotion, tint: accent(state))
                            .frame(width: 18, height: 14)
                    }
                    Spacer(minLength: 0)
                    progress(state)
                    transport(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: NotchLayoutSpec.albumArtSize)
        .foregroundStyle(.white)
        .background {
            if !isIdle {
                // Artwork wash: the accent fades out left to right behind the card.
                LinearGradient(colors: [accent(state).opacity(0.30), .clear], startPoint: .leading, endPoint: .trailing)
                    .padding(-10).blur(radius: 14).allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.6), value: state.artworkData?.count)
            }
        }
    }

    /// The player's own artwork when it hands one over; the vinyl otherwise, spinning only while the
    /// track is playing (Phase 43 — it used to be a static note glyph either way).
    private func art(_ data: Data?, isPlaying: Bool) -> some View {
        let glow = ArtworkAccentCache.accent(for: data).map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? Color.black
        let size = NotchLayoutSpec.albumArtSize
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
            HStack(spacing: 8) {
                Text(verbatim: Self.clock(fraction * duration)).frame(minWidth: 30, alignment: .trailing)
                MusicScrubBar(progress: fraction, duration: duration, trackHeight: 4, tint: accent(state),
                              onSeek: { feed.seek(to: $0) })
                Text(verbatim: duration > 0 ? "-" + Self.clock(max(0, duration - fraction * duration)) : "–:––").frame(minWidth: 30, alignment: .leading)
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
        }
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func transport(_ state: NowPlayingState) -> some View {
        HStack(spacing: 20) {
            Button { feed.previousTrack() } label: { Image(systemName: "backward.end.fill").font(.system(size: 15)) }
            Button { feed.togglePlayPause() } label: {
                Image(systemName: state.isPlaying && !isIdle ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.black)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.white))
            }
            Button { feed.nextTrack() } label: { Image(systemName: "forward.end.fill").font(.system(size: 15)) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
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
