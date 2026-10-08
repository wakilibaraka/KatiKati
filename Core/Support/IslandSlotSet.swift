import Foundation

/// Pure calculation of island panel slots across displays and layout modes.
///
/// In KatiKati Phase 2, each screen is divided into 1, 3, or 4 island panels according
/// to `BarLayoutMode.slotCount`. `IslandSlotSet` expands the display keys from
/// `TaskbarDisplaySet` into per-island `SlotKey` entries (e.g. `displayUUID#0`, `displayUUID#1`, etc.).
///
/// Orchestrators use this to reconcile and manage `PanelCoordinator` instances without
/// tearing down survivors on layout mode changes.
enum IslandSlotSet {
    struct SlotKey: Hashable, Sendable, CustomStringConvertible {
        /// nil = follow settings (default display); otherwise the fixed display UUID.
        let display: String?
        /// Index of the island slot on the display (0..<mode.slotCount).
        let slot: Int

        init(display: String?, slot: Int) {
            self.display = display
            self.slot = slot
        }

        var description: String {
            "\(display ?? "follow")#\(slot)"
        }
    }

    struct Diff: Equatable {
        /// Order matches `current`.
        let added: [SlotKey]
        /// Order matches `previous`.
        let removed: [SlotKey]
        /// Order matches `current`.
        let kept: [SlotKey]
    }

    /// Computes added, removed, and kept slot keys between two states.
    /// Ordering semantics match `TaskbarDisplaySet.diff`.
    static func diff(previous: [SlotKey], current: [SlotKey]) -> Diff {
        let previousSet = Set(previous)
        let currentSet = Set(current)
        return Diff(
            added: current.filter { !previousSet.contains($0) },
            removed: previous.filter { !currentSet.contains($0) },
            kept: current.filter { previousSet.contains($0) }
        )
    }

    /// Computes the desired slot keys for a given screen placement, connected display UUIDs,
    /// and layout mode.
    ///
    /// Expands each display key from `TaskbarDisplaySet.desiredUnitKeys` across `0..<mode.slotCount`.
    static func desiredSlots(
        placement: TaskbarScreenPlacement,
        connectedKeys: [String],
        mode: BarLayoutMode
    ) -> [SlotKey] {
        let displayKeys = TaskbarDisplaySet.desiredUnitKeys(placement: placement, connectedKeys: connectedKeys)
        let count = max(1, mode.slotCount)
        return displayKeys.flatMap { display in
            (0..<count).map { slot in
                SlotKey(display: display, slot: slot)
            }
        }
    }
}
