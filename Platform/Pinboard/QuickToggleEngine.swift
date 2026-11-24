import AppKit
import CoreBluetooth
import CoreGraphics
import CoreWLAN
import IOKit.pwr_mgt
import SwiftUI

/// Reads and flips the one-tap system switches (Phase 7B-V2). Lazy: nothing runs until a Quick Settings card
/// refreshes it. Everything uses public tools (`defaults`, `osascript`, `killall`, IOKit power assertions,
/// CoreWLAN); Night Shift and Bluetooth power use private frameworks and report unavailable if the symbols are gone.
@MainActor
final class QuickToggleEngine: ObservableObject {
    /// Phase 16d: the Control Center grid and the edge deck's Quick Settings panel share one
    /// engine, so keep-awake and the switch states never diverge between the two surfaces.
    static let shared = QuickToggleEngine()

    @Published private(set) var states: [QuickToggleID: Bool] = [:]
    @Published private(set) var unavailable: Set<QuickToggleID> = []
    @Published private(set) var flash: QuickToggleID?
    @Published private(set) var vpnServices: [VPNServiceParser.Entry] = []
    private var micPrevious = 70

    /// The owner's manual switch; agent-driven holds are reported by `KeepAwakeService`.
    var keepAwakeOn: Bool { KeepAwakeService.shared.manualOn }

    func refresh() {
        Task.detached(priority: .utility) {
            var next: [QuickToggleID: Bool] = [:]
            var gone = Set<QuickToggleID>()
            let liveMic = Self.readInputVolume()
            let services = VPNService.list()
            for id in QuickToggleID.allCases where !id.isAction {
                if id == .muteMic {
                    if let liveMic { next[.muteMic] = (liveMic == 0) } else { gone.insert(.muteMic) }
                } else if id == .vpn {
                    next[.vpn] = services.contains(where: \.connected)
                } else if let v = Self.read(id) {
                    next[id] = v
                } else if id == .bluetooth {
                    next[id] = false
                } else {
                    gone.insert(id)
                }
            }
            let result = next, missing = gone
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let liveMic, liveMic > 0 { self.micPrevious = liveMic }
                self.vpnServices = services
                var merged = result
                merged[.keepAwake] = self.keepAwakeOn
                self.states = merged
                self.unavailable = missing
            }
        }
    }

    func perform(_ id: QuickToggleID) {
        if id == .keepAwake { setKeepAwake(!keepAwakeOn); return }
        if id == .cleanKeyboard { BarActionService.run(.cleanKeyboard); flashAction(id); return }
        let target = !(states[id] ?? false)
        if !id.isAction { states[id] = target }
        let savedMic = micPrevious
        Task.detached(priority: .userInitiated) {
            let currentMic = id == .muteMic ? Self.readInputVolume() : nil
            let transition = QuickToggleID.resolvedMicTransition(
                turningMuteOn: target,
                currentInputVolume: currentMic,
                savedPrevious: savedMic
            )
            let ok = Self.write(id, target, micPrevious: transition.nextSavedPrevious)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if id == .muteMic { self.micPrevious = transition.nextSavedPrevious }
                if id.isAction { self.flashAction(id) }
                if !ok { self.unavailable.insert(id) }
                self.refresh()
            }
        }
    }

    func toggleVPNService(_ entry: VPNServiceParser.Entry) {
        let target = !entry.connected
        Task.detached(priority: .userInitiated) {
            _ = VPNService.setService(entry.id, connected: target)
            await MainActor.run { [weak self] in self?.refresh() }
        }
    }

    func setKeepAwake(_ on: Bool) {
        KeepAwakeService.shared.setManual(on)
        states[.keepAwake] = on
    }

    private func flashAction(_ id: QuickToggleID) {
        flash = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.flash == id { self?.flash = nil }
        }
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
            guard let v = readInputVolume() else { return nil }
            return v == 0
        case .wifi: return CWWiFiClient.shared().interface()?.powerOn()
        case .bluetooth: return BluetoothPower.read()
        case .nightShift: return NightShift.read()
        case .trueTone: return TrueTone.read()
        case .vpn: return VPNService.anyConnected()
        case .muteOutput: return SystemStatusService.isDefaultOutputMuted()
        case .emptyTrash, .ejectDisks, .screenSaver, .lockScreen, .relaunchFinder, .screenMirroring, .cleanKeyboard: return nil
        }
    }

    nonisolated private static func readInputVolume() -> Int? {
        Int(osascript("input volume of (get volume settings)").trimmingCharacters(in: .whitespacesAndNewlines))
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
        case .trueTone: return TrueTone.write(on)
        case .vpn: return VPNService.set(on)
        case .muteOutput: return SystemStatusService.setDefaultOutputMuted(on)
        case .cleanKeyboard: return true
        case .screenSaver: return run("/usr/bin/open", ["-a", "ScreenSaverEngine"])
        case .lockScreen: return run("/usr/bin/pmset", ["displaysleepnow"])
        case .relaunchFinder: return run("/usr/bin/killall", ["Finder"])
        case .screenMirroring: return run("/usr/bin/open", ["x-apple.systempreferences:com.apple.Displays-Settings.extension"])
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

    /// Reading power goes through IOBluetooth, which asks for Bluetooth access. Never read before the user has granted it
    /// (the first tap on the switch triggers the system prompt), so merely opening the Control Center can't pop a permission dialog.
    static func read() -> Bool? {
        guard CBManager.authorization == .allowedAlways else { return nil }
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

/// Phase 16i: built-in display brightness via the private **DisplayServices** framework, loaded with
/// `dlopen`/`dlsym` so nothing links a private framework at build time. Fail-closed: unsupported → nil,
/// the Control Center simply hides the slider. Mirrors OnlySwitch's `DisplayManager`/`DisplayServices`
/// usage (MIT) — credited in `NOTICE`. External displays are out of scope.
enum DisplayServicesBrightness {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func builtInDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return 0 }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? 0
    }

    /// 0...1 for the built-in panel, or nil when the symbols are gone / no built-in display.
    static func current() -> Double? {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        let id = builtInDisplay()
        guard id != 0 else { return nil }
        var value: Float = 0
        guard unsafeBitCast(sym, to: GetFn.self)(id, &value) == 0, value >= 0, value <= 1.5 else { return nil }
        return Double(min(1, max(0, value)))
    }

    static func set(_ level: Double) {
        guard let h = handle, let sym = dlsym(h, "DisplayServicesSetBrightness") else { return }
        let id = builtInDisplay()
        guard id != 0 else { return }
        let clamped = min(1, max(0, level))
        _ = unsafeBitCast(sym, to: SetFn.self)(id, Float(clamped))
        NotificationCenter.default.post(name: Notification.Name("com.katikati.displayBrightnessChanged"), object: clamped)
    }
}

/// Phase 16i: built-in keyboard backlight via the private CoreBrightness `KeyboardBrightnessClient`
/// (same ObjC-runtime technique as the Night Shift client above). Fail-closed on missing symbols.
/// Mirrors OnlySwitch's `KeyboardManager`/`KeyboardBrightnessClient` (MIT) — credited in `NOTICE`.
enum KeyboardBacklight {
    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type)?.init()
    }()

    private static let getSel = NSSelectorFromString("brightnessForKeyboard:")
    private static let setSel = NSSelectorFromString("setBrightness:forKeyboard:")

    static var isAvailable: Bool { client?.responds(to: getSel) ?? false }

    static func current() -> Double? {
        guard let client, client.responds(to: getSel) else { return nil }
        typealias Fn = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let value = unsafeBitCast(client.method(for: getSel), to: Fn.self)(client, getSel, 1)
        guard value.isFinite else { return nil }
        return Double(min(1, max(0, value)))
    }

    static func set(_ level: Double) {
        guard let client, client.responds(to: setSel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let clamped = min(1, max(0, level))
        _ = unsafeBitCast(client.method(for: setSel), to: Fn.self)(client, setSel, Float(clamped), 1)
        NotificationCenter.default.post(name: Notification.Name("com.katikati.keyboardBrightnessChanged"), object: clamped)
    }
}

/// Phase 16i: True Tone via the private CoreBrightness `CBTrueToneClient` (same ObjC-runtime technique
/// as the Night Shift client above; gated on `supported() && available()`). Fail-closed. Mirrors
/// OnlySwitch (MIT) — credited in `NOTICE`.
private enum TrueTone {
    private static let client: NSObject? = {
        _ = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        return (NSClassFromString("CBTrueToneClient") as? NSObject.Type)?.init()
    }()

    static func read() -> Bool? {
        guard let client else { return nil }
        typealias FlagFn = @convention(c) (AnyObject, Selector) -> Bool
        for sel in ["supported", "available", "enabled"] {
            guard client.responds(to: NSSelectorFromString(sel)) else { return nil }
        }
        let supported = unsafeBitCast(client.method(for: NSSelectorFromString("supported")), to: FlagFn.self)(client, NSSelectorFromString("supported"))
        let available = unsafeBitCast(client.method(for: NSSelectorFromString("available")), to: FlagFn.self)(client, NSSelectorFromString("available"))
        guard supported, available else { return nil }
        return unsafeBitCast(client.method(for: NSSelectorFromString("enabled")), to: FlagFn.self)(client, NSSelectorFromString("enabled"))
    }

    static func write(_ on: Bool) -> Bool {
        guard let client, client.responds(to: NSSelectorFromString("setEnabled:")) else { return false }
        typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Bool
        return unsafeBitCast(client.method(for: NSSelectorFromString("setEnabled:")), to: Fn.self)(client, NSSelectorFromString("setEnabled:"), on)
    }
}

/// Phase 16m: thin wrapper over the single Core implementation (`VPNServiceParser`);
/// the 16i-2 same-shaped-copy debt is paid — no parser lives here anymore.
enum VPNService {
    typealias Entry = VPNServiceParser.Entry
    static func list() -> [Entry] { VPNServiceParser.list() }
    static func anyConnected() -> Bool { VPNServiceParser.anyConnected() }
    static func set(_ on: Bool) -> Bool { VPNServiceParser.set(on) }
    static func setService(_ id: String, connected: Bool) -> Bool { VPNServiceParser.setService(id, connected: connected) }
}

// MARK: - MB-5: Shortcuts, Evolutions & Coalesced Hub Scheduler

enum ShortcutsCatalogRunner {
    static let timeout: TimeInterval = 5

    static func listNames() async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let raw = runOutput("/usr/bin/shortcuts", ["list"])
                let names = raw.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                continuation.resume(returning: names)
            }
        }
    }

    @discardableResult
    static func runShortcut(named name: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runStatus("/usr/bin/shortcuts", ["run", name]))
            }
        }
    }

    fileprivate static func runOutput(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        watchdog.cancel()
        return String(data: data, encoding: .utf8) ?? ""
    }

    fileprivate static func runStatus(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let watchdog = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        p.waitUntilExit()
        watchdog.cancel()
        return p.terminationStatus == 0
    }
}

enum EvolutionRunner {
    static func run(_ item: EvolutionItem) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ok: Bool
                switch item.shell {
                case .sh: ok = ShortcutsCatalogRunner.runStatus("/bin/sh", ["-c", item.runScript])
                case .appleScript: ok = ShortcutsCatalogRunner.runStatus("/usr/bin/osascript", ["-e", item.runScript])
                }
                continuation.resume(returning: ok)
            }
        }
    }

    static func probeStatus(_ item: EvolutionItem) async -> Bool? {
        guard item.kind == .toggle, let script = item.statusScript, !script.isEmpty else { return nil }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let ok: Bool
                switch item.shell {
                case .sh: ok = ShortcutsCatalogRunner.runStatus("/bin/sh", ["-c", script])
                case .appleScript: ok = ShortcutsCatalogRunner.runStatus("/usr/bin/osascript", ["-e", script])
                }
                continuation.resume(returning: ok)
            }
        }
    }
}

@MainActor
final class HubScheduleCoordinator: ObservableObject {
    static let shared = HubScheduleCoordinator()

    @Published private(set) var rules: [HubScheduleRule] = []
    private var timer: DispatchSourceTimer?
    private var defaultsObserver: NSObjectProtocol?

    func startIfNeeded() {
        reload()
        guard defaultsObserver == nil else { return }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reload() }
        }
    }

    func save(_ next: [HubScheduleRule]) {
        rules = next
        UserDefaults.standard.set(HubScheduleRule.encode(next), forKey: HubScheduleRule.defaultsKey)
        reschedule()
    }

    func reload() {
        let parsed = HubScheduleRule.parse(UserDefaults.standard.data(forKey: HubScheduleRule.defaultsKey))
        if parsed != rules {
            rules = parsed
            reschedule()
        } else if timer == nil, !rules.isEmpty {
            reschedule()
        }
    }

    private func reschedule() {
        timer?.cancel()
        timer = nil
        guard let next = HubScheduleRule.nextPendingRule(in: rules, after: Date()) else { return }
        let delay = max(0.5, next.fireDate.timeIntervalSinceNow)
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + delay, leeway: .seconds(1))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fireDueRules() }
        }
        source.resume()
        timer = source
    }

    private func fireDueRules() {
        let now = Date()
        var updated = rules
        var changed = false
        for idx in updated.indices where updated[idx].isEnabled {
            if let fire = updated[idx].nextFireDate(after: now.addingTimeInterval(-2)), fire <= now.addingTimeInterval(2) {
                execute(updated[idx])
                if case .afterMinutes = updated[idx].kind {
                    updated[idx].isEnabled = false
                    changed = true
                }
            }
        }
        if changed { save(updated) } else { reschedule() }
    }

    private func execute(_ rule: HubScheduleRule) {
        guard let switchID = HubSwitchID(token: rule.targetToken) else { return }
        switch switchID {
        case .system(let q):
            if q == .keepAwake {
                QuickToggleEngine.shared.setKeepAwake(rule.desiredState)
            } else if q.isAction || (QuickToggleEngine.shared.states[q] ?? false) != rule.desiredState {
                QuickToggleEngine.shared.perform(q)
            }
        case .surface(let s):
            Self.applySurface(s, enabled: rule.desiredState)
        case .shortcut(let name):
            Task { _ = await ShortcutsCatalogRunner.runShortcut(named: name) }
        case .evolution(let uuid):
            let items = EvolutionItem.parse(UserDefaults.standard.data(forKey: EvolutionItem.defaultsKey))
            if let item = items.first(where: { $0.id == uuid }) {
                Task { _ = await EvolutionRunner.run(item) }
            }
        }
    }

    static func applySurface(_ surface: KatiKatiSurfaceToggle, enabled: Bool) {
        let d = UserDefaults.standard
        switch surface {
        case .notch:
            AppDelegate.shared?.settingsStore.setNotchIslandEnabled(enabled)
        case .desktopBoxes:
            d.set(enabled, forKey: DesktopCanvasConfig.enabledKey)
        case .nowPlaying:
            d.set(enabled, forKey: MusicSurfaceConfig.enabledKey)
            MusicSurfaceConfig.notifyChange()
        case .lockScreenCard:
            d.set(enabled, forKey: MusicSurfaceConfig.lockScreenCardKey)
            MusicSurfaceConfig.notifyChange()
        case .metricsBar:
            d.set(enabled, forKey: MenuBarStatModel.masterEnabledKey)
        }
    }
}
