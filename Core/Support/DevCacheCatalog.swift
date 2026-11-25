import Foundation

/// SD-3d: the developer-cache catalogue — where Xcode, node, CocoaPods, SwiftPM, Docker, pip and Cargo keep
/// their rebuildable data, how risky each root is to reclaim, and how to add them up.
///
/// The catalogue and its risk levels follow `bysiber/cleardisk` (MIT); the code is written here against
/// KatiKati's own storage scan. Pure by construction: paths are derived from a home directory and every disk
/// read is injected, so `DevCacheCatalogTests` pins every path and total without touching the filesystem.
struct DevCacheTarget: Identifiable, Hashable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case derivedData, archives, nodeModules, cocoaPods, swiftPackages, docker, pip, cargo
    }

    /// How much the owner should think before reclaiming a root.
    enum Risk: Int, CaseIterable, Comparable, Sendable {
        /// Rebuilt on the next build or install with nothing lost.
        case low
        /// Rebuilt, but the next build or install is slow (or needs the network).
        case medium
        /// Holds state the owner may still need: submitted archives, container images.
        case high

        static func < (lhs: Risk, rhs: Risk) -> Bool { lhs.rawValue < rhs.rawValue }

        /// Low and medium are safe to reclaim in one click; high always asks first.
        var isReclaimableInOneClick: Bool { self != .high }

        /// A risk level the catalogue already localizes (Low / Medium / High), never a new key.
        var localizedTitle: String {
            switch self {
            case .low: return String(localized: "Low")
            case .medium: return String(localized: "Medium")
            case .high: return String(localized: "High")
            }
        }
    }

    let kind: Kind
    /// A proper noun (Xcode, node_modules, pip…), shown verbatim, exactly as the tools spell it.
    let title: String
    let symbol: String
    let risk: Risk
    /// Home-relative roots. Empty for a kind that has to be discovered (`node_modules`).
    let relativePaths: [String]

    var id: String { kind.rawValue }

    func resolvedPaths(home: String) -> [String] {
        relativePaths.map { home + "/" + $0 }
    }
}

/// One target with the roots that actually exist and what they weigh.
struct DevCacheReading: Identifiable, Equatable, Sendable {
    let target: DevCacheTarget
    let paths: [String]
    let bytes: Int64

    var id: String { target.id }
}

enum DevCacheCatalog {
    static let targets: [DevCacheTarget] = [
        DevCacheTarget(kind: .derivedData, title: "Xcode", symbol: "hammer", risk: .low,
                       relativePaths: ["Library/Developer/Xcode/DerivedData",
                                       "Library/Developer/Xcode/iOS DeviceSupport"]),
        DevCacheTarget(kind: .archives, title: "Xcode Archives", symbol: "archivebox", risk: .high,
                       relativePaths: ["Library/Developer/Xcode/Archives"]),
        DevCacheTarget(kind: .nodeModules, title: "node_modules", symbol: "shippingbox", risk: .medium,
                       relativePaths: []),
        DevCacheTarget(kind: .cocoaPods, title: "CocoaPods", symbol: "leaf", risk: .low,
                       relativePaths: ["Library/Caches/CocoaPods"]),
        DevCacheTarget(kind: .swiftPackages, title: "Swift Package Manager", symbol: "swift", risk: .low,
                       relativePaths: ["Library/Caches/org.swift.swiftpm", "Library/org.swift.swiftpm"]),
        DevCacheTarget(kind: .docker, title: "Docker", symbol: "shippingbox.fill", risk: .high,
                       relativePaths: ["Library/Containers/com.docker.docker/Data/vms",
                                       "Library/Group Containers/group.com.docker"]),
        DevCacheTarget(kind: .pip, title: "pip", symbol: "terminal", risk: .low,
                       relativePaths: ["Library/Caches/pip"]),
        DevCacheTarget(kind: .cargo, title: "Cargo", symbol: "cube.box", risk: .low,
                       relativePaths: ["Library/Caches/org.rust-lang.cargo", ".cargo/registry/cache"]),
    ]

    /// Where a `node_modules` is worth looking for: one directory deep under the usual source folders.
    static func projectRoots(home: String) -> [String] {
        var seen = Set<String>()
        return ["Developer", "Documents/GitHub", "Projects", "Code", "src"]
            .map { home + "/" + $0 }
            .filter { seen.insert($0).inserted }
    }

    /// Reads the catalogue through injected filesystem access: a root is reported only when it exists and is
    /// non-empty, so a machine without Docker never sees a Docker row.
    static func snapshot(home: String,
                         isDirectory: (String) -> Bool,
                         size: (String) -> Int64,
                         children: (String) -> [String]) -> [DevCacheReading] {
        targets.compactMap { target in
            var found = target.resolvedPaths(home: home).filter(isDirectory)
            if target.kind == .nodeModules {
                for root in projectRoots(home: home) where isDirectory(root) {
                    for project in children(root) {
                        let modules = project + "/node_modules"
                        if isDirectory(modules) { found.append(modules) }
                    }
                }
            }
            let bytes = found.reduce(Int64(0)) { $0 + size($1) }
            guard !found.isEmpty, bytes > 0 else { return nil }
            return DevCacheReading(target: target, paths: found, bytes: bytes)
        }
    }

    /// What a single "reclaim" click may take: low and medium only, so an archive or a container image is
    /// never swept up by a total the owner did not read.
    static func reclaimableBytes(_ readings: [DevCacheReading]) -> Int64 {
        readings.filter { $0.target.risk.isReclaimableInOneClick }.reduce(0) { $0 + $1.bytes }
    }

    /// Highest risk first (so the rows that need thought stay visible), then largest.
    static func ordered(_ readings: [DevCacheReading]) -> [DevCacheReading] {
        readings.sorted {
            $0.target.risk == $1.target.risk ? $0.bytes > $1.bytes : $0.target.risk > $1.target.risk
        }
    }
}

/// The Storage page's last developer-cache measurement, kept for surfaces that must not scan.
struct DevCacheSnapshot: Equatable, Sendable {
    var measuredAt: Date
    var reclaimableBytes: Int64
}

/// One writer, many readers: the Storage page saves what it measured while it was open, and the
/// dashboard reads that total instead of starting a scan of its own. A dashboard that is off screen
/// therefore costs nothing, and an open one costs one preferences read — the 0.0 % idle rule holds
/// without the deck ever measuring the disk.
enum DevCacheSnapshotStore {
    static let key = "com.katikati.devcache.snapshot.v1"
    private static let prefix = "v1"

    static func encode(_ snapshot: DevCacheSnapshot) -> String {
        "\(prefix)|\(Int(snapshot.measuredAt.timeIntervalSince1970))|\(snapshot.reclaimableBytes)"
    }

    static func decode(_ raw: String?) -> DevCacheSnapshot? {
        guard let raw else { return nil }
        let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix,
              let seconds = TimeInterval(parts[1]),
              let bytes = Int64(parts[2]), bytes >= 0 else { return nil }
        return DevCacheSnapshot(measuredAt: Date(timeIntervalSince1970: seconds), reclaimableBytes: bytes)
    }

    /// Called by the page that already ran the measurement — never by a timer or a second surface.
    static func save(_ readings: [DevCacheReading], at date: Date = Date(),
                     defaults: UserDefaults = .standard) {
        let snapshot = DevCacheSnapshot(measuredAt: date,
                                        reclaimableBytes: DevCacheCatalog.reclaimableBytes(readings))
        defaults.set(encode(snapshot), forKey: key)
    }

    static func load(defaults: UserDefaults = .standard) -> DevCacheSnapshot? {
        decode(defaults.string(forKey: key))
    }
}
