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
