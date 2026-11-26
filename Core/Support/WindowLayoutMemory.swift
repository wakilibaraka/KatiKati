import CoreGraphics
import Foundation

/// Phase 20c — remembers where windows sat for each display topology so the layout can be put back after the
/// displays return (sleep/wake, unplug/replug). Pure; the controller feeds it snapshots and applies the moves.
/// Inspired by DeskBar's sleep-layout idea, reimplemented from the behaviour.
///
/// MD-4: every window also remembers its frame as fractions of its display's visible area, keyed by
/// EDID UUID. When a display comes back at a different size (a different external, or a resolution
/// change) the absolute frame would be clamped onto the wrong part of the screen; the fractions keep
/// the window where it was relative to that display. A display that returns unchanged restores the
/// absolute frame, exactly as before.
struct WindowLayoutMemory: Equatable, Codable, Sendable {
    struct Window: Equatable, Codable, Sendable {
        let pid: Int32
        let cgWindowID: UInt32
        let frame: CGRect
        /// Display the window was on, when it could be attributed.
        var displayUUID: String? = nil
        /// Frame fractions on that display's visible area (MD-4).
        var relative: RelativeFrame? = nil
        var key: String { "\(pid):\(cgWindowID)" }
    }

    /// Origin and size as fractions of a display's visible area, plus the area it was measured in so a
    /// later restore can tell whether the display changed size at all.
    struct RelativeFrame: Equatable, Codable, Sendable {
        let displayUUID: String
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        let visibleWidth: CGFloat
        let visibleHeight: CGFloat
    }

    struct Move: Equatable, Codable, Sendable {
        let pid: Int32
        let cgWindowID: UInt32
        let frame: CGRect
    }

    /// A connected display as the restore path sees it. `visibleFrame` must be in the same coordinate
    /// space as the recorded window frames.
    struct Display: Equatable, Codable, Sendable {
        let uuid: String
        let visibleFrame: CGRect
    }

    /// Persisted filename inside Application Support/KatiKati and settings backups.
    static let fileName = "window-layouts.json"
    /// Frame differences at or below this many points are not worth moving a window for.
    static let tolerance: CGFloat = 8
    /// Topologies remembered at once (oldest dropped); a laptop with two docks is already three.
    static let topologyLimit = 6
    /// Smallest window worth remembering or restoring.
    static let minimumSize: CGFloat = 40

    private(set) var layouts: [String: [String: Window]] = [:]
    private var recency: [String] = []

    /// One stable key for a set of connected displays.
    static func topologyKey(displayUUIDs: [String]) -> String {
        displayUUIDs.sorted().joined(separator: "|")
    }

    /// Replaces the remembered layout of `topology` with the windows currently placed. Windows that vanished
    /// are forgotten, so a closed window is never resurrected.
    mutating func record(topology: String, windows: [Window], displays: [Display] = []) {
        guard !topology.isEmpty, !windows.isEmpty else { return }
        let enriched = windows.map { Self.addingRelativeFrame(to: $0, displays: displays) }
        layouts[topology] = Dictionary(enriched.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        recency.removeAll { $0 == topology }
        recency.append(topology)
        while recency.count > Self.topologyLimit {
            layouts[recency.removeFirst()] = nil
        }
    }

    /// Moves that put windows back where `topology` remembers them. Windows with no memory are left alone.
    func plan(topology: String, current: [Window], displays: [Display] = []) -> [Move] {
        guard let saved = layouts[topology] else { return [] }
        return current.compactMap { window in
            guard let old = saved[window.key] else { return nil }
            let target = Self.restoredFrame(for: old, displays: displays) ?? old.frame
            guard !Self.isClose(target, window.frame) else { return nil }
            return Move(pid: window.pid, cgWindowID: window.cgWindowID, frame: target)
        }
    }

    /// The frame a remembered window should take today: its fractions when its display changed size,
    /// otherwise nil so the absolute frame is used.
    static func restoredFrame(for window: Window, displays: [Display]) -> CGRect? {
        guard let relative = window.relative,
              let display = displays.first(where: { $0.uuid == relative.displayUUID }),
              display.visibleFrame.width > 0, display.visibleFrame.height > 0 else { return nil }
        let area = display.visibleFrame
        // Same-size display: the absolute frame is already right (and avoids rounding drift).
        guard abs(area.width - relative.visibleWidth) > tolerance
            || abs(area.height - relative.visibleHeight) > tolerance else { return nil }
        let width = min(area.width, max(minimumSize, (relative.width * area.width).rounded()))
        let height = min(area.height, max(minimumSize, (relative.height * area.height).rounded()))
        let x = area.minX + (relative.x * area.width).rounded()
        let y = area.minY + (relative.y * area.height).rounded()
        return CGRect(x: min(max(x, area.minX), area.maxX - width),
                      y: min(max(y, area.minY), area.maxY - height),
                      width: width, height: height)
    }

    /// Attaches the display UUID and the visible-area fractions to a window frame.
    static func addingRelativeFrame(to window: Window, displays: [Display]) -> Window {
        guard let display = display(containing: window.frame, in: displays) else { return window }
        let area = display.visibleFrame
        guard area.width > 0, area.height > 0 else { return window }
        var copy = window
        copy.displayUUID = display.uuid
        copy.relative = RelativeFrame(
            displayUUID: display.uuid,
            x: (window.frame.minX - area.minX) / area.width,
            y: (window.frame.minY - area.minY) / area.height,
            width: window.frame.width / area.width,
            height: window.frame.height / area.height,
            visibleWidth: area.width,
            visibleHeight: area.height
        )
        return copy
    }

    /// The display a frame sits on: the one it overlaps most (a window straddling a seam belongs to
    /// the display that shows most of it).
    static func display(containing frame: CGRect, in displays: [Display]) -> Display? {
        var best: (display: Display, area: CGFloat)?
        for display in displays {
            let overlap = display.visibleFrame.intersection(frame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (display, area) }
        }
        return best?.display ?? displays.first { $0.visibleFrame.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }

    static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
