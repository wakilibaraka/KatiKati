import AppKit
import SwiftUI

struct TrashChip: View {
    let isFull: Bool
    let isDropTargeted: Bool
    let scale: CGFloat
    let hoverStyle: HoverStyle
    let isHovered: Bool
    let menuItems: [TrashMenuPlan.Item]
    let onTap: () -> Void
    let onOpen: () -> Void
    let onEmpty: () -> Void
    @State private var isPressed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: isFull ? "trash.fill" : "trash")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(
                    LinearGradient(
                        colors: isFull ? [.red.opacity(0.8), .red] : [.gray.opacity(0.7), .gray],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 2)
                .frame(width: ChipPillMetrics.bareIconSlot * scale, height: ChipPillMetrics.bareIconSlot * scale)
                
            // Dynamic badge placeholder (dot or count)
            if isFull {
                Circle()
                    .fill(Color.red)
                    .frame(width: 4 * scale, height: 4 * scale)
                    .padding(.top, 2 * scale)
            }
        }
        .frame(width: ChipPillMetrics.cardWidth * scale, height: ChipPillMetrics.chipHeight * scale)
        .scaleEffect(isDropTargeted ? 1.08 : 1, anchor: .bottom)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
        .chipQuietHoverScale(hoverStyle.showsQuietHoverFeedback(isHovering: isHovered),
                             cardWidth: ChipPillMetrics.cardWidth * scale, scale: scale)
        .chipPressScale(isPressed)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .chipPressGesture(isPressed: $isPressed)
        .nativeContextMenu { buildMenu() }
        .help(String(localized: "Trash"))
        .accessibilityLabel(String(localized: "Trash"))
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in menuItems {
            switch item {
            case .open:
                menu.addItem(ClosureMenuItem(String(localized: "Open Trash"), handler: onOpen))
            case let .empty(enabled):
                let row = ClosureMenuItem(String(localized: "Empty Trash…"), handler: onEmpty)
                row.isEnabled = enabled
                menu.addItem(row)
            }
        }
        return menu
    }
}

