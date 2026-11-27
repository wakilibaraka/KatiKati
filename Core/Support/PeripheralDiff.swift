import Foundation

/// Connect / disconnect / low-battery transition detected across peripheral reads.
enum PeripheralEvent: Equatable, Sendable {
    case connected(BluetoothDevice)
    case disconnected(BluetoothDevice)
    case low(BluetoothDevice)
}

/// Pure diff between two connected-peripheral snapshots (`old` → `new`), keyed by canonical device id.
/// Low-battery alerts follow `BatteryBuddyPolicy`: a connected device alerts once per dip until it
/// recovers above `lowThreshold` or disconnects.
enum PeripheralDiff {
    static func canonicalID(of device: BluetoothDevice) -> String {
        device.id.lowercased()
    }

    static func diff(
        old: [BluetoothDevice],
        new: [BluetoothDevice],
        alreadyLow: Set<String>,
        lowThreshold: Int = PowerNotificationPolicy.peripheralLowLevel
    ) -> (events: [PeripheralEvent], low: Set<String>) {
        let oldConnected = old.filter(\.isConnected)
        let newConnected = new.filter(\.isConnected)
        let oldByID = Dictionary(oldConnected.map { (canonicalID(of: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let newByID = Dictionary(newConnected.map { (canonicalID(of: $0), $0) }, uniquingKeysWith: { first, _ in first })

        var events: [PeripheralEvent] = []
        var nextLow = Set<String>()

        for device in newConnected {
            let key = canonicalID(of: device)
            let isLow = (device.lowestBattery ?? 100) <= lowThreshold
            if isLow { nextLow.insert(key) }

            if oldByID[key] == nil {
                events.append(.connected(device))
            } else if isLow && !alreadyLow.contains(key) {
                events.append(.low(device))
            }
        }

        for device in oldConnected {
            let key = canonicalID(of: device)
            if newByID[key] == nil {
                events.append(.disconnected(device))
            }
        }

        return (events, nextLow)
    }

    /// AirPods often join CoreAudio a moment before `system_profiler` populates L/R/Case levels.
    static func needsBatteryFollowUp(in events: [PeripheralEvent]) -> Bool {
        events.contains { event in
            guard case let .connected(device) = event else { return false }
            return device.isAudioPeripheral && device.lowestBattery == nil
        }
    }
}
