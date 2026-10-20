import Foundation
import SwiftUI

struct NowPlayingPopup: View {
    let state: NowPlayingState
    let theme: NowPlayingTheme
    /// `.refused` when the player may not be read: the popup says so instead of "Not Playing" (Phase 45).
    var access: PlayerAccess = .unknown
    let onToggle: () -> Void
    var onNext: () -> Void = {}
    var onPrevious: () -> Void = {}
    var onSeek: (Double) -> Void = { _ in }

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
                        Text(access.unreadableMessage ?? state.title ?? "Not Playing")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(isDarkMode ? .white : .black)
                            .lineLimit(1)
                        if access.unreadableMessage == nil {
                            Text(state.artist ?? "Unknown Artist")
                                .font(.system(size: 12))
                                .foregroundColor(isDarkMode ? .gray : .secondary)
                                .lineLimit(1)
                        } else {
                            Button(String(localized: "Open System Settings")) {
                                if let url = PlayerAccess.automationSettingsURL { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(isDarkMode ? .white.opacity(0.9) : .black.opacity(0.8))
                            .lineLimit(1)
                        }
                    }
                    Spacer()
                    // AirPlay Icon
                    AudioOutputMenu {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 12))
                            .foregroundColor(isDarkMode ? .white : .primary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                    }
                }
                
                // Playback Controls
                HStack(spacing: 24) {
                    Button(action: onPrevious) {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onToggle) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onNext) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(isDarkMode ? .white : .black)

                // A scrubber, not a ProgressView (Phase 47): the popup is the dock chip's own surface,
                // so seeking has to work here too.
                if let duration = state.duration, duration > 0 {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if let fraction = state.progress(at: context.date) {
                            MusicScrubBar(progress: fraction, duration: duration, trackHeight: 3, tint: .pink,
                                          onSeek: onSeek)
                        }
                    }
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
