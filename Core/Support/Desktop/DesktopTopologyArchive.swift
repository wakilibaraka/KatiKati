import CoreGraphics
import Foundation

/// Keys and bounded defaults for multi-display topology memory (Phase 65).
enum DesktopTopologyConfig {
    static let archiveKey = "com.katikati.desktop.topologyArchive"
    static let defaultDisplayUUIDKey = "com.katikati.desktop.defaultDisplayUUID"
    static let disconnectActionKey = "com.katikati.desktop.disconnectAction"
    static let disconnectGraceSecondsKey = "com.katikati.desktop.disconnectGraceSeconds"

    static let defaultDisconnectGraceSeconds: Double = 8
    static let disconnectGraceRange: ClosedRange<Double> = 0...60
    static let archiveEntryLimit = 24

    static func clampedGraceSeconds(_ value: Double) -> Double {
        min(max(value, disconnectGraceRange.lowerBound), disconnectGraceRange.upperBound)
    }

    static func graceSeconds(defaults: UserDefaults = .standard) -> Double {
        let raw = defaults.object(forKey: disconnectGraceSecondsKey) as? Double
            ?? defaultDisconnectGraceSeconds
        return clampedGraceSeconds(raw)
    }

    static func disconnectAction(defaults: UserDefaults = .standard) -> DesktopDisconnectAction {
        guard let raw = defaults.string(forKey: disconnectActionKey),
              let action = DesktopDisconnectAction(rawValue: raw)
        else { return .relocate }
        return action
    }

    static func defaultDisplayUUID(defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: defaultDisplayUUIDKey), !raw.isEmpty else { return nil }
        return raw
    }
}

/// What happens to widgets whose display disappears after the grace period.
enum DesktopDisconnectAction: String, Codable, CaseIterable, Sendable {
    case relocate
    case capsule
}

/// A Codable rectangle because `CGRect` encoding is not stable across SDKs.
struct TopologyRect: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var area: CGFloat { max(0, width) * max(0, height) }
}

/// One connected display as the archive and planner see it (AppKit coordinates).
struct TopologyDisplay: Codable, Equatable, Sendable {
    let uuid: String
    var screenFrame: TopologyRect
    var visibleFrame: TopologyRect

    init(uuid: String, screenFrame: TopologyRect, visibleFrame: TopologyRect) {
        self.uuid = uuid
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
    }

    init(uuid: String, screenFrame: CGRect, visibleFrame: CGRect) {
        self.init(uuid: uuid, screenFrame: TopologyRect(screenFrame), visibleFrame: TopologyRect(visibleFrame))
    }
}

/// One display as the Settings Displays stage lists it.
struct DesktopConnectedDisplay: Identifiable, Equatable, Sendable {
    let uuid: String
    let title: String
    let isPrimary: Bool
    let screenFrame: CGRect
    let visibleFrame: CGRect

    var id: String { uuid }
}

/// Canonical sorted EDID-UUID signature: stable across cable/port changes and screen ordering.
enum DisplayTopologySignature {
    static func make(_ uuids: [String]) -> String {
        let unique = Array(Set(uuids.filter { !$0.isEmpty })).sorted()
        return unique.joined(separator: "|")
    }

    static func uuids(in signature: String) -> [String] {
        signature.split(separator: "|").map(String.init).filter { !$0.isEmpty }
    }
}

/// A widget's remembered spot in one topology.
struct TopologyWidgetPlacement: Codable, Equatable, Sendable {
    var displayUUID: String?
    var normalizedFrame: NormalizedWidgetRect
    var capsuleMode: DesktopCapsuleMode
}

/// One remembered arrangement: which displays were present and where each widget sat.
struct TopologyArchiveEntry: Codable, Equatable, Sendable {
    var signature: String
    var displays: [TopologyDisplay]
    var placements: [String: TopologyWidgetPlacement]
    var updatedAt: Date
}

/// Bounded, most-recent-first archive of arrangements keyed by canonical signature.
struct TopologyLayoutArchive: Codable, Equatable, Sendable {
    var entries: [TopologyArchiveEntry]

    init(entries: [TopologyArchiveEntry] = []) {
        self.entries = entries
    }

    func entry(forSignature signature: String) -> TopologyArchiveEntry? {
        entries.first { $0.signature == signature }
    }

    /// Stores `entry` at the front, replacing the same signature, and drops the oldest beyond `limit`.
    func recording(_ entry: TopologyArchiveEntry, limit: Int = DesktopTopologyConfig.archiveEntryLimit) -> TopologyLayoutArchive {
        var next = entries.filter { $0.signature != entry.signature }
        next.insert(entry, at: 0)
        if limit > 0, next.count > limit {
            next.removeLast(next.count - limit)
        }
        return TopologyLayoutArchive(entries: next)
    }
}

/// Pure similarity scoring used to choose a relocation target and a first-seen seed.
enum DisplayTopologySimilarity {
    /// Jaccard overlap of two canonical signatures (0...1).
    static func signatureSimilarity(_ a: String, _ b: String) -> Double {
        let left = Set(DisplayTopologySignature.uuids(in: a))
        let right = Set(DisplayTopologySignature.uuids(in: b))
        guard !left.isEmpty || !right.isEmpty else { return 1 }
        let union = left.union(right).count
        guard union > 0 else { return 1 }
        return Double(left.intersection(right).count) / Double(union)
    }

    /// Geometry similarity: size dominates, aspect ratio breaks ties (0...1).
    static func displaySimilarity(_ a: TopologyDisplay, _ b: TopologyDisplay) -> Double {
        let aScreen = a.screenFrame
        let bScreen = b.screenFrame
        let aArea = aScreen.area
        let bArea = bScreen.area
        guard aArea > 0, bArea > 0 else { return 0 }
        let areaRatio = min(aArea, bArea) / max(aArea, bArea)

        let aAspect = aScreen.height > 0 ? aScreen.width / aScreen.height : 1
        let bAspect = bScreen.height > 0 ? bScreen.width / bScreen.height : 1
        let aspectRatio = min(aAspect, bAspect) / max(aAspect, bAspect)
        return 0.7 * Double(areaRatio) + 0.3 * Double(aspectRatio)
    }

    /// The connected display that most resembles `previous` (nil only when `candidates` is empty).
    static func mostSimilarDisplay(
        to previous: TopologyDisplay,
        among candidates: [TopologyDisplay]
    ) -> TopologyDisplay? {
        candidates.max { lhs, rhs in
            displaySimilarity(lhs, previous) < displaySimilarity(rhs, previous)
        }
    }

    /// How well an archived arrangement matches the connected displays right now (0...1).
    static func entryScore(_ entry: TopologyArchiveEntry, current: [TopologyDisplay]) -> Double {
        guard !current.isEmpty else { return 0 }
        let currentSignature = DisplayTopologySignature.make(current.map(\.uuid))
        let signatureScore = signatureSimilarity(entry.signature, currentSignature)
        let overlap = Double(current.filter { display in
            entry.displays.contains { $0.uuid == display.uuid }
        }.count) / Double(current.count)

        var geometryTotal = 0.0
        for display in current {
            if let match = entry.displays.first(where: { $0.uuid == display.uuid }) ?? mostSimilarDisplay(to: display, among: entry.displays) {
                geometryTotal += displaySimilarity(display, match)
            }
        }
        let geometry = geometryTotal / Double(current.count)
        return 0.5 * overlap + 0.2 * signatureScore + 0.3 * geometry
    }

    /// Best archived arrangement for the current displays, ignoring empty archives.
    static func bestEntry(in archive: TopologyLayoutArchive, for current: [TopologyDisplay]) -> TopologyArchiveEntry? {
        archive.entries.max { lhs, rhs in
            entryScore(lhs, current: current) < entryScore(rhs, current: current)
        }
    }
}
