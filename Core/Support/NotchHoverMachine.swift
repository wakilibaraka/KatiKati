import CoreGraphics
import Foundation

// Notch hover intent — a pure state machine so the panel opens on a deliberate dwell and closes after a
// short grace period, independent of the window resizing (which used to feed back into SwiftUI's
// `.onHover` and made the notch flicker open/closed). The controller feeds it the cursor position from a
// mouse-moved monitor and schedules a wake-up at `nextDeadline`. Dual-compiled.

struct NotchHoverMachine {
    /// How long the cursor must rest on the notch before it opens (a fast pass along the menu bar doesn't).
    var openDelay: TimeInterval = 0.12
    /// How long the cursor may be outside the open panel before it closes (absorbs jitter and overshoot).
    var closeDelay: TimeInterval = 0.25

    private(set) var isOpen = false
    private var openingSince: Date?
    private var closingSince: Date?

    /// Feed the latest facts; returns whether the notch should now be open.
    /// - Parameters:
    ///   - inTrigger: cursor is over the closed notch (opens it).
    ///   - inKeepOpen: cursor is inside the open panel's keep-open zone (holds it open).
    ///   - pinned: something holds it open regardless (a drag in progress, an event toast).
    @discardableResult
    mutating func update(inTrigger: Bool, inKeepOpen: Bool, pinned: Bool, now: Date) -> Bool {
        if isOpen {
            openingSince = nil
            if inKeepOpen || pinned {
                closingSince = nil
            } else {
                let since = closingSince ?? now
                closingSince = since
                if now.timeIntervalSince(since) >= closeDelay {
                    isOpen = false
                    closingSince = nil
                }
            }
        } else {
            closingSince = nil
            if inTrigger {
                let since = openingSince ?? now
                openingSince = since
                if now.timeIntervalSince(since) >= openDelay {
                    isOpen = true
                    openingSince = nil
                }
            } else {
                openingSince = nil
            }
        }
        return isOpen
    }

    /// Opens immediately (an event toast) and resets any pending close.
    mutating func forceOpen() {
        isOpen = true
        openingSince = nil
        closingSince = nil
    }

    /// Closes immediately (after an action such as opening Settings).
    mutating func forceClose() {
        isOpen = false
        openingSince = nil
        closingSince = nil
    }

    /// When the controller should call `update` again even if the cursor doesn't move, or nil.
    var nextDeadline: Date? {
        if let openingSince { return openingSince.addingTimeInterval(openDelay) }
        if let closingSince { return closingSince.addingTimeInterval(closeDelay) }
        return nil
    }
}

enum NotchHoverZones {
    /// The trigger zone: the closed capsule, a little larger, and reaching past the top screen edge so a
    /// cursor pinned to y = maxY still counts (rect containment is half-open at the top).
    static func trigger(closedFrame: CGRect) -> CGRect {
        CGRect(x: closedFrame.minX - 2, y: closedFrame.minY - 2, width: closedFrame.width + 4, height: closedFrame.height + 2 + 8)
    }

    /// The keep-open zone: the open panel outset so overshooting a button doesn't collapse it.
    static func keepOpen(openFrame: CGRect) -> CGRect {
        CGRect(x: openFrame.minX - 8, y: openFrame.minY - 8, width: openFrame.width + 16, height: openFrame.height + 8 + 8)
    }
}
