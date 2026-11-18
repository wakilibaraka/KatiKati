import Foundation

enum DesktopCanvasVisibility: Equatable, Sendable {
    case desktopLayer
    case quickRevealed
    case hiddenAll
}

enum DesktopInteractionLock: String, Hashable, Sendable {
    case drag
    case contextMenu
    case inlineRename
    case popover
    case confirmDialog
}

enum DesktopDismissReason: Equatable, Sendable {
    case escapeKey
    case outsideClick
    case appDeactivated
    case explicit
}

enum DesktopCanvasNotification {
    static let quickReveal = Notification.Name("com.katikati.desktop.quickReveal")
    static let toggleHidden = Notification.Name("com.katikati.desktop.toggleHidden")
}

/// Pure state machine governing desktop-layer vs Quick Reveal vs Hide All and interaction locks.
struct DesktopRevealStateMachine: Equatable, Sendable {
    private(set) var visibility: DesktopCanvasVisibility = .desktopLayer
    private(set) var activeLocks: Set<DesktopInteractionLock> = []
    private(set) var pendingDismissAfterUnlock = false
    private(set) var lastToggleTimestamp: TimeInterval?
    private var returnHiddenAfterQuickReveal = false

    let toggleCooldown: TimeInterval

    init(
        visibility: DesktopCanvasVisibility = .desktopLayer,
        toggleCooldown: TimeInterval = 0.18
    ) {
        self.visibility = visibility
        self.toggleCooldown = toggleCooldown
    }

    /// Toggles Quick Reveal (or dismisses back to desktop/hidden). Returns `true` if state changed.
    @discardableResult
    mutating func toggleQuickReveal(now: TimeInterval) -> Bool {
        guard canToggle(at: now) else { return false }
        lastToggleTimestamp = now
        switch visibility {
        case .desktopLayer:
            returnHiddenAfterQuickReveal = false
            pendingDismissAfterUnlock = false
            visibility = .quickRevealed
            return true
        case .hiddenAll:
            returnHiddenAfterQuickReveal = true
            pendingDismissAfterUnlock = false
            visibility = .quickRevealed
            return true
        case .quickRevealed:
            pendingDismissAfterUnlock = false
            visibility = returnHiddenAfterQuickReveal ? .hiddenAll : .desktopLayer
            returnHiddenAfterQuickReveal = false
            return true
        }
    }

    /// Toggles Hide All desktop boxes. Returns `true` if state changed.
    @discardableResult
    mutating func toggleHiddenAll(now: TimeInterval) -> Bool {
        guard canToggle(at: now) else { return false }
        lastToggleTimestamp = now
        pendingDismissAfterUnlock = false
        returnHiddenAfterQuickReveal = false
        visibility = (visibility == .hiddenAll) ? .desktopLayer : .hiddenAll
        return true
    }

    /// Requests leaving Quick Reveal (e.g. Esc or outside click). Defers if an interaction lock is active.
    @discardableResult
    mutating func requestDismissQuickReveal(reason: DesktopDismissReason) -> Bool {
        guard visibility == .quickRevealed else { return false }
        if reason != .explicit && !activeLocks.isEmpty {
            pendingDismissAfterUnlock = true
            return false
        }
        pendingDismissAfterUnlock = false
        visibility = returnHiddenAfterQuickReveal ? .hiddenAll : .desktopLayer
        returnHiddenAfterQuickReveal = false
        return true
    }

    mutating func acquireLock(_ lock: DesktopInteractionLock) {
        activeLocks.insert(lock)
    }

    /// Releases `lock`. If no locks remain and a Quick Reveal dismiss was deferred, applies it and returns `true`.
    @discardableResult
    mutating func releaseLock(_ lock: DesktopInteractionLock) -> Bool {
        activeLocks.remove(lock)
        guard activeLocks.isEmpty, pendingDismissAfterUnlock, visibility == .quickRevealed else {
            return false
        }
        pendingDismissAfterUnlock = false
        visibility = returnHiddenAfterQuickReveal ? .hiddenAll : .desktopLayer
        returnHiddenAfterQuickReveal = false
        return true
    }

    private func canToggle(at now: TimeInterval) -> Bool {
        guard let last = lastToggleTimestamp else { return true }
        return now - last >= toggleCooldown
    }
}
