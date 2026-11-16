import Foundation

// Phase 9c safeguards (2026-11-16) — when the hover preview may capture a window.
//
// The capture loop had three holes: every 0.5 s tick started a fresh capture per window
// with nothing tracking the ones still running, nothing paused it when the display slept or
// the session locked, and Screen Recording could be revoked under an open panel while the
// frames taken before it stayed on screen. The decisions live here, pure, so each one is
// tested without a panel, a clock or a permission grant.

struct ChipPanelCapturePolicy {
    enum Verdict: Equatable {
        case run
        /// Closed, or showing the jump list, which draws no thumbnails.
        case idle
        /// Not authorised: drop what was captured and stop refreshing until it returns.
        case revoked
    }

    /// One decision per tick, using the cached verdict. TCC is refreshed off-main at a
    /// throttled cadence; a revoked result invalidates already captured frames.
    static func verdict(isOpen: Bool, isPreview: Bool, isAuthorized: Bool) -> Verdict {
        guard isOpen, isPreview else { return .idle }
        return isAuthorized ? .run : .revoked
    }

    /// Display sleep, system sleep and a locked or switched-away session all make a capture
    /// pointless; the frames taken before them are stale once the screen comes back.
    static func isPaused(displayAsleep: Bool, systemAsleep: Bool, sessionInactive: Bool) -> Bool {
        displayAsleep || systemAsleep || sessionInactive
    }

    /// Whether a cached authorization verdict is old enough to refresh. The synchronous TCC
    /// preflight must run away from the main actor, and only one check may be outstanding.
    static func shouldCheckAuthorization(now: TimeInterval, lastCheck: TimeInterval,
                                         interval: TimeInterval, isInFlight: Bool,
                                         force: Bool = false) -> Bool {
        !isInFlight && (force || now - lastCheck >= interval)
    }

    /// Whether an asynchronous authorization result still belongs to the current availability epoch.
    static func mayApplyAuthorizationResult(startedGeneration: UInt64,
                                            currentGeneration: UInt64) -> Bool {
        startedGeneration == currentGeneration
    }

    /// Whether a completed capture still belongs to the current visible/authorized panel state.
    static func mayApplyCapture(isOpen: Bool, isAuthorized: Bool,
                                startedGeneration: UInt64, currentGeneration: UInt64) -> Bool {
        isOpen && isAuthorized && startedGeneration == currentGeneration
    }

    /// Windows that may start a capture now.
    ///
    /// The preview list is already capped by `ChipPanelModel.previewWindows`; this only
    /// removes captures still in-flight and collapses duplicate IDs. A hung window stays
    /// unavailable until its operation actually returns, so ticks and wake events cannot
    /// stack replacements behind it.
    static func dueWindowIDs(_ ready: [String], inFlight: Set<String>) -> [String] {
        var claimed = inFlight
        var due: [String] = []
        for id in ready where !claimed.contains(id) {
            claimed.insert(id)
            due.append(id)
        }
        return due
    }
}
