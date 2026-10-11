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
