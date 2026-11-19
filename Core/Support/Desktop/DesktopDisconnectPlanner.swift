import CoreGraphics
import Foundation

/// A widget as the planner sees it: which display it claims and where it sits proportionally.
struct DesktopTopologyWidget: Equatable, Sendable {
    let id: UUID
    let displayUUID: String?
    let normalizedFrame: NormalizedWidgetRect
    let frame: CGRect
    let capsuleMode: DesktopCapsuleMode

    init(
        id: UUID,
        displayUUID: String?,
        normalizedFrame: NormalizedWidgetRect,
        frame: CGRect,
        capsuleMode: DesktopCapsuleMode
    ) {
        self.id = id
        self.displayUUID = displayUUID
        self.normalizedFrame = normalizedFrame
        self.frame = frame
        self.capsuleMode = capsuleMode
    }

    init(item: DesktopWidgetItem, resolvedDisplayUUID: String?, visibleFrame: CGRect) {
        self.init(
            id: item.id,
            displayUUID: resolvedDisplayUUID,
            normalizedFrame: item.normalizedFrame ?? DesktopLayoutEngine.normalize(item.frame, in: visibleFrame),
            frame: item.frame,
            capsuleMode: item.capsuleMode
        )
    }
}

/// One widget's planned destination after a topology transition.
struct DisplayWidgetMove: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case relocate
        case collapse
        case restore
        case seed
    }

    let kind: Kind
    let displayUUID: String
    let normalizedFrame: NormalizedWidgetRect
    let capsuleMode: DesktopCapsuleMode
}

/// The aggregate result of planning one topology transition.
struct DisplayTopologyPlan: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case unchanged
        case disconnect
        case reconnect
        case firstSeen
    }

    let kind: Kind
    let signature: String
    let disconnectedUUIDs: [String]
    let reconnectedUUIDs: [String]
    let moves: [UUID: DisplayWidgetMove]

    var isEmpty: Bool { moves.isEmpty }

    static func empty(kind: Kind = .unchanged, signature: String = "") -> DisplayTopologyPlan {
        DisplayTopologyPlan(
            kind: kind,
            signature: signature,
            disconnectedUUIDs: [],
            reconnectedUUIDs: [],
            moves: [:]
        )
    }
}

/// Pure planning for display loss, exact-spot restore and first-seen seeding.
enum DisplayDisconnectPlanner {
    /// Widgets on a removed display either move proportionally onto the most similar remaining
    /// display, or collapse to capsules there. Displays never disappear without a remaining screen.
    static func disconnectPlan(
        disconnected: [TopologyDisplay],
        current: [TopologyDisplay],
        widgets: [DesktopTopologyWidget],
        action: DesktopDisconnectAction
    ) -> DisplayTopologyPlan {
        let removedUUIDs = Set(disconnected.map(\.uuid))
        guard !removedUUIDs.isEmpty, !current.isEmpty else {
            return .empty(kind: .disconnect, signature: DisplayTopologySignature.make(current.map(\.uuid)))
        }

        var moves: [UUID: DisplayWidgetMove] = [:]
        for widget in widgets {
            guard let homeUUID = widget.displayUUID, removedUUIDs.contains(homeUUID) else { continue }
            let oldDisplay = disconnected.first { $0.uuid == homeUUID }
            let target = oldDisplay.flatMap { DisplayTopologySimilarity.mostSimilarDisplay(to: $0, among: current) }
                ?? current.first
            guard let target else { continue }
            moves[widget.id] = DisplayWidgetMove(
                kind: action == .capsule ? .collapse : .relocate,
                displayUUID: target.uuid,
                normalizedFrame: widget.normalizedFrame,
                capsuleMode: action == .capsule ? .capsule : widget.capsuleMode
            )
        }

        return DisplayTopologyPlan(
            kind: .disconnect,
            signature: DisplayTopologySignature.make(current.map(\.uuid)),
            disconnectedUUIDs: disconnected.map(\.uuid),
            reconnectedUUIDs: [],
            moves: moves
        )
    }

    /// Exact-spot restore: a widget whose archive entry names a display that just came back
    /// returns to that display's remembered proportional frame (and capsule state).
    static func restorePlan(
        reconnectedUUIDs: Set<String>,
        widgets: [DesktopTopologyWidget],
        placements: [String: TopologyWidgetPlacement]
    ) -> DisplayTopologyPlan {
        guard !reconnectedUUIDs.isEmpty, !placements.isEmpty else {
            return .empty(kind: .reconnect)
        }
        var moves: [UUID: DisplayWidgetMove] = [:]
        for widget in widgets {
            guard let placement = placements[widget.id.uuidString],
                  let homeUUID = placement.displayUUID,
                  reconnectedUUIDs.contains(homeUUID)
            else { continue }
            moves[widget.id] = DisplayWidgetMove(
                kind: .restore,
                displayUUID: homeUUID,
                normalizedFrame: placement.normalizedFrame,
                capsuleMode: placement.capsuleMode
            )
        }
        return DisplayTopologyPlan(
            kind: .reconnect,
            signature: DisplayTopologySignature.make(reconnectedUUIDs.sorted()),
            disconnectedUUIDs: [],
            reconnectedUUIDs: reconnectedUUIDs.sorted(),
            moves: moves
        )
    }

    /// First-seen topology: seed from the most similar archived arrangement, mapping every archived
    /// display onto its closest connected display.
    static func seedPlan(
        entry: TopologyArchiveEntry,
        current: [TopologyDisplay],
        widgets: [DesktopTopologyWidget]
    ) -> DisplayTopologyPlan {
        guard !current.isEmpty, !entry.placements.isEmpty else {
            return .empty(kind: .firstSeen)
        }
        let widgetsByID = Dictionary(uniqueKeysWithValues: widgets.map { ($0.id.uuidString, $0) })
        var moves: [UUID: DisplayWidgetMove] = [:]

        for (key, placement) in entry.placements {
            guard let widget = widgetsByID[key] else { continue }
            let archivedDisplay = placement.displayUUID.flatMap { uuid in
                entry.displays.first { $0.uuid == uuid }
            } ?? entry.displays.first
            guard let archivedDisplay,
                  let target = DisplayTopologySimilarity.mostSimilarDisplay(to: archivedDisplay, among: current)
            else { continue }
            moves[widget.id] = DisplayWidgetMove(
                kind: .seed,
                displayUUID: target.uuid,
                normalizedFrame: placement.normalizedFrame,
                capsuleMode: placement.capsuleMode
            )
        }

        return DisplayTopologyPlan(
            kind: .firstSeen,
            signature: DisplayTopologySignature.make(current.map(\.uuid)),
            disconnectedUUIDs: [],
            reconnectedUUIDs: [],
            moves: moves
        )
    }

    /// Placement snapshot for archiving the current arrangement.
    static func placements(from widgets: [DesktopTopologyWidget]) -> [String: TopologyWidgetPlacement] {
        Dictionary(uniqueKeysWithValues: widgets.map { widget in
            (widget.id.uuidString, TopologyWidgetPlacement(
                displayUUID: widget.displayUUID,
                normalizedFrame: widget.normalizedFrame,
                capsuleMode: widget.capsuleMode
            ))
        })
    }
}
