import CoreGraphics
import Foundation

/// Phase 25a: the pure core behind notification relocation. Banner-slot geometry, the fail-closed
/// Notification Center UI probe, and the debounce that keeps a move-triggered AX change from
/// looping. No AppKit, no AX: callers hand in frames already in CG (top-left origin) space.

/// The eight banner slots — the 3×3 grid without the dead centre (the plan's 8-slot picker).
enum NotificationSlot: String, CaseIterable, Codable, Equatable, Sendable {
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

// PHN-3: what a banner on one display should do — land in a slot, or stay out of the way because the
// notch already lists it. Pure, so the per-display resolution is unit-tested instead of read from AX.
enum NotificationTarget: Codable, Hashable, Sendable {
    case slot(NotificationSlot)
    case notch

    var slot: NotificationSlot? {
        if case .slot(let slot) = self { return slot }
        return nil
    }

    var routesToNotch: Bool { self == .notch }
}

/// PHN-3: PingPlace's per-display rules — one global zone, an optional override per display UUID, and the
/// displays whose banners are routed to the notch instead of being moved. `NotificationMoveService` owns
/// the persistence; this type is the whole decision.
struct NotificationPlacementRule: Codable, Equatable, Sendable {
    static let storageKey = "com.katikati.notifications.rule.v1"

    var global: NotificationSlot = .topCenter
    var perDisplay: [String: NotificationSlot] = [:]
    var notchDisplays: Set<String> = []

    init(global: NotificationSlot = .topCenter,
         perDisplay: [String: NotificationSlot] = [:],
         notchDisplays: Set<String> = []) {
        self.global = global
        self.perDisplay = perDisplay
        self.notchDisplays = notchDisplays
    }

    /// Notch first, then a per-display zone, then the global one. A display that cannot be identified
    /// (`nil`) always takes the global zone.
    func target(forDisplay uuid: String?) -> NotificationTarget {
        if let uuid, notchDisplays.contains(uuid) { return .notch }
        if let uuid, let slot = perDisplay[uuid] { return .slot(slot) }
        return .slot(global)
    }

    /// Convenience for callers that only move banners: the notch case answers with the global zone, so a
    /// caller that ignores routing still never sends a banner nowhere.
    func slot(forDisplay uuid: String?) -> NotificationSlot {
        target(forDisplay: uuid).slot ?? global
    }

    /// `nil` clears the override (that display follows the global zone again).
    func assigning(_ slot: NotificationSlot?, toDisplay uuid: String) -> NotificationPlacementRule {
        var copy = self
        if let slot { copy.perDisplay[uuid] = slot } else { copy.perDisplay.removeValue(forKey: uuid) }
        // Any explicit zone choice also ends a notch route on that display.
        copy.notchDisplays.remove(uuid)
        return copy
    }

    func routingToNotch(_ on: Bool, display uuid: String) -> NotificationPlacementRule {
        var copy = self
        if on { copy.notchDisplays.insert(uuid) } else { copy.notchDisplays.remove(uuid) }
        return copy
    }

    func withGlobal(_ slot: NotificationSlot) -> NotificationPlacementRule {
        var copy = self
        copy.global = slot
        return copy
    }

    static func decode(_ data: Data?) -> NotificationPlacementRule? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(NotificationPlacementRule.self, from: data)
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
}

/// PHN-3: the visual picker's grid — three rows of three, with the dead centre as the one cell that is
/// not a target (the plan's 8-zone picker).
enum NotificationZoneGrid {
    static let rows: [[NotificationSlot?]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, nil, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    /// Reading order, which is exactly `NotificationSlot.allCases` — pinned by a test so the grid and the
    /// stored raw values cannot drift apart.
    static var selectable: [NotificationSlot] { rows.flatMap { $0.compactMap { $0 } } }
}
