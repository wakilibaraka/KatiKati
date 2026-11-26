import SwiftUI

/// Color, typography, and size tokens tuned for `#000000` hardware OLED and ProMotion macOS surfaces,
/// matching `opencoredev/islandcn/components/islandcn/theme.ts`.
enum IslandTheme {
    enum Accent {
        static let lagoon = Color(red: 0x46 / 255.0, green: 0xF0 / 255.0, blue: 0xC6 / 255.0)
        static let green = Color(red: 0x32 / 255.0, green: 0xD7 / 255.0, blue: 0x4B / 255.0)
        static let chargingGreen = Color(red: 0x53 / 255.0, green: 0xFA / 255.0, blue: 0x6D / 255.0)
        static let red = Color(red: 0xFF / 255.0, green: 0x45 / 255.0, blue: 0x3A / 255.0)
        static let orange = Color(red: 0xFF / 255.0, green: 0x9F / 255.0, blue: 0x0A / 255.0)
        static let yellow = Color(red: 0xFF / 255.0, green: 0xD6 / 255.0, blue: 0x0A / 255.0)
        static let blue = Color(red: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0)
        static let sky = Color(red: 0x64 / 255.0, green: 0xD2 / 255.0, blue: 0xFF / 255.0)
        static let pink = Color(red: 0xFF / 255.0, green: 0x37 / 255.0, blue: 0x5F / 255.0)
        static let purple = Color(red: 0xBF / 255.0, green: 0x5A / 255.0, blue: 0xF2 / 255.0)
        static let indigo = Color(red: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0)
    }

    enum Ink {
        static let primary = Color.white
        static let secondary = Color(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0).opacity(0.62)
        static let tertiary = Color(red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 245.0 / 255.0).opacity(0.36)
        static let track = Color.white.opacity(0.16)
        static let fill = Color.white.opacity(0.14)
        static let fillPressed = Color.white.opacity(0.24)
    }

    enum Size {
        static let compactGlyph: CGFloat = 22
        static let compactText: CGFloat = 15
        static let expandedTile: CGFloat = 52
        static let expandedTileRadius: CGFloat = 12
        static let expandedValue: CGFloat = 34
        static let title: CGFloat = 17
        static let subtitle: CGFloat = 15
        static let caption: CGFloat = 13
        static let button: CGFloat = 44
    }
}

/// SwiftUI `Shape` wrapping our pure `continuousRectCGPath` (`smoothing = 0.72`).
struct IslandContinuousRectShape: Shape {
    var radius: CGFloat
    var smoothing: CGFloat = 0.72
    var leadingRadius: CGFloat? = nil

    func path(in rect: CGRect) -> Path {
        Path(
            continuousRectCGPath(
                x: Double(rect.minX),
                y: Double(rect.minY),
                width: Double(rect.width),
                height: Double(rect.height),
                radius: Double(radius),
                smoothing: Double(smoothing),
                leading: leadingRadius.map { Double($0) }
            )
        )
    }
}

/// Numeric text with tabular figures and smooth blur/scale digit turnover (`IslandNumber`).
struct IslandNumberText: View {
    let value: String
    var fontSize: CGFloat = 15
    var weight: Font.Weight = .semibold
    var color: Color = IslandTheme.Ink.primary
    var monospaced: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: value)
            .font(
                monospaced
                    ? .system(size: fontSize, weight: weight, design: .monospaced)
                    : .system(size: fontSize, weight: weight).monospacedDigit()
            )
            .foregroundStyle(color)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.92), value: value)
            .lineLimit(1)
    }
}

/// Circular progress ring starting at 12 o'clock with rounded stroke caps.
struct IslandProgressRing<Content: View>: View {
    let value: Double
    var color: Color = IslandTheme.Accent.blue
    var track: Color = IslandTheme.Ink.track
    var size: CGFloat = 22
    var thickness: CGFloat = 3
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        value: Double,
        color: Color = IslandTheme.Accent.blue,
        track: Color = IslandTheme.Ink.track,
        size: CGFloat = 22,
        thickness: CGFloat = 3,
        @ViewBuilder content: @escaping () -> Content = { EmptyView() }
    ) {
        self.value = value
        self.color = color
        self.track = track
        self.size = size
        self.thickness = thickness
        self.content = content
    }

    private var clamped: Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: thickness)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(clamped > 0 ? 1 : 0)
                .animation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.42), value: clamped)
            content()
        }
        .frame(width: size, height: size)
    }
}

struct IslandIconRing: View {
    let systemImage: String
    let value: Double
    let accent: Color
    var size: CGFloat = 22

    var body: some View {
        let isLarge = size > 30
        IslandProgressRing(
            value: value,
            color: accent,
            track: accent.opacity(0.22),
            size: size,
            thickness: isLarge ? 3.5 : 2.5
        ) {
            ZStack {
                if isLarge {
                    Circle()
                        .fill(accent.opacity(0.18))
                        .frame(width: size - 10, height: size - 10)
                }
                Image(systemName: systemImage)
                    .font(.system(size: size * (isLarge ? 0.38 : 0.46), weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
    }
}

/// Capsule linear progress bar supporting round or square-cut media scrubbers.
struct IslandLinearProgress: View {
    enum EndStyle {
        case round
        case square
    }

    let value: Double
    var color: Color = IslandTheme.Accent.blue
    var track: Color = IslandTheme.Ink.track
    var height: CGFloat = 6
    var ends: EndStyle = .round

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(track)
                if ends == .square {
                    Rectangle()
                        .fill(color)
                        .frame(width: w * clamped, height: height)
                        .clipShape(Capsule())
                } else {
                    Capsule()
                        .fill(color)
                        .frame(width: max(clamped > 0 ? height : 0, w * clamped), height: height)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.9), value: clamped)
        }
        .frame(height: height)
    }
}

/// Interactive scrubbable progress/level bar shared by Volume/Brightness HUDs and Music Scrubbers.
struct IslandInteractiveLevelBar: View {
    let value: Double
    var color: Color = IslandTheme.Accent.blue
    var track: Color = IslandTheme.Ink.track
    var height: CGFloat = 6
    var onScrub: ((Double) -> Void)? = nil

    @State private var dragFraction: Double?

    var body: some View {
        let displayed = min(1, max(0, dragFraction ?? value))
        if let onScrub {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(track)
                    Capsule().fill(color)
                        .frame(width: max(displayed > 0 ? height : 0, geo.size.width * displayed), height: height)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let frac = min(1, max(0, drag.location.x / max(1, geo.size.width)))
                            dragFraction = frac
                            onScrub(frac)
                        }
                        .onEnded { drag in
                            let frac = min(1, max(0, drag.location.x / max(1, geo.size.width)))
                            dragFraction = nil
                            onScrub(frac)
                        }
                )
            }
            .frame(height: max(height, 12))
        } else {
            IslandLinearProgress(value: displayed, color: color, track: track, height: height)
        }
    }
}

/// Self-updating countdown ring aligned on whole-second ticks (`Pause` free when static).
struct IslandCountdownRing<Content: View>: View {
    let start: Date
    let end: Date
    var color: Color = IslandTheme.Accent.orange
    var size: CGFloat = 20
    var drains: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        start: Date,
        end: Date,
        color: Color = IslandTheme.Accent.orange,
        size: CGFloat = 20,
        drains: Bool = true,
        @ViewBuilder content: @escaping () -> Content = { EmptyView() }
    ) {
        self.start = start
        self.end = end
        self.color = color
        self.size = size
        self.drains = drains
        self.content = content
    }

    var body: some View {
        TimelineView(.periodic(from: start, by: reduceMotion ? 1.0 : 0.25)) { context in
            let total = max(1.0, end.timeIntervalSince(start))
            let gone = min(1.0, max(0.0, context.date.timeIntervalSince(start) / total))
            IslandProgressRing(
                value: drains ? (1.0 - gone) : gone,
                color: color,
                track: color.opacity(0.25),
                size: size,
                thickness: size > 24 ? 3 : 2.5,
                content: content
            )
        }
    }
}

enum IslandStepState: Equatable, Sendable {
    case done
    case active
    case failed
    case pending
}

struct IslandStepProgress: View {
    enum ShapeStyle {
        case bar
        case dots
    }

    let steps: [IslandStepState]
    var color: Color = IslandTheme.Accent.blue
    var style: ShapeStyle = .bar
    var height: CGFloat = 5

    private func fillColor(for state: IslandStepState) -> Color {
        switch state {
        case .done: return color
        case .active: return color.opacity(0.5)
        case .failed: return IslandTheme.Accent.red
        case .pending: return IslandTheme.Ink.track
        }
    }

    var body: some View {
        if style == .dots {
            HStack(spacing: 5) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Capsule()
                        .fill(step == .active ? color : fillColor(for: step))
                        .frame(width: step == .active ? 16 : 7, height: 7)
                }
            }
        } else {
            HStack(spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    Capsule()
                        .fill(fillColor(for: step))
                        .frame(height: height)
                }
            }
        }
    }
}

struct IslandSparkline: View {
    let values: [Double]
    var color: Color = IslandTheme.Ink.primary
    var height: CGFloat = 16
    var lineWidth: CGFloat = 2
    var showsArea: Bool = false
    var baseline: Double? = nil
    var showsDot: Bool = true

    var body: some View {
        Canvas { ctx, size in
            let normalized = values.count > 1 ? values : [values.first ?? 0, values.first ?? 0]
            var range = normalized
            if let baseline { range.append(baseline) }
            let minVal = range.min() ?? 0
            let maxVal = range.max() ?? 0
            let span = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal)
            let pad = lineWidth * 1.4

            func pointAt(index: Int, value: Double) -> CGPoint {
                let x = (CGFloat(index) / CGFloat(max(1, normalized.count - 1))) * size.width
                let y = pad + (1.0 - CGFloat((value - minVal) / span)) * max(1, size.height - 2 * pad)
                return CGPoint(x: x, y: y)
            }

            let pts = normalized.enumerated().map { pointAt(index: $0.offset, value: $0.element) }
            guard let firstPt = pts.first, let lastPt = pts.last else { return }

            var linePath = Path()
            linePath.move(to: firstPt)
            for pt in pts.dropFirst() {
                linePath.addLine(to: pt)
            }

            if showsArea {
                var areaPath = linePath
                areaPath.addLine(to: CGPoint(x: size.width, y: size.height))
                areaPath.addLine(to: CGPoint(x: 0, y: size.height))
                areaPath.closeSubpath()
                ctx.fill(
                    areaPath,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0.28), color.opacity(0)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            if let baseline {
                let by = pointAt(index: 0, value: baseline).y
                var basePath = Path()
                basePath.move(to: CGPoint(x: 0, y: by))
                basePath.addLine(to: CGPoint(x: size.width, y: by))
                ctx.stroke(
                    basePath,
                    with: .color(IslandTheme.Ink.tertiary),
                    style: StrokeStyle(lineWidth: 1, dash: [2, 3])
                )
            }

            ctx.stroke(
                linePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )

            if showsDot {
                let d = lineWidth * 2.6
                let dotRect = CGRect(x: lastPt.x - d / 2, y: lastPt.y - d / 2, width: d, height: d)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
            }
        }
        .frame(height: height)
    }
}

/// Audio / equalizer meter bars paused completely when inactive or reduced-motion (`0%` idle CPU).
struct IslandLevelMeter: View {
    var bars: Int = 4
    var color: Color = IslandTheme.Ink.primary
    var coreColor: Color? = nil
    var height: CGFloat = 16
    var barWidth: CGFloat = 3
    var gap: CGFloat = 2
    var active: Bool = true
    var levels: [Double]? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func pseudoHash(_ n: Int) -> Double {
        let x = sin(Double(n) * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active || reduceMotion || levels != nil)) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: gap) {
                ForEach(0..<bars, id: \.self) { index in
                    let scale: CGFloat = {
                        if let levels, index < levels.count {
                            return CGFloat(min(1, max(0.12, levels[index])))
                        }
                        if !active { return 0.22 }
                        let hi = 0.55 + pseudoHash(index + 17) * 0.45
                        if reduceMotion { return CGFloat(hi) }
                        let lo = 0.22 + pseudoHash(index) * 0.12
                        let period = 0.42 + pseudoHash(index + 5) * 0.5
                        let phase = pseudoHash(index + 9) * .pi * 2.0
                        let wave = 0.5 + 0.5 * sin((now / period) * .pi * 2.0 + phase)
                        return CGFloat(lo + (hi - lo) * wave)
                    }()

                    ZStack {
                        Capsule()
                            .fill(color)
                            .frame(width: barWidth, height: max(barWidth, height * scale))
                        if let coreColor {
                            Capsule()
                                .fill(coreColor)
                                .frame(width: barWidth, height: max(2, height * scale * 0.45))
                        }
                    }
                    .frame(width: barWidth, height: height)
                }
            }
        }
    }
}

enum IslandTimeSource: Equatable, Sendable {
    case elapsed(since: Date)
    case remaining(until: Date)
    case fixed(ms: Double)
}

func islandFormatClock(ms: Double) -> String {
    let total = max(0, Int(floor(ms / 1000.0)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    let ss = String(format: "%02d", seconds)
    return hours > 0 ? "\(hours):\(String(format: "%02d", minutes)):\(ss)" : "\(minutes):\(ss)"
}

struct IslandTickingTime: View {
    let source: IslandTimeSource
    var fontSize: CGFloat = 15
    var weight: Font.Weight = .semibold
    var color: Color = IslandTheme.Ink.primary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch source {
        case let .fixed(ms):
            IslandNumberText(
                value: islandFormatClock(ms: ms),
                fontSize: fontSize,
                weight: weight,
                color: color
            )
        case let .elapsed(since):
            TimelineView(.periodic(from: since, by: 1.0)) { context in
                let ms = max(0, context.date.timeIntervalSince(since) * 1000.0)
                IslandNumberText(
                    value: islandFormatClock(ms: ms),
                    fontSize: fontSize,
                    weight: weight,
                    color: color
                )
            }
        case let .remaining(until):
            TimelineView(.periodic(from: until, by: 1.0)) { context in
                let rawMs = until.timeIntervalSince(context.date) * 1000.0
                let ms = ceil(max(0, rawMs) / 1000.0) * 1000.0
                IslandNumberText(
                    value: islandFormatClock(ms: ms),
                    fontSize: fontSize,
                    weight: weight,
                    color: color
                )
            }
        }
    }
}
