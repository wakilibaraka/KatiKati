import CoreGraphics
import Foundation

/// Phase 25a: the pure core behind notification relocation. Banner-slot geometry, the fail-closed
/// Notification Center UI probe, and the debounce that keeps a move-triggered AX change from
/// looping. No AppKit, no AX: callers hand in frames already in CG (top-left origin) space.

/// The eight banner slots — the 3×3 grid without the dead centre (the plan's 8-slot picker).
enum NotificationSlot: String, CaseIterable, Equatable, Sendable {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight

    enum Column: Sendable { case left, center, right }
    enum Row: Sendable { case top, middle, bottom }

    var column: Column {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: return .left
        case .topCenter, .bottomCenter: return .center
        case .topRight, .middleRight, .bottomRight: return .right
        }
    }

    var row: Row {
        switch self {
        case .topLeft, .topCenter, .topRight: return .top
        case .middleLeft, .middleRight: return .middle
        case .bottomLeft, .bottomCenter, .bottomRight: return .bottom
        }
    }
}

enum NotificationPlacement {
    /// Gap kept between the banner and the work-area edge (Notification Center's own margin is ~12 pt).
    static let edgeMargin: CGFloat = 12

    /// The banner's frame after relocation, clamped inside `workArea` so a slot can never push a
    /// banner under the Dock or off the side of a narrow display.
    static func frame(slot: NotificationSlot, workArea: CGRect, banner: CGRect) -> CGRect {
        let width = min(banner.width, workArea.width)
        let height = min(banner.height, workArea.height)
        let x: CGFloat
        switch slot.column {
        case .left: x = workArea.minX + edgeMargin
        case .center: x = workArea.midX - width / 2
        case .right: x = workArea.maxX - edgeMargin - width
        }
        let y: CGFloat
        switch slot.row {
        case .top: y = workArea.minY + edgeMargin
        case .middle: y = workArea.midY - height / 2
        case .bottom: y = workArea.maxY - edgeMargin - height
        }
        return CGRect(
            x: min(max(x, workArea.minX), max(workArea.minX, workArea.maxX - width)),
            y: min(max(y, workArea.minY), max(workArea.minY, workArea.maxY - height)),
            width: width,
            height: height
        )
    }
}

/// What the observer saw while walking one Notification Center window.
struct NotificationUIObservation: Equatable, Sendable {
    var bannerSubrole: String?
    var bannerFrameReadable = false
    var windowFrameReadable = false
    var positionSettable = false
    var visitedNodes = 0
}

enum NotificationUICapability {
    /// Banner subroles macOS has shipped. Any other subrole is an unknown UI shape → do nothing.
    static let bannerSubroles: Set<String> = [
        "AXNotificationCenterBanner", "AXNotificationCenterAlert",
        "AXNotificationCenterNotification", "AXNotificationCenterBannerWindow"
    ]
    static let maxNodes = 10_000

    /// Fail-closed probe: only a recognised banner with readable frames and a settable position
    /// gets moved. Notification Center's UI is private and changes per release — no match, no move.
    static func evaluate(_ observed: NotificationUIObservation) -> Bool {
        guard let subrole = observed.bannerSubrole, bannerSubroles.contains(subrole) else { return false }
        return observed.bannerFrameReadable
            && observed.windowFrameReadable
            && observed.positionSettable
            && observed.visitedNodes <= maxNodes
    }
}

/// Our own AX position write can provoke more AX chatter; a short cooldown stops that from
/// turning into a move storm. Injected clock so tests drive it.
struct NotificationMoveGuard: Equatable, Sendable {
    var cooldown: TimeInterval = 0.35
    private(set) var lastMoveAt: Date?

    mutating func shouldMove(now: Date) -> Bool {
        guard let last = lastMoveAt else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    mutating func noteMove(at now: Date) { lastMoveAt = now }
}
