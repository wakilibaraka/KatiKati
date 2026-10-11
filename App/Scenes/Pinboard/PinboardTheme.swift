import SwiftUI

/// Vibrant iPadOS-style look for Pinboard cards (Phase 7B-V1): saturated gradient, soft inner highlight, white
/// content. Cards always use dark-scheme content so text stays white on the colour in light and dark mode.
enum PinboardTheme {
    static let unit: CGFloat = 154
    static let gap: CGFloat = 12
    static let corner: CGFloat = 26
    static var panelWidth: CGFloat { unit * 2 + gap }

    static func height(_ size: PinboardSize) -> CGFloat { size == .large ? unit * 2 + gap : unit }
    static func width(_ size: PinboardSize) -> CGFloat { size == .small ? unit : panelWidth }

    static func gradient(_ w: PinboardWidget) -> [Color] {
        switch w {
        case .clock: return [Color(red: 0.16, green: 0.20, blue: 0.42), Color(red: 0.42, green: 0.27, blue: 0.80)]
        case .calendar: return [Color(red: 1.00, green: 0.36, blue: 0.38), Color(red: 0.93, green: 0.22, blue: 0.45)]
        case .weather: return [Color(red: 0.20, green: 0.55, blue: 0.98), Color(red: 0.30, green: 0.80, blue: 0.95)]
        case .nowPlaying: return [Color(red: 0.99, green: 0.30, blue: 0.45), Color(red: 0.98, green: 0.55, blue: 0.30)]
        case .calculator: return [Color(red: 0.30, green: 0.32, blue: 0.38), Color(red: 0.14, green: 0.15, blue: 0.20)]
        case .countdown: return [Color(red: 0.98, green: 0.62, blue: 0.20), Color(red: 0.98, green: 0.80, blue: 0.30)]
        case .screenTime: return [Color(red: 0.36, green: 0.30, blue: 0.90), Color(red: 0.70, green: 0.35, blue: 0.92)]
        case .system: return [Color(red: 0.05, green: 0.55, blue: 0.50), Color(red: 0.20, green: 0.80, blue: 0.55)]
        case .network: return [Color(red: 0.10, green: 0.45, blue: 0.85), Color(red: 0.35, green: 0.35, blue: 0.95)]
        case .battery: return [Color(red: 0.18, green: 0.70, blue: 0.40), Color(red: 0.55, green: 0.85, blue: 0.30)]
        case .topApps: return [Color(red: 0.90, green: 0.35, blue: 0.20), Color(red: 0.95, green: 0.60, blue: 0.25)]
        case .batteries: return [Color(red: 0.25, green: 0.55, blue: 0.75), Color(red: 0.30, green: 0.75, blue: 0.80)]
        case .quickSettings: return [Color(red: 0.12, green: 0.14, blue: 0.22), Color(red: 0.20, green: 0.22, blue: 0.34)]
        }
    }
}

/// One card. `title` is a localized key passed as a Text so the string checker sees the literal at the call site.
struct WidgetCard<Content: View>: View {
    let widget: PinboardWidget
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            title.font(.system(size: 11, weight: .bold)).textCase(.uppercase).foregroundColor(.white.opacity(0.7))
            content
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: PinboardTheme.width(widget.size), height: PinboardTheme.height(widget.size), alignment: .topLeading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PinboardTheme.corner, style: .continuous)
                    .fill(LinearGradient(colors: PinboardTheme.gradient(widget), startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: PinboardTheme.corner, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            })
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .environment(\.colorScheme, .dark)
    }
}
