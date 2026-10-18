import AppKit
import Foundation
import IOKit
import OpenDirectory

/// Platform readers behind the system-health tiles (Phase 16m: moved verbatim from
/// `Platform/Pinboard/PinboardReaders.swift`). Each is a one-shot read; the tile decides how often to call.
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
