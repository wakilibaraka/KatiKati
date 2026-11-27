import CoreGraphics
import Foundation

/// E1: Pure drop-index calculator for vertical edge-bar drag reordering.
enum EdgeInsertIndex {
    static func index(forY pointerY: CGFloat, itemMidYs: [CGFloat]) -> Int {
        for (idx, midY) in itemMidYs.enumerated() where pointerY < midY {
            return idx
        }
        return itemMidYs.count
    }
}

/// E1: Pure user-defined ordering helpers (`com.katikati.edge.order`) that keep `.settings` pinned at the end.
enum EdgeCustomOrder {
    static let defaultsKey = "com.katikati.edge.order"

    static func decode(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return ids
    }

    static func encode(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func sort<T>(order: [String], items: [T], id: (T) -> String?, isPinnedLast: (T) -> Bool) -> [T] {
        guard !order.isEmpty else { return items }
        let indexByID = Dictionary(
            order.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        let pinned = items.filter(isPinnedLast)
        let movable = items.filter { !isPinnedLast($0) }.enumerated().sorted { lhs, rhs in
            let li = id(lhs.element).flatMap { indexByID[$0] }
            let ri = id(rhs.element).flatMap { indexByID[$0] }
            switch (li, ri) {
            case let (a?, b?):
                return a != b ? a < b : lhs.offset < rhs.offset
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.offset < rhs.offset
            }
        }.map(\.element)
        return movable + pinned
    }

    static func apply(order: [String], to items: [EdgeItem]) -> [EdgeItem] {
        sort(order: order, items: items, id: { $0.rawValue }, isPinnedLast: { $0 == .settings })
    }

    static func inserting(_ item: EdgeItem, at index: Int, in current: [EdgeItem]) -> [EdgeItem] {
        guard item != .settings else { return current }
        let hasSettings = current.contains(.settings)
        var movable = current.filter { $0 != .settings && $0 != item }
        let clamped = min(max(0, index), movable.count)
        movable.insert(item, at: clamped)
        return hasSettings ? movable + [.settings] : movable
    }

    static func removing(_ item: EdgeItem, from current: [EdgeItem]) -> [EdgeItem] {
        guard item != .settings else { return current }
        return current.filter { $0 != item }
    }
}

/// E5: Hover spotlight policy (gentle 1.04× pop on hovered icon, 0.85 opacity dim on siblings; neutral when Reduce Motion is on).
enum EdgeSpotlightPolicy {
    static func scale(hoveredID: String?, itemID: String, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion, let hoveredID else { return 1.0 }
        return hoveredID == itemID ? 1.04 : 0.98
    }

    static func opacity(hoveredID: String?, itemID: String) -> Double {
        guard let hoveredID else { return 1.0 }
        return hoveredID == itemID ? 1.0 : 0.85
    }
}
