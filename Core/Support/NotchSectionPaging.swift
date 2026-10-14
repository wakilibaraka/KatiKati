import Foundation

// Phase 33c — NotchSectionPaging: 5-page bento gallery structure, discrete row paging,
// and context-aware default page opening logic. Dual-compiled.

/// The 6 dedicated pages of the redesigned Dynamic Island Notch bento gallery.
enum NotchPage: Int, CaseIterable, Identifiable, Sendable {
    case aiTracker = 0      // Page 1: AI Mission Control (Claude, Codex, OpenCode, Copilot)
    case audioDeck = 1      // Page 2: Vinyl Turntable & Audio Scrubber Deck
    case retroClock = 2     // Page 3: Split-Flap Orange Clock & LED Dot Matrix Ticker
    case downloadDeck = 3   // Page 4: Download Manager & Torrent Hub
    case calendarFocus = 4  // Page 5: Obsidian Calendar & Focus Hourglass / Spinner
    case hardwareHud = 5    // Page 6: Hardware HUD & Sensory Deck

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .aiTracker: return "AI Mission Control"
        case .audioDeck: return "Vinyl Audio Deck"
        case .retroClock: return "Retro Flip Clock"
        case .downloadDeck: return "Downloads & Torrents"
        case .calendarFocus: return "Obsidian Calendar"
        case .hardwareHud: return "Hardware HUD"
        }
    }

    var symbol: String {
        switch self {
        case .aiTracker: return "sparkles"
        case .audioDeck: return "music.note"
        case .retroClock: return "clock.fill"
        case .downloadDeck: return "arrow.down.circle.fill"
        case .calendarFocus: return "calendar"
        case .hardwareHud: return "cpu"
        }
    }

    func next(wrap: Bool = true) -> NotchPage {
        let all = Self.allCases
        let nextIndex = rawValue + 1
        if nextIndex < all.count {
            return all[nextIndex]
        }
        return wrap ? all[0] : self
    }

    func previous(wrap: Bool = true) -> NotchPage {
        let all = Self.allCases
        let prevIndex = rawValue - 1
        if prevIndex >= 0 {
            return all[prevIndex]
        }
        return wrap ? all[all.count - 1] : self
    }
}

/// Dynamic context-aware default page resolver.
enum NotchPagingPolicy {
    static func defaultPage(
        nowPlayingActive: Bool,
        aiTurnActive: Bool,
        timerActive: Bool,
        downloadsActive: Bool = false,
        userPinnedPage: NotchPage? = nil
    ) -> NotchPage {
        if let pinned = userPinnedPage { return pinned }
        if downloadsActive { return .downloadDeck }
        if aiTurnActive { return .aiTracker }
        if nowPlayingActive { return .audioDeck }
        if timerActive { return .calendarFocus }
        return .aiTracker
    }
}

/// Pure Companion State policy:
/// When Notch is active / expanded, the dock capsule auto-hides or dims to avoid visual duplication.
enum NotchDockCompanionPolicy {
    static func shouldHideDockCapsule(notchExpanded: Bool, dockCompanionAutoHide: Bool = true) -> Bool {
        dockCompanionAutoHide && notchExpanded
    }
}

/// Wheel and trackpad input accumulator for horizontal page stepping.
struct NotchSectionScroll: Sendable {
    static let firstStep: Double = 24.0
    static let pageStep: Double = 60.0
    static let sequenceGap: TimeInterval = 0.35

    private var distance: Double = 0.0
    private var direction: Int = 0
    private var stepped: Bool = false
    private var lastTimestamp: TimeInterval?

    /// Steps to move across pages; positive = forward (next), negative = backward (previous).
    mutating func steps(
        deltaX: Double,
        timestamp: TimeInterval,
        precise: Bool,
        hasPhase: Bool,
        began: Bool,
        ended: Bool,
        momentum: Bool
    ) -> Int {
        guard deltaX.isFinite, timestamp.isFinite else { self = Self(); return 0 }
        if momentum { return 0 }
        if ended { self = Self(); return 0 }
        guard precise else {
            self = Self()
            return deltaX == 0 ? 0 : (deltaX < 0 ? 1 : -1)
        }
        if began || lastTimestamp.map({ timestamp < $0 || (!hasPhase && timestamp - $0 > Self.sequenceGap) }) == true {
            self = Self()
        }
        lastTimestamp = timestamp
        if deltaX != 0 {
            let incomingDirection = deltaX < 0 ? 1 : -1
            if direction != 0, direction != incomingDirection { distance = 0; stepped = false }
            direction = incomingDirection
        }
        distance += deltaX
        var steps = 0
        let threshold = stepped ? Self.pageStep : Self.firstStep
        while abs(distance) >= threshold {
            distance = distance > 0 ? distance - threshold : distance + threshold
            stepped = true
            steps += 1
        }
        return direction * steps
    }
}
