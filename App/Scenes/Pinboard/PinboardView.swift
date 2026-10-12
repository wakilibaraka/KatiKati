import SwiftUI

/// The Pinboard page: a vertical stack of rows from `PinboardLayout`, scrolling when taller than the screen.
struct PinboardView: View {
    let widgets: [PinboardWidget]
    let context: PinboardContext

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: PinboardTheme.gap) {
                // Grab handle: the whole panel drags, this just says so.
                Capsule().fill(Color.primary.opacity(0.28)).frame(width: 38, height: 4).frame(maxWidth: .infinity)
                ForEach(Array(PinboardLayout.rows(widgets).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: PinboardTheme.gap) {
                        ForEach(row, id: \.self) { PinboardWidgetView(widget: $0, context: context) }
                    }
                }
            }
            .padding(PinboardTheme.gap)
        }
        .frame(width: PinboardTheme.panelWidth + PinboardTheme.gap * 2)
    }
}

/// The full-screen widget wall (Phase 7B): every enabled card on one dense grid (`PinboardGrid`), scaled up so the
/// wall fills the screen like the launcher does — no long scroll, no empty half. Cards keep their design size and are
/// scaled as a whole, so text and rings grow with them. A tap outside the grid closes the wall.
struct PinboardFullScreenView: View {
    let widgets: [PinboardWidget]
    let context: PinboardContext
    let onClose: () -> Void

    /// Clear of the menu bar / notch above and KatiKati's own bar below.
    private static let topInset: CGFloat = 64
    private static let bottomInset: CGFloat = 100
    private static let sideInset: CGFloat = 48

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            GeometryReader { geo in
                let availW = max(1, geo.size.width - Self.sideInset * 2)
                let availH = max(1, geo.size.height - Self.topInset - Self.bottomInset)
                let fit = PinboardGrid.fit(widgets, width: Double(availW), height: Double(availH),
                                           unit: Double(PinboardTheme.unit), gap: Double(PinboardTheme.gap))
                let layout = PinboardGrid.pack(widgets, columns: fit.columns)
                let unit = PinboardTheme.unit, gap = PinboardTheme.gap
                let designW = CGFloat(fit.columns) * unit + CGFloat(fit.columns - 1) * gap
                let designH = CGFloat(fit.rows) * unit + CGFloat(max(0, fit.rows - 1)) * gap
                let scale = CGFloat(fit.scale)
                ZStack(alignment: .topLeading) {
                    ForEach(Array(layout.cells.enumerated()), id: \.offset) { _, cell in
                        PinboardWidgetView(widget: cell.widget, context: context)
                            .offset(x: CGFloat(cell.col) * (unit + gap), y: CGFloat(cell.row) * (unit + gap))
                    }
                }
                .frame(width: designW, height: designH, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: designW * scale, height: designH * scale, alignment: .topLeading)
                .position(x: geo.size.width / 2,
                          y: Self.topInset + availH / 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text("Pinboard"))
    }
}
