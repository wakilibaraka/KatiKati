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

/// The full-screen widget wall (Phase 7B): the same coloured card grid as the floating panel, now a
/// wide wall that fills the screen instead of a narrow two-column column that scrolls forever.
/// Slots come from `PinboardLayout.wall` — a small takes one column, a wide two, a large starts a tall
/// row so the smalls stack beside it. A tap outside the grid closes the wall (same as the launcher).
struct PinboardFullScreenView: View {
    let widgets: [PinboardWidget]
    let context: PinboardContext
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001).onTapGesture(perform: onClose)
            GeometryReader { geo in
                let columns = PinboardFullScreen.columns(forWidth: geo.size.width)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: PinboardTheme.gap) {
                        ForEach(Array(PinboardLayout.wall(widgets, columns: columns).enumerated()), id: \.offset) {
                            _, row in
                            wallRow(row)
                        }
                    }
                    .padding(PinboardTheme.gap)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(Text("Pinboard"))
    }

    /// A wall row — cards left to right, whatever their height. Rows are packed by
    /// `PinboardLayout.wall`, so a row that opens with the tall Quick Settings card carries the smalls
    /// that follow stacked two per column beside it, keeping the row's height to the card's.
    @ViewBuilder private func wallRow(_ row: [PinboardWidget]) -> some View {
        if row.first?.size == .large, let first = row.first {
            HStack(alignment: .top, spacing: PinboardTheme.gap) {
                PinboardWidgetView(widget: first, context: context)
                ForEach(Array(pairs(Array(row.dropFirst())).enumerated()), id: \.offset) { _, stack in
                    VStack(spacing: PinboardTheme.gap) {
                        ForEach(stack, id: \.self) { PinboardWidgetView(widget: $0, context: context) }
                    }
                }
            }
        } else {
            HStack(alignment: .top, spacing: PinboardTheme.gap) {
                ForEach(row, id: \.self) { PinboardWidgetView(widget: $0, context: context) }
            }
        }
    }

    /// Split the smalls of a tall row into stacks of two, so each column beside the large card keeps
    /// the same 2-unit height (small + gap + small == large's height).
    private func pairs(_ rest: [PinboardWidget]) -> [[PinboardWidget]] {
        stride(from: 0, to: rest.count, by: 2).map { i in
            Array(rest[i..<min(i + 2, rest.count)])
        }
    }
}
