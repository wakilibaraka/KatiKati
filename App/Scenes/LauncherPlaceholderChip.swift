import SwiftUI

public struct LauncherPlaceholderChip: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var settingsStore: AppSettingsStore
    
    @State private var isHovering = false
    
    public init() {}
    
    private var theme: DockThemeTokens { .resolved(for: colorScheme, style: settingsStore.themeMaterial) }
    
    public var body: some View {
        Button(action: {
            // Placeholder action
        }) {
            ZStack {
                // Same base background geometry as the drawer capsule
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0.05))
                    .frame(width: 36, height: 36) // Adjust width to be standard for apps strip icons
                
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .help("Launcher")
    }
}
