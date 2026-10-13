import CoreGraphics
import Foundation

/// Phase 20c — remembers where windows sat for each display topology so the layout can be put back after the
/// displays return (sleep/wake, unplug/replug). Pure; the controller feeds it snapshots and applies the moves.
/// Inspired by DeskBar's sleep-layout idea, reimplemented from the behaviour.
struct WindowLayoutMemory: Equatable {
    struct Window: Equatable {
        let pid: Int32
        let cgWindowID: UInt32
        let frame: CGRect
        var key: String { "\(pid):\(cgWindowID)" }
    }

    struct Move: Equatable {
        let pid: Int32
        let cgWindowID: UInt32
        let frame: CGRect
    }

    /// Frame differences at or below this many points are not worth moving a window for.
    static let tolerance: CGFloat = 8
    /// Topologies remembered at once (oldest dropped); a laptop with two docks is already three.
    static let topologyLimit = 6

    private(set) var layouts: [String: [String: Window]] = [:]
    private var recency: [String] = []

    /// One stable key for a set of connected displays.
    static func topologyKey(displayUUIDs: [String]) -> String {
        displayUUIDs.sorted().joined(separator: "|")
    }

    /// Replaces the remembered layout of `topology` with the windows currently placed. Windows that vanished
    /// are forgotten, so a closed window is never resurrected.
    mutating func record(topology: String, windows: [Window]) {
        guard !topology.isEmpty, !windows.isEmpty else { return }
        layouts[topology] = Dictionary(windows.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        recency.removeAll { $0 == topology }
        recency.append(topology)
        while recency.count > Self.topologyLimit {
            layouts[recency.removeFirst()] = nil
        }
    }

    /// Moves that put windows back where `topology` remembers them. Windows with no memory are left alone.
    func plan(topology: String, current: [Window]) -> [Move] {
        guard let saved = layouts[topology] else { return [] }
        return current.compactMap { window in
            guard let old = saved[window.key], !Self.isClose(old.frame, window.frame) else { return nil }
            return Move(pid: window.pid, cgWindowID: window.cgWindowID, frame: old.frame)
        }
    }

    static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
