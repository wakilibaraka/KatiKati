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
            // Central icon rendered with ideal proportions (26pt glyph)
            LauncherIconView(style: settingsStore.launcherIcon, size: 26)
        }
        .frame(width: 40, height: 40)
        // The plate is the shared one now (Phase 40f) — this button is one of the two the recipe was
        // named after, so its pixels are unchanged.
        .dockTileChrome(isHovered: isHovered)
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
