import SwiftUI

/// Dictionary / Terminal as dock widgets: a compact glyph tile (no size presets). A click opens the panel.
private struct ToolDockChip: View {
    let symbol: String
    let label: LocalizedStringKey
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .opacity(DockWidgetStyle.secondaryOpacity)
        }
        .frame(maxHeight: .infinity)
        .dockWidgetChip()
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(.isButton)
    }
}

struct DictionaryDockChip: View {
    let onOpen: () -> Void
    var body: some View { ToolDockChip(symbol: "character.book.closed", label: "Define…", onOpen: onOpen) }
}

struct TerminalDockChip: View {
    let onOpen: () -> Void
    var body: some View { ToolDockChip(symbol: "terminal", label: "Terminal", onOpen: onOpen) }
}

struct RailDictionaryTile: View {
    var body: some View {
        Image(systemName: "character.book.closed")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .dockWidgetRailTile()
            .accessibilityLabel(Text("Dictionary"))
    }
}

struct RailTerminalTile: View {
    var body: some View {
        Image(systemName: "terminal")
            .font(.system(size: 13, weight: .semibold))
            .frame(width: 28, height: 28)
            .dockWidgetRailTile()
            .accessibilityLabel(Text("Terminal"))
    }
}
