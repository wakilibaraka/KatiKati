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
    @EnvironmentObject var runtime: AppRuntime
    @State private var showingDetail = false

    public init() {}

    public var body: some View {
        let state = weatherService.currentState
        let art = WeatherArt.gradient(condition: state.conditionFamily, isNight: state.isNight)

        // ViewThatFits is macOS 13+; the floor is 12, so the fallback there is the full layout
        // with its labels truncating (the compact pill is a nicety, not a requirement).
        Group {
            if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    fullPill(state: state, art: art)
                    compactPill(state: state, art: art)
                }
            } else {
                fullPill(state: state, art: art)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(art))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { showingDetail = true }
        .popover(isPresented: $showingDetail, arrowEdge: .top) {
            WeatherPopupView()
        }
    }

    /// Owner sample: condition over city on the left, temperature with its degree ring, spot
    /// illustration on the right.
    private func fullPill(state: WeatherState, art: LinearGradient) -> some View {
        HStack(spacing: 8) {
            Button(action: {
                runtime.onToggleDrawer?()
            }) {
                Image(systemName: "macstudio")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Launcher"))
            
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 1, height: 20)
                
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

            temperature(state: state, size: 17)

            WeatherIllustration(condition: state.conditionFamily,
                                isNight: state.isNight,
                                size: 24)
        }
    }

    /// Narrow widget widths (the Settings slider goes down to 60pt): keep the two load-bearing
    /// elements instead of crushing all four.
    private func compactPill(state: WeatherState, art: LinearGradient) -> some View {
        HStack(spacing: 6) {
            Button(action: {
                runtime.onToggleDrawer?()
            }) {
                Image(systemName: "macstudio")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Launcher"))
            
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(width: 1, height: 16)
                
            Spacer(minLength: 0)
            temperature(state: state, size: 15)
            WeatherIllustration(condition: state.conditionFamily,
                                isNight: state.isNight,
                                size: 20)
        }
    }

    private func temperature(state: WeatherState, size: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 1) {
            Text(verbatim: "\(Int(round(state.temperatureCelsius)))")
                .font(.system(size: size, weight: .semibold, design: .rounded))
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

// MARK: - Popup (card)

/// The full reference card: condition label, big temperature with its ring, divider, date and
/// city, spot illustration — on the condition's gradient. Opens from the pill (owner sample).
public struct WeatherPopupView: View {
    @EnvironmentObject var weatherService: WeatherService

    public init() {}

    public var body: some View {
        let state = weatherService.currentState
        let art = WeatherArt.gradient(condition: state.conditionFamily, isNight: state.isNight)

        VStack(alignment: .leading, spacing: 12) {
            Text(state.conditionText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)

            HStack(alignment: .top, spacing: 14) {
                HStack(alignment: .top, spacing: 2) {
                    Text(verbatim: "\(Int(round(state.temperatureCelsius)))")
                        .font(.system(size: 40, weight: .light, design: .rounded))
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 2)
                        .frame(width: 12, height: 12)
                        .offset(y: 6)
                }
                .foregroundStyle(.white)

                Rectangle()
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 1, height: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.system(size: 13, weight: .regular))
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 11))
                        Text(state.cityName)
                            .font(.system(size: 13, weight: .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .foregroundStyle(.white.opacity(0.95))

                Spacer(minLength: 0)

                WeatherIllustration(condition: state.conditionFamily,
                                    isNight: state.isNight,
                                    size: 72)
            }
        }
        .padding(18)
        .frame(width: 320, alignment: .leading)
        .background(art)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
