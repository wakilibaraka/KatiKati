import CoreGraphics
import Foundation

// Phase 9-0 — geometry of the floating chip panel (preview + jump list). Pure and derived: the
// window size is computed from the content counts, never measured, so the panel can be placed
// before SwiftUI lays out (same rule as `StackPopupChrome`).

enum ChipPanelLayout {
    static let plateInset: CGFloat = 12
    static let cardSpacing: CGFloat = 10
    static let titleHeight: CGFloat = 20
    static let headerHeight: CGFloat = 28
    static let maxColumns = 4
    static let maxRows = 3
    static let maxPreviewCards = maxColumns * maxRows

    static let menuWidth: CGFloat = 264
    static let menuRowHeight: CGFloat = 26
    static let menuHeaderHeight: CGFloat = 38
    static let menuSeparatorHeight: CGFloat = 9
    static let menuSectionLabelHeight: CGFloat = 20

    struct PreviewGrid: Equatable {
        let columns: Int
        let rows: Int
        let shown: Int
        let hidden: Int
    }

    static func previewGrid(count: Int) -> PreviewGrid {
        guard count > 0 else { return PreviewGrid(columns: 0, rows: 0, shown: 0, hidden: 0) }
        let shown = min(count, maxPreviewCards)
        let columns = min(shown, maxColumns)
        let rows = Int((Double(shown) / Double(columns)).rounded(.up))
        return PreviewGrid(columns: columns, rows: rows, shown: shown, hidden: count - shown)
    }

    static func previewPlateSize(count: Int, thumb: CGSize) -> CGSize {
        let grid = previewGrid(count: count)
        guard grid.shown > 0 else { return .zero }
        let cardH = thumb.height + titleHeight
        let width = CGFloat(grid.columns) * thumb.width + CGFloat(grid.columns - 1) * cardSpacing + 2 * plateInset
        let height = CGFloat(grid.rows) * cardH + CGFloat(grid.rows - 1) * cardSpacing + 2 * plateInset
            + (grid.hidden > 0 ? titleHeight : 0)
        return CGSize(width: width, height: height)
    }

    static func menuPlateSize(windowRows: Int, recentRows: Int, actionRows: Int,
                              actionSeparators: Int = 0, hasHeader: Bool = true) -> CGSize {
        var height = plateInset / 2 + (hasHeader ? menuHeaderHeight : 0)
        if windowRows > 0 { height += menuSeparatorHeight + CGFloat(windowRows) * menuRowHeight }
        if recentRows > 0 { height += menuSeparatorHeight + menuSectionLabelHeight + CGFloat(recentRows) * menuRowHeight }
        if actionRows > 0 {
            height += (hasHeader || windowRows > 0 || recentRows > 0 ? menuSeparatorHeight : 0)
                + CGFloat(actionRows) * menuRowHeight + CGFloat(actionSeparators) * menuSeparatorHeight
        }
        return CGSize(width: menuWidth, height: height + plateInset / 2)
    }

    struct Placement: Equatable {
        /// The panel window's frame (plate + arrow strip + transparent shadow margin).
        let panelFrame: CGRect
        /// Arrow centre minus plate centre, for `StackPopupArrowModel`.
        let arrowOffsetFromCenter: CGFloat
    }

    /// Centres the plate over `anchor` (screen coordinates, y up), clamps it inside `screen`, and keeps
    /// the arrow pointing at the anchor.
    static func placement(
        anchor: CGRect,
        plate: CGSize,
        screen: CGRect,
        margin: CGFloat = StackPopupMetrics.panelMargin,
        arrowHeight: CGFloat = StackPopupMetrics.arrowHeight,
        tipGap: CGFloat = StackPopupMetrics.tipGap,
        screenMargin: CGFloat = 8,
        arrowInset: CGFloat = StackPopupMetrics.arrowInset,
        stripPlacement: StripPlacement = .bottom
    ) -> Placement {
        if stripPlacement.isVertical {
            // Beside a side rail (Phase 18d): inward of the anchor, vertically centred, clamped to
            // the screen; no arrow (the caller hides it), so the arrow strip stays empty.
            let height = plate.height + arrowHeight + 2 * margin
            let width = plate.width + 2 * margin
            let x = stripPlacement == .right
                ? anchor.minX - tipGap + margin - width
                : anchor.maxX + tipGap - margin
            let minY = screen.minY + screenMargin - margin
            let maxY = screen.maxY - screenMargin + margin - height
            let desired = anchor.midY - height / 2
            let y = maxY >= minY ? min(max(desired, minY), maxY) : minY
            return Placement(panelFrame: CGRect(x: x, y: y, width: width, height: height), arrowOffsetFromCenter: 0)
        }
        let minX = screen.minX + screenMargin
        let maxX = screen.maxX - screenMargin - plate.width
        let desired = anchor.midX - plate.width / 2
        let plateX = maxX >= minX ? min(max(desired, minX), maxX) : minX
        // The arrow's tip sits `tipGap` above the anchor; the plate sits above the arrow strip.
        let panelFrame = CGRect(
            x: plateX - margin,
            y: anchor.maxY + tipGap - margin,
            width: plate.width + 2 * margin,
            height: plate.height + arrowHeight + 2 * margin
        )
        let limit = max(0, plate.width / 2 - arrowInset)
        let offset = min(max(anchor.midX - (plateX + plate.width / 2), -limit), limit)
        return Placement(panelFrame: panelFrame, arrowOffsetFromCenter: offset)
    }

    /// The visible plate (arrow strip included) inside a panel frame — the pointer hit area.
    static func plateFrame(panelFrame: CGRect, margin: CGFloat = StackPopupMetrics.panelMargin) -> CGRect {
        panelFrame.insetBy(dx: margin, dy: margin)
    }
}
