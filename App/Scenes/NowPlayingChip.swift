import SwiftUI

public struct NowPlayingChip: View {
    @StateObject private var service = NowPlayingService()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // Album Art Placeholder
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    colors: [.purple.opacity(0.8), .blue.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                )
            
            // Text and Controls
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title ?? "Not Playing")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let artist = service.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 100, alignment: .leading)
            
            // Minimal playback control
            Button(action: {
                // Play/Pause toggle would call service
            }) {
                Image(systemName: service.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }
}
