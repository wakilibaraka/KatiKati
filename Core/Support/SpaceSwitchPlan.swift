import Foundation

/// Which Space a request lands on, and how the Dock is asked to get there.
///
/// Ported from Spacewalk (MIT, © 2026 InsaneArts) — the pure half of its `SpaceEngine.Plan`. The
/// switching itself is the Dock's own, driven by `DockSwipeEventPoster`; nothing here touches the OS.
enum SpaceTransitionEffect: String, CaseIterable, Sendable {
    case instant, fade
}

/// Where Settings › Appearance keeps the two Space-transition knobs. Read straight from the
/// defaults on every switch, so the controller and the pane need no shared object.
enum SpaceTransitionSettings {
    static let effectKey = "com.katikati.spaces.effect"
    static let durationKey = "com.katikati.spaces.duration"
    static let defaultDuration: Double = 0.24
    static let durationRange: ClosedRange<Double> = 0.1 ... 0.6

    static func effect(from defaults: UserDefaults = .standard) -> SpaceTransitionEffect {
        SpaceTransitionEffect(rawValue: defaults.string(forKey: effectKey) ?? "") ?? .fade
    }

    /// Clamped: a hand-edited key cannot leave the slider's range.
    static func duration(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: durationKey) != nil else { return defaultDuration }
        return min(max(defaults.double(forKey: durationKey), durationRange.lowerBound), durationRange.upperBound)
    }
}

struct SpaceSwitchPlan: Equatable, Sendable {
    let fromIndex: Int
    let toIndex: Int

    /// Dock swipes it takes: one per Space crossed, so 2→4 is two rightward swipes.
    var steps: Int { abs(toIndex - fromIndex) }

    /// A rightward swipe, in the same sense the fullscreen-intent code uses (`SpaceSwitchDirection.right`
    /// is the next Space in Mission Control order). `DockSwipeEventPoster` flips the sign on the macOS 27
    /// path, where direction is relative to natural scrolling.
    var direction: SpaceSwitchDirection { toIndex > fromIndex ? .right : .left }

    /// `nil` when there is nowhere to go: one Space, no wrap, or an index that is not in the list.
    /// Indices are positions in the desktop-only list — fullscreen Spaces are not switchable this way.
    static func plan(
        currentIndex: Int,
        spaceCount: Int,
        direction: SpaceSwitchDirection,
        wrap: Bool
    ) -> SpaceSwitchPlan? {
        guard spaceCount > 1, (0 ..< spaceCount).contains(currentIndex) else { return nil }
        let raw = direction == .right ? currentIndex + 1 : currentIndex - 1
        guard raw < 0 || raw >= spaceCount else {
            return SpaceSwitchPlan(fromIndex: currentIndex, toIndex: raw)
        }
        guard wrap else { return nil }
        return SpaceSwitchPlan(fromIndex: currentIndex, toIndex: raw >= spaceCount ? 0 : spaceCount - 1)
    }
}
