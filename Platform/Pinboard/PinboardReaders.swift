import Foundation
import IOKit

/// Platform readers behind the V3 cards. Each is a one-shot read; the card decides how often to call.
enum BatteryHealthReader {
    static func read() -> BatteryHealth? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return BatteryHealth(registry: dict)
    }
}

enum TopProcessReader {
    static func read(limit: Int) -> [TopProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-Ao", "pcpu=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return TopProcessParser.parse(String(data: data, encoding: .utf8) ?? "", limit: limit)
    }
}
