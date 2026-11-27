import CoreGraphics
import Foundation

/// P1: three Dockset-style peripheral dock bar layouts (`Status` = glyph + %, `Ring` = circular ring, `Icon only` = glyph + charging bolt).
enum PeripheralWidgetLayoutStyle: String, CaseIterable, Identifiable, Sendable {
    case status
    case ring
    case iconOnly

    var id: String { rawValue }
}

/// Pure arrangement & width-fitting planner shared by `DevicesDockWidget` (P1, P2) and `BluetoothFlyoutView` (P3).
enum PeripheralWidgetPrefs {
    static let layoutKey = "com.katikati.peripherals.layout"
    static let orderKey = "com.katikati.peripherals.order"
    static let hiddenKey = "com.katikati.peripherals.hidden"
    static let pinnedKey = "com.katikati.peripherals.pinned"

    static func style(from raw: String) -> PeripheralWidgetLayoutStyle {
        PeripheralWidgetLayoutStyle(rawValue: raw) ?? .status
    }

    static func decodeIDs(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    static func encodeIDs(_ ids: [String]) -> String {
        guard let data = try? JSONEncoder().encode(ids),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    static func arranged(
        devices: [BluetoothDevice],
        order: [String] = [],
        hiddenIDs: Set<String> = [],
        pinnedID: String = "",
        includeHidden: Bool = false
    ) -> [BluetoothDevice] {
        let normalizedHidden = Set(hiddenIDs.map { $0.lowercased() })
        let normalizedPinned = pinnedID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let orderIndex = Dictionary(
            order.enumerated().map { ($0.element.lowercased(), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        let filtered = includeHidden
            ? devices
            : devices.filter { !normalizedHidden.contains($0.id.lowercased()) }

        return filtered.enumerated().sorted { lhs, rhs in
            let lKey = lhs.element.id.lowercased()
            let rKey = rhs.element.id.lowercased()
            let lPinned = !normalizedPinned.isEmpty && lKey == normalizedPinned
            let rPinned = !normalizedPinned.isEmpty && rKey == normalizedPinned
            if lPinned != rPinned { return lPinned }

            let lOrder = orderIndex[lKey]
            let rOrder = orderIndex[rKey]
            switch (lOrder, rOrder) {
            case let (a?, b?):
                if a != b { return a < b }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            if lhs.element.isConnected != rhs.element.isConnected {
                return lhs.element.isConnected
            }
            let lHasBattery = lhs.element.lowestBattery != nil
            let rHasBattery = rhs.element.lowestBattery != nil
            if lHasBattery != rHasBattery { return lHasBattery }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func slice(
        devices: [BluetoothDevice],
        availableWidth: CGFloat,
        style: PeripheralWidgetLayoutStyle,
        order: [String] = [],
        hiddenIDs: Set<String> = [],
        pinnedID: String = ""
    ) -> (visible: [BluetoothDevice], overflowCount: Int) {
        let sorted = arranged(devices: devices, order: order, hiddenIDs: hiddenIDs, pinnedID: pinnedID)
        guard !sorted.isEmpty else { return ([], 0) }

        let usableWidth = max(44, availableWidth - 14)
        let itemWidth: CGFloat
        let spacing: CGFloat
        switch style {
        case .iconOnly:
            itemWidth = 24
            spacing = 8
        case .ring:
            itemWidth = 30
            spacing = 7
        case .status:
            itemWidth = availableWidth >= 190 ? 74 : 52
            spacing = 8
        }

        func width(for count: Int, withOverflowChip: Bool) -> CGFloat {
            guard count > 0 else { return 0 }
            let items = CGFloat(count) * itemWidth + CGFloat(count - 1) * spacing
            return withOverflowChip ? items + spacing + 28 : items
        }

        if width(for: sorted.count, withOverflowChip: false) <= usableWidth {
            return (sorted, 0)
        }

        var count = sorted.count - 1
        while count > 1 && width(for: count, withOverflowChip: true) > usableWidth {
            count -= 1
        }
        let clipped = max(1, count)
        return (Array(sorted.prefix(clipped)), max(0, sorted.count - clipped))
    }

    static func togglingHidden(id: String, in raw: String) -> String {
        let current = decodeIDs(raw)
        let key = id.lowercased()
        if current.contains(where: { $0.lowercased() == key }) {
            return encodeIDs(current.filter { $0.lowercased() != key })
        }
        return encodeIDs(current + [id])
    }

    static func moving(id: String, by offset: Int, devices: [BluetoothDevice], orderRaw: String, pinnedID: String = "") -> String {
        let current = arranged(devices: devices, order: decodeIDs(orderRaw), pinnedID: pinnedID, includeHidden: true).map(\.id)
        guard let index = current.firstIndex(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) else {
            return orderRaw
        }
        let nextIndex = min(max(0, index + offset), current.count - 1)
        guard nextIndex != index else { return encodeIDs(current) }
        var reordered = current
        let moved = reordered.remove(at: index)
        reordered.insert(moved, at: nextIndex)
        return encodeIDs(reordered)
    }
}
