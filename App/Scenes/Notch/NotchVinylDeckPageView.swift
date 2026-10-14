import SwiftUI

// Phase 33e — Page 2: Vinyl Audio Deck (Bento Card A: Spinning Grooved Vinyl, Card B: Controls & Cyan Volume Arc)

struct NotchVinylDeckPageView: View {
    @ObservedObject var feed: LiveActivityFeed
    @State private var rotationAngle: Double = 0.0

    var body: some View {
        let isPlaying = feed.nowPlayingState.isPlaying
        let title = feed.nowPlayingState.title ?? "No Audio Playing"
        let artist = feed.nowPlayingState.artist ?? "Select Music to Play"

        HStack(spacing: NotchDesignSpec.cardSpacing) {
            // Card A: Tactile Grooved Vinyl Turntable
            HStack(spacing: 16) {
                ZStack {
                    // Outer vinyl record
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

                    // Center label / album artwork
                    if let artworkData = feed.nowPlayingState.artworkData,
                       let nsImage = NSImage(data: artworkData) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(LinearGradient(colors: [Color.pink, Color.orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            )
                    }

                    // Spindle hole
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
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
                        Text(verbatim: "Hi-Fi Turntable")
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

                // Interactive scrubber bar
                if let fraction = feed.nowPlayingState.progress(at: Date()),
                   let duration = feed.nowPlayingState.duration, duration > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.12)).frame(height: 5)
                            Capsule().fill(Color.pink).frame(width: max(5, geo.size.width * CGFloat(fraction)), height: 5)
                        }
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let clickFraction = max(0, min(1, value.location.x / geo.size.width))
                                    feed.seek(to: Double(clickFraction) * duration)
                                }
                        )
                    }
                    .frame(height: 5)
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

                    // Cyan Volume Arc Meter
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text(verbatim: "54 dB")
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
        .onAppear {
            if isPlaying {
                withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
                    rotationAngle = 360.0
                }
            }
        }
    }
}
