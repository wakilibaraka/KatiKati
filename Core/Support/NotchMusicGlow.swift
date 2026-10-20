import Foundation

/// The artwork-coloured glow on the collapsed notch's right ear (roadmap 50d). It stands in for the
/// old track-change popup: the notch no longer opens for a new song, the glow brightens instead.
enum NotchMusicGlow: String, CaseIterable, Identifiable, Sendable {
    case halo, pulse, edge

    static let defaultsKey = "com.katikati.notch.musicGlow"
    static let `default`: NotchMusicGlow = .halo
    /// Resting brightness; a track change flashes to 1 and eases back.
    static let restLevel = 0.55
    static let pulsePeriod: TimeInterval = 3

    var id: String { rawValue }

    /// Only `pulse` moves, and Reduce Motion turns it into the static halo.
    func isAnimated(reduceMotion: Bool) -> Bool { self == .pulse && !reduceMotion }

    /// 0...1 brightness at `time` seconds; `boost` (0...1) lifts it toward full on a track change.
    func level(at time: TimeInterval, boost: Double, reduceMotion: Bool) -> Double {
        var base = Self.restLevel
        if isAnimated(reduceMotion: reduceMotion) {
            base *= 0.7 + 0.3 * (0.5 + 0.5 * sin(2 * .pi * time / Self.pulsePeriod))
        }
        return min(1, base + (1 - base) * min(max(boost, 0), 1))
    }
}
