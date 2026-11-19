import CoreGraphics
import Foundation

struct DesktopPanelGroup: Equatable, Identifiable {
    var id: UUID { panelKey }
    let panelKey: UUID
    let activeItem: DesktopWidgetItem
    let tabs: [DesktopWidgetItem]
}

/// Pure coordinator logic for tabbed desktop widget groups (merge, switch, cycle, detach, frame sync).
enum DesktopTabGroupEngine {
    static func panelGroups(from items: [DesktopWidgetItem]) -> [DesktopPanelGroup] {
        var result: [DesktopPanelGroup] = []
        var groupedBuckets: [UUID: [DesktopWidgetItem]] = [:]
        var groupOrder: [UUID] = []

        for item in items {
            if let gid = item.tabGroupID {
                if groupedBuckets[gid] == nil { groupOrder.append(gid) }
                groupedBuckets[gid, default: []].append(item)
            } else {
                result.append(DesktopPanelGroup(panelKey: item.id, activeItem: item, tabs: [item]))
            }
        }

        for gid in groupOrder {
            guard let rawTabs = groupedBuckets[gid], !rawTabs.isEmpty else { continue }
            let sorted = sortedTabs(rawTabs)
            let active = sorted.first(where: \.isActiveTab) ?? sorted[0]
            let key = sorted.count == 1 ? active.id : gid
            result.append(DesktopPanelGroup(panelKey: key, activeItem: active, tabs: sorted))
        }
        return result
    }

    static func reconcile(_ items: [DesktopWidgetItem]) -> [DesktopWidgetItem] {
        var next = items
        var indicesByGroup: [UUID: [Int]] = [:]
        for idx in next.indices {
            if let gid = next[idx].tabGroupID {
                indicesByGroup[gid, default: []].append(idx)
            } else {
                next[idx].tabOrder = 0
                next[idx].isActiveTab = true
            }
        }

        for (_, indices) in indicesByGroup {
            if indices.count == 1 {
                let single = indices[0]
                next[single].tabGroupID = nil
                next[single].tabOrder = 0
                next[single].isActiveTab = true
                continue
            }

            let ordered = indices.sorted {
                if next[$0].tabOrder != next[$1].tabOrder {
                    return next[$0].tabOrder < next[$1].tabOrder
                }
                return next[$0].id.uuidString < next[$1].id.uuidString
            }
            let activeIndex = ordered.first(where: { next[$0].isActiveTab }) ?? ordered[0]
            let template = next[activeIndex]

            for (position, idx) in ordered.enumerated() {
                next[idx].tabOrder = position
                next[idx].isActiveTab = (idx == activeIndex)
                next[idx].frame = template.frame
                next[idx].normalizedFrame = template.normalizedFrame
                next[idx].displayUUID = template.displayUUID
                next[idx].isHidden = template.isHidden
            }
        }
        return next
    }

    static func merge(
        movingID: UUID,
        into targetID: UUID,
        in items: [DesktopWidgetItem]
    ) -> [DesktopWidgetItem] {
        guard movingID != targetID,
              let movingItem = items.first(where: { $0.id == movingID }),
              let targetItem = items.first(where: { $0.id == targetID })
        else { return items }

        let targetGroupID = targetItem.tabGroupID
        let movingGroupID = movingItem.tabGroupID
        if let targetGroupID, targetGroupID == movingGroupID {
            return selectTab(id: movingID, in: items)
        }

        let resolvedGroupID = targetGroupID ?? UUID()
        let baseCount = targetGroupID.map { gid in
            items.filter { $0.tabGroupID == gid }.count
        } ?? 1

        var next = items
        let targetIndices = next.indices.filter {
            next[$0].id == targetID || (targetGroupID != nil && next[$0].tabGroupID == targetGroupID)
        }
        let targetSorted = sortedIndices(targetIndices, in: next)
        for (pos, idx) in targetSorted.enumerated() {
            next[idx].tabGroupID = resolvedGroupID
            next[idx].tabOrder = pos
            next[idx].isActiveTab = false
        }

        let movingIndices = next.indices.filter {
            next[$0].id == movingID || (movingGroupID != nil && next[$0].tabGroupID == movingGroupID)
        }
        let movingSorted = sortedIndices(movingIndices, in: next)
        for (offset, idx) in movingSorted.enumerated() {
            next[idx].tabGroupID = resolvedGroupID
            next[idx].tabOrder = baseCount + offset
            next[idx].isActiveTab = (next[idx].id == movingID)
            next[idx].frame = targetItem.frame
            next[idx].normalizedFrame = targetItem.normalizedFrame
            next[idx].displayUUID = targetItem.displayUUID
            next[idx].isHidden = targetItem.isHidden
        }
        return reconcile(next)
    }

    static func selectTab(id: UUID, in items: [DesktopWidgetItem]) -> [DesktopWidgetItem] {
        guard let target = items.first(where: { $0.id == id }),
              let gid = target.tabGroupID
        else { return items }

        var next = items
        for idx in next.indices where next[idx].tabGroupID == gid {
            next[idx].isActiveTab = (next[idx].id == id)
        }
        return reconcile(next)
    }

    static func cycleTab(
        groupID: UUID,
        delta: Int,
        in items: [DesktopWidgetItem]
    ) -> [DesktopWidgetItem] {
        guard delta != 0 else { return items }
        let ordered = sortedTabs(items.filter { $0.tabGroupID == groupID })
        guard ordered.count > 1 else { return items }
        let currentIdx = ordered.firstIndex(where: \.isActiveTab) ?? 0
        let count = ordered.count
        let targetIdx = ((currentIdx + delta) % count + count) % count
        return selectTab(id: ordered[targetIdx].id, in: items)
    }

    static func detachTab(
        id: UUID,
        in items: [DesktopWidgetItem],
        visibleFrame: CGRect,
        edgeMargin: CGFloat
    ) -> [DesktopWidgetItem] {
        guard let detachedIndex = items.firstIndex(where: { $0.id == id }),
              let gid = items[detachedIndex].tabGroupID
        else { return items }

        var next = items
        let wasActive = next[detachedIndex].isActiveTab
        let remaining = sortedTabs(next.filter { $0.tabGroupID == gid && $0.id != id })

        if wasActive, let fallback = remaining.first,
           let fallbackIdx = next.firstIndex(where: { $0.id == fallback.id }) {
            for idx in next.indices where next[idx].tabGroupID == gid {
                next[idx].isActiveTab = (idx == fallbackIdx)
            }
        }

        let offsetFrame = next[detachedIndex].frame.offsetBy(dx: 28, dy: -28)
        let clamped = DesktopLayoutEngine.clamp(offsetFrame, in: visibleFrame, edgeMargin: edgeMargin)
        next[detachedIndex].tabGroupID = nil
        next[detachedIndex].tabOrder = 0
        next[detachedIndex].isActiveTab = true
        next[detachedIndex].frame = clamped
        next[detachedIndex].normalizedFrame = DesktopLayoutEngine.normalize(clamped, in: visibleFrame)

        return reconcile(next)
    }

    static func syncGroupGeometry(
        for activeID: UUID,
        frame: CGRect,
        normalizedFrame: NormalizedWidgetRect?,
        displayUUID: String?,
        in items: [DesktopWidgetItem]
    ) -> [DesktopWidgetItem] {
        guard let anchor = items.first(where: { $0.id == activeID }) else { return items }
        let gid = anchor.tabGroupID
        var next = items
        for idx in next.indices {
            let matches = (next[idx].id == activeID) || (gid != nil && next[idx].tabGroupID == gid)
            guard matches else { continue }
            next[idx].frame = frame
            next[idx].normalizedFrame = normalizedFrame
            if let displayUUID { next[idx].displayUUID = displayUUID }
        }
        return next
    }

    private static func sortedTabs(_ tabs: [DesktopWidgetItem]) -> [DesktopWidgetItem] {
        tabs.sorted {
            if $0.tabOrder != $1.tabOrder { return $0.tabOrder < $1.tabOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func sortedIndices(_ indices: [Int], in items: [DesktopWidgetItem]) -> [Int] {
        indices.sorted {
            if items[$0].tabOrder != items[$1].tabOrder {
                return items[$0].tabOrder < items[$1].tabOrder
            }
            return items[$0].id.uuidString < items[$1].id.uuidString
        }
    }
}
