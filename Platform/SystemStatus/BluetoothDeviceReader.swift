import Foundation

/// Reads the Bluetooth device list by running `/usr/sbin/system_profiler SPBluetoothDataType -json`
/// (Phase 7A-8b). Launched only when the flyout opens (or Refresh is tapped) — never polled — and
/// off the main thread with a hard timeout. Fixed arguments, no shell.
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
}
