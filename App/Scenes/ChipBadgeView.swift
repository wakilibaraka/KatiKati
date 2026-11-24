import AppKit
import ApplicationServices
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Chip Badge

/// Classic Dock-style unread badge: red capsule, white text, top-right of the chip.
/// Renders whatever string the app put on its Dock tile ("3", "99+", "•") as-is.
/// Not a hit target — taps fall through to the chip underneath.
///
/// **它由 chip 自己画（`ChipView.bareIconChip` / `LauncherChip` 的 overlay），不是由调用方
/// 套一层 ZStack 叠上去的。** 2026-08-17 之前是后者，于是它落在 `chipQuietHoverScale` 的
/// **外面**：安静档悬停时图标放大 10%，红点纹丝不动（owner 实测两帧都是 16×15pt），
/// 看着像图标从红点底下鼓出来。放进 chip 里之后，悬停放大、按压回缩、档位缩放它全都跟着走。
///
/// 尺寸常量在 `ChipPillMetrics.badge*`，中档与历史字面值逐字相同。
struct ChipBadgeView: View {
    let text: String
    /// 档位系数。**故意不给默认值**——同 `scale` / `hoverStyle` 那条铁律。
    let scale: CGFloat
    var effect: IconBadgeEffectSpec = .init()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let triggered = effect.isTriggered(byBadgeText: text)
        let bgColor: Color = (triggered && effect.kind == .waxSeal)
            ? Color(red: 0.68, green: 0.10, blue: 0.14)
            : Color(red: 1.0, green: 0.23, blue: 0.19)
        Text(text)
            .font(.system(size: ChipPillMetrics.badgeFontSize * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, ChipPillMetrics.badgeHorizontalPadding * scale)
            .frame(minWidth: ChipPillMetrics.badgeMinimumSize * scale,
                   minHeight: ChipPillMetrics.badgeMinimumSize * scale)
            .background(Capsule().fill(bgColor))
            .overlay(
                // 0.5pt 是发丝线，和分隔线同理，不随档位缩放。
                Capsule().strokeBorder(
                    triggered && effect.kind == .waxSeal ? Color(red: 0.95, green: 0.72, blue: 0.45).opacity(0.6) : .black.opacity(0.25),
                    lineWidth: triggered && effect.kind == .waxSeal ? 1.2 : 0.5
                )
            )
            .background {
                if triggered {
                    IconBadgeEffectView(kind: effect.kind, scale: scale, reduceMotion: reduceMotion)
                }
            }
            // 原生的角标大部分压在图标上，只稍稍探出圆角：卡片 40×54、可见图标方块 32.5，
            // 这个下推量让角标中心正好落在图标右上角内侧。
            .offset(x: 0, y: ChipPillMetrics.badgeTopOffset * scale)
            .allowsHitTesting(false)
    }
}

struct IconBadgeEffectView: View {
    let kind: IconBadgeEffectKind
    let scale: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let animates = !reduceMotion && kind != .none && kind != .waxSeal
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !animates)) { context in
            let t = animates ? context.date.timeIntervalSinceReferenceDate : 0
            switch kind {
            case .none:
                EmptyView()
            case .fire:
                let flicker = animates ? (0.86 + 0.14 * sin(t * 9.0)) : 0.95
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [.yellow.opacity(0.85), .orange.opacity(0.65), .red.opacity(0)], center: .bottom, startRadius: 1, endRadius: 14 * scale))
                        .frame(width: 24 * scale, height: 24 * scale)
                        .offset(y: -5 * scale)
                        .scaleEffect(x: 1.0, y: flicker, anchor: .bottom)
                }
            case .sunlight:
                let spin = animates ? t * 24.0 : 0
                ZStack {
                    ForEach(0..<8, id: \.self) { idx in
                        Capsule()
                            .fill(Color.yellow.opacity(0.65))
                            .frame(width: 2 * scale, height: 7 * scale)
                            .offset(y: -11 * scale)
                            .rotationEffect(.degrees(Double(idx) * 45.0 + spin))
                    }
                }
            case .waxSeal:
                Circle()
                    .strokeBorder(Color(red: 0.55, green: 0.06, blue: 0.10), style: StrokeStyle(lineWidth: 3 * scale, dash: [3 * scale, 2 * scale]))
                    .frame(width: 20 * scale, height: 20 * scale)
            case .glint:
                let sweep = animates ? ((t.truncatingRemainder(dividingBy: 2.2) / 2.2) * 2.0 - 1.0) : 0.0
                Capsule()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18 * scale, height: 14 * scale)
                    .offset(x: CGFloat(sweep) * 8 * scale)
            }
        }
        .allowsHitTesting(false)
    }
}

struct IconDressUpOverlayView: View {
    let decorations: [IconDecoration]
    let size: CGFloat
    let isHovered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ForEach(decorations) { deco in
                decorationView(deco)
                    .position(x: size * deco.anchorX, y: size * deco.anchorY)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func decorationView(_ deco: IconDecoration) -> some View {
        let s = CGFloat(deco.scale)
        switch deco.kind {
        case .stringLights:
            let count = max(3, min(9, Int((3 + (1.0 - deco.spacing) * 6).rounded())))
            HStack(spacing: max(1, (size * 0.72 / CGFloat(count)) * 0.35)) {
                ForEach(0..<count, id: \.self) { i in
                    let colors: [Color] = [.yellow, .red, .green, .cyan, .orange]
                    Circle()
                        .fill(colors[i % colors.count])
                        .frame(width: max(3, size * 0.09 * s), height: max(3, size * 0.09 * s))
                        .shadow(color: colors[i % colors.count].opacity(0.75), radius: max(1.5, size * 0.04))
                        .offset(y: sin(Double(i) / Double(max(1, count - 1)) * .pi) * size * 0.07)
                }
            }
            .frame(width: size * 0.88)
        case .pine:
            HStack(spacing: -size * 0.05) {
                Image(systemName: "leaf.fill").foregroundStyle(Color(red: 0.14, green: 0.56, blue: 0.24)).rotationEffect(.degrees(-25))
                Circle().fill(Color.red).frame(width: max(3, size * 0.09 * s), height: max(3, size * 0.09 * s))
                Image(systemName: "leaf.fill").foregroundStyle(Color(red: 0.10, green: 0.45, blue: 0.18)).rotationEffect(.degrees(25))
            }
            .font(.system(size: max(8, size * 0.24 * s)))
        case .snowGlobe:
            let snow = isHovered && !reduceMotion
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .cyan.opacity(0.35), .white.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(1.2, size * 0.04))
                if snow {
                    TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !snow)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate
                        Canvas { ctx, sz in
                            for idx in 0..<8 {
                                let x = sz.width * (0.12 + 0.76 * Double((idx * 37) % 10) / 10.0)
                                let y = (sz.height * (Double(idx) * 0.18 + t * 0.45)).truncatingRemainder(dividingBy: sz.height)
                                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: max(1.5, size * 0.04), height: max(1.5, size * 0.04))), with: .color(.white.opacity(0.85)))
                            }
                        }
                    }
                }
            }
            .frame(width: size * 0.96, height: size * 0.96)
        }
    }
}

// MARK: - IS-4.2 Finder Companion Live Icon

struct FinderCompanionIconView: View {
    let config: LiveIconConfig
    let size: CGFloat
    var isHovered: Bool = false
    var isCopying: Bool = false

    @ObservedObject private var activityProbe = LiveAppActivityProbe.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gaze: CGPoint = .zero
    @State private var isBlinking = false
    @State private var blinkTimer: Timer?

    var body: some View {
        let style = config.finderStyle ?? FinderCompanionStyle()
        let leftColor = finderColor(style.leftHex, fallback: Color(red: 0.34, green: 0.73, blue: 1.0))
        let rightColor = finderColor(style.rightHex, fallback: Color(red: 0.84, green: 0.93, blue: 1.0))
        let ink = finderColor(style.featureHex, fallback: Color(red: 0.08, green: 0.10, blue: 0.14))
        let offset = FinderCompanionGeometry.pupilOffset(normalizedX: gaze.x, normalizedY: gaze.y, maxTravel: size * 0.032)
        let copying = isCopying || (config.optInActivityProbe && activityProbe.finderCopyActive)
        let activeEye: FinderCompanionStyle.EyeStyle = copying ? .focused : style.eyeStyle

        ZStack {
            HStack(spacing: 0) {
                leftColor
                rightColor
            }
            // Classic split curve
            Path { p in
                p.move(to: CGPoint(x: size * 0.54, y: 0))
                p.addQuadCurve(to: CGPoint(x: size * 0.48, y: size * 0.62), control: CGPoint(x: size * 0.42, y: size * 0.35))
                p.addLine(to: CGPoint(x: size * 0.56, y: size * 0.62))
                p.addQuadCurve(to: CGPoint(x: size * 0.54, y: size), control: CGPoint(x: size * 0.45, y: size * 0.82))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addLine(to: CGPoint(x: size, y: 0))
                p.closeSubpath()
            }
            .fill(rightColor)

            // Eyes
            HStack(spacing: size * 0.28) {
                eyeView(style: activeEye, ink: ink, offset: offset)
                eyeView(style: activeEye, ink: ink, offset: offset)
            }
            .offset(y: -size * 0.12)

            // Nose
            noseView(style: style.noseStyle, ink: ink)

            // Mouth
            Path { p in
                let y = style.mouthStyle == .calm ? size * 0.70 : size * 0.66
                let sag = style.mouthStyle == .grin ? size * 0.18 : (style.mouthStyle == .calm ? size * 0.02 : size * 0.12)
                p.move(to: CGPoint(x: size * 0.25, y: y))
                p.addQuadCurve(to: CGPoint(x: size * 0.75, y: y), control: CGPoint(x: size * 0.50, y: y + sag))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: max(1.5, size * 0.065), lineCap: .round))
        }
        .frame(width: size, height: size)
        .onContinuousHover { phase in
            switch phase {
            case .active(let pt):
                let nx = (pt.x / max(1, size)) * 2.0 - 1.0
                let ny = (pt.y / max(1, size)) * 2.0 - 1.0
                gaze = CGPoint(x: nx, y: ny)
            case .ended:
                gaze = .zero
            }
        }
        .onAppear { startBlinkIfNeeded() }
        .onDisappear { blinkTimer?.invalidate(); blinkTimer = nil }
        .onChange(of: reduceMotion) { _ in startBlinkIfNeeded() }
    }

    @ViewBuilder
    private func eyeView(style: FinderCompanionStyle.EyeStyle, ink: Color, offset: (dx: Double, dy: Double)) -> some View {
        let w = max(2.5, size * (style == .wide ? 0.12 : 0.08))
        let h = isBlinking ? max(1.5, size * 0.02) : max(3, size * (style == .focused ? 0.09 : 0.17))
        RoundedRectangle(cornerRadius: w * 0.5, style: .continuous)
            .fill(ink)
            .frame(width: w, height: h)
            .offset(x: offset.dx, y: offset.dy)
            .animation(.easeOut(duration: 0.09), value: isBlinking)
    }

    @ViewBuilder
    private func noseView(style: FinderCompanionStyle.NoseStyle, ink: Color) -> some View {
        switch style {
        case .classic:
            Path { p in
                p.move(to: CGPoint(x: size * 0.49, y: size * 0.36))
                p.addLine(to: CGPoint(x: size * 0.44, y: size * 0.57))
                p.addLine(to: CGPoint(x: size * 0.54, y: size * 0.57))
            }
            .stroke(ink, style: StrokeStyle(lineWidth: max(1.3, size * 0.05), lineCap: .round, lineJoin: .round))
        case .button:
            Circle().fill(ink).frame(width: max(3, size * 0.12), height: max(3, size * 0.12)).offset(y: size * 0.06)
        case .minimal:
            Capsule().fill(ink).frame(width: max(2, size * 0.06), height: max(4, size * 0.14)).offset(y: size * 0.05)
        }
    }

    private func startBlinkIfNeeded() {
        blinkTimer?.invalidate(); blinkTimer = nil
        guard !reduceMotion else { isBlinking = false; return }
        let t = Timer.scheduledTimer(withTimeInterval: 5.5, repeats: true) { _ in
            Task { @MainActor in
                isBlinking = true
                try? await Task.sleep(nanoseconds: 130_000_000)
                isBlinking = false
            }
        }
        t.tolerance = 0.8
        blinkTimer = t
    }

    private func finderColor(_ hex: String, fallback: Color) -> Color {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let v = UInt32(raw, radix: 16) else { return fallback }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - IS-3.2 AI & Now Playing Live Icon Overlays

struct AILiveIconOverlay: View {
    let config: LiveIconConfig
    let size: CGFloat
    var isHovered: Bool = false
    var previewPercentOverride: Double? = nil

    @ObservedObject private var usage = AgentUsageService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resolvedUsedPercent: Double? {
        if let override = previewPercentOverride { return min(100, max(0, override)) }
        switch config.kind {
        case .claude:
            if let pct = usage.snapshot.limits[.claude]?.windows.first(where: { $0.kind == .session })?.usedPercent
                ?? usage.snapshot.limits[.claude]?.windows.first?.usedPercent { return pct }
            return usage.snapshot.providerToday[.claude].map { min(100, ($0.cost / 10.0) * 100.0) }
        case .codex:
            if let pct = usage.snapshot.limits[.codex]?.windows.first?.usedPercent { return pct }
            return usage.snapshot.providerToday[.codex].map { CursorBudgetEstimator.estimatedUsedPercent(todayCostUSD: $0.cost) }
        case .cursor:
            return CursorBudgetEstimator.estimatedUsedPercent(todayCostUSD: usage.snapshot.todayCost)
        default: return nil
        }
    }

    private var isTurnActive: Bool {
        guard let turn = usage.snapshot.activeTurn, turn.isActive else { return false }
        return (config.kind == .claude && turn.provider == .claude) || (config.kind == .codex && turn.provider == .codex)
    }

    private var accentColor: Color {
        switch config.kind {
        case .claude: return Color(red: 0.85, green: 0.45, blue: 0.25)
        case .codex: return Color.white
        default: return Color(red: 0.30, green: 0.68, blue: 0.96)
        }
    }

    var body: some View {
        let fraction = LiveIconMetrics.usageFillFraction(usedPercent: resolvedUsedPercent, mode: config.usageMode)
        let shouldTick = (isTurnActive || (previewPercentOverride != nil && isHovered)) && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !shouldTick)) { context in
            let phase = shouldTick ? context.date.timeIntervalSinceReferenceDate : 0
            ZStack(alignment: .bottom) {
                if let fraction {
                    let h = size * CGFloat(fraction)
                    let tiltDeg = (config.kind == .cursor && isHovered && !reduceMotion) ? 5.0 : 0.0
                    Rectangle()
                        .fill(accentColor.opacity(config.usageStyle == .colorFill ? 0.34 : 0.28))
                        .frame(width: size * 1.15, height: h)
                        .overlay(alignment: .top) {
                            if config.usageStyle == .water || config.usageStyle == .fadeTide {
                                Rectangle().fill(Color.white.opacity(0.45)).frame(height: max(1, size * 0.03))
                            }
                        }
                        .rotationEffect(.degrees(tiltDeg))
                        .frame(width: size, height: size, alignment: .bottom)
                        .clipped()
                }
                if config.usageStyle == .fadeTide, shouldTick {
                    let xShift = CGFloat(sin(phase * 2.2)) * size * 0.45
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: size * 0.6, height: size)
                        .offset(x: xShift)
                }
                if config.usageStyle == .glyphTracer, shouldTick {
                    let head = phase.truncatingRemainder(dividingBy: 1.6) / 1.6
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .trim(from: max(0, head - 0.22), to: head)
                        .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: max(1.5, size * 0.05), lineCap: .round))
                        .padding(size * 0.06)
                }
                if config.showWeeklyReset,
                   let resetsAt = usage.snapshot.limits[config.kind == .claude ? .claude : .codex]?.windows.first(where: { $0.kind == .weekly })?.resetsAt,
                   let w = LiveIconMetrics.weeklyResetFraction(now: context.date, resetsAt: resetsAt) {
                    Circle()
                        .trim(from: 0, to: w)
                        .stroke(Color.white.opacity(0.9), lineWidth: max(1.5, size * 0.06))
                        .frame(width: size * 0.22, height: size * 0.22)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(size * 0.08)
                }
                if config.showPercentage, let fraction {
                    Text(verbatim: LiveIconMetrics.formattedPercentage(fraction))
                        .font(.system(size: max(8, size * 0.22), weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, max(3, size * 0.08))
                        .padding(.vertical, max(1, size * 0.02))
                        .background(Capsule().fill(Color.black.opacity(0.72)))
                        .padding(.bottom, max(2, size * 0.06))
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

struct MusicLiveIconOverlay: View {
    let config: LiveIconConfig
    let size: CGFloat
    var previewPercentOverride: Double? = nil

    @ObservedObject private var feed = LiveActivityFeed.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var baseAngle: Double = 0
    @State private var spinStartedAt: Date?

    private var activePlayback: (isPlaying: Bool, artwork: NSImage?, progress: Double, countdown: String)? {
        if let pct = previewPercentOverride {
            let dur: TimeInterval = 180
            let el = dur * min(1, max(0, pct / 100.0))
            return (true, nil, el / dur, MusicTimecode.remaining(elapsed: el, duration: dur))
        }
        let s = feed.nowPlayingState
        let matches = s.bundleIdentifier == config.kind.defaultBundleID
            || (config.kind == .appleMusic && s.appName == "Music")
            || (config.kind == .spotify && s.appName == "Spotify")
        guard matches, !(s.title?.isEmpty ?? true) else { return nil }
        let now = Date()
        let el = NowPlayingProgress.elapsed(at: now, elapsed: s.elapsed, asOf: s.elapsedAsOf, rate: s.rate, duration: s.duration) ?? (s.elapsed ?? 0)
        let frac = NowPlayingProgress.fraction(at: now, elapsed: s.elapsed, asOf: s.elapsedAsOf, rate: s.rate, duration: s.duration) ?? 0
        return (s.isPlaying, s.artworkData.flatMap(NSImage.init(data:)), frac, MusicTimecode.remaining(elapsed: el, duration: s.duration))
    }

    var body: some View {
        let playback = activePlayback
        let shouldSpin = (playback?.isPlaying == true) && config.musicStyle != .cdJewelCase && !reduceMotion
        if let playback {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !shouldSpin)) { context in
                let delta = (shouldSpin ? spinStartedAt.map { context.date.timeIntervalSince($0) * 48.0 } : nil) ?? 0
                let angle = (baseAngle + delta).truncatingRemainder(dividingBy: 360.0)
                ZStack(alignment: .bottom) {
                    if config.musicStyle == .cdJewelCase {
                        jewelCaseBody(artwork: playback.artwork)
                    } else {
                        discBody(artwork: playback.artwork, angle: angle, prismatic: config.musicStyle == .prismaticDisc)
                    }
                    VStack(spacing: max(1, size * 0.03)) {
                        if config.showCountdown {
                            Text(verbatim: playback.countdown)
                                .font(.system(size: max(7.5, size * 0.19), weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, max(3, size * 0.08))
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.black.opacity(0.78)))
                        }
                        GeometryReader { geo in
                            Capsule().fill(Color.white.opacity(0.28))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.white).frame(width: max(2, geo.size.width * playback.progress))
                                }
                        }
                        .frame(height: max(2, size * 0.05))
                        .padding(.horizontal, size * 0.1)
                    }
                    .padding(.bottom, max(2, size * 0.06))
                }
            }
            .frame(width: size, height: size)
            .allowsHitTesting(false)
            .onAppear { if shouldSpin { spinStartedAt = Date() } }
            .onChange(of: shouldSpin) { active in
                if active {
                    spinStartedAt = Date()
                } else if let started = spinStartedAt {
                    baseAngle = (baseAngle + Date().timeIntervalSince(started) * 48.0).truncatingRemainder(dividingBy: 360.0)
                    spinStartedAt = nil
                }
            }
        }
    }

    @ViewBuilder
    private func jewelCaseBody(artwork: NSImage?) -> some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [Color.white.opacity(0.32), Color.black.opacity(0.35), Color.white.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                .frame(width: size * 0.13)
            Group {
                if let artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .overlay(LinearGradient(colors: [.white.opacity(0.26), .clear], startPoint: .topLeading, endPoint: .center))
    }

    @ViewBuilder
    private func discBody(artwork: NSImage?, angle: Double, prismatic: Bool) -> some View {
        ZStack {
            Circle().fill(prismatic
                ? AnyShapeStyle(AngularGradient(colors: [.pink, .yellow, .mint, .cyan, .indigo, .pink], center: .center))
                : AnyShapeStyle(RadialGradient(colors: [Color(white: 0.18), Color(white: 0.06)], center: .center, startRadius: 2, endRadius: size * 0.5)))
            if let artwork {
                Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size * (prismatic ? 0.52 : 0.44), height: size * (prismatic ? 0.52 : 0.44))
                    .clipShape(Circle())
            }
            Circle().fill(Color.black.opacity(0.85)).frame(width: max(3, size * 0.12), height: max(3, size * 0.12))
        }
        .padding(size * 0.04)
        .rotationEffect(.degrees(angle))
        .background(Color.black.opacity(0.82))
    }
}

// MARK: - IS-6.1 Opt-In App Activity Probe & Overlays

@MainActor
final class LiveAppActivityProbe: ObservableObject {
    static let shared = LiveAppActivityProbe()

    @Published private(set) var finderCopyActive = false
    @Published private(set) var mailComposeActive = false
    @Published private(set) var messagesComposeActive = false
    @Published private(set) var safariPageLoading = false
    @Published private(set) var chromeTabLoading = false

    private var watchedBundleIDs: Set<String> = []
    private var timer: Timer?
    private var isScanning = false
    private var cancellables: Set<AnyCancellable> = []

    struct ProbeSnapshot: Sendable {
        var finderCopy = false
        var mailCompose = false
        var messagesCompose = false
        var safariLoading = false
        var chromeLoading = false
    }

    private init() {
        IconStudioController.shared.$state
            .sink { [weak self] next in self?.reconcile(state: next) }
            .store(in: &cancellables)
        reconcile(state: IconStudioController.shared.state)
    }

    private func reconcile(state: IconStudioState) {
        watchedBundleIDs = AppActivityLiveMetrics.activeProbeBundleIDs(in: state)
        guard !watchedBundleIDs.isEmpty else {
            timer?.invalidate(); timer = nil
            apply(.init())
            return
        }
        guard timer == nil else { return }
        pollOnce()
        let t = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollOnce() }
        }
        t.tolerance = 0.6
        timer = t
    }

    private func pollOnce() {
        guard !watchedBundleIDs.isEmpty, AXIsProcessTrusted(), !isScanning else {
            if !AXIsProcessTrusted() { apply(.init()) }
            return
        }
        var pids: [String: pid_t] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, watchedBundleIDs.contains(bid) {
                pids[bid] = app.processIdentifier
            }
        }
        guard !pids.isEmpty else { apply(.init()); return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        isScanning = true
        Task.detached(priority: .utility) { [pids, front] in
            let snap = Self.scanAX(pids: pids, frontmostBundleID: front)
            await MainActor.run { [weak self] in
                self?.isScanning = false
                self?.apply(snap)
            }
        }
    }

    private func apply(_ s: ProbeSnapshot) {
        if finderCopyActive != s.finderCopy { finderCopyActive = s.finderCopy }
        if mailComposeActive != s.mailCompose { mailComposeActive = s.mailCompose }
        if messagesComposeActive != s.messagesCompose { messagesComposeActive = s.messagesCompose }
        if safariPageLoading != s.safariLoading { safariPageLoading = s.safariLoading }
        if chromeTabLoading != s.chromeLoading { chromeTabLoading = s.chromeLoading }
    }

    private nonisolated static func axAttr(_ el: AXUIElement, _ attr: String) -> AnyObject? {
        var val: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &val) == .success else { return nil }
        return val
    }

    private nonisolated static func axApp(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.12)
        return app
    }

    private nonisolated static func windows(for pid: pid_t) -> [AXUIElement] {
        (axAttr(axApp(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    private nonisolated static func hasToolbarStopButton(_ win: AXUIElement) -> Bool {
        guard let kids = axAttr(win, kAXChildrenAttribute) as? [AXUIElement] else { return false }
        for child in kids where (axAttr(child, kAXRoleAttribute) as? String) == kAXToolbarRole {
            for item in (axAttr(child, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
                let desc = (axAttr(item, kAXDescriptionAttribute) as? String) ?? (axAttr(item, kAXTitleAttribute) as? String) ?? ""
                if desc == "Stop" || desc.localizedCaseInsensitiveContains("Stop loading") { return true }
            }
        }
        return false
    }

    private nonisolated static func scanAX(pids: [String: pid_t], frontmostBundleID: String?) -> ProbeSnapshot {
        var out = ProbeSnapshot()
        if let pid = pids["com.apple.finder"] {
            out.finderCopy = windows(for: pid).contains { win in
                let sub = (axAttr(win, kAXSubroleAttribute) as? String) ?? ""
                let title = (axAttr(win, kAXTitleAttribute) as? String) ?? ""
                return sub == kAXDialogSubrole || title.localizedCaseInsensitiveContains("Copy") || title.localizedCaseInsensitiveContains("Moving")
            }
        }
        if let pid = pids["com.apple.mail"] {
            out.mailCompose = windows(for: pid).contains { win in
                let ident = (axAttr(win, kAXIdentifierAttribute) as? String) ?? ""
                let title = (axAttr(win, kAXTitleAttribute) as? String) ?? ""
                return ident == "ComposeWindow" || title.localizedCaseInsensitiveContains("New Message") || title == "Untitled"
            }
        }
        if let pid = pids["com.apple.MobileSMS"], frontmostBundleID == "com.apple.MobileSMS",
           let focused = axAttr(axApp(pid), kAXFocusedUIElementAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            let el = focused as! AXUIElement
            let role = (axAttr(el, kAXRoleAttribute) as? String) ?? ""
            let value = (axAttr(el, kAXValueAttribute) as? String) ?? ""
            out.messagesCompose = (role == kAXTextAreaRole) && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let pid = pids["com.apple.Safari"], let w = windows(for: pid).first { out.safariLoading = hasToolbarStopButton(w) }
        if let pid = pids["com.google.Chrome"], let w = windows(for: pid).first { out.chromeLoading = hasToolbarStopButton(w) }
        return out
    }
}

struct AppActivityLiveIconOverlay: View {
    let config: LiveIconConfig
    let size: CGFloat
    var badgeText: String? = nil
    var isHovered: Bool = false
    var previewPercentOverride: Double? = nil

    @ObservedObject private var probe = LiveAppActivityProbe.shared
    @ObservedObject private var downloads = DownloadManagerService.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch config.kind {
        case .mail: mailBody
        case .messages: messagesBody
        case .safari: safariBody
        case .chrome: chromeBody
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var mailBody: some View {
        let compose = config.optInActivityProbe && probe.mailComposeActive
        let isOpen = AppActivityLiveMetrics.mailEnvelopeOpen(composeActive: compose, previewPercentOverride: previewPercentOverride)
        if isOpen {
            ZStack(alignment: .top) {
                Path { p in
                    p.move(to: CGPoint(x: size * 0.18, y: size * 0.24))
                    p.addLine(to: CGPoint(x: size * 0.50, y: size * 0.05))
                    p.addLine(to: CGPoint(x: size * 0.82, y: size * 0.24))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.92))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
            }
            .frame(width: size, height: size).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var messagesBody: some View {
        let unread = IconUnreadBadgeParser.parseCount(badgeText)
        let typing = (config.optInActivityProbe && probe.messagesComposeActive) || (previewPercentOverride ?? 0) >= 50
        let bubbles = AppActivityLiveMetrics.messagesBubbleCount(unreadCount: unread)
        if typing {
            TimelineView(.animation(minimumInterval: 1.0 / 10.0, paused: reduceMotion)) { ctx in
                let step = Int(ctx.date.timeIntervalSinceReferenceDate * 3.0) % 3
                HStack(spacing: max(1.5, size * 0.04)) {
                    ForEach(0..<3, id: \.self) { idx in
                        Circle().fill(Color(red: 0.14, green: 0.56, blue: 0.24))
                            .frame(width: max(2, size * 0.08), height: max(2, size * 0.08))
                            .opacity(reduceMotion || idx == step ? 1.0 : 0.35)
                    }
                }
                .padding(.horizontal, max(3, size * 0.09)).padding(.vertical, max(2, size * 0.05))
                .background(Capsule().fill(Color.white.opacity(0.95)))
                .frame(width: size, height: size, alignment: .bottomTrailing).padding(size * 0.08)
            }
            .allowsHitTesting(false)
        } else if bubbles > 0 {
            HStack(spacing: max(2, size * 0.05)) {
                ForEach(0..<bubbles, id: \.self) { _ in
                    Capsule().fill(Color.white.opacity(0.9)).frame(width: max(4, size * 0.14), height: max(3, size * 0.10))
                }
            }
            .offset(y: (isHovered && !reduceMotion) ? -size * 0.05 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.65), value: isHovered)
            .frame(width: size, height: size, alignment: .bottomTrailing).padding(size * 0.10)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var safariBody: some View {
        let dlPairs = downloads.items.filter { $0.state == .active }.map { ($0.bytesDownloaded, $0.totalBytes) }
        let dlFrac = previewPercentOverride.map { min(1, max(0, $0 / 100.0)) } ?? AppActivityLiveMetrics.aggregateDownloadFraction(activePairs: dlPairs)
        let loading = (config.optInActivityProbe && probe.safariPageLoading) || ((previewPercentOverride ?? 0) > 0 && isHovered)
        ZStack(alignment: .bottom) {
            if let dlFrac, dlFrac > 0 {
                Rectangle().fill(Color.cyan.opacity(0.28))
                    .frame(width: size, height: size * CGFloat(dlFrac))
                Text(verbatim: LiveIconMetrics.formattedPercentage(dlFrac))
                    .font(.system(size: max(7.5, size * 0.20), weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, max(3, size * 0.07)).padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, max(2, size * 0.06))
            }
            if loading {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: reduceMotion)) { ctx in
                    let deg = reduceMotion ? 0 : (ctx.date.timeIntervalSinceReferenceDate * 150).truncatingRemainder(dividingBy: 360)
                    Capsule().fill(Color.red.opacity(0.92))
                        .frame(width: max(2, size * 0.06), height: size * 0.44)
                        .rotationEffect(.degrees(deg))
                        .frame(width: size, height: size)
                }
            }
        }
        .frame(width: size, height: size).allowsHitTesting(false)
    }

    @ViewBuilder
    private var chromeBody: some View {
        let spinning = ((config.optInActivityProbe && probe.chromeTabLoading) || ((previewPercentOverride ?? 0) > 0 && isHovered)) && !reduceMotion
        if config.optInActivityProbe && probe.chromeTabLoading || (previewPercentOverride ?? 0) > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !spinning)) { ctx in
                let deg = spinning ? (ctx.date.timeIntervalSinceReferenceDate * 180).truncatingRemainder(dividingBy: 360) : 0
                Circle()
                    .trim(from: 0.08, to: 0.85)
                    .stroke(AngularGradient(colors: [.red, .yellow, .green, .blue, .red], center: .center),
                            style: StrokeStyle(lineWidth: max(2, size * 0.075), lineCap: .round))
                    .rotationEffect(.degrees(deg))
                    .padding(size * 0.05)
            }
            .frame(width: size, height: size).allowsHitTesting(false)
        }
    }
}
