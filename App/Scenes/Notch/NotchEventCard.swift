import SwiftUI

/// How an event shows in the open notch: a tinted icon tile, the headline and detail, and a thin bar that
/// drains over the toast's lifetime so the person can see when it will go. Tap dismisses early.
struct NotchEventCard: View {
    let event: LiveEventPresentation
    let lifetime: TimeInterval
    var dismiss: () -> Void = {}
    @State private var drained = false

    /// Hue by what the event is about; unknown symbols fall back to the neutral cyan.
    private var tint: Color {
        switch event.symbol {
        case "music.note": return .pink
        case "timer", "stopwatch": return .orange
        case "brain.head.profile": return .purple
        case "checkmark.circle.fill": return .green
        case "calendar": return .red
        default: return .cyan
        }
    }

    var body: some View {
        Button(action: dismiss) {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: event.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(LinearGradient(colors: [tint, tint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        )
                        .shadow(color: tint.opacity(0.5), radius: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: event.headline)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        if let detail = event.detail, !detail.isEmpty {
                            Text(verbatim: detail)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                Capsule().fill(Color.white.opacity(0.12)).frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule().fill(tint)
                                .frame(width: drained ? 0 : geo.size.width)
                        }
                    }
            }
            .foregroundStyle(.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.linear(duration: lifetime)) { drained = true } }
    }
}
