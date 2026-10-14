import SwiftUI

/// Launcher FAB button on the far left of the Dock, perfectly matching
/// the 40x40 continuous squircle container, dark glass backdrop, elevation shadow,
/// and spring hover physics of the Wi-Fi/Volume and RAM/CPU buttons on the right.
struct LauncherFABView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    var onTap: (() -> Void)?

    @State private var isHovered = false

    init(settingsStore: AppSettingsStore, onTap: (() -> Void)? = nil) {
        self.settingsStore = settingsStore
        self.onTap = onTap
    }

    public var body: some View {
        ZStack {
            // Container backdrop matching WiFiVolumeFABView & DynamicGaugeFABView
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.11, green: 0.12, blue: 0.16).opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isHovered ? Color.white.opacity(0.28) : Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(isHovered ? 0.32 : 0.16), radius: isHovered ? 6 : 3, x: 0, y: 2)

            // Central icon rendered with ideal proportions (26pt glyph)
            LauncherIconView(style: settingsStore.launcherIcon, size: 26)
        }
        .frame(width: 40, height: 40)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isHovered)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap?()
        }
        .help(Text(verbatim: "Launcher"))
    }
}
