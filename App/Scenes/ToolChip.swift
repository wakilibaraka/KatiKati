import AppKit
import SwiftUI

/// Strip chip for Dictionary / Terminal: an opaque rounded tile with an SF glyph, shaped like the Shelf's
/// fallback tile so it sits beside it. Click opens the panel; not draggable.
struct ToolChip: View {
    let symbol: String
    let tint: Color
    let help: String
    /// Strip size-tier scale. Deliberately no default — a missed call site must not compile (AGENTS: Taskbar Size Tiers).
    let scale: CGFloat
    let railTile: Bool
    let hoverStyle: HoverStyle
    let isHovered: Bool
    let onTap: () -> Void

    private var quietHoverFeedback: Bool { hoverStyle.showsQuietHoverFeedback(isHovering: isHovered) }

    var body: some View {
        let art = ChipPillMetrics.bareIconVisibleSlot * scale
        ZStack {
            RoundedRectangle(cornerRadius: art * 0.215, style: .continuous).fill(tint)
            Image(systemName: symbol)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: art * 0.52, height: art * 0.52)
                .foregroundStyle(.white)
        }
        .frame(width: art, height: art)
        .frame(width: ChipPillMetrics.bareIconSlot * scale, height: ChipPillMetrics.bareIconSlot * scale)
        .frame(width: ChipPillMetrics.cardWidth * scale,
               height: ChipPillMetrics.cardFrameHeight(scale, onRail: railTile))
        .chipQuietHoverScale(quietHoverFeedback, cardWidth: ChipPillMetrics.cardWidth * scale, scale: scale)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .help(help)
    }
}
