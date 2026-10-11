import AppKit
import CoreWLAN
import IOKit.pwr_mgt
import SwiftUI

/// Reads and flips the one-tap system switches (Phase 7B-V2). Lazy: nothing runs until a Quick Settings card
/// refreshes it. Everything uses public tools (`defaults`, `osascript`, `killall`, IOKit power assertions,
/// CoreWLAN); Night Shift and Bluetooth power use private frameworks and report unavailable if the symbols are gone.
@MainActor
final class QuickToggleEngine: ObservableObject {
    @Published private(set) var states: [QuickToggleID: Bool] = [:]
    @Published private(set) var unavailable: Set<QuickToggleID> = []
    @Published private(set) var flash: QuickToggleID?
    private var awakeAssertion: IOPMAssertionID = 0
    private var micPrevious = 70

    var keepAwakeOn: Bool { awakeAssertion != 0 }

    func refresh() {
        Task.detached(priority: .utility) {
            var next: [QuickToggleID: Bool] = [:]
            var gone = Set<QuickToggleID>()
            for id in QuickToggleID.allCases where !id.isAction {
                if let v = Self.read(id) { next[id] = v } else { gone.insert(id) }
            }
            let result = next, missing = gone
            await MainActor.run { [weak self] in
                guard let self else { return }
                var merged = result
                merged[.keepAwake] = self.keepAwakeOn
                self.states = merged
                self.unavailable = missing
            }
        }
    }

    func perform(_ id: QuickToggleID) {
        if id == .keepAwake { setKeepAwake(!keepAwakeOn); return }
        let target = !(states[id] ?? false)
        if !id.isAction { states[id] = target }
        Task.detached(priority: .userInitiated) {
            let ok = Self.write(id, target, micPrevious: await self.micPrevious)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if id.isAction { self.flash = id; DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { self.flash = nil } }
                if !ok { self.unavailable.insert(id) }
                self.refresh()
            }
        }
    }

    func setKeepAwake(_ on: Bool) {
        if on, awakeAssertion == 0 {
            IOPMAssertionCreateWithName("PreventUserIdleDisplaySleep" as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "KatiKati Keep Awake" as CFString, &awakeAssertion)
        } else if !on, awakeAssertion != 0 {
            IOPMAssertionRelease(awakeAssertion); awakeAssertion = 0
        }
        states[.keepAwake] = keepAwakeOn
    }

    // MARK: Reading (background)

    nonisolated private static func read(_ id: QuickToggleID) -> Bool? {
        switch id {
        case .darkMode: return UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        case .keepAwake: return false
        case .hideDesktopIcons: return !(defaultsBool("com.apple.finder", "CreateDesktop") ?? true)
        case .showHiddenFiles: return defaultsBool("com.apple.finder", "AppleShowAllFiles") ?? false
        case .dockAutoHide: return defaultsBool("com.apple.dock", "autohide") ?? false
        case .pathBar: return defaultsBool("com.apple.finder", "ShowPathbar") ?? false
        case .muteMic:
            guard let v = Int(osascript("input volume of (get volume settings)").trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            return v == 0
        case .wifi: return CWWiFiClient.shared().interface()?.powerOn()
        case .bluetooth: return BluetoothPower.read()
        case .nightShift: return NightShift.read()
        case .emptyTrash, .ejectDisks: return nil
        }
    }

    nonisolated private static func defaultsBool(_ domain: String, _ key: String) -> Bool? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) else { return nil }
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.boolValue }
        return nil
    }

    // MARK: Writing (background)

    nonisolated private static func write(_ id: QuickToggleID, _ on: Bool, micPrevious: Int) -> Bool {
        switch id {
        case .darkMode:
            return osascriptOK("tell application \"System Events\" to tell appearance preferences to set dark mode to \(on)")
        case .keepAwake: return true
        case .hideDesktopIcons: return finderDefault("CreateDesktop", !on, restart: "Finder")
        case .showHiddenFiles: return finderDefault("AppleShowAllFiles", on, restart: "Finder")
        case .pathBar: return finderDefault("ShowPathbar", on, restart: "Finder")
        case .dockAutoHide:
            return run("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", on ? "true" : "false"])
                && run("/usr/bin/killall", ["Dock"])
        case .muteMic: return osascriptOK("set volume input volume \(on ? 0 : max(micPrevious, 40))")
        case .emptyTrash: return osascriptOK("tell application \"Finder\" to empty the trash")
        case .ejectDisks: return osascriptOK("tell application \"Finder\" to eject (every disk whose ejectable is true)")
        case .wifi:
            guard let iface = CWWiFiClient.shared().interface() else { return false }
            return (try? iface.setPower(on)) != nil
        case .bluetooth: return BluetoothPower.write(on)
        case .nightShift: return NightShift.write(on)
        }
    }

    nonisolated private static func finderDefault(_ key: String, _ value: Bool, restart: String) -> Bool {
        run("/usr/bin/defaults", ["write", "com.apple.finder", key, "-bool", value ? "true" : "false"]) && run("/usr/bin/killall", [restart])
    }

    nonisolated private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    nonisolated private static func osascript(_ source: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    nonisolated private static func osascriptOK(_ source: String) -> Bool {
        run("/usr/bin/osascript", ["-e", source])
    }
}

/// Private-framework switches. Every lookup is dynamic so a missing symbol means "unavailable", never a crash.
private enum BluetoothPower {
    typealias GetFn = @convention(c) () -> Int32
    typealias SetFn = @convention(c) (Int32) -> Void

    private static let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY)

    static func read() -> Bool? {
        guard let h = handle, let sym = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        return unsafeBitCast(sym, to: GetFn.self)() != 0
    }

    static func write(_ on: Bool) -> Bool {
        guard let h = handle, let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") else { return false }
        unsafeBitCast(sym, to: SetFn.self)(on ? 1 : 0)
        return true
    }
}

private enum NightShift {
    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("CBBlueLightClient") as? NSObject.Type)?.init()
    }()

    static func read() -> Bool? {
        guard let client, client.responds(to: NSSelectorFromString("getBlueLightStatus:")) else { return nil }
        var status = [UInt8](repeating: 0, count: 64)
        typealias Fn = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        let imp = client.method(for: NSSelectorFromString("getBlueLightStatus:"))
        let ok = status.withUnsafeMutableBytes { unsafeBitCast(imp, to: Fn.self)(client, NSSelectorFromString("getBlueLightStatus:"), $0.baseAddress!) }
        guard ok else { return nil }
        // struct { BOOL active; BOOL enabled; ... } — `enabled` is the second field.
        return status[1] != 0
    }

    static func write(_ on: Bool) -> Bool {
        guard let client, client.responds(to: NSSelectorFromString("setEnabled:")) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        return unsafeBitCast(client.method(for: NSSelectorFromString("setEnabled:")), to: Fn.self)(client, NSSelectorFromString("setEnabled:"), on)
    }
}
