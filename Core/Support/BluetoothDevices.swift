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
                            batteryCase: percent(info["device_batteryLevelCase"])
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
