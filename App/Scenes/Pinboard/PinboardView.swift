import SwiftUI

/// The Pinboard page: a vertical stack of rows from `PinboardLayout`, scrolling when taller than the screen.
struct PinboardView: View {
    let widgets: [PinboardWidget]
    let context: PinboardContext

    var body: some View {
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
    }
}
