import Foundation

/// One-tap system switches (Phase 7B-V2). State and actions live in the Platform engine; this is the catalog.
enum QuickToggleID: String, CaseIterable, Sendable {
    case darkMode, keepAwake, hideDesktopIcons, showHiddenFiles, dockAutoHide, pathBar
    case muteMic, emptyTrash, ejectDisks, wifi, bluetooth, nightShift
    case trueTone, vpn, muteOutput, cleanKeyboard
    /// Phase 16s: utility actions in the OnlySwitch genre (open-only or fire-and-done, no new
    /// permission, no private API): start the screen saver, lock the screen, relaunch the Finder,
    /// open Display Settings for screen mirroring.
    case screenSaver, lockScreen, relaunchFinder, screenMirroring

    /// Actions have no on/off state: they run and report done.
    var isAction: Bool {
        self == .emptyTrash || self == .ejectDisks || self == .screenSaver || self == .lockScreen
            || self == .relaunchFinder || self == .screenMirroring || self == .cleanKeyboard
    }
    /// Needs a confirmation click before it runs.
    var needsConfirm: Bool { self == .emptyTrash || self == .lockScreen || self == .relaunchFinder }

    var symbolName: String {
        switch self {
        case .darkMode: return "moon.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .hideDesktopIcons: return "eye.slash.fill"
        case .showHiddenFiles: return "folder.fill"
        case .dockAutoHide: return "dock.rectangle"
        case .pathBar: return "chevron.right.square.fill"
        case .muteMic: return "mic.slash.fill"
        case .emptyTrash: return "trash.fill"
        case .ejectDisks: return "eject.fill"
        case .wifi: return "wifi"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .nightShift: return "sun.max.fill"
        case .trueTone: return "circle.lefthalf.filled"
        case .vpn: return "network"
        case .muteOutput: return "speaker.slash.fill"
        case .cleanKeyboard: return "keyboard.badge.ellipsis"
        case .screenSaver: return "moon.zzz.fill"
        case .lockScreen: return "lock.fill"
        case .relaunchFinder: return "arrow.clockwise"
        case .screenMirroring: return "airplayvideo"
        }
    }

    static let defaultOrder: [QuickToggleID] = allCases

    static func parse(_ raw: String?) -> [QuickToggleID] {
        guard let raw else { return defaultOrder }
        var seen = Set<QuickToggleID>()
        return raw.split(separator: ",").compactMap { QuickToggleID(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func serialize(_ ids: [QuickToggleID]) -> String { ids.map(\.rawValue).joined(separator: ",") }

    /// Computes the target input volume and updated `micPrevious` when toggling `.muteMic`.
    static func resolvedMicTransition(
        turningMuteOn: Bool,
        currentInputVolume: Int?,
        savedPrevious: Int
    ) -> (targetVolume: Int, nextSavedPrevious: Int) {
        let nextSaved = (currentInputVolume ?? 0) > 0 ? (currentInputVolume ?? savedPrevious) : savedPrevious
        let clampedRestore = min(100, max(40, nextSaved))
        return (turningMuteOn ? 0 : clampedRestore, nextSaved)
    }
}

/// Phase 16i: Network-configured VPNs via `/usr/sbin/scutil --nc`. Best-effort single toggle — the tile
/// reflects whether any configured service is connected; turning on connects the first configured
/// service, turning off disconnects the connected one. Third-party agents without a Network service are
/// out of scope. Lives in Core (not Platform) so the pure parser is dual-compiled and unit-tested.
///
/// Phase 16m: single implementation — the Platform `VPNService` delegates here (the 16i-2 debt is paid).
enum VPNServiceParser {
    struct Entry: Equatable {
        let id: String
        let name: String
        let connected: Bool
    }

    static func list() -> [Entry] { parse(output("/usr/sbin/scutil", ["--nc", "list"])) }

    /// `scutil --nc list` prints lines like
    /// ``  * (Connected)  01234567-89AB-CDEF-0123-456789ABCDEF  "My VPN"  [VPN:...] ``.
    /// Tolerant: skips unparseable lines, never fabricates a service.
    static func parse(_ text: String) -> [Entry] {
        var entries: [Entry] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("*") || trimmed.hasPrefix("(") else { continue }
            let connected = trimmed.contains("(Connected)")
            guard let id = trimmed.split(separator: " ").first(where: { $0.contains("-") && $0.count >= 8 }).map(String.init) else { continue }
            let name: String = {
                guard let first = trimmed.firstIndex(of: "\""),
                      let last = trimmed.lastIndex(of: "\""), first != last else { return id }
                return String(trimmed[trimmed.index(after: first)..<last])
            }()
            entries.append(Entry(id: id, name: name, connected: connected))
        }
        return entries
    }

    static func anyConnected() -> Bool { list().contains { $0.connected } }

    static func set(_ on: Bool) -> Bool {
        let services = list()
        if on {
            guard let target = services.first(where: { !$0.connected }) ?? services.first else { return false }
            return status("/usr/sbin/scutil", ["--nc", "start", target.id]) == 0
        }
        guard let active = services.first(where: { $0.connected }) else { return true }
        return status("/usr/sbin/scutil", ["--nc", "stop", active.id]) == 0
    }

    static func setService(_ id: String, connected: Bool) -> Bool {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return status("/usr/sbin/scutil", ["--nc", connected ? "start" : "stop", id]) == 0
    }

    private static func status(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus } catch { return -1 }
    }

    private static func output(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - MB-4: Menu Bar Creative Hub Switchboard & Schedules

enum KatiKatiSurfaceToggle: String, CaseIterable, Identifiable, Codable, Sendable {
    case notch, desktopBoxes, nowPlaying, lockScreenCard, metricsBar

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .notch: return "capsule.tophalf.filled"
        case .desktopBoxes: return "macwindow.on.rectangle"
        case .nowPlaying: return "music.note"
        case .lockScreenCard: return "lock.fill"
        case .metricsBar: return "menubar.rectangle"
        }
    }
}

enum HubSwitchID: Hashable, Identifiable, Sendable {
    case system(QuickToggleID)
    case surface(KatiKatiSurfaceToggle)
    case shortcut(String)
    case evolution(UUID)

    var id: String { token }

    var token: String {
        switch self {
        case .system(let q): return "sys:\(q.rawValue)"
        case .surface(let s): return "surf:\(s.rawValue)"
        case .shortcut(let name): return "sc:\(name)"
        case .evolution(let uuid): return "evo:\(uuid.uuidString)"
        }
    }

    init?(token: String) {
        if token.hasPrefix("sys:"), let q = QuickToggleID(rawValue: String(token.dropFirst(4))) {
            self = .system(q)
        } else if token.hasPrefix("surf:"), let s = KatiKatiSurfaceToggle(rawValue: String(token.dropFirst(5))) {
            self = .surface(s)
        } else if token.hasPrefix("sc:") {
            let name = String(token.dropFirst(3))
            guard !name.isEmpty else { return nil }
            self = .shortcut(name)
        } else if token.hasPrefix("evo:"), let uuid = UUID(uuidString: String(token.dropFirst(4))) {
            self = .evolution(uuid)
        } else {
            return nil
        }
    }
}

enum HubSwitchCatalog {
    static let orderKey = "com.katikati.menuBarHub.switchOrder"
    static let hiddenKey = "com.katikati.menuBarHub.hiddenSwitches"

    static var defaultOrder: [HubSwitchID] {
        KatiKatiSurfaceToggle.allCases.map { .surface($0) } + QuickToggleID.allCases.map { .system($0) }
    }

    static func orderedSwitches(
        extra: [HubSwitchID] = [],
        includeHidden: Bool = false,
        defaults: UserDefaults = .standard
    ) -> [HubSwitchID] {
        let hidden: Set<String> = includeHidden ? [] : Set(
            (defaults.string(forKey: hiddenKey) ?? "").split(separator: ",").map(String.init)
        )
        let pool = defaultOrder + extra
        let rawOrder = (defaults.string(forKey: orderKey) ?? "")
            .split(separator: ",")
            .compactMap { HubSwitchID(token: String($0)) }
        var seen = Set<HubSwitchID>()
        var result: [HubSwitchID] = []
        for item in rawOrder + pool where pool.contains(item) && seen.insert(item).inserted {
            if !hidden.contains(item.token) { result.append(item) }
        }
        return result
    }

    static func serialize(_ ids: [HubSwitchID]) -> String {
        ids.map(\.token).joined(separator: ",")
    }

    static func filter(_ items: [HubSwitchID], query: String, titleOf: (HubSwitchID) -> String) -> [HubSwitchID] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { titleOf($0).localizedCaseInsensitiveContains(q) }
    }
}

struct HubScheduleRule: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Codable, Equatable, Sendable {
        case afterMinutes(Int)
        case daily(hour: Int, minute: Int)
    }

    var id: UUID
    var targetToken: String
    var desiredState: Bool
    var kind: Kind
    var isEnabled: Bool
    var createdAt: Date

    static let defaultsKey = "com.katikati.menuBarHub.schedules"

    init(
        id: UUID = UUID(),
        targetToken: String,
        desiredState: Bool,
        kind: Kind,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.targetToken = targetToken
        self.desiredState = desiredState
        self.kind = kind
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    func nextFireDate(after reference: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        switch kind {
        case .afterMinutes(let minutes):
            let target = createdAt.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
            return target > reference ? target : nil
        case .daily(let hour, let minute):
            let comps = DateComponents(hour: min(23, max(0, hour)), minute: min(59, max(0, minute)), second: 0)
            return calendar.nextDate(after: reference, matching: comps, matchingPolicy: .nextTime)
        }
    }

    static func nextPendingRule(
        in rules: [HubScheduleRule],
        after now: Date,
        calendar: Calendar = .current
    ) -> (rule: HubScheduleRule, fireDate: Date)? {
        rules.compactMap { rule in
            rule.nextFireDate(after: now, calendar: calendar).map { (rule, $0) }
        }
        .min { $0.fireDate < $1.fireDate }
    }

    static func parse(_ data: Data?) -> [HubScheduleRule] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([HubScheduleRule].self, from: data)) ?? []
    }

    static func encode(_ rules: [HubScheduleRule]) -> Data? {
        try? JSONEncoder().encode(rules)
    }
}
