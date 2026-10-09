import SwiftUI

public struct NowPlayingChip: View {
    @StateObject private var service = NowPlayingService()
    @EnvironmentObject var settingsStore: AppSettingsStore
    @State private var isHovering = false
    @State private var showPopup = false
    
    public init() {}
    
    public var body: some View {
        Button(action: {
            showPopup.toggle()
        }) {
            Image(systemName: service.state.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isHovering ? .primary : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.primary.opacity(isHovering ? 0.1 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .popover(isPresented: $showPopup, arrowEdge: .top) {
            NowPlayingPopup(state: service.state, theme: settingsStore.nowPlayingTheme, onToggle: {
                service.togglePlayPause()
            })
        }
    }
}

struct NowPlayingPopup: View {
    let state: NowPlayingState
    let theme: NowPlayingTheme
    let onToggle: () -> Void

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
            // Album Art Placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "music.note")
                    .foregroundColor(.white)
                    .font(.system(size: 24))
            }
            .frame(width: 56, height: 56)
            
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
                    Button(action: {}) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: onToggle) {
                        Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: {}) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundColor(isDarkMode ? .white : .black)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(isDarkMode ? Color(white: 0.15) : Color.white)
        .colorScheme(isDarkMode ? .dark : .light)
    }
}
