import SwiftUI

public struct NowPlayingChip: View {
    @StateObject private var service = NowPlayingService()
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
            NowPlayingPopup(state: service.state, onToggle: {
                service.togglePlayPause()
            })
        }
    }
}

struct NowPlayingPopup: View {
    let state: NowPlayingState
    let onToggle: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = state.title {
                Text(title)
                    .font(.headline)
            } else {
                Text("Not Playing")
                    .font(.headline)
            }
            if let artist = state.artist {
                Text(artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                Button(action: onToggle) {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(width: 200)
    }
}
