#!/bin/bash
cat << 'INNER' > App/Scenes/TrashChip.swift
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

    private var currentImage: String {
        if isDropTargeted {
            return "TrashRecycle"
        } else if isFull {
            return "TrashFull"
        } else {
            return "TrashEmpty"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(currentImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 2)
                .frame(width: ChipPillMetrics.bareIconSlot * scale, height: ChipPillMetrics.bareIconSlot * scale)
                
            // Standard macOS red badge (dot) for full state
            if isFull {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8 * scale, height: 8 * scale)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.8), lineWidth: 1 * scale)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(x: -2 * scale, y: 2 * scale)
            }
        }
        .frame(width: ChipPillMetrics.cardWidth * scale, height: ChipPillMetrics.chipHeight * scale)
        // Add subtle scale/bounce animation on hover
        .scaleEffect(isHovered ? 1.05 : 1.0, anchor: .bottom)
        .scaleEffect(isDropTargeted ? 1.15 : 1.0, anchor: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0), value: isDropTargeted)
        .animation(.easeInOut(duration: 0.12), value: isFull)
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
INNER
