import SwiftUI

/// Phase 8d — a small pulsing count on the Downloads chip while browsers are mid-download. Holds the
/// shared `DownloadsMonitor` only while on screen, so a folder chip that isn't Downloads (or a Downloads
/// folder the user hasn't opened yet) costs nothing and reads nothing.
struct DownloadsActivityBadge: View {
    @ObservedObject private var monitor = DownloadsMonitor.shared
    let scale: CGFloat
    @State private var pulse = false

    var body: some View {
        Group {
            if monitor.activeCount > 0 {
                Text(verbatim: "\(monitor.activeCount)")
                    .font(.system(size: 9 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4 * scale)
                    .frame(minWidth: 14 * scale, minHeight: 14 * scale)
                    .background(Capsule().fill(Color.blue))
                    .opacity(pulse ? 1 : 0.6)
                    .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { pulse = true } }
                    .accessibilityHidden(true)
            }
        }
        .onAppear { monitor.retain() }
        .onDisappear { monitor.release() }
    }
}
