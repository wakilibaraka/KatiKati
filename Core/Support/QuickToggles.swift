import Foundation

/// One-tap system switches (Phase 7B-V2). State and actions live in the Platform engine; this is the catalog.
enum QuickToggleID: String, CaseIterable, Sendable {
    case darkMode, keepAwake, hideDesktopIcons, showHiddenFiles, dockAutoHide, pathBar
    case muteMic, emptyTrash, ejectDisks, wifi, bluetooth, nightShift
    case trueTone, vpn

    /// Actions have no on/off state: they run and report done.
    var isAction: Bool { self == .emptyTrash || self == .ejectDisks }
    /// Needs a confirmation click before it runs.
    var needsConfirm: Bool { self == .emptyTrash }

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
        }
    }

    static let defaultOrder: [QuickToggleID] = allCases

    static func parse(_ raw: String?) -> [QuickToggleID] {
        guard let raw else { return defaultOrder }
        var seen = Set<QuickToggleID>()
        return raw.split(separator: ",").compactMap { QuickToggleID(rawValue: String($0)) }.filter { seen.insert($0).inserted }
    }

    static func serialize(_ ids: [QuickToggleID]) -> String { ids.map(\.rawValue).joined(separator: ",") }
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
