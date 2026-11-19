import CoreGraphics
import Foundation

/// An undoable plan that moves every widget proportionally onto one display.
struct MoveAllWidgetsUndoPlan: Equatable, Sendable {
    /// The geometry a widget owned before or after the move.
    struct Placement: Equatable, Sendable {
        var displayUUID: String?
        var frame: CGRect
        var normalizedFrame: NormalizedWidgetRect?
        var capsuleMode: DesktopCapsuleMode

        init(item: DesktopWidgetItem) {
            displayUUID = item.displayUUID
            frame = item.frame
            normalizedFrame = item.normalizedFrame
            capsuleMode = item.capsuleMode
        }

        init(
            displayUUID: String?,
            frame: CGRect,
            normalizedFrame: NormalizedWidgetRect?,
            capsuleMode: DesktopCapsuleMode
        ) {
            self.displayUUID = displayUUID
            self.frame = frame
            self.normalizedFrame = normalizedFrame
            self.capsuleMode = capsuleMode
        }
    }

    struct Change: Equatable, Sendable {
        let id: UUID
        let before: Placement
        let after: Placement
    }

    let targetDisplayUUID: String
    let changes: [Change]

    var isEmpty: Bool { changes.isEmpty }

    init(targetDisplayUUID: String, changes: [Change]) {
        self.targetDisplayUUID = targetDisplayUUID
        self.changes = changes
    }

    /// Applies the plan forward (`after`) or undoes it (`before`), leaving other widgets untouched.
    func applying(_ items: [DesktopWidgetItem], forward: Bool = true) -> [DesktopWidgetItem] {
        let byID = Dictionary(uniqueKeysWithValues: changes.map { ($0.id, $0) })
        return items.map { item in
            guard let change = byID[item.id] else { return item }
            let placement = forward ? change.after : change.before
            var copy = item
            copy.displayUUID = placement.displayUUID
            copy.frame = placement.frame
            copy.normalizedFrame = placement.normalizedFrame
            copy.capsuleMode = placement.capsuleMode
            return copy
        }
    }
}

enum DesktopMoveAllPlanner {
    /// Proportional move-all: each frame keeps its relative position and relative size, scaled from
    /// `sourceDisplay`'s visible frame into `targetDisplay`'s visible frame.
    static func plan(
        items: [DesktopWidgetItem],
        sourceDisplay: TopologyDisplay,
        targetDisplay: TopologyDisplay,
        edgeMargin: CGFloat
    ) -> MoveAllWidgetsUndoPlan {
        let sourceVisible = sourceDisplay.visibleFrame.cgRect
        let targetVisible = targetDisplay.visibleFrame.cgRect
        guard sourceVisible.width > 0, sourceVisible.height > 0, !items.isEmpty else {
            return MoveAllWidgetsUndoPlan(targetDisplayUUID: targetDisplay.uuid, changes: [])
        }
        let scaleX = targetVisible.width / sourceVisible.width
        let scaleY = targetVisible.height / sourceVisible.height

        let changes = items.map { item -> MoveAllWidgetsUndoPlan.Change in
            let before = MoveAllWidgetsUndoPlan.Placement(item: item)
            let raw = CGRect(
                x: targetVisible.minX + (item.frame.minX - sourceVisible.minX) * scaleX,
                y: targetVisible.minY + (item.frame.minY - sourceVisible.minY) * scaleY,
                width: item.frame.width * scaleX,
                height: item.frame.height * scaleY
            )
            let clamped = DesktopLayoutEngine.clamp(raw, in: targetVisible, edgeMargin: edgeMargin)
            let after = MoveAllWidgetsUndoPlan.Placement(
                displayUUID: targetDisplay.uuid,
                frame: clamped,
                normalizedFrame: DesktopLayoutEngine.normalize(clamped, in: targetVisible),
                capsuleMode: item.capsuleMode
            )
            return MoveAllWidgetsUndoPlan.Change(id: item.id, before: before, after: after)
        }
        return MoveAllWidgetsUndoPlan(targetDisplayUUID: targetDisplay.uuid, changes: changes)
    }

    /// Merges several source-display plans into one undoable move-all.
    static func combined(_ plans: [MoveAllWidgetsUndoPlan], targetDisplayUUID: String) -> MoveAllWidgetsUndoPlan {
        MoveAllWidgetsUndoPlan(
            targetDisplayUUID: targetDisplayUUID,
            changes: plans.flatMap(\.changes)
        )
    }
}
