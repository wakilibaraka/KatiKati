import SwiftUI

// Phase 33e — Page 2: Vinyl Audio Deck (Bento Card A: Spinning Grooved Vinyl, Card B: Controls & Cyan Volume Arc)

struct NotchVinylDeckPageView: View {
    @ObservedObject var feed: LiveActivityFeed
    @StateObject private var status = SystemStatusService()
    @State private var rotationAngle: Double = 0.0

    var body: some View {
        let isPlaying = feed.nowPlayingState.isPlaying
        let title = feed.nowPlayingState.title ?? "No Audio Playing"
        let artist = feed.nowPlayingState.artist ?? "Select Music to Play"
        let artwork = feed.nowPlayingState.artworkData

        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: the player's own album art when it hands one over, the turntable otherwise
            // (Phase 43). Either way the record spins only while a track is playing.
            HStack(spacing: 16) {
                ZStack {
                    if let artwork, let nsImage = NSImage(data: artwork) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else {
                        vinylRecord(isPlaying: isPlaying)
                    }
                }

                // Tone arm indicator
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Circle().fill(isPlaying ? Color.pink : Color.white.opacity(0.3)).frame(width: 6, height: 6)
                        Text(verbatim: isPlaying ? "SPINNING" : "STOPPED")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(isPlaying ? .pink : .white.opacity(0.5))
                    }
                    Text(verbatim: "33⅓ RPM")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    
                    if let appName = feed.nowPlayingState.appName, !appName.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform")
                                .font(.system(size: 8))
                            Text(verbatim: appName)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.cyan.opacity(0.8))
                    } else {
                        // The player named no app: say nothing rather than a made-up device name
                        // (Phase 43; this used to read "Hi-Fi Turntable").
                        Text(verbatim: "—")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )

            // Card B: Scrubber & Cyan Volume Arc Meter
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(verbatim: artist)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }

                // Interactive scrubber bar, elapsed on the left and the track's length on the right.
                // Phase 47: this was the only surface that could seek; the bar itself now lives in
                // `MusicScrubBar` and is shared with the dock card, the popup and the notch panel, so
                // one gesture behaves the same everywhere.
                if let fraction = feed.nowPlayingState.progress(at: Date()),
                   let duration = feed.nowPlayingState.duration, duration > 0 {
                    VStack(spacing: 3) {
                        MusicScrubBar(progress: fraction, duration: duration, trackHeight: 5, tint: .pink,
                                      onSeek: { feed.seek(to: $0) })

                        HStack {
                            Text(verbatim: NotchLayoutSpec.clockText(fraction * duration))
                            Spacer()
                            Text(verbatim: NotchLayoutSpec.clockText(duration))
                        }
                        .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 16) {
                    // Tactile playback buttons
                    HStack(spacing: 12) {
                        Button { feed.previousTrack() } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.10)))
                        }
                        Button { feed.togglePlayPause() } label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(Circle().fill(Color.white.opacity(0.20)))
                        }
                        Button { feed.nextTrack() } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 14))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(Color.white.opacity(0.10)))
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)

                    Spacer()

                    // Real output volume (Phase 43: this badge used to print a hard-coded "54 dB").
                    HStack(spacing: 6) {
                        Image(systemName: status.status.volume.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text(verbatim: status.status.volume.isMuted ? "Muted" : "\(status.status.volume.percent)%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.cyan.opacity(0.12)))
                }
            }
            .padding(NotchDesignSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(NotchDesignSpec.cardFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(NotchDesignSpec.cardStrokeOpacity), lineWidth: NotchDesignSpec.cardStrokeWidth)
                    )
            )
        }
        .onAppear { status.acquire() }
        .onDisappear { status.release() }
    }

    /// The fallback record: a grooved disc with its label, turning only while a track plays.
    private func vinylRecord(isPlaying: Bool) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.12),
                        Color(white: 0.04),
                        Color(white: 0.10),
                        Color(white: 0.02)
                    ]),
                    center: .center,
                    startRadius: 5,
                    endRadius: 55
                ))
                .frame(width: 110, height: 110)
                .overlay(
                    // Concentric vinyl sound grooves
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.06), lineWidth: 1).frame(width: 95, height: 95)
                        Circle().stroke(Color.white.opacity(0.08), lineWidth: 1).frame(width: 82, height: 82)
                        Circle().stroke(Color.white.opacity(0.05), lineWidth: 1).frame(width: 68, height: 68)
                    }
                )
                .rotationEffect(.degrees(rotationAngle))

            Circle()
                .fill(LinearGradient(colors: [Color.pink, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                )

            // Spindle hole
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
        }
        .animation(isPlaying ? Animation.linear(duration: 6.0).repeatForever(autoreverses: false) : .default,
                   value: isPlaying)
        .onChange(of: isPlaying) { playing in
            if playing { rotationAngle += 360 }
        }
        .onAppear {
            if isPlaying { rotationAngle += 360 }
        }
    }
}
