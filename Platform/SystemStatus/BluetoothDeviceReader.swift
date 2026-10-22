import Foundation
import IOKit

/// Reads the Bluetooth device list by running `/usr/sbin/system_profiler SPBluetoothDataType -json`
/// (Phase 7A-8b). Launched only when the flyout opens (or Refresh is tapped) — never polled — and
/// off the main thread with a hard timeout. Fixed arguments, no shell.
///
/// 2026-10-22: the profiler leaves the battery out for some HID accessories (BLE mice, keyboards and
/// headsets are the common case) while the HID driver still publishes it. The registry pass below is
/// taken from BeteriApp's `BBBluetoothManager` (a BatteryBoi fork, GPL-3.0 like BeteriApp): services of class
/// `AppleDeviceManagementHIDEventService` carry `BatteryPercent` next to `DeviceAddress`/`Product`.
/// Neither source is authoritative for every device, so their readings are merged, not replaced.
enum BluetoothDeviceReader {
    static let timeout: TimeInterval = 8

    static func read() async -> [BluetoothDevice] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: readBlocking())
            }
        }
    }

    static func readBlocking() -> [BluetoothDevice] {
        BluetoothDeviceRegistry.merge(profiledDevices(), registryDevices())
    }

    private static func profiledDevices() -> [BluetoothDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()
        return BluetoothDeviceParser.parse(data)
    }

    /// Connected accessories the HID driver knows a charge for. Internal hardware is skipped: the
    /// built-in keyboard/trackpad are not peripherals and have no meaningful charge reading.
    static func registryDevices() -> [BluetoothDevice] {
        var devices: [BluetoothDevice] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                          IOServiceMatching("AppleDeviceManagementHIDEventService"),
                                          &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            let address = IORegistryEntryCreateCFProperty(service, "DeviceAddress" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            let product = IORegistryEntryCreateCFProperty(service, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String
            let level = IORegistryEntryCreateCFProperty(service, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber
            if let address, let product, let level, !product.localizedCaseInsensitiveContains("internal") {
                devices.append(BluetoothDevice(
                    name: product,
                    address: address,
                    isConnected: true,
                    kind: BluetoothDeviceRegistry.kind(of: product),
                    batteryMain: min(100, max(0, level.intValue))))
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return devices
    }

}
