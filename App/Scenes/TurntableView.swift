import Foundation
import SwiftUI

struct TurntableView: View {
    let isPlaying: Bool
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Base layer
            Circle()
                .fill(Color(white: 0.15))
            
            // Grooves
            ForEach(0..<4) { i in
                Circle()
                    .stroke(Color.black.opacity(0.3), lineWidth: 0.5)
                    .padding(CGFloat(i) * 3 + 2)
            }
            
            // Center label
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.red, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 20, height: 20)
            
            // Spindle
            Circle()
                .fill(Color.black)
                .frame(width: 4, height: 4)
        }
        .rotationEffect(.degrees(rotation))
        .animation(
            isPlaying ? Animation.linear(duration: 3.0).repeatForever(autoreverses: false) : .default,
            value: isPlaying
        )
        .onChange(of: isPlaying) { playing in
            if playing {
                rotation += 360
            }
        }
        .onAppear {
            if isPlaying {
                rotation += 360
            }
        }
    }
}
