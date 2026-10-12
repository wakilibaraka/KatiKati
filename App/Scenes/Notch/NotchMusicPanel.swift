import AppKit
import SwiftUI

/// Left half of the full notch skin when music is the winning activity: album art, title / artist,
/// a thin progress bar with elapsed / remaining time, and the transport row.
struct NotchMusicPanel: View {
    @ObservedObject var feed: LiveActivityFeed
    /// Nothing is playing (the winning activity isn't music): the player shows as "Not Playing" with a
    /// row of quick actions instead of a progress bar.
    var isIdle = false

    var body: some View {
        let state = feed.nowPlayingState
        HStack(alignment: .top, spacing: 12) {
            art(isIdle ? nil : state.artworkData)
            VStack(alignment: .leading, spacing: 4) {
                if isIdle {
                    Text("Not Playing").font(.system(size: 14, weight: .bold)).lineLimit(1)
                    transport(state)
                    NotchQuickActions()
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: state.title ?? "").font(.system(size: 14, weight: .bold)).lineLimit(1)
                        Text(verbatim: state.artist ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    progress(state)
                    transport(state)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func art(_ data: Data?) -> some View {
        let size = NotchLayoutSpec.albumArtSize
        return Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.1).overlay(Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(.white.opacity(0.5)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous))
    }

    @ViewBuilder
    private func progress(_ state: NowPlayingState) -> some View {
        // TimelineView only ticks while music is showing; the bar moves without the feed's own tick.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let fraction = state.progress(at: context.date) ?? 0
            let total = state.duration ?? 0
            let elapsed = fraction * total
            VStack(spacing: 2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.2))
                        Capsule().fill(Color.white).frame(width: geo.size.width * fraction)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(verbatim: NotchLayoutSpec.clockText(elapsed))
                    Spacer()
                    Text(verbatim: total > 0 ? "-" + NotchLayoutSpec.clockText(total - elapsed) : "")
                }
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func transport(_ state: NowPlayingState) -> some View {
        HStack(spacing: 22) {
            Button { feed.previousTrack() } label: { Image(systemName: "backward.fill").font(.system(size: 16)) }
            Button { feed.togglePlayPause() } label: { Image(systemName: state.isPlaying && !isIdle ? "pause.fill" : "play.fill").font(.system(size: 24)) }
            Button { feed.nextTrack() } label: { Image(systemName: "forward.fill").font(.system(size: 16)) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

/// Left half when something other than music is winning (timer, focus, stopwatch, countdown, clock):
/// the activity's glyph, label and value, large.
struct NotchActivityPanel: View {
    let activity: LiveActivity
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: LiveIslandStyle.symbolName(for: activity.kind))
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LiveIslandStyle.tint(for: activity.kind))
                .frame(width: NotchLayoutSpec.albumArtSize, height: NotchLayoutSpec.albumArtSize)
                .background(RoundedRectangle(cornerRadius: NotchLayoutSpec.albumArtCorner, style: .continuous).fill(Color.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 2) {
                LiveIslandStyle.labelText(for: activity.kind).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                if let value = LiveIslandStyle.valueText(for: activity) {
                    value.font(.system(size: 26, weight: .semibold)).monospacedDigit().foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
                }
                controls
            }
            Spacer(minLength: 0)
        }
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

/// Idle extras under the Now Playing placeholder (instead of a clock): start a Pomodoro, start a 5-minute
/// timer, and the system output volume (the "HUD" slider, via the shared `SystemStatusService`).
struct NotchQuickActions: View {
    @StateObject private var power = SystemStatusService()
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(spacing: 10) {
            chip("brain.head.profile", Text("Focus")) { services.focus.toggle() }
            chip("timer", Text("Timer")) { services.timer.set(seconds: 300); services.timer.toggle() }
            Image(systemName: power.status.volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            Slider(value: Binding(get: { Double(power.status.volume.level) },
                                  set: { _ = power.setVolume(Float($0)) }), in: 0...1)
                .controlSize(.mini)
                .frame(maxWidth: .infinity)
        }
        .foregroundStyle(.white)
        .onAppear { power.acquire() }
        .onDisappear { power.release() }
    }

    private func chip(_ symbol: String, _ title: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11))
                title.font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
    }
}
