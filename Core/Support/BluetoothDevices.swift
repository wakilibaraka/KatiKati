import Foundation

/// One Bluetooth device as reported by `system_profiler SPBluetoothDataType -json` (Phase 7A-8b).
/// Pure parsing only; the Platform reader launches the process. No IOBluetooth / CoreBluetooth, so
/// there is no Bluetooth permission prompt.
struct BluetoothDevice: Equatable, Identifiable, Sendable {
    var name: String
    var address: String
    var isConnected: Bool
    /// `device_minorType` ("Headphones", "Mouse", "Keyboard", …) when present.
    var kind: String?
    /// 0...100; single battery (mice, keyboards, most headsets).
    var batteryMain: Int?
    /// Earbud / case batteries (AirPods and similar).
    var batteryLeft: Int?
    var batteryRight: Int?
    var batteryCase: Int?
    var isCharging: Bool = false

    var id: String { address.isEmpty ? name : address }

    /// Lowest known level — what a single "battery" badge should show.
    var lowestBattery: Int? { [batteryMain, batteryLeft, batteryRight, batteryCase].compactMap { $0 }.min() }

    /// Phase 56c: "L 80 · R 75 · C 60" for earbuds and their case; nil when the device reports one number.
    var batteryBreakdown: String? {
        let parts = [("L", batteryLeft), ("R", batteryRight), ("C", batteryCase)].compactMap { label, v in v.map { "\(label) \($0)" } }
        return parts.count > 1 ? parts.joined(separator: " · ") : nil
    }

    var isLowBattery: Bool { (lowestBattery ?? 100) <= PowerNotificationPolicy.peripheralLowLevel }

    var symbolName: String {
        switch kind?.lowercased() {
        case "headphones", "headset": return "headphones"
        case "mouse": return "computermouse"
        case "keyboard": return "keyboard"
        case "trackpad": return "rectangle.and.hand.point.up.left"
        case "gamepad", "game controller": return "gamecontroller"
        case "speaker": return "hifispeaker"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Richer device-specific SF Symbol used by Peripherals Wing & Notch UI while keeping `symbolName`
    /// backward-compatible for minorType-based unit assertions.
    var richSymbolName: String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") || lower.contains("buds") || lower.contains("earbud") { return "earbuds" }
        if lower.contains("iphone") { return "iphone" }
        if lower.contains("ipad") { return "ipad" }
        return symbolName
    }

    var isAudioPeripheral: Bool {
        if let k = kind?.lowercased(), k == "headphones" || k == "headset" || k == "speaker" {
            return true
        }
        let lower = name.lowercased()
        return lower.contains("airpods") || lower.contains("beats") || lower.contains("buds")
            || lower.contains("earbud") || lower.contains("headphone") || lower.contains("speaker")
    }
}

/// The two sources of a device list — `system_profiler` and the HID driver's registry — merged into
/// one, plus the product-name → kind rule. Pure, so the merge is tested without running either source.
enum BluetoothDeviceRegistry {
    /// The registry's levels fill the profiler's gaps; a device only one source knows is added once.
    static func merge(_ devices: [BluetoothDevice], _ registry: [BluetoothDevice]) -> [BluetoothDevice] {
        var merged = devices
        for candidate in registry {
            let sameAddress = candidate.address.isEmpty ? nil : merged.firstIndex {
                $0.address.caseInsensitiveCompare(candidate.address) == .orderedSame
            }
            if let index = sameAddress {
                if merged[index].batteryMain == nil { merged[index].batteryMain = candidate.batteryMain }
                merged[index].isCharging = merged[index].isCharging || candidate.isCharging
            } else if !merged.contains(where: { $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame }) {
                merged.append(candidate)
            }
        }
        return merged.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// `BluetoothDevice.symbolName` keys on these words.
    static func kind(of product: String) -> String? {
        let name = product.lowercased()
        if name.contains("mouse") { return "Mouse" }
        if name.contains("keyboard") { return "Keyboard" }
        if name.contains("trackpad") { return "Trackpad" }
        if name.contains("airpods") || name.contains("headphone") || name.contains("earbud") { return "Headphones" }
        if name.contains("speaker") { return "Speaker" }
        if name.contains("gamepad") || name.contains("controller") { return "Gamepad" }
        return nil
    }
}

enum BluetoothDeviceParser {
    /// Connected devices first, then by name (case-insensitive). Malformed JSON → empty.
    static func parse(_ data: Data) -> [BluetoothDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }
        var devices: [BluetoothDevice] = []
        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in section[key] as? [[String: Any]] ?? [] {
                    for (name, raw) in entry {
                        guard let info = raw as? [String: Any] else { continue }
                        devices.append(BluetoothDevice(
                            name: name,
                            address: info["device_address"] as? String ?? "",
                            isConnected: connected,
                            kind: info["device_minorType"] as? String,
                            batteryMain: percent(info["device_batteryLevelMain"]),
                            batteryLeft: percent(info["device_batteryLevelLeft"]),
                            batteryRight: percent(info["device_batteryLevelRight"]),
                            batteryCase: percent(info["device_batteryLevelCase"]),
                            isCharging: boolFlag(info["device_charging"])
                        ))
                    }
                }
            }
        }
        return devices.sorted {
            if $0.isConnected != $1.isConnected { return $0.isConnected }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func boolFlag(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        if let s = value as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "attrib_yes" || trimmed == "yes" || trimmed == "true" || trimmed == "1"
        }
        return false
    }

    /// "85%" / "85" / 85 → 85, clamped to 0...100; anything else → nil.
    static func percent(_ value: Any?) -> Int? {
        let text: String
        if let s = value as? String { text = s } else if let n = value as? Int { text = String(n) } else { return nil }
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "% ").union(.whitespaces))
        guard let n = Int(digits) else { return nil }
        return min(100, max(0, n))
    }
}

/// 51d: which connected devices just fell to a low charge. A device alerts once per dip, and again only
/// after it has recovered or disconnected. `system_profiler` reports no charging flag, so "charging" is not
/// a trigger.
enum BatteryBuddyPolicy {
    static let lowThreshold = PowerNotificationPolicy.peripheralLowLevel

    static func update(alreadyLow: Set<String>, devices: [BluetoothDevice]) -> (alerts: [BluetoothDevice], low: Set<String>) {
        let low = PowerNotificationPolicy.lowDevices(devices)
        return (low.filter { !alreadyLow.contains($0.id) }, Set(low.map(\.id)))
    }
}

/// Pure snapshot of Mac + connected Bluetooth peripheral battery levels for Wing & Notch Peripherals surfaces.
struct DockPeripheralBatteryOverview: Equatable, Sendable {
    var macPercent: Int?
    var macCharging: Bool
    var macOnAC: Bool
    var connectedPeripherals: [BluetoothDevice]

    static func build(
        macPercent: Int?,
        macCharging: Bool,
        macOnAC: Bool,
        devices: [BluetoothDevice]
    ) -> DockPeripheralBatteryOverview {
        let clampedMac = macPercent.map { min(100, max(0, $0)) }
        let sorted = devices.filter(\.isConnected).sorted { lhs, rhs in
            let lHas = lhs.lowestBattery != nil
            let rHas = rhs.lowestBattery != nil
            if lHas != rHas { return lHas }
            if lhs.isLowBattery != rhs.isLowBattery { return lhs.isLowBattery }
            if let l = lhs.lowestBattery, let r = rhs.lowestBattery, l != r { return l < r }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return DockPeripheralBatteryOverview(
            macPercent: clampedMac,
            macCharging: macCharging,
            macOnAC: macOnAC,
            connectedPeripherals: sorted
        )
    }

    var batteryPeripherals: [BluetoothDevice] {
        connectedPeripherals.filter { $0.lowestBattery != nil }
    }

    func topBatteryPeripherals(limit: Int) -> [BluetoothDevice] {
        guard limit > 0 else { return [] }
        return Array(batteryPeripherals.prefix(limit))
    }

    var lowestOverallPercent: Int? {
        ([macPercent].compactMap { $0 } + batteryPeripherals.compactMap(\.lowestBattery)).min()
    }

    var hasAnyLowDevice: Bool {
        (macPercent.map { !macCharging && $0 <= 20 } ?? false) || batteryPeripherals.contains(where: \.isLowBattery)
    }
}
