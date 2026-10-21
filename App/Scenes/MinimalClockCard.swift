import SwiftUI

/// Phase 56 resize pass: the Modern weather card's look for the clock — flat graphite, a light numeral,
/// one accent dot, the date as a quiet second line. Small is the time; Medium and Large add the date.
struct MinimalClockCard: View {
    let content: ClockContent
    let widgetSize: WidgetSize
    @State private var isHovered = false

    private var plate: LinearGradient {
        let c = Color(white: 0.085)
        return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.97, green: 0.58, blue: 0.24)).frame(width: 6, height: 6)
                if widgetSize != .small, let date = content.secondaryText {
                    Text(verbatim: date).font(.system(size: 11, weight: .regular)).opacity(0.58).lineLimit(1)
                }
            }
            Text(verbatim: content.primaryText)
                .font(.system(size: widgetSize == .large ? 28 : 24, weight: .light)).monospacedDigit().kerning(-1)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(Color(white: 0.96))
        .dockTileChrome(isHovered: isHovered, fill: plate)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [content.primaryText, content.secondaryText].compactMap { $0 }.joined(separator: ", ")))
    }
}
