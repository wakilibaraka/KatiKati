import AppKit
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
