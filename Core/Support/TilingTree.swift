import CoreGraphics
import Foundation

/// Split orientation for a binary space partitioning tree node (Phase 26b).
enum TilingSplitAxis: String, Codable, Sendable {
    /// Horizontal split: divides width into left and right sub-regions.
    case horizontal
    /// Vertical split: divides height into top and bottom sub-regions.
    case vertical
}

/// Recursive binary space partitioning node representing either a window leaf or a split region.
enum TilingTreeNode: Equatable, Sendable {
    case leaf(WindowID)
    indirect case split(axis: TilingSplitAxis, ratio: CGFloat, first: TilingTreeNode, second: TilingTreeNode)

    /// All window identifiers contained within this subtree, in traversal order.
    var windowIDs: [WindowID] {
        switch self {
        case .leaf(let id):
            return [id]
        case .split(_, _, let first, let second):
            return first.windowIDs + second.windowIDs
        }
    }

    /// Whether this subtree contains the given window identifier.
    func contains(_ id: WindowID) -> Bool {
        switch self {
        case .leaf(let leafID):
            return leafID == id
        case .split(_, _, let first, let second):
            return first.contains(id) || second.contains(id)
        }
    }
}

/// A pure Binary Space Partitioning (BSP) tree managing window layout per display (Phase 26b).
struct TilingTree: Equatable, Sendable {
    /// The root node of the BSP tree, or `nil` if no windows are managed.
    private(set) var root: TilingTreeNode?
    /// The currently focused window ID in this tree, if any.
    private(set) var focusedID: WindowID?

    init(root: TilingTreeNode? = nil, focusedID: WindowID? = nil) {
        self.root = root
        self.focusedID = focusedID
    }

    /// Total count of managed windows.
    var count: Int {
        root?.windowIDs.count ?? 0
    }

    /// Whether the tree has no managed windows.
    var isEmpty: Bool {
        root == nil
    }

    /// All managed window identifiers in tree traversal order.
    var allWindowIDs: [WindowID] {
        root?.windowIDs ?? []
    }

    /// Whether the specified window is managed in this tree.
    func contains(_ id: WindowID) -> Bool {
        root?.contains(id) ?? false
    }

    // MARK: - Mutation

    /// Focus a managed window.
    mutating func focus(_ id: WindowID) {
        guard contains(id) else { return }
        focusedID = id
    }

    /// Insert a window into the tree.
    /// If the tree is empty, becomes the root leaf.
    /// Otherwise, splits the focused window's region. Split direction alternates by tree depth:
    /// even depth splits horizontally, odd depth splits vertically.
    mutating func insert(_ id: WindowID) {
        // If already present, focus it and do nothing.
        if contains(id) {
            focusedID = id
            return
        }

        guard let currentRoot = root else {
            root = .leaf(id)
            focusedID = id
            return
        }

        let targetID = (focusedID.flatMap { contains($0) ? $0 : nil }) ?? currentRoot.windowIDs.first!
        let (newRoot, _) = insert(newID: id, atTarget: targetID, in: currentRoot, currentDepth: 0)
        root = newRoot
        focusedID = id
    }

    private func insert(
        newID: WindowID,
        atTarget targetID: WindowID,
        in node: TilingTreeNode,
        currentDepth: Int
    ) -> (TilingTreeNode, Bool) {
        switch node {
        case .leaf(let leafID):
            if leafID == targetID {
                let axis: TilingSplitAxis = (currentDepth % 2 == 0) ? .horizontal : .vertical
                let splitNode = TilingTreeNode.split(
                    axis: axis,
                    ratio: 0.5,
                    first: .leaf(leafID),
                    second: .leaf(newID)
                )
                return (splitNode, true)
            }
            return (node, false)

        case .split(let axis, let ratio, let first, let second):
            let (newFirst, foundInFirst) = insert(
                newID: newID,
                atTarget: targetID,
                in: first,
                currentDepth: currentDepth + 1
            )
            if foundInFirst {
                return (.split(axis: axis, ratio: ratio, first: newFirst, second: second), true)
            }
            let (newSecond, foundInSecond) = insert(
                newID: newID,
                atTarget: targetID,
                in: second,
                currentDepth: currentDepth + 1
            )
            return (.split(axis: axis, ratio: ratio, first: first, second: newSecond), foundInSecond)
        }
    }

    /// Remove a window from the tree. Its sibling expands to fill the parent split region.
    @discardableResult
    mutating func remove(_ id: WindowID) -> Bool {
        guard contains(id) else { return false }

        guard let currentRoot = root else { return false }
        if case .leaf(let rootID) = currentRoot, rootID == id {
            root = nil
            focusedID = nil
            return true
        }

        let updatedRoot = remove(id: id, from: currentRoot)
        root = updatedRoot

        if focusedID == id {
            focusedID = updatedRoot?.windowIDs.first
        }
        return true
    }

    private func remove(id: WindowID, from node: TilingTreeNode) -> TilingTreeNode? {
        switch node {
        case .leaf(let leafID):
            return leafID == id ? nil : node

        case .split(let axis, let ratio, let first, let second):
            // Check if immediate children are the target leaf
            if case .leaf(let firstID) = first, firstID == id {
                return second
            }
            if case .leaf(let secondID) = second, secondID == id {
                return first
            }

            // Recurse into children
            let newFirst = remove(id: id, from: first)
            let newSecond = remove(id: id, from: second)

            if newFirst == nil {
                return newSecond
            }
            if newSecond == nil {
                return newFirst
            }
            return .split(axis: axis, ratio: ratio, first: newFirst!, second: newSecond!)
        }
    }

    /// Swaps the positions of two windows in the tree.
    mutating func swap(_ a: WindowID, with b: WindowID) {
        guard a != b, contains(a), contains(b), let currentRoot = root else { return }
        root = swap(a: a, with: b, in: currentRoot)
    }

    private func swap(a: WindowID, with b: WindowID, in node: TilingTreeNode) -> TilingTreeNode {
        switch node {
        case .leaf(let leafID):
            if leafID == a { return .leaf(b) }
            if leafID == b { return .leaf(a) }
            return node
        case .split(let axis, let ratio, let first, let second):
            return .split(
                axis: axis,
                ratio: ratio,
                first: swap(a: a, with: b, in: first),
                second: swap(a: a, with: b, in: second)
            )
        }
    }

    // MARK: - Focus & Swap Navigation

    /// Advance focus to the next window in traversal order.
    mutating func focusNext() {
        let windows = allWindowIDs
        guard windows.count > 1, let current = focusedID, let idx = windows.firstIndex(of: current) else { return }
        let nextIdx = (idx + 1) % windows.count
        focusedID = windows[nextIdx]
    }

    /// Move focus to the previous window in traversal order.
    mutating func focusPrevious() {
        let windows = allWindowIDs
        guard windows.count > 1, let current = focusedID, let idx = windows.firstIndex(of: current) else { return }
        let prevIdx = (idx - 1 + windows.count) % windows.count
        focusedID = windows[prevIdx]
    }

    /// Swap the focused window with the next window in traversal order.
    mutating func swapWithNext() {
        let windows = allWindowIDs
        guard windows.count > 1, let current = focusedID, let idx = windows.firstIndex(of: current) else { return }
        let nextIdx = (idx + 1) % windows.count
        swap(current, with: windows[nextIdx])
    }

    /// Swap the focused window with the previous window in traversal order.
    mutating func swapWithPrevious() {
        let windows = allWindowIDs
        guard windows.count > 1, let current = focusedID, let idx = windows.firstIndex(of: current) else { return }
        let prevIdx = (idx - 1 + windows.count) % windows.count
        swap(current, with: windows[prevIdx])
    }

    // MARK: - Tile Layout Geometry

    /// Resolves exact geometry frames for all managed windows within `workArea`, applying `gaps`.
    /// Cocoa coordinates (bottom-left origin).
    func resolveTiles(in workArea: CGRect, gaps: TilingGaps = .default) -> [WindowID: CGRect] {
        guard let currentRoot = root else { return [:] }

        // Apply outer gaps inset around work area perimeter
        let outer = gaps.outer
        let contentArea = CGRect(
            x: workArea.minX + outer,
            y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer),
            height: max(0, workArea.height - 2 * outer)
        )

        var result: [WindowID: CGRect] = [:]
        resolve(node: currentRoot, in: contentArea, gaps: gaps, result: &result)
        return result
    }

    private func resolve(
        node: TilingTreeNode,
        in rect: CGRect,
        gaps: TilingGaps,
        result: inout [WindowID: CGRect]
    ) {
        switch node {
        case .leaf(let id):
            let pixelAligned = CGRect(
                x: rect.minX.rounded(),
                y: rect.minY.rounded(),
                width: max(1, rect.width.rounded()),
                height: max(1, rect.height.rounded())
            )
            result[id] = pixelAligned

        case .split(let axis, let ratio, let first, let second):
            let clampedRatio = max(0.1, min(0.9, ratio))
            let inner = gaps.inner

            switch axis {
            case .horizontal:
                // Left and right division
                let availableWidth = max(0, rect.width - inner)
                let firstWidth = (availableWidth * clampedRatio).rounded()
                let secondWidth = max(0, availableWidth - firstWidth)

                let firstRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: firstWidth,
                    height: rect.height
                )
                let secondRect = CGRect(
                    x: rect.minX + firstWidth + inner,
                    y: rect.minY,
                    width: secondWidth,
                    height: rect.height
                )

                resolve(node: first, in: firstRect, gaps: gaps, result: &result)
                resolve(node: second, in: secondRect, gaps: gaps, result: &result)

            case .vertical:
                // Top and bottom division: first is top, second is bottom (Cocoa bottom-left origin)
                let availableHeight = max(0, rect.height - inner)
                let firstHeight = (availableHeight * clampedRatio).rounded()
                let secondHeight = max(0, availableHeight - firstHeight)

                let secondRect = CGRect(
                    x: rect.minX,
                    y: rect.minY,
                    width: rect.width,
                    height: secondHeight
                )
                let firstRect = CGRect(
                    x: rect.minX,
                    y: rect.minY + secondHeight + inner,
                    width: rect.width,
                    height: firstHeight
                )

                resolve(node: first, in: firstRect, gaps: gaps, result: &result)
                resolve(node: second, in: secondRect, gaps: gaps, result: &result)
            }
        }
    }
}
