import SwiftUI

/// Phase 56 W8: the Modern weather card in the dock slot. Flat graphite, a light-weight numeral, one
/// accent dot, and the next hours as a single thin line (no sky, no glyph art). Same size ladder as the
/// iPad card: Small is the header, Medium adds the line, Large adds the range and condition.
struct WeatherModernChip: View {
    let state: WeatherState
    let size: WidgetSize
    @AppStorage(WidgetMotionPreset.storageKey) private var motionPreset: WidgetMotionPreset = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var naturalHeight: CGFloat = 0

    private static let ink = Color(white: 0.96)
    private var accent: Color {
        let c = WeatherModernSpec.accent(condition: state.conditionFamily, isNight: state.isNight)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
    private var reading: Int { Int(round(state.temperatureCelsius)) }
    private var plate: LinearGradient {
        let c = Color(white: 0.085)
        return LinearGradient(colors: [c, c], startPoint: .top, endPoint: .bottom)
    }

    var body: some View {
        GeometryReader { geo in
            ladder
                .frame(width: geo.size.width)
                .background(ContentHeightReader())
                .scaleEffect(SlotFitScale.scale(naturalHeight: naturalHeight, availableHeight: geo.size.height), anchor: .center)
                .frame(width: geo.size.width, height: geo.size.height)
                .onPreferenceChange(ContentHeightKey.self) { naturalHeight = $0 }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(Self.ink)
        .dockTileChrome(isHovered: isHovered, fill: plate)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .dockReadingMorph(motionPreset.effective(reduceMotion: reduceMotion), value: reading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(state.cityName), \(reading)°, \(state.conditionText)"))
        .accessibilityAddTraits(.isButton)
    }

    private var ladder: some View {
        Group {
            switch size {
            case .small: header(detail: false)
            case .medium: ViewThatFits(in: .horizontal) { row(hours: 4, detail: false); row(hours: 3, detail: false); header(detail: false) }
            case .large:
                ViewThatFits(in: .horizontal) { row(hours: 6, detail: true); row(hours: 4, detail: false); row(hours: 3, detail: false); header(detail: false) }
            }
        }
    }

    private func row(hours count: Int, detail: Bool) -> some View {
        let slots = WeatherHourSlot.slots(from: state, count: count)
        return HStack(spacing: 10) {
            header(detail: detail)
            if slots.count > 1 {
                VStack(spacing: 2) {
                    HourLine(fractions: WeatherModernSpec.fractions(slots.map(\.temperatureCelsius)), accent: accent)
                        .frame(height: 20)
                    HStack {
                        ForEach(slots) { slot in
                            if slot.isNow { Text("Now") } else { Text(verbatim: slot.hour) }
                            if slot.id != slots.last?.id { Spacer(minLength: 0) }
                        }
                    }
                    .font(.system(size: 11, weight: .regular)).monospacedDigit().lineLimit(1).opacity(0.58)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func header(detail: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(verbatim: state.cityName).font(.system(size: 11, weight: .regular)).opacity(0.58).lineLimit(1)
                if !state.isLive || WeatherStaleness(lastUpdated: state.lastUpdated) == .old {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).opacity(0.6)
                }
            }
            Text(verbatim: "\(reading)°").font(.system(size: 26, weight: .light)).monospacedDigit().kerning(-1)
            if detail {
                Text(verbatim: "\(state.conditionText) · \(Int(round(state.highCelsius)))/\(Int(round(state.lowCelsius)))")
                    .font(.system(size: 11, weight: .regular)).monospacedDigit().opacity(0.58).lineLimit(1)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// The hourly line: a thin polyline across the width with an accent dot on one hour (the first by default).
struct HourLine: View {
    let fractions: [Double]
    let accent: Color
    var dot = 0

    var body: some View {
        Canvas { ctx, size in
            let n = fractions.count
            let pts = fractions.enumerated().map { i, f in
                CGPoint(x: 4 + CGFloat(i) * (size.width - 8) / CGFloat(max(n - 1, 1)), y: size.height - 4 - CGFloat(f) * (size.height - 8))
            }
            var path = Path()
            path.addLines(pts)
            ctx.stroke(path, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            if pts.indices.contains(dot) { let p = pts[dot]; ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(accent)) }
        }
    }
}
