import SwiftUI

// MARK: - Art tokens
//
// Owner reference samples (4d, 2026-10-09): one gradient family per condition, colours sampled
// straight out of the reference images — sunny = the blue card, cloudy day = the blue pill,
// cloudy night = the indigo/violet card, rain = the teal-green card. Snow/fog have no sample and
// pick the nearest family in the same language (recorded in the 4d check note).

public enum WeatherArt {
    /// (leading, trailing) gradient stops for the condition's card/pill.
    public static func stops(condition: WeatherCondition, isNight: Bool) -> (Color, Color) {
        if isNight, condition == .clear || condition == .partlyCloudy || condition == .cloudy {
            // Sampled: "Cloudy Night" card.
            return (Color(red: 72/255, green: 105/255, blue: 240/255),
                    Color(red: 128/255, green: 114/255, blue: 228/255))
        }
        switch condition {
        case .clear:
            // Sampled: "Sunny" card.
            return (Color(red: 48/255, green: 158/255, blue: 255/255),
                    Color(red: 86/255, green: 180/255, blue: 255/255))
        case .partlyCloudy, .cloudy:
            // Sampled: the "Mostly Cloudy" pill.
            return (Color(red: 45/255, green: 143/255, blue: 210/255),
                    Color(red: 44/255, green: 104/255, blue: 180/255))
        case .rain, .showers, .drizzle, .thunderstorm:
            // Sampled: "Rain" card.
            return (Color(red: 22/255, green: 201/255, blue: 165/255),
                    Color(red: 76/255, green: 225/255, blue: 163/255))
        case .snow:
            return (Color(red: 110/255, green: 190/255, blue: 255/255),
                    Color(red: 190/255, green: 232/255, blue: 255/255))
        case .fog:
            return (Color(red: 120/255, green: 140/255, blue: 165/255),
                    Color(red: 190/255, green: 205/255, blue: 220/255))
        }
    }

    public static func gradient(condition: WeatherCondition, isNight: Bool) -> LinearGradient {
        let (a, b) = stops(condition: condition, isNight: isNight)
        return LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Illustration (drawn, no image assets)

/// The soft-3D spot illustration from the reference cards, built from shapes so it retints with
/// the gradient and scales with the widget (owner decision: drawn in SwiftUI, not assets).
public struct WeatherIllustration: View {
    let condition: WeatherCondition
    let isNight: Bool
    var size: CGFloat = 72

    public init(condition: WeatherCondition, isNight: Bool, size: CGFloat = 72) {
        self.condition = condition
        self.isNight = isNight
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch condition {
            case .clear:
                if isNight { moon } else { sun }
            case .partlyCloudy, .cloudy:
                if isNight {
                    moon.offset(x: size * 0.22, y: -size * 0.26)
                    cloud
                } else if condition == .partlyCloudy {
                    sun.offset(x: size * 0.26, y: -size * 0.30)
                    cloud
                } else {
                    cloud
                }
            case .fog:
                cloud.offset(y: -size * 0.10)
                fogLines
            case .drizzle, .rain, .showers:
                cloud.offset(y: -size * 0.12)
                rainStreaks
            case .thunderstorm:
                cloud.offset(y: -size * 0.14)
                rainStreaks.offset(x: size * 0.10)
                bolt
            case .snow:
                cloud.offset(y: -size * 0.12)
                snowDots
            }
        }
        .frame(width: size, height: size)
    }

    private var sun: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(red: 1, green: 0.93, blue: 0.55),
                             Color(red: 1, green: 0.76, blue: 0.28)],
                    center: .center, startRadius: 1, endRadius: size * 0.34))
                .frame(width: size * 0.62, height: size * 0.62)
            Circle()
                .stroke(Color.white.opacity(0.28), lineWidth: size * 0.045)
                .frame(width: size * 0.86, height: size * 0.86)
        }
    }

    private var moon: some View {
        let (a, b) = WeatherArt.stops(condition: condition, isNight: isNight)
        return ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.92, blue: 0.55),
                                              Color(red: 1, green: 0.78, blue: 0.30)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 0.56, height: size * 0.56)
            // Crescent: punch the background gradient back over the disc (same trick the
            // reference uses — the cut-out is the card's own gradient).
            Circle()
                .fill(LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 0.50, height: size * 0.50)
                .offset(x: -size * 0.16, y: -size * 0.14)
        }
    }

    private var cloud: some View {
        ZStack {
            Capsule()
                .frame(width: size * 0.78, height: size * 0.40)
                .offset(y: size * 0.14)
            Circle()
                .frame(width: size * 0.44, height: size * 0.44)
                .offset(x: -size * 0.14, y: -size * 0.02)
            Circle()
                .frame(width: size * 0.32, height: size * 0.32)
                .offset(x: size * 0.16, y: size * 0.02)
        }
        .foregroundStyle(LinearGradient(
            colors: [.white, Color(red: 0.93, green: 0.95, blue: 0.99)],
            startPoint: .top, endPoint: .bottom))
        .shadow(color: .black.opacity(0.12), radius: size * 0.05, y: size * 0.03)
    }

    private var rainStreaks: some View {
        VStack(spacing: size * 0.08) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: size * 0.05, height: size * 0.20)
                    .offset(x: CGFloat(i) * size * 0.20 - size * 0.20)
            }
        }
        .offset(y: size * 0.34)
        .rotationEffect(.degrees(10))
    }

    private var snowDots: some View {
        VStack(spacing: size * 0.10) {
            ForEach(0..<2, id: \.self) { i in
                HStack(spacing: size * 0.14) {
                    Circle().frame(width: size * 0.08, height: size * 0.08)
                    Circle().frame(width: size * 0.06, height: size * 0.06)
                }
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: i == 0 ? -size * 0.10 : size * 0.10)
            }
        }
        .offset(y: size * 0.34)
    }

    private var fogLines: some View {
        VStack(spacing: size * 0.09) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.85 - Double(i) * 0.2))
                    .frame(width: size * (0.62 - Double(i) * 0.12), height: size * 0.07)
            }
        }
        .offset(y: size * 0.30)
    }

    private var bolt: some View {
        Path { p in
            let u = size
            p.move(to: CGPoint(x: u * 0.46, y: u * 0.16))
            p.addLine(to: CGPoint(x: u * 0.22, y: u * 0.52))
            p.addLine(to: CGPoint(x: u * 0.42, y: u * 0.52))
            p.addLine(to: CGPoint(x: u * 0.30, y: u * 0.84))
            p.addLine(to: CGPoint(x: u * 0.60, y: u * 0.44))
            p.addLine(to: CGPoint(x: u * 0.40, y: u * 0.44))
            p.closeSubpath()
        }
        .fill(Color(red: 1, green: 0.85, blue: 0.30))
        .frame(width: size, height: size)
        .offset(x: size * 0.06)
    }
}

// MARK: - Bar widget (pill)

public struct WeatherChip: View {
    @EnvironmentObject var weatherService: WeatherService
    @Environment(\.widgetSize) private var widgetSize
    @AppStorage("com.katikati.weather.chipPreset") private var chipPreset: WeatherChipPreset = .detailedForecast
    // Phase 32b: the reading morphs with the dock's motion preset; Instant, or Reduce Motion, cuts it.
    @AppStorage(WidgetMotionPreset.storageKey) private var motionPreset: WidgetMotionPreset = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public init() {}

    public var body: some View {
        let state = weatherService.currentState
        // The reading's own sky — its condition at its hour — is what the widget is *about*, so both
        // presets that carry it draw the plate from it (Phase 46: the pod used to be plain dock glass
        // while the pill was already sky, so the same reading looked like two different widgets).
        let sky = chipPreset.usesSkyPlate
            ? WeatherArt.gradient(condition: state.conditionFamily, isNight: state.isNight)
            : nil
        if !state.hasData {
            // No place and no cached forecast: say that, instead of a temperature for a city we made up.
            WeatherNoPlaceHint(needsLocation: weatherService.needsLocation)
                .onTapGesture { WidgetPanelController.weather.toggle() }
        } else if chipPreset.isDetailed {
            DetailedWeatherPodView(state: state, widgetSize: widgetSize, sky: sky)
                .onTapGesture { WidgetPanelController.weather.toggle() }
        } else {
            Group {
                if widgetSize == .small {
                    compactPill(state: state)
                } else {
                    ViewThatFits(in: .horizontal) {
                        fullPill(state: state)
                        compactPill(state: state)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(sky.map { AnyShapeStyle($0) } ?? AnyShapeStyle(DockTileChrome.plate)))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture { WidgetPanelController.weather.toggle() }
        }
    }

    /// Owner sample: condition over city on the left, temperature with its degree ring, spot
    /// illustration on the right.
    private func fullPill(state: WeatherState) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(state.conditionText)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(state.cityName)
                    .font(.system(size: 10, weight: .regular))
                    .opacity(0.85)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(.white)

            Spacer(minLength: 4)

            temperature(state: state, size: widgetSize == .large ? 19 : 17)

            WeatherIllustration(condition: state.conditionFamily,
                                isNight: state.isNight,
                                size: widgetSize == .large ? 28 : 24)
        }
    }

    /// Narrow widget widths (the Settings slider goes down to 60pt): keep the two load-bearing
    /// elements instead of crushing all four.
    private func compactPill(state: WeatherState) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            temperature(state: state, size: 15)
            WeatherIllustration(condition: state.conditionFamily,
                                isNight: state.isNight,
                                size: 20)
        }
    }

    private func temperature(state: WeatherState, size: CGFloat) -> some View {
        let reading = Int(round(state.temperatureCelsius))
        return HStack(alignment: .top, spacing: 1) {
            Text(verbatim: "\(reading)")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .dockReadingMorph(motionPreset.effective(reduceMotion: reduceMotion), value: reading)
            // The reference draws the degree as a small ring, not a glyph.
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1.4)
                .frame(width: size * 0.36, height: size * 0.36)
                .offset(y: size * 0.10)
            if !state.isLive {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: size * 0.5))
                    .opacity(0.75)
                    .offset(y: size * 0.10)
            }
        }
        .foregroundStyle(.white)
    }
}

/// No location and no cached forecast: one honest, tappable glyph in the shared dock plate (the tap opens
/// the panel's city search). Drawn instead of a temperature nobody measured.
struct WeatherNoPlaceHint: View {
    let needsLocation: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 12, weight: .semibold))
            if needsLocation {
                Text("Add City")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            } else {
                Text(verbatim: "—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .dockTileChrome(isHovered: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - Rail tile (Phase 18c)

/// Weather on a side rail: condition glyph over the temperature, in the same 40 × 40 chrome as the app
/// chips and the FABs beside it (Phase 40b/40f — it used to be 44 × 56 on a 10 pt-radius weather gradient,
/// so it read as a different dock from the 40 pt icons it sat among). Drawn at native size; the strip
/// scales it by `dockScale` like every other rail metric.
struct RailWeatherTile: View {
    @EnvironmentObject var weatherService: WeatherService
    @State private var isHovered = false

    var body: some View {
        let state = weatherService.currentState
        VStack(spacing: 1) {
            // Same rule as the bar chip: with no forecast there is no temperature to print, only the
            // mark that a place is missing (the tap below opens the panel's city search).
            Image(systemName: state.hasData ? state.glyphName : "location.slash.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14, weight: .semibold))
            if state.hasData {
                Text(verbatim: "\(Int(round(state.temperatureCelsius)))°")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: BarSection.railTileSize, height: BarSection.railTileSize)
        .dockTileChrome(isHovered: isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { WidgetPanelController.weather.toggle() }
    }
}

// MARK: - Widget size (Phase 10a-2)

/// The laid-out height of the pod's width-chosen form, so the whole form can scale to the slot.
/// Measured on an unscaled copy (transforms don't change layout), so the scale never feeds back.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContentHeightReader: View {
    var body: some View {
        GeometryReader { measure in
            Color.clear.preference(key: ContentHeightKey.self, value: measure.size.height)
        }
    }
}

private struct WidgetSizeKey: EnvironmentKey {
    static let defaultValue: WidgetSize = .medium
}

extension EnvironmentValues {
    /// The S/M/L preset the strip resolved for the chip being drawn.
    var widgetSize: WidgetSize {
        get { self[WidgetSizeKey.self] }
        set { self[WidgetSizeKey.self] = newValue }
    }
}

// MARK: - Detailed Weather Pod (Phase 32)

private struct DetailedWeatherPodView: View {
    let state: WeatherState
    let widgetSize: WidgetSize
    /// The reading's condition + hour sky as the pod's plate; `nil` keeps the shared dock glass.
    let sky: LinearGradient?
    // Phase 32b: one morph for all three sizes — the plate never changes, its reading does.
    @AppStorage(WidgetMotionPreset.storageKey) private var motionPreset: WidgetMotionPreset = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        // The slot is a fixed width (`WidgetSize.widgetWidth`) and this pod's own content can be wider
        // than it — the three forecast columns used to run past the plate into the widget beside it
        // (Phase 43). Same auto-degrade the classic pill already uses: draw the widest form that fits
        // the slot, never a form that overflows it, and never larger than the size the user picked.
        // The slot is also a fixed height (bar height minus insets, ~40pt on a 47pt bar) and the pod's
        // forecast forms are taller than that — width-only fitting stuck the pod out over the top of
        // the dock (2026-10-17). Height is not a second degrade axis: dropping to the compact pill hid
        // the forecast the dock is for. So width picks the form, height scales it whole to the slot —
        // the forecast stays, inside the dock, text and spacing proportional.
        GeometryReader { geo in
            widthLadder
                .frame(width: geo.size.width)
                .background(ContentHeightReader())
                .scaleEffect(SlotFitScale.scale(naturalHeight: naturalHeight, availableHeight: geo.size.height),
                             anchor: .center)
                .frame(width: geo.size.width, height: geo.size.height)
                .onPreferenceChange(ContentHeightKey.self) { naturalHeight = $0 }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        // Phase 40f: the FABs' own chrome, so the pod and the buttons beside it cannot drift
        // (it used to hover at 1.02 / damping 0.72 against the FABs' 1.04 / 0.75). Phase 46 hands it
        // the sky when the preset asks for it — same chrome, same hover, a different plate.
        .dockTileChrome(isHovered: isHovered, fill: sky)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .dockReadingMorph(motionPreset.effective(reduceMotion: reduceMotion),
                          value: Int(round(state.temperatureCelsius)))
    }

    /// Width picks the form (never larger than the size the user picked); height scales it.
    private var widthLadder: some View {
        Group {
            switch widgetSize {
            case .small:
                compactDetailedView
            case .medium:
                ViewThatFits(in: .horizontal) {
                    mediumDetailedView
                    compactDetailedView
                }
            case .large:
                ViewThatFits(in: .horizontal) {
                    largeDetailedView
                    mediumDetailedView
                    compactDetailedView
                }
            }
        }
    }

    private var compactDetailedView: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "\(Int(round(state.temperatureCelsius)))°")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(state.cityName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(1)
            }

            Image(systemName: state.glyphName)
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.multicolor)
        }
    }

    private var mediumDetailedView: some View {
        HStack(spacing: 8) {
            // Left column: Current temperature & city
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(verbatim: "\(Int(round(state.temperatureCelsius)))°")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Image(systemName: state.glyphName)
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                }

                Text(state.cityName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.80))
                    .lineLimit(1)
            }

            // Right column: the feed's own days, one equal-width column each so the two sides balance
            // (Phase 40a: `weekdayLabel()`, never the raw API date — that printed as "2026-…").
            // No days → no divider and no columns; the temperature and the city stand alone.
            if !forecastItems.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 24)

                HStack(spacing: 6) {
                    ForEach(forecastItems) { item in
                        VStack(spacing: 2) {
                            Text(verbatim: item.weekdayLabel())
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Image(systemName: item.symbolName)
                                .font(.system(size: 10.5, weight: .medium))
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 12)

                            Text(verbatim: "\(Int(round(item.highCelsius)))°")
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var largeDetailedView: some View {
        HStack(spacing: 10) {
            // Left column: Temp + Icon, City, High/Low
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(Int(round(state.temperatureCelsius)))°")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Image(systemName: state.glyphName)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                }

                Text(state.cityName)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)

                Text(verbatim: "H:\(Int(round(state.highCelsius)))° L:\(Int(round(state.lowCelsius)))°")
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.65))
            }

            // Right: the feed's own days, one equal-width column each so the two sides balance
            // (Phase 40a: `weekdayLabel()`, never the raw API date).
            // No days → no divider and no columns; the temperature and the city stand alone.
            if !forecastItems.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 1, height: 26)

                HStack(spacing: 6) {
                    ForEach(forecastItems) { item in
                        VStack(spacing: 3) {
                            Text(verbatim: item.weekdayLabel())
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Image(systemName: item.symbolName)
                                .font(.system(size: 12, weight: .medium))
                                .symbolRenderingMode(.multicolor)
                                .frame(height: 13)

                            HStack(spacing: 2) {
                                Text(verbatim: "\(Int(round(item.highCelsius)))°")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                Text(verbatim: "\(Int(round(item.lowCelsius)))°")
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.62))
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The feed's own days — a short or empty forecast shows fewer columns, never invented ones.
    private var forecastItems: [DailyForecast] { state.threeDayForecast }
}

