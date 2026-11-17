import AppKit
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
