import Foundation

// Phase 5g-F — pure, deterministic particle layout for the animated hero background. Every
// position is an analytic function of (index, time), so there is no mutable simulation state:
// the view just asks "where is everything at t?" once per frame. Normalised 0…1 coordinates.

public struct WeatherEffectPlan: Equatable, Sendable {
    public var rainDrops = 0
    public var snowflakes = 0
    public var clouds = 0
    public var stars = 0
    public var fog = false
    public var sunGlow = false
    public var thunder = false
    /// 0 light … 1 storm-dark; deepens the cloud colour.
    public var cloudDarkness = 0.0

    public var isStatic: Bool { self == WeatherEffectPlan() }

    public static func plan(condition: WeatherCondition, isNight: Bool) -> WeatherEffectPlan {
        var p = WeatherEffectPlan()
        switch condition {
        case .clear:
            if isNight { p.stars = 45 } else { p.sunGlow = true; p.clouds = 1 }
        case .partlyCloudy:
            p.clouds = 3
            if isNight { p.stars = 25 } else { p.sunGlow = true }
        case .cloudy:
            p.clouds = 5; p.cloudDarkness = 0.35
        case .fog:
            p.fog = true; p.clouds = 2; p.cloudDarkness = 0.2
        case .drizzle:
            p.rainDrops = 40; p.clouds = 4; p.cloudDarkness = 0.4
        case .rain:
            p.rainDrops = 90; p.clouds = 5; p.cloudDarkness = 0.55
        case .showers:
            p.rainDrops = 160; p.clouds = 6; p.cloudDarkness = 0.65
        case .snow:
            p.snowflakes = 80; p.clouds = 4; p.cloudDarkness = 0.25
        case .thunderstorm:
            p.rainDrops = 140; p.clouds = 6; p.thunder = true; p.cloudDarkness = 0.9
        }
        return p
    }
}

public enum WeatherEffects {
    /// Stable pseudo-random value in 0..<1 for (index, salt).
    public static func unit(_ index: Int, _ salt: Int) -> Double {
        var x = UInt64(truncatingIfNeeded: index &* 0x9E37_79B9 &+ salt &* 0x85EB_CA6B &+ 0x1234_5678)
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        x ^= x >> 31
        return Double(x % 1_000_000) / 1_000_000
    }

    private static func fract(_ v: Double) -> Double { v - v.rounded(.down) }

    public struct Drop: Equatable { public let x, y, length, alpha: Double }
    public static func rain(count: Int, at t: Double) -> [Drop] {
        (0..<count).map { i in
            let speed = 0.9 + unit(i, 2) * 0.8
            let y = fract(unit(i, 3) + t * speed)
            return Drop(x: fract(unit(i, 1) + y * 0.12), y: y, length: 0.035 + unit(i, 4) * 0.05, alpha: 0.25 + unit(i, 5) * 0.45)
        }
    }

    public struct Flake: Equatable { public let x, y, radius, alpha: Double }
    public static func snow(count: Int, at t: Double) -> [Flake] {
        (0..<count).map { i in
            let speed = 0.06 + unit(i, 2) * 0.10
            let sway = 0.025 * sin(t * (0.6 + unit(i, 6)) + unit(i, 7) * 6.28)
            return Flake(x: fract(unit(i, 1) + sway), y: fract(unit(i, 3) + t * speed),
                         radius: 1 + unit(i, 4) * 2.4, alpha: 0.5 + unit(i, 5) * 0.5)
        }
    }

    public struct Cloud: Equatable { public let x, y, scale, alpha: Double }
    /// x spans -0.3…1.3 so a cloud drifts fully off one side before wrapping to the other.
    public static func clouds(count: Int, at t: Double) -> [Cloud] {
        (0..<count).map { i in
            let speed = 0.012 + unit(i, 2) * 0.02
            return Cloud(x: fract(unit(i, 1) + t * speed) * 1.6 - 0.3, y: 0.05 + unit(i, 3) * 0.55,
                         scale: 0.6 + unit(i, 4) * 0.8, alpha: 0.35 + unit(i, 5) * 0.4)
        }
    }

    public struct Star: Equatable { public let x, y, radius, alpha: Double }
    public static func stars(count: Int, at t: Double) -> [Star] {
        (0..<count).map { i in
            let twinkle = 0.5 + 0.5 * sin(t * (0.8 + unit(i, 6) * 1.6) + unit(i, 7) * 6.28)
            return Star(x: unit(i, 1), y: unit(i, 3) * 0.75, radius: 0.6 + unit(i, 4) * 1.1, alpha: 0.25 + 0.75 * twinkle)
        }
    }

    /// Lightning flash brightness 0…1: most 6-second blocks carry a quick double flash.
    public static func flash(at t: Double) -> Double {
        let block = Int((t / 6).rounded(.down))
        guard unit(block, 10) > 0.3 else { return 0 }
        let local = t - Double(block) * 6 - (1 + unit(block, 9) * 4)
        if local > 0, local < 0.12 { return 1 }
        if local > 0.2, local < 0.3 { return 0.6 }
        return 0
    }

    /// Slow 0…1 breathing for the sun glow / fog drift.
    public static func pulse(at t: Double, period: Double = 8) -> Double { 0.5 + 0.5 * sin(t * 2 * .pi / period) }
}
