import AppKit
import Foundation
import IOKit
import IOKit.ps
import OpenDirectory

/// Platform readers behind the system-health tiles (Phase 16m: moved verbatim from
/// `Platform/Pinboard/PinboardReaders.swift`). Each is a one-shot read; the tile decides how often to call.
enum BatteryHealthReader {
    static func read() -> BatteryHealth? {
        smartBattery().flatMap(BatteryHealth.init(registry:))
    }

    /// One registry read, shared with `PowerFactsReader` so the two never disagree about the battery.
    static func smartBattery() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }
}

/// 59c — the live power numbers, read once per call: macOS's own time estimate, the registry's
/// amperage × voltage, and the OS's thermal and low-power state. Nothing here shells out.
enum PowerFactsReader {
    static func read(isCharging: Bool) -> PowerFacts {
        var facts = PowerFacts(thermal: PowerThermal(ProcessInfo.processInfo.thermalState),
                               isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                               isCharging: isCharging)
        facts.secondsRemaining = iopsBattery().flatMap {
            PowerFacts.secondsRemaining(powerSource: $0, isCharging: isCharging)
        }
        if let props = BatteryHealthReader.smartBattery() {
            facts.watts = PowerFacts.watts(amperage: signed64(props["InstantAmperage"]),
                                           millivolts: signed64(props["Voltage"]))
        }
        return facts
    }

    /// The internal battery's IOPS description (the same one `SystemStatusService` reads).
    static func iopsBattery() -> [String: Any]? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        return list.lazy
            .compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
            .first { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }
    }

    /// A discharging amperage reaches us as the unsigned 64-bit wrap of a negative number, which is
    /// exactly why `PowerFacts.watts` reads it back through `Int64(bitPattern:)`.
    static func signed64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.uint64Value > UInt64(Int64.max)
            ? Int64(bitPattern: number.uint64Value) : number.int64Value }
        if let value = value as? Int { return Int64(value) }
        return nil
    }
}

enum TopProcessReader {
    static func read(limit: Int) -> [TopProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        // Pid first: the rows stay actionable. Still one shot, still off the main thread at every call site.
        p.arguments = ["-Ao", "pid=,pcpu=,comm=", "-r"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return TopProcessParser.parse(String(data: data, encoding: .utf8) ?? "", limit: limit)
    }
}

/// The current macOS user for the Control Center account row (Phase 16u). Local directory only —
/// no permission, no network. Falls back to the login names with no picture when unreadable.
struct CurrentUser: Equatable {
    var fullName: String
    var avatar: Data?
}

enum CurrentUserReader {
    static func read() -> CurrentUser {
        let login = NSUserName()
        var fullName = NSFullUserName()
        var avatar: Data?
        if let session = try? ODSession.default(),
           let node = try? ODNode(session: session, name: "/Local/Default"),
           let record = try? node.record(
               withRecordType: kODRecordTypeUsers, name: login,
               attributes: [kODAttributeTypeFullName, kODAttributeTypeJPEGPhoto, kODAttributeTypePicture]) {
            if let names = try? record.values(forAttribute: kODAttributeTypeFullName) as? [String],
               let first = names.first, !first.isEmpty {
                fullName = first
            }
            if let photos = try? record.values(forAttribute: kODAttributeTypeJPEGPhoto) as? [Data],
               let first = photos.first, !first.isEmpty {
                avatar = first
            } else if let pictures = try? record.values(forAttribute: kODAttributeTypePicture) as? [String],
                      let path = pictures.first, !path.isEmpty {
                avatar = try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return CurrentUser(fullName: fullName.isEmpty ? login : fullName, avatar: avatar)
    }

    /// Users & Groups in System Settings ("Manage accounts"); falls back to the main Settings page.
    static func openUsersGroups() {
        let pane = URL(string: "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension")!
        if !NSWorkspace.shared.open(pane) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        }
    }
}
