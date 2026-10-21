import Foundation

/// 54e — when a focus-follows-mouse move may raise another app's window. Off by default, and every rule
/// here exists to keep it out of the way: it never acts mid-drag, while one of our own panels has the
/// keyboard, for our own windows, or for the app that is already in front, and at most once per 120 ms.
struct FocusFollowPolicy: Equatable, Sendable {
    static let minimumInterval: TimeInterval = 0.12

    /// When the last raise actually happened; nil = none yet.
    var lastRaiseAt: Date?

    func allowsRaise(targetPID: pid_t?, frontmostPID: pid_t?, ownPID: pid_t,
                     mouseButtonDown: Bool, ownPanelIsKey: Bool, now: Date) -> Bool {
        guard !mouseButtonDown, !ownPanelIsKey else { return false }
        guard let targetPID, targetPID != ownPID, targetPID != frontmostPID else { return false }
        if let lastRaiseAt, now.timeIntervalSince(lastRaiseAt) < Self.minimumInterval { return false }
        return true
    }
}
