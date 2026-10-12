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

/// The full-screen widget wall (Phase 7B): the same two-column coloured card grid as `PinboardView`,
/// centered on the screen over the launcher backdrop. Cards are unchanged — full-screen is a frame,
/// not a re-skin. A tap outside the grid closes the wall (same as the launcher's background tap).
struct PinboardFullScreenView: View {
    let widgets: [PinboardWidget]
    let context: PinboardContext
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: PinboardTheme.gap) {
                    ForEach(Array(PinboardLayout.rows(widgets).enumerated()), id: \.offset) { _, row in
                        HStack(spacing: PinboardTheme.gap) {
                            ForEach(row, id: \.self) { PinboardWidgetView(widget: $0, context: context) }
                        }
                    }
                }
                .padding(PinboardTheme.gap)
            }
            .frame(width: PinboardTheme.panelWidth + PinboardTheme.gap * 2)
            .padding(.vertical, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text("Pinboard"))
    }
}
