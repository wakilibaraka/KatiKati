import Foundation

/// Which screen edge an edge bar (Phase 7A) hugs.
enum EdgeSide: String, CaseIterable, Sendable {
    case left
    case right
}

/// Pure calculation of edge-bar slots across displays. Parallel to `IslandSlotSet`
/// (bottom islands) — it never changes island slot semantics. Keys render as
/// `displayUUID#edge-left` / `displayUUID#edge-right`.
enum EdgeSlotSet {
    struct SlotKey: Hashable, Sendable, CustomStringConvertible {
        /// nil = follow settings (default display); otherwise the fixed display UUID.
        let display: String?
        let side: EdgeSide

        var description: String {
            "\(display ?? "follow")#edge-\(side.rawValue)"
        }
    }

    /// Desired edge slots: each display key from `TaskbarDisplaySet.desiredUnitKeys` crossed
    /// with the enabled sides, sides in `EdgeSide.allCases` order (left, right).
    static func desiredSlots(
        placement: TaskbarScreenPlacement,
        connectedKeys: [String],
        sides: Set<EdgeSide>
    ) -> [SlotKey] {
        guard !sides.isEmpty else { return [] }
        let displayKeys = TaskbarDisplaySet.desiredUnitKeys(placement: placement, connectedKeys: connectedKeys)
        return displayKeys.flatMap { display in
            EdgeSide.allCases.filter(sides.contains).map { SlotKey(display: display, side: $0) }
        }
    }
}

/// What an edge bar hosts. Notes always live on the right edge; status follows the user's side.
enum EdgeBarContent: String, Sendable {
    case notes
    case status
}

/// User-facing edge-bar presets (Phase 7A-2). Pure: resolves to content per edge.
enum EdgeBarPreset: String, CaseIterable, Sendable {
    case off
    case notes
    case notesAndStatus
    case status

    static let notesSide: EdgeSide = .right

    /// Content hosted on each active edge for this preset and status side.
    func content(statusSide: EdgeSide) -> [EdgeSide: [EdgeBarContent]] {
        switch self {
        case .off: return [:]
        case .notes: return [Self.notesSide: [.notes]]
        case .status: return [statusSide: [.status]]
        case .notesAndStatus:
            if statusSide == Self.notesSide { return [Self.notesSide: [.notes, .status]] }
            return [Self.notesSide: [.notes], statusSide: [.status]]
        }
    }

    func activeSides(statusSide: EdgeSide) -> Set<EdgeSide> {
        Set(content(statusSide: statusSide).keys)
    }
}
