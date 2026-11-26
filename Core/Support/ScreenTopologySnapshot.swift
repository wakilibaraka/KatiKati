import Foundation

/// One ordered reading of the connected displays. Every consumer in a topology
/// transition uses this value so a transient UUID failure cannot split decisions.
struct ScreenTopologySnapshot: Equatable {
    let physicalDisplayCount: Int
    let identifiedDisplayUUIDs: [String]
    let attributionTable: WindowDisplayAttribution.Table
}

/// One side of a display's frame. Used to tell a true screen edge (nothing beyond it) from a seam
/// (another display is flush against it).
enum ScreenEdge: String, CaseIterable, Hashable, Sendable {
    case left, right, top, bottom
}

/// MD-2: which edges of each display are *outer* (the pointer leaves all displays there) and which
/// are *seams* (a neighbour touches them). Pure geometry over Cocoa frames, so Core stays AppKit-free.
///
/// Two displays share an edge when their frames touch on that axis within `tolerance` and overlap by
/// more than zero points on the other axis. On a stacked desk the external's `.bottom` is a seam and
/// the built-in's `.top` is a seam; two side-by-side displays seam `.right` / `.left`. A display the
/// topology does not know about keeps every edge outer, so a single-display desk is unchanged.
struct ScreenEdgeTopology: Equatable, Sendable {
    static let defaultTolerance: CGFloat = 2

    /// Display UUID → edges with no neighbour beyond them.
    let outer: [String: Set<ScreenEdge>]
    /// Display UUID → edges another display touches.
    let seam: [String: Set<ScreenEdge>]

    static let empty = ScreenEdgeTopology(outer: [:], seam: [:])

    static func resolve(displays: [TopologyDisplay], tolerance: CGFloat = defaultTolerance) -> ScreenEdgeTopology {
        let frames = displays.map { (uuid: $0.uuid, rect: $0.screenFrame.cgRect) }
        var seams: [String: Set<ScreenEdge>] = [:]
        func mark(_ a: String, _ aEdge: ScreenEdge, _ b: String, _ bEdge: ScreenEdge) {
            seams[a, default: []].insert(aEdge)
            seams[b, default: []].insert(bEdge)
        }
        for i in frames.indices {
            for j in frames.indices where j > i {
                let (uuidA, a) = frames[i]
                let (uuidB, b) = frames[j]
                guard uuidA != uuidB else { continue }
                if min(a.maxY, b.maxY) - max(a.minY, b.minY) > 0 {
                    if abs(b.minX - a.maxX) <= tolerance { mark(uuidA, .right, uuidB, .left) }
                    if abs(a.minX - b.maxX) <= tolerance { mark(uuidA, .left, uuidB, .right) }
                }
                if min(a.maxX, b.maxX) - max(a.minX, b.minX) > 0 {
                    if abs(b.minY - a.maxY) <= tolerance { mark(uuidA, .top, uuidB, .bottom) }
                    if abs(a.minY - b.maxY) <= tolerance { mark(uuidA, .bottom, uuidB, .top) }
                }
            }
        }
        var outer: [String: Set<ScreenEdge>] = [:]
        for frame in frames {
            outer[frame.uuid] = Set(ScreenEdge.allCases).subtracting(seams[frame.uuid] ?? [])
        }
        return ScreenEdgeTopology(outer: outer, seam: seams)
    }

    func seamEdges(for displayUUID: String) -> Set<ScreenEdge> {
        seam[displayUUID] ?? []
    }

    /// Edges with nothing beyond them. An unknown display is all outer — never widen a suppression
    /// because a lookup failed.
    func outerEdges(for displayUUID: String) -> Set<ScreenEdge> {
        if let known = outer[displayUUID] { return known }
        return Set(ScreenEdge.allCases).subtracting(seam[displayUUID] ?? [])
    }

    func isOuter(_ edge: ScreenEdge, on displayUUID: String) -> Bool {
        outerEdges(for: displayUUID).contains(edge)
    }

    /// Displays whose `edge` is topology-outer, in the order given.
    func hosts(for edge: ScreenEdge, among displayUUIDs: [String]) -> [String] {
        displayUUIDs.filter { isOuter(edge, on: $0) }
    }
}
