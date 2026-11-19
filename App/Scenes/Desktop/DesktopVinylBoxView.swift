import AppKit
import SwiftUI

/// One shared system-wide now-playing reader for every Vinyl Music widget (created on first use).
@MainActor
enum DesktopWidgetServices {
    static let nowPlaying = NowPlayingService()
}

/// Desktop Vinyl Music: album art on a record that spins only while playing (and never under Reduce Motion).
struct DesktopVinylBoxView: View {
    @ObservedObject var service: NowPlayingService
    @ObservedObject private var performance = DesktopPerformanceStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let state = service.state
        let spins = performance.settings.allowsAnimation(.vinylSpin)
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !state.isPlaying || reduceMotion || !spins)) { context in
                record(state: state)
                    .rotationEffect(.degrees(state.isPlaying && !reduceMotion && spins
                        ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 9) * 40
                        : 0))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let title = state.title {
                VStack(spacing: 1) {
                    Text(verbatim: title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let artist = state.artist {
                        Text(verbatim: artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else {
                Text("Not Playing").font(.system(size: 12)).foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                Button { service.previousTrack() } label: { Image(systemName: "backward.fill") }
                    .accessibilityLabel(Text("Previous"))
                Button { service.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(state.isPlaying ? Text("Pause") : Text("Play"))
                Button { service.nextTrack() } label: { Image(systemName: "forward.fill") }
                    .accessibilityLabel(Text("Next"))
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }

    private func record(state: NowPlayingState) -> some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.85))
            ForEach([0.92, 0.80, 0.68], id: \.self) { scale in
                Circle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1).scaleEffect(scale)
            }
            if let data = state.artworkData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
                    .clipShape(Circle()).scaleEffect(0.5)
            } else {
                Circle().fill(Color.accentColor.opacity(0.6)).scaleEffect(0.5)
                Image(systemName: "music.note").foregroundStyle(.white.opacity(0.8))
            }
            Circle().fill(Color.black).scaleEffect(0.07)
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }
}
