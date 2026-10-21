import SwiftUI

/// Phase 56 W3: the iPad-style weather card in the dock slot. A sky plate that follows the reading's
/// condition and hour, the header (temperature, glyph, city) that never moves, and the hourly strip
/// that Medium and Large append (`WeatherLayoutSpec`). The 7-day range rows need height the dock slot
/// does not have; they arrive with the panel (W4).
struct WeatherIPadChip: View {
    let state: WeatherState
    let size: WidgetSize
    @AppStorage(WidgetMotionPreset.storageKey) private var motionPreset: WidgetMotionPreset = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var naturalHeight: CGFloat = 0

    private var tint: SkyTint { SkyTint.tint(condition: state.conditionFamily, isNight: state.isNight) }
    private var ink: Color { tint.prefersDarkText ? Color(white: 0.10) : .white }
    private var reading: Int { Int(round(state.temperatureCelsius)) }

    var body: some View {
        let sky = LinearGradient(colors: [color(tint.top), color(tint.bottom)], startPoint: .top, endPoint: .bottom)
        // Same fit rule as the 3-day pod: width picks the form, height scales it whole to the slot.
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
        .foregroundStyle(ink)
        .background {
            // Static frame in the dock: animated rain on an always-visible chip costs more battery than it earns.
            if WeatherLayoutSpec.showsEffects(for: size) {
                WeatherEffectsView(plan: .plan(condition: state.conditionFamily, isNight: state.isNight), animate: false, cloudOpacity: 0.25)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .dockTileChrome(isHovered: isHovered, fill: sky)
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
            case .small: header(showsRange: false)
            case .medium:
                ViewThatFits(in: .horizontal) { row(slots: 3, showsRange: false); row(slots: 2, showsRange: false); header(showsRange: false) }
            case .large:
                ViewThatFits(in: .horizontal) {
                    row(slots: 5, showsRange: true); row(slots: 4, showsRange: false); row(slots: 3, showsRange: false)
                    row(slots: 2, showsRange: false); header(showsRange: false)
                }
            }
        }
    }

    private func row(slots count: Int, showsRange: Bool) -> some View {
        let slots = WeatherHourSlot.slots(from: state, count: count)
        return HStack(spacing: 8) {
            header(showsRange: showsRange)
            if !slots.isEmpty {
                // The divider only earns its 9 pt once there is room (a 2-slot Medium row is 8 pt short with it).
                if count > 2 { Rectangle().fill(ink.opacity(0.18)).frame(width: 1, height: 26) }
                let hasRain = slots.contains { $0.rainPercent != nil }
                HStack(spacing: 2) { ForEach(slots) { slot in hourSlot(slot, reservesRain: hasRain) } }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func header(showsRange: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: "\(reading)°").font(.system(size: 19, weight: .bold, design: .rounded)).monospacedDigit()
                Image(systemName: state.glyphName).symbolRenderingMode(.multicolor).font(.system(size: 13, weight: .medium))
                if !state.isLive || WeatherStaleness(lastUpdated: state.lastUpdated) == .old {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).opacity(0.75)
                }
            }
            Text(verbatim: state.cityName).font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.85).lineLimit(1)
            if showsRange {
                Text(verbatim: "H:\(Int(round(state.highCelsius)))° L:\(Int(round(state.lowCelsius)))°")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit().opacity(0.7)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func hourSlot(_ slot: WeatherHourSlot, reservesRain: Bool) -> some View {
        VStack(spacing: 2) {
            Group { if slot.isNow { Text("Now") } else { Text(verbatim: slot.hour) } }
                .font(.system(size: 11, weight: slot.isNow ? .bold : .medium, design: .rounded)).opacity(0.8)
            Image(systemName: slot.symbolName).symbolRenderingMode(.multicolor).font(.system(size: 12, weight: .medium)).frame(height: 13)
            Text(verbatim: "\(Int(round(slot.temperatureCelsius)))°").font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
            if reservesRain {
                Text(verbatim: slot.rainPercent.map { "\($0)%" } ?? " ")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.cyan).minimumScaleFactor(0.7)
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private func color(_ c: TileRGB) -> Color { Color(red: c.r, green: c.g, blue: c.b) }
}
