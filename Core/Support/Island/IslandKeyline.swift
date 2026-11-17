import Foundation

public enum IslandKeylineSetting: String, CaseIterable, Hashable, Sendable {
    case auto
    case on
    case off
}

/// Computes gamma-encoded Rec. 709 luma (`0...1`) of a `#RGB`, `#RRGGBB`, or `rgb(r,g,b)` color string.
/// Returns `nil` if unparseable.
public func islandColourLuma(_ colour: String) -> Double? {
    let trimmed = colour.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.hasPrefix("#") {
        let hex = String(trimmed.dropFirst())
        let pairs: [String]
        if hex.count == 3 {
            pairs = hex.map { "\($0)\($0)" }
        } else if hex.count == 6 || hex.count == 8 {
            let chars = Array(hex.prefix(6))
            pairs = stride(from: 0, to: 6, by: 2).map { String(chars[$0...($0 + 1)]) }
        } else {
            return nil
        }
        guard pairs.count == 3,
              let r = Int(pairs[0], radix: 16),
              let g = Int(pairs[1], radix: 16),
              let b = Int(pairs[2], radix: 16) else {
            return nil
        }
        return (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
    }

    if trimmed.hasPrefix("rgb") {
        guard let open = trimmed.firstIndex(of: "("),
              let close = trimmed.firstIndex(of: ")"),
              open < close else {
            return nil
        }
        let body = trimmed[trimmed.index(after: open)..<close]
        let parts = body.split { $0 == "," || $0 == " " || $0 == "/" }.prefix(3)
        let values = parts.compactMap { Double($0) }
        guard values.count == 3 else { return nil }
        return (0.2126 * values[0] + 0.7152 * values[1] + 0.0722 * values[2]) / 255.0
    }

    return nil
}

/// Computes Rec. 709 luma from linearized/display sRGB `0...1` channel components.
public func islandSRGBLuma(r: Double, g: Double, b: Double) -> Double {
    let clamp = { (v: Double) in min(1.0, max(0.0, v)) }
    return 0.2126 * clamp(r) + 0.7152 * clamp(g) + 0.0722 * clamp(b)
}

/// Interpolated keyline rim opacity from `metrics.keylineFade` table (`islandcn` OLED dark rim calibration).
public func islandKeylineAlphaFor(luma: Double, metrics: IslandMetrics) -> Double {
    let k = metrics.keyline
    guard !luma.isNaN else { return 0 }
    if luma >= k.noneFrom { return 0 }
    if luma <= k.fullUntil { return k.alpha }
    var from = IslandMetrics.KeylineFadePoint(luma: k.fullUntil, share: 1.0)
    for point in metrics.keylineFade {
        if point.luma <= from.luma || point.luma >= k.noneFrom {
            continue
        }
        if luma <= point.luma {
            let t = (luma - from.luma) / (point.luma - from.luma)
            return k.alpha * from.share * pow(point.share / from.share, t)
        }
        from = point
    }
    return k.alpha * from.share * (1.0 - (luma - from.luma) / (k.noneFrom - from.luma))
}

/// Resolves steady keyline alpha across system dark appearance, OLED black backdrop, and optional sampled wallpaper luma.
public func islandResolvedKeylineAlpha(
    setting: IslandKeylineSetting,
    backdropLuma: Double?,
    isDarkAppearance: Bool,
    isOLEDDisplay: Bool,
    metrics: IslandMetrics
) -> Double {
    switch setting {
    case .off:
        return 0
    case .on:
        if let backdropLuma {
            return max(islandKeylineAlphaFor(luma: backdropLuma, metrics: metrics), metrics.keyline.alpha * 0.5)
        }
        return metrics.keyline.alpha
    case .auto:
        if let backdropLuma {
            return islandKeylineAlphaFor(luma: backdropLuma, metrics: metrics)
        }
        return (isDarkAppearance || isOLEDDisplay) ? metrics.keyline.alpha : 0
    }
}

/// Transient keyline dim multiplier (`dip` -> `1.0`) played during expanded -> compact/split collapses.
public func islandKeylineDimMultiplier(elapsedSeconds: Double?, motion: IslandKeylineMotion) -> Double {
    guard let elapsed = elapsedSeconds, elapsed >= 0 else { return 1.0 }
    if elapsed >= motion.backAt { return 1.0 }
    if elapsed <= motion.dipAt {
        let u = min(1.0, elapsed / max(1e-4, motion.dipAt))
        return 1.0 - (1.0 - motion.dip) * u
    }
    let u = (elapsed - motion.dipAt) / max(1e-4, motion.backAt - motion.dipAt)
    return motion.dip + (1.0 - motion.dip) * u
}
