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

    var body: some View {
        Text(text)
            .font(.system(size: ChipPillMetrics.badgeFontSize * scale, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, ChipPillMetrics.badgeHorizontalPadding * scale)
            .frame(minWidth: ChipPillMetrics.badgeMinimumSize * scale,
                   minHeight: ChipPillMetrics.badgeMinimumSize * scale)
            .background(
                Capsule().fill(Color(red: 1.0, green: 0.23, blue: 0.19))   // Apple badge red
            )
            .overlay(
                // 0.5pt 是发丝线，和分隔线同理，不随档位缩放。
                Capsule().strokeBorder(.black.opacity(0.25), lineWidth: 0.5)
            )
            // 原生的角标大部分压在图标上，只稍稍探出圆角：卡片 40×54、可见图标方块 32.5，
            // 这个下推量让角标中心正好落在图标右上角内侧。
            .offset(x: 0, y: ChipPillMetrics.badgeTopOffset * scale)
            .allowsHitTesting(false)
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
