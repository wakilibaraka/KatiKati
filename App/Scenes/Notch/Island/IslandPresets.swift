import AppKit
import AVKit
import Metal
import QuartzCore
import SwiftUI

/// Production activity preset view builders faithful to `opencoredev/islandcn/components/islandcn/*`
/// and adapted for KatiKati's macOS Dock + Notch + M5 OLED multi-touch experience.
@MainActor
enum IslandPresets {
    // MARK: 1. Now Playing

    static func nowPlaying(
        title: String,
        artist: String,
        artwork: NSImage?,
        progress: Double?,
        isPlaying: Bool,
        accent: Color = IslandTheme.Accent.pink,
        onTogglePlayPause: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> IslandActivityViews {
        let thumbCompact = IslandTileArtwork(image: artwork, systemImage: "music.note", accent: accent, size: 22, radius: 6)
        let meter = IslandLevelMeter(bars: 4, color: accent, height: 15, barWidth: 2.8, gap: 2, active: isPlaying)
        let progressValue = progress ?? 0.35

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 22,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 18),
                    detached: IslandSlotPair(leading: 20, trailing: 18)
                ),
                expandedHeight: 92
            ),
            compactLeading: AnyView(thumbCompact),
            compactTrailing: AnyView(meter),
            minimal: AnyView(thumbCompact),
            expandedLeading: AnyView(
                IslandTileArtwork(image: artwork, systemImage: "music.note", accent: accent, size: 52, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: title.isEmpty ? "Now Playing" : title, subtitle: artist)
            ),
            expandedTrailing: AnyView(
                IslandLevelMeter(bars: 4, color: accent, height: 18, barWidth: 3, gap: 2.2, active: isPlaying)
            ),
            expandedBottom: AnyView(
                VStack(spacing: 8) {
                    IslandLinearProgress(value: progressValue, color: accent, height: 5, ends: .square)
                    HStack(spacing: 12) {
                        IslandRoundButton(size: 36, accessibilityLabel: "Previous", action: onPrevious) {
                            Image(systemName: "backward.fill").font(.system(size: 13, weight: .semibold))
                        }
                        IslandRoundButton(size: 40, fill: accent.opacity(0.24), foreground: accent, accessibilityLabel: isPlaying ? "Pause" : "Play", action: onTogglePlayPause) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold))
                        }
                        IslandRoundButton(size: 36, accessibilityLabel: "Next", action: onNext) {
                            Image(systemName: "forward.fill").font(.system(size: 13, weight: .semibold))
                        }
                    }
                }
            )
        )
    }

    // MARK: 2. Timer / Countdown

    static func timer(
        label: String,
        source: IslandTimeSource,
        progressRemaining: Double,
        isPaused: Bool,
        accent: Color = IslandTheme.Accent.orange,
        onToggle: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil
    ) -> IslandActivityViews {
        let color = isPaused ? IslandTheme.Ink.secondary : accent
        let ring = IslandProgressRing(value: progressRemaining, color: accent, track: accent.opacity(0.25), size: 22, thickness: 2.8) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
        }

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 46,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 44),
                    detached: IslandSlotPair(leading: 20, trailing: 18)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(ring),
            compactTrailing: AnyView(IslandTickingTime(source: source, fontSize: 15, weight: .semibold, color: color)),
            minimal: AnyView(ring),
            expandedLeading: AnyView(
                HStack(spacing: 10) {
                    if let onToggle {
                        IslandRoundButton(size: 46, fill: accent.opacity(0.3), foreground: accent, accessibilityLabel: isPaused ? "Resume" : "Pause", action: onToggle) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill").font(.system(size: 18, weight: .semibold))
                        }
                    } else {
                        IslandTileArtwork(systemImage: "timer", accent: accent)
                    }
                    if let onCancel {
                        IslandRoundButton(size: 46, accessibilityLabel: "Cancel", action: onCancel) {
                            Image(systemName: "xmark").font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            ),
            expandedCenter: AnyView(EmptyView()),
            expandedTrailing: AnyView(
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: isPaused ? "Paused" : label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                    IslandTickingTime(source: source, fontSize: 32, weight: .bold, color: color)
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 3. Download / Upload Progress

    static func download(
        fileName: String,
        progress: Double,
        detail: String,
        isDone: Bool,
        accent: Color = IslandTheme.Accent.blue,
        onCancel: (() -> Void)? = nil
    ) -> IslandActivityViews {
        let pct = Int(min(100, max(0, floor(progress * 100))))
        let ring = IslandIconRing(systemImage: isDone ? "checkmark" : "arrow.down", value: progress, accent: accent, size: 22)

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 38,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 34),
                    detached: IslandSlotPair(leading: 20, trailing: 18)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                IslandTileArtwork(systemImage: "doc.fill", accent: accent, size: 22, radius: 6)
            ),
            compactTrailing: AnyView(
                HStack(spacing: 4) {
                    IslandNumberText(value: "\(pct)%", fontSize: 13, weight: .semibold, color: accent)
                    ring
                }
            ),
            minimal: AnyView(ring),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: isDone ? "checkmark.circle.fill" : "arrow.down.circle.fill", accent: accent, size: 52, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: fileName, subtitle: detail, subtitleColor: IslandTheme.Ink.secondary)
            ),
            expandedTrailing: AnyView(
                Group {
                    if let onCancel, !isDone {
                        IslandRoundButton(size: 40, fill: accent.opacity(0.2), foreground: accent, accessibilityLabel: "Stop", action: onCancel) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accent)
                                .frame(width: 12, height: 12)
                        }
                    } else {
                        IslandIconRing(systemImage: isDone ? "checkmark" : "arrow.down", value: progress, accent: accent, size: 38)
                    }
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 4. Call / Meeting

    static func call(
        caller: String,
        subtitle: String,
        since: Date,
        isMuted: Bool,
        accent: Color = IslandTheme.Accent.green,
        onToggleMute: (() -> Void)? = nil,
        onHangUp: (() -> Void)? = nil
    ) -> IslandActivityViews {
        let meter = IslandLevelMeter(bars: 6, color: accent, coreColor: .white.opacity(0.8), height: 15, barWidth: 2.5, gap: 1.8, active: !isMuted)

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 42,
                trailing: 28,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 38, trailing: 26),
                    detached: IslandSlotPair(leading: 20, trailing: 0)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                HStack(spacing: 5) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    IslandTickingTime(source: .elapsed(since: since), fontSize: 14, weight: .semibold, color: accent)
                }
            ),
            compactTrailing: AnyView(meter),
            minimal: AnyView(
                Image(systemName: "phone.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: "person.crop.circle.fill", accent: accent, size: 48, radius: 24)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: caller, subtitle: subtitle, subtitleColor: accent)
            ),
            expandedTrailing: AnyView(
                HStack(spacing: 8) {
                    if let onToggleMute {
                        IslandRoundButton(
                            size: 44,
                            fill: isMuted ? .white.opacity(0.85) : IslandTheme.Ink.fill,
                            foreground: isMuted ? .black : .white,
                            accessibilityLabel: isMuted ? "Unmute" : "Mute",
                            action: onToggleMute
                        ) {
                            Image(systemName: isMuted ? "mic.slash.fill" : "mic.fill").font(.system(size: 16, weight: .semibold))
                        }
                    }
                    if let onHangUp {
                        IslandRoundButton(
                            size: 44,
                            fill: IslandTheme.Accent.red,
                            foreground: .white,
                            accessibilityLabel: "End Call",
                            action: onHangUp
                        ) {
                            Image(systemName: "phone.down.fill").font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 5. Recording / Camera Mirror

    static func recording(
        title: String,
        kindSystemImage: String = "video.fill",
        since: Date,
        accent: Color = IslandTheme.Accent.red,
        onStop: (() -> Void)? = nil
    ) -> IslandActivityViews {
        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 24,
                trailing: 42,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 22, trailing: 40),
                    detached: IslandSlotPair(leading: 20, trailing: 0)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 8, height: 8)
                    Image(systemName: kindSystemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                }
            ),
            compactTrailing: AnyView(
                IslandLevelMeter(bars: 6, color: accent, height: 14, barWidth: 1.8, gap: 1.6, active: true)
            ),
            minimal: AnyView(
                Image(systemName: kindSystemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            expandedLeading: AnyView(
                IslandLevelMeter(bars: 11, color: accent, height: 32, barWidth: 3, gap: 2.5, active: true)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: title, subtitle: nil)
            ),
            expandedTrailing: AnyView(
                HStack(spacing: 10) {
                    IslandTickingTime(source: .elapsed(since: since), fontSize: 18, weight: .medium, color: IslandTheme.Ink.primary)
                    if let onStop {
                        IslandRoundButton(size: 46, fill: Color.white.opacity(0.22), foreground: accent, accessibilityLabel: "Stop", action: onStop) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(accent)
                                .frame(width: 20, height: 20)
                        }
                    }
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 6. Shelf / File Drop Transfer

    static func shelfTransfer(
        itemCount: Int,
        latestName: String,
        accent: Color = IslandTheme.Accent.blue,
        onOpenShelf: @escaping () -> Void
    ) -> IslandActivityViews {
        IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 28,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 24),
                    detached: IslandSlotPair(leading: 20, trailing: 16)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            compactTrailing: AnyView(
                IslandNumberText(value: "\(itemCount)", fontSize: 14, weight: .semibold, color: accent)
            ),
            minimal: AnyView(
                IslandNumberText(value: "\(itemCount)", fontSize: 13, weight: .bold, color: accent)
            ),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: "tray.full.fill", accent: accent, size: 52, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: latestName, subtitle: "\(itemCount) queued")
            ),
            expandedTrailing: AnyView(
                IslandRoundButton(size: 40, fill: accent.opacity(0.22), foreground: accent, accessibilityLabel: "Open Shelf", action: onOpenShelf) {
                    Image(systemName: "arrow.up.forward").font(.system(size: 15, weight: .semibold))
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 7. Battery / Charging

    static func battery(
        level: Double,
        charging: Bool,
        deviceName: String,
        detail: String
    ) -> IslandActivityViews {
        let clamped = min(1, max(0, level))
        let pct = Int((clamped * 100).rounded())
        let accent: Color = clamped < 0.2 ? IslandTheme.Accent.red : IslandTheme.Accent.chargingGreen

        let glyph = HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(charging ? Color(red: 0x2E / 255.0, green: 0x71 / 255.0, blue: 0x24 / 255.0) : accent.opacity(0.4))
                    .frame(width: 26, height: 13)
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: charging
                                ? [Color(red: 0x5A / 255.0, green: 0xFE / 255.0, blue: 0xB6 / 255.0), Color(red: 0x63 / 255.0, green: 0xFF / 255.0, blue: 0x39 / 255.0)]
                                : [accent, accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(4, 26 * clamped), height: 13)
            }
            RoundedRectangle(cornerRadius: 1)
                .fill(charging ? Color(red: 0x2E / 255.0, green: 0x71 / 255.0, blue: 0x24 / 255.0) : accent.opacity(0.4))
                .frame(width: 2, height: 5)
        }

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 64,
                trailing: 64,
                attached: 24,
                detached: 30,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 48, trailing: 26),
                    detached: IslandSlotPair(leading: 24, trailing: 22)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                Text(verbatim: charging ? "Charging" : deviceName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(IslandTheme.Ink.primary)
                    .lineLimit(1)
            ),
            compactTrailing: AnyView(
                HStack(spacing: 4) {
                    IslandNumberText(value: "\(pct)%", fontSize: 14, weight: .semibold, color: accent)
                    glyph
                }
            ),
            minimal: AnyView(
                IslandNumberText(value: "\(pct)%", fontSize: 13, weight: .semibold, color: accent)
            ),
            expandedLeading: AnyView(
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: charging ? "Charging" : deviceName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(IslandTheme.Ink.primary)
                    Text(verbatim: detail)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(IslandTheme.Ink.secondary)
                }
            ),
            expandedCenter: AnyView(EmptyView()),
            expandedTrailing: AnyView(
                HStack(spacing: 6) {
                    IslandNumberText(value: "\(pct)%", fontSize: 22, weight: .bold, color: accent)
                    glyph
                }
            ),
            expandedBottom: nil
        )
    }

    // MARK: 8. AI Agent Live Turn

    static func aiAgent(
        providerName: String,
        model: String,
        toolName: String?,
        tokenSummary: String,
        sparklineValues: [Double]
    ) -> IslandActivityViews {
        let accent = IslandTheme.Accent.lagoon
        let glyph = Image(systemName: "cpu.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(accent)

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 24,
                trailing: 48,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 22, trailing: 44),
                    detached: IslandSlotPair(leading: 20, trailing: 16)
                ),
                expandedHeight: 74
            ),
            compactLeading: AnyView(glyph),
            compactTrailing: AnyView(
                HStack(spacing: 5) {
                    IslandSparkline(values: sparklineValues.isEmpty ? [0.2, 0.4, 0.7] : sparklineValues, color: accent, height: 14, lineWidth: 1.75)
                        .frame(width: 28)
                    IslandNumberText(value: tokenSummary, fontSize: 13, weight: .semibold, color: accent, monospaced: true)
                }
            ),
            minimal: AnyView(glyph),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: "sparkles.rectangle.stack.fill", accent: accent, size: 52, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: "\(providerName) · \(model)", subtitle: toolName ?? "Generating", subtitleColor: accent)
            ),
            expandedTrailing: AnyView(
                IslandExpandedValueStack(value: tokenSummary, caption: "tokens", accent: accent)
            ),
            expandedBottom: AnyView(
                IslandSparkline(
                    values: sparklineValues.isEmpty ? [0.1, 0.3, 0.6, 0.4, 0.9] : sparklineValues,
                    color: accent,
                    height: 22,
                    lineWidth: 2,
                    showsArea: true
                )
            )
        )
    }

    // MARK: 9. System / Live Notice HUD

    static func systemHUD(
        title: String,
        subtitle: String?,
        systemImage: String,
        progress: Double? = nil,
        accent: Color = IslandTheme.Accent.sky
    ) -> IslandActivityViews {
        IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 44,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 40),
                    detached: IslandSlotPair(leading: 20, trailing: 0)
                ),
                expandedHeight: 68
            ),
            compactLeading: AnyView(
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            compactTrailing: AnyView(
                Group {
                    if let progress {
                        IslandLinearProgress(value: progress, color: accent, height: 5)
                            .frame(width: 44)
                    } else {
                        Text(verbatim: title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(IslandTheme.Ink.primary)
                            .lineLimit(1)
                    }
                }
            ),
            minimal: AnyView(
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: systemImage, accent: accent, size: 48, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: title, subtitle: subtitle)
            ),
            expandedTrailing: AnyView(EmptyView()),
            expandedBottom: progress.map { AnyView(IslandLinearProgress(value: $0, color: accent, height: 6)) }
        )
    }

    // MARK: 10. Reusable ETA Activity Template (Playground / Future Extensions)

    static func etaTemplate(
        title: String,
        subtitle: String,
        etaMinutes: String,
        stepsDone: Int,
        totalSteps: Int,
        accent: Color = IslandTheme.Accent.green
    ) -> IslandActivityViews {
        let steps = (0..<max(1, totalSteps)).map { idx -> IslandStepState in
            if idx < stepsDone { return .done }
            if idx == stepsDone { return .active }
            return .pending
        }

        return IslandActivityViews(
            measure: IslandContentMeasure(
                leading: 22,
                trailing: 42,
                attached: 22,
                detached: 22,
                split: IslandSplitMeasure(
                    attached: IslandSlotPair(leading: 20, trailing: 38),
                    detached: IslandSlotPair(leading: 20, trailing: 14)
                ),
                expandedHeight: 88
            ),
            compactLeading: AnyView(
                Image(systemName: "box.truck.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            ),
            compactTrailing: AnyView(
                IslandNumberText(value: etaMinutes, fontSize: 14, weight: .semibold, color: accent)
            ),
            minimal: AnyView(
                IslandNumberText(value: etaMinutes, fontSize: 13, weight: .bold, color: accent)
            ),
            expandedLeading: AnyView(
                IslandTileArtwork(systemImage: "box.truck.fill", accent: accent, size: 52, radius: 12)
            ),
            expandedCenter: AnyView(
                IslandTitleStack(title: title, subtitle: subtitle)
            ),
            expandedTrailing: AnyView(
                IslandExpandedValueStack(value: etaMinutes, caption: "ETA", accent: accent)
            ),
            expandedBottom: AnyView(
                IslandStepProgress(steps: steps, color: accent, style: .bar, height: 5)
            )
        )
    }
}

// MARK: - Liquid Notch Metal Renderer, Animator & Shell (MIT: fellipegoncalvesleite/liquid-notch)

enum LiquidShaderSource {
    static let metal = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct Uniforms {
        float4 view;
        float4 notch;
        float4 mainB;
        float4 drop;
        float4 merge;
        float4 glow;
        float4 aura;
        float4 fill;
        float4 card;
        float4 card2;
        float4 pulse;
        float4 hair;
        float4 extra1;
        float4 extra2;
    };

    struct VOut { float4 position [[position]]; };

    vertex VOut liquid_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.position = float4(p * float2(2, -2) + float2(-1, 1), 0, 1);
        return o;
    }

    static float smin(float a, float b, float k) {
        if (k <= 1e-4) return min(a, b);
        float h = max(k - abs(a - b), 0.0) / k;
        return min(a, b) - h * h * k * 0.25;
    }

    static float sdRoundBox(float2 p, float2 b, float r, float n) {
        r = min(r, min(b.x, b.y));
        float2 q = abs(p) - b + r;
        float2 m = max(q, 0.0);
        float outside = (n == 2.0) ? length(m) : powr(powr(m.x, n) + powr(m.y, n), 1.0 / n);
        return outside + min(max(q.x, q.y), 0.0) - r;
    }

    static float sdEllipse(float2 p, float2 r) {
        float k0 = length(p / r);
        float k1 = length(p / (r * r));
        return k1 > 1e-5 ? k0 * (k0 - 1.0) / k1 : -min(r.x, r.y);
    }

    static float sdSegment(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
        return length(pa - ba * h);
    }

    constant float kTopExtension = 64.0;
    struct Field { float fill; float blob; float glow; };

    static Field liquidField(float2 p, constant Uniforms &u) {
        float cx = u.view.x * 0.5;
        float nh = u.notch.y;
        float dNotch = sdRoundBox(p - float2(cx, (nh - kTopExtension) * 0.5),
                                  float2(u.notch.x, (nh + kTopExtension) * 0.5), u.notch.z, 2.0);
        float mh = u.mainB.y;
        float dMain = sdRoundBox(p - float2(cx + u.card2.w, (mh - kTopExtension) * 0.5),
                                 float2(u.mainB.x, (mh + kTopExtension) * 0.5), u.mainB.z, u.mainB.w);
        float d = smin(dNotch, dMain, u.merge.x);

        float2 dr = u.drop.zw;
        if (min(dr.x, dr.y) > 0.05) {
            float2 dc = u.drop.xy;
            d = smin(d, sdEllipse(p - dc, dr), u.merge.y);
            float neck = u.merge.w;
            if (neck > 0.05) {
                float2 a = float2(cx + u.mainB.x - neck, dc.y);
                float dNeck = sdSegment(p, a, dc) - neck;
                d = smin(d, dNeck, min(u.merge.y, neck * 3.0));
            }
        }
        for (int i = 0; i < 2; i++) {
            float4 e = i == 0 ? u.extra1 : u.extra2;
            if (e.z > 0.05) d = smin(d, length(p - e.xy) - e.z, e.w);
        }
        float glowD = d;
        if (u.card.x > 0.5 && u.card.z > 0.5) {
            float rest = d;
            float dCard = sdRoundBox(p - float2(cx + u.card2.z, u.card.y + u.card.z * 0.5),
                                     float2(u.card.x, u.card.z * 0.5), u.card.w, u.mainB.w);
            float cn = u.card2.x;
            float kc = min(u.merge.y, cn * 3.0);
            if (cn > 0.05) {
                float dBridge = sdSegment(p, float2(cx + u.card2.w, mh - cn), float2(cx + u.card2.z, u.card.y + cn)) - cn;
                dCard = smin(dCard, dBridge, kc);
            }
            d = smin(d, dCard, kc);
            glowD = u.card2.y > 0.0 ? min(dCard, rest + u.card2.y) : d;
        }
        Field f;
        f.blob = d;
        f.glow = glowD;
        f.fill = smin(d, p.y, u.merge.z);
        return f;
    }

    static float hash12(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    fragment float4 liquid_fragment(VOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float scale = u.view.z;
        float2 p = in.position.xy / scale;
        Field f = liquidField(p, u);
        float px = max(fwidth(f.fill), 1e-4) * max(u.view.w, 0.25);
        float coverage = saturate(0.5 - f.fill / px);
        float g = u.glow.x * exp(-max(f.glow, 0.0) / max(u.glow.y, 0.1));
        g += (hash12(in.position.xy) - 0.5) * u.glow.z * step(1e-3, u.glow.x);
        g = saturate(g) * (1.0 - coverage);
        float gp = u.pulse.w * exp(-max(f.glow, 0.0) / 34.0) * (1.0 - coverage);
        float3 rgb = u.fill.rgb * coverage + u.aura.rgb * g + u.pulse.rgb * gp;
        float a = coverage + g + gp;
        if (u.hair.x > 0.0) {
            float line = u.hair.x * saturate(1.0 - abs(f.fill / px) / max(u.hair.y, 0.5)) * step(0.5, p.y);
            rgb += float3(line);
            a = max(a, line);
        }
        return float4(rgb, min(a, 1.0));
    }
    """#
}

struct LiquidSpring {
    var value: Double
    var velocity: Double = 0
    var target: Double
    var stiffness: Double
    var damping: Double
    var epsilon: Double

    init(_ value: Double, stiffness: Double = 190, damping: Double = 15, epsilon: Double = 0.01) {
        self.value = value
        self.target = value
        self.stiffness = stiffness
        self.damping = damping
        self.epsilon = epsilon
    }

    var isResting: Bool { value == target && velocity == 0 }

    mutating func step(_ dt: Double) {
        guard !isResting, dt > 0 else { return }
        let x0 = value - target
        let v0 = velocity
        let w = stiffness.squareRoot()
        let zeta = damping / (2 * w)
        let x: Double
        let v: Double
        if abs(zeta - 1) < 1e-4 {
            let e = exp(-w * dt)
            let c = v0 + w * x0
            x = e * (x0 + c * dt)
            v = e * (v0 - w * c * dt)
        } else if zeta < 1 {
            let a = zeta * w
            let wd = w * (1 - zeta * zeta).squareRoot()
            let e = exp(-a * dt)
            let cosT = cos(wd * dt), sinT = sin(wd * dt)
            x = e * (x0 * cosT + (v0 + a * x0) / wd * sinT)
            v = e * (v0 * cosT - (a * v0 + w * w * x0) / wd * sinT)
        } else {
            let s = (zeta * zeta - 1).squareRoot()
            let r1 = -w * (zeta - s), r2 = -w * (zeta + s)
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            let e1 = exp(r1 * dt), e2 = exp(r2 * dt)
            x = c1 * e1 + c2 * e2
            v = c1 * r1 * e1 + c2 * r2 * e2
        }
        if abs(x) < epsilon && abs(v) < epsilon * 10 {
            value = target; velocity = 0
        } else {
            value = target + x; velocity = v
        }
    }
}

@MainActor
final class LiquidRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: LiquidShaderSource.metal, options: nil) else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "liquid_vertex")
        desc.fragmentFunction = library.makeFunction(name: "liquid_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func draw(to layer: CAMetalLayer, uniforms: LiquidShapeUniforms) {
        guard let drawable = layer.nextDrawable(),
              let cb = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }
        var u = uniforms
        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&u, length: MemoryLayout<LiquidShapeUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilScheduled()
        drawable.present()
    }
}

@MainActor
final class LiquidMetalNSView: NSView {
    private let metalLayer = CAMetalLayer()
    private let renderer = LiquidRenderer()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var currentState: LiquidShapeState
    private var springs: [(WritableKeyPath<LiquidShapeState, Double>, LiquidSpring)] = []
    private var targetState: LiquidShapeState
    private var notchHalfWidth: Double = 92.5
    private var notchHeight: Double = 32

    init(initial: LiquidShapeState) {
        self.currentState = initial
        self.targetState = initial
        super.init(frame: .zero)
        wantsLayer = true
        metalLayer.device = renderer?.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        layer = metalLayer
        let keys: [WritableKeyPath<LiquidShapeState, Double>] = [
            \.mainHalfWidth, \.mainHeight, \.mainRadius, \.dropX, \.dropY, \.dropRadius,
            \.cardHalfWidth, \.cardTop, \.cardHeight, \.cardRadius, \.kBezel, \.glowIntensity
        ]
        springs = keys.map { ($0, LiquidSpring(initial[keyPath: $0])) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        link?.invalidate()
        guard window != nil else { return }
        let l = displayLink(target: self, selector: #selector(onFrame(_:)))
        l.isPaused = true
        l.add(to: .main, forMode: .common)
        link = l
        drawCurrent()
    }

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        drawCurrent()
    }

    func update(target: LiquidShapeState, notchHalfWidth: Double, notchHeight: Double, reduceMotion: Bool) {
        self.notchHalfWidth = notchHalfWidth
        self.notchHeight = notchHeight
        guard target != targetState else { return }
        targetState = target
        if reduceMotion {
            currentState = target
            for i in springs.indices {
                springs[i].1.value = target[keyPath: springs[i].0]
                springs[i].1.target = target[keyPath: springs[i].0]
                springs[i].1.velocity = 0
            }
            link?.isPaused = true
            drawCurrent()
            return
        }
        for i in springs.indices { springs[i].1.target = target[keyPath: springs[i].0] }
        if link?.isPaused == true {
            lastTimestamp = nil
            link?.isPaused = false
        }
    }

    @objc private func onFrame(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let dt = min(max(lastTimestamp.map { now - $0 } ?? (link.targetTimestamp - link.timestamp), 0), 1.0 / 30.0)
        lastTimestamp = now
        var moving = false
        for i in springs.indices {
            springs[i].1.step(dt)
            currentState[keyPath: springs[i].0] = springs[i].1.value
            if !springs[i].1.isResting { moving = true }
        }
        drawCurrent()
        if !moving {
            link.isPaused = true
            lastTimestamp = nil
        }
    }

    private func drawCurrent() {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let scale = Double(window?.backingScaleFactor ?? 2)
        let cardGap = max(0, currentState.cardTop - currentState.mainHeight)
        let cardNeck = (currentState.cardHalfWidth > 1 && cardGap < 14) ? max(0, 18 - cardGap) : 0
        let uniforms = LiquidShapeUniforms(
            state: currentState,
            viewSize: SIMD2(Double(bounds.width), Double(bounds.height)),
            scale: scale,
            notchHalfWidth: max(0, notchHalfWidth - 1),
            notchHeight: max(0, notchHeight - 1),
            cardNeck: cardNeck
        )
        renderer?.draw(to: metalLayer, uniforms: uniforms)
    }
}

private struct LiquidSurfaceRepresentable: NSViewRepresentable {
    let target: LiquidShapeState
    let notchHalfWidth: Double
    let notchHeight: Double
    let reduceMotion: Bool

    func makeNSView(context: Context) -> LiquidMetalNSView { LiquidMetalNSView(initial: target) }
    func updateNSView(_ nsView: LiquidMetalNSView, context: Context) {
        nsView.update(target: target, notchHalfWidth: notchHalfWidth, notchHeight: notchHeight, reduceMotion: reduceMotion)
    }
}

/// Liquid Notch shell view rendered when `LiveIslandSkin.liquid` is active.
struct LiquidNotchShellView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var feed: LiveActivityFeed
    let metrics: NotchMetrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPeekingEars = false
    @State private var showLyrics = false
    @State private var lyricsCache: [String: LiquidLyrics] = [:]
    @State private var lyricsLoadingKey: String?

    private var nowPlaying: NowPlayingState { feed.nowPlayingState }
    private var hasMusic: Bool { !(nowPlaying.title ?? "").isEmpty || feed.activity.kind == .music }

    private var mode: LiquidPresentationMode {
        if model.isExpanded { return .card }
        if isPeekingEars && hasMusic { return .peek }
        if feed.activity.kind != .clock || hasMusic { return .compact }
        return .idle
    }

    private var cardSize: CGSize {
        if showLyrics { return CGSize(width: 480, height: 220) }
        return model.openSize
    }

    private var targetState: LiquidShapeState {
        var s = LiquidShapeTargets.resting(
            mode: mode,
            notchHalfWidth: Double(metrics.closedSize.width) / 2,
            notchHeight: Double(metrics.closedSize.height),
            hasHardwareNotch: metrics.hasHardwareNotch,
            earExtent: (feed.activity.kind != .clock || hasMusic) ? 58 : 0,
            cardSize: cardSize
        )
        if let aura = albumAuraLab {
            s.auraL = aura.x; s.auraA = aura.y; s.auraB = aura.z
        }
        return s
    }

    private var albumAuraLab: SIMD3<Double>? {
        guard let data = nowPlaying.artworkData, let img = NSImage(data: data),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = NSBitmapImageRep(cgImage: cg).converting(to: .sRGB, renderingIntent: .perceptual),
              let c = rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2) else { return nil }
        return LiquidOKLab.fromSRGB(SIMD3(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)))
    }

    private var artworkImage: NSImage? {
        nowPlaying.artworkData.flatMap(NSImage.init(data:))
    }

    var body: some View {
        ZStack(alignment: .top) {
            LiquidSurfaceRepresentable(
                target: targetState,
                notchHalfWidth: metrics.hasHardwareNotch ? Double(metrics.closedSize.width) / 2 : 0,
                notchHeight: metrics.hasHardwareNotch ? Double(metrics.closedSize.height) : 0,
                reduceMotion: reduceMotion
            )
            .allowsHitTesting(false)

            if !model.isExpanded && hasMusic {
                compactEarsAndPeek
            }

            if model.isExpanded {
                expandedContent
                    .frame(width: cardSize.width, height: cardSize.height)
                    .padding(.top, targetState.cardTop)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: model.isExpanded) { _, expanded in
            if !expanded { showLyrics = false }
        }
    }

    private var compactEarsAndPeek: some View {
        let earWidth = targetState.mainHalfWidth * 2
        return VStack(spacing: 2) {
            HStack {
                IslandTileArtwork(image: artworkImage, systemImage: "music.note", accent: .pink, size: 20, radius: 6)
                Spacer()
                IslandLevelMeter(bars: 4, color: .pink, height: 13, barWidth: 2.4, gap: 1.8, active: nowPlaying.isPlaying)
            }
            .padding(.horizontal, 10)
            .frame(width: earWidth, height: targetState.mainHeight - (isPeekingEars ? 12 : 0))

            if isPeekingEars {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: nowPlaying.title ?? "")
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(verbatim: nowPlaying.artist ?? "")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Button { feed.previousTrack() } label: { Image(systemName: "backward.fill").font(.system(size: 10)) }
                        Button { feed.togglePlayPause() } label: { Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 11)) }
                        Button { feed.nextTrack() } label: { Image(systemName: "forward.fill").font(.system(size: 10)) }
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                }
                .padding(.horizontal, 12)
                .frame(width: earWidth, height: 22)
            }
        }
        .contentShape(Rectangle())
        .onHover { isPeekingEars = $0 }
        .onTapGesture { model.requestOpen() }
    }

    @ViewBuilder
    private var expandedContent: some View {
        if hasMusic && showLyrics {
            LiquidSyncedLyricsView(
                nowPlaying: nowPlaying,
                lyrics: lyricsCache[LiquidLyricsSource.key(title: nowPlaying.title ?? "", artist: nowPlaying.artist ?? "")],
                isLoading: lyricsLoadingKey == LiquidLyricsSource.key(title: nowPlaying.title ?? "", artist: nowPlaying.artist ?? ""),
                onBack: { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { showLyrics = false } },
                onSeek: { feed.seek(to: $0) }
            )
        } else if hasMusic {
            LiquidPlayerCardView(
                nowPlaying: nowPlaying,
                artwork: artworkImage,
                onToggleLyrics: { openLyricsIfNeeded() },
                onPrevious: { feed.previousTrack() },
                onTogglePlayPause: { feed.togglePlayPause() },
                onNext: { feed.nextTrack() },
                onSeek: { feed.seek(to: $0) }
            )
        } else {
            NotchHomeView(model: model, feed: feed, metrics: metrics, calendarEnabled: true)
        }
    }

    private func openLyricsIfNeeded() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { showLyrics = true }
        let title = nowPlaying.title ?? ""
        let artist = nowPlaying.artist ?? ""
        let key = LiquidLyricsSource.key(title: title, artist: artist)
        guard !title.isEmpty, lyricsCache[key] == nil, lyricsLoadingKey != key else { return }
        lyricsLoadingKey = key
        let album = nowPlaying.album ?? ""
        let duration = nowPlaying.duration
        Task {
            let fetched = await LiquidLyricsSource.fetch(title: title, artist: artist, album: album, duration: duration)
            await MainActor.run {
                if let fetched { lyricsCache[key] = fetched }
                if lyricsLoadingKey == key { lyricsLoadingKey = nil }
            }
        }
    }
}

private struct LiquidPlayerCardView: View {
    let nowPlaying: NowPlayingState
    let artwork: NSImage?
    let onToggleLyrics: () -> Void
    let onPrevious: () -> Void
    let onTogglePlayPause: () -> Void
    let onNext: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: nowPlaying.isPlaying ? 0.5 : 60)) { context in
            let progress = nowPlaying.progress(at: context.date) ?? 0
            let elapsed = NowPlayingProgress.elapsed(
                at: context.date, elapsed: nowPlaying.elapsed, asOf: nowPlaying.elapsedAsOf,
                rate: nowPlaying.rate, duration: nowPlaying.duration
            ) ?? 0
            let duration = nowPlaying.duration ?? 0
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: onToggleLyrics) {
                        IslandTileArtwork(image: artwork, systemImage: "music.note", accent: .pink, size: 54, radius: 14)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Lyrics"))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: nowPlaying.title ?? "")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        Text(verbatim: nowPlaying.artist ?? "")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                    Spacer()
                    IslandLevelMeter(bars: 4, color: .pink, height: 18, barWidth: 3, gap: 2.2, active: nowPlaying.isPlaying)
                }
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.18))
                            Capsule().fill(.white).frame(width: max(4, geo.size.width * progress))
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                            guard duration > 0 else { return }
                            let frac = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                            onSeek(frac * duration)
                        })
                    }
                    .frame(height: 5)
                    HStack {
                        Text(verbatim: formatTime(elapsed)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                        Spacer()
                        Text(verbatim: duration > 0 ? formatTime(duration) : "--:--").font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                ZStack {
                    HStack(spacing: 32) {
                        Button(action: onPrevious) { Image(systemName: "backward.fill").font(.system(size: 18)) }
                        Button(action: onTogglePlayPause) { Image(systemName: nowPlaying.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 22)) }
                        Button(action: onNext) { Image(systemName: "forward.fill").font(.system(size: 18)) }
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    HStack {
                        Button(action: onToggleLyrics) { Image(systemName: "quote.bubble").font(.system(size: 14)) }
                            .buttonStyle(.plain).foregroundStyle(.white.opacity(0.75))
                        Spacer()
                        LiquidRoutePickerView().frame(width: 22, height: 22)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
    }

    private func formatTime(_ sec: Double) -> String {
        let s = max(0, Int(sec.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

private struct LiquidRoutePickerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.isRoutePickerButtonBordered = false
        v.setRoutePickerButtonColor(.white, for: .normal)
        v.setRoutePickerButtonColor(.systemBlue, for: .active)
        return v
    }
    func updateNSView(_ nsView: AVRoutePickerView, context: Context) {}
}

private struct LiquidSyncedLyricsView: View {
    let nowPlaying: NowPlayingState
    let lyrics: LiquidLyrics?
    let isLoading: Bool
    let onBack: () -> Void
    let onSeek: (Double) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: nowPlaying.isPlaying ? 0.1 : 60)) { context in
            let elapsed = NowPlayingProgress.elapsed(
                at: context.date, elapsed: nowPlaying.elapsed, asOf: nowPlaying.elapsedAsOf,
                rate: nowPlaying.rate, duration: nowPlaying.duration
            ) ?? 0
            let activeIndex = lyrics?.current(at: elapsed)
            VStack(spacing: 8) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    Text(verbatim: nowPlaying.title ?? "")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer()
                }
                if isLoading {
                    Spacer()
                    ProgressView().controlSize(.small).tint(.white)
                    Spacer()
                } else if let lyrics, !lyrics.lines.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 8) {
                                ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { idx, line in
                                    Button { onSeek(line.time) } label: {
                                        Text(verbatim: line.text.isEmpty ? "•••" : line.text)
                                            .font(.system(size: 14, weight: idx == activeIndex ? .bold : .medium))
                                            .foregroundStyle(.white.opacity(idx == activeIndex ? 1.0 : 0.38))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.plain)
                                    .id(idx)
                                }
                            }
                            .padding(.vertical, 24)
                        }
                        .onChange(of: activeIndex) { _, target in
                            guard let target else { return }
                            withAnimation(.timingCurve(0.35, 0, 0.15, 1, duration: 0.6)) {
                                proxy.scrollTo(target, anchor: .center)
                            }
                        }
                    }
                } else if let lyrics, !lyrics.plain.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(Array(lyrics.plain.enumerated()), id: \.offset) { _, line in
                                Text(verbatim: line).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8))
                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                } else {
                    Spacer()
                    Text("No lyrics found").font(.system(size: 13)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
        }
    }
}
