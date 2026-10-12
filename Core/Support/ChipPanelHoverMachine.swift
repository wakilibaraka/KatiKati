import Foundation

// Phase 9-0 — hover intent for the floating chip panel (window preview). Pure: the caller passes
// `now`, so the open delay, the close grace and the "bridge" (pointer travelling from the chip to
// the panel keeps it open) are all unit-tested without a clock. Same shape as `NotchHoverMachine`.

struct ChipPanelHoverMachine {
    enum Output: Equatable {
        case none
        case open(chipID: String)
        case switchTo(chipID: String)
        case close
    }

    var openDelay: TimeInterval
    var closeGrace: TimeInterval

    private(set) var shown: String?
    private var pendingChip: String?
    private var pendingSince: TimeInterval = 0
    private var leftSince: TimeInterval?

    init(openDelay: TimeInterval = 0.35, closeGrace: TimeInterval = 0.25) {
        self.openDelay = openDelay
        self.closeGrace = closeGrace
    }

    var isIdle: Bool { shown == nil && pendingChip == nil }

    /// - Parameters:
    ///   - overChip: the chip the pointer is on right now (nil = none).
    ///   - overPanel: the pointer is inside the open panel (the bridge).
    ///   - blocked: a drag is in progress or previews are off — nothing may open.
    mutating func update(overChip: String?, overPanel: Bool, blocked: Bool = false, now: TimeInterval) -> Output {
        if blocked {
            pendingChip = nil
            return forceClose()
        }
        if shown != nil {
            if overPanel {
                leftSince = nil
                return .none
            }
            if let chip = overChip {
                leftSince = nil
                if chip == shown { return .none }
                shown = chip
                return .switchTo(chipID: chip)
            }
            let since = leftSince ?? now
            leftSince = since
            if now - since >= closeGrace { return forceClose() }
            return .none
        }
        guard let chip = overChip else {
            pendingChip = nil
            return .none
        }
        if pendingChip != chip {
            pendingChip = chip
            pendingSince = now
        }
        if now - pendingSince >= openDelay {
            pendingChip = nil
            shown = chip
            leftSince = nil
            return .open(chipID: chip)
        }
        return .none
    }

    @discardableResult
    mutating func forceClose() -> Output {
        pendingChip = nil
        leftSince = nil
        guard shown != nil else { return .none }
        shown = nil
        return .close
    }
}
