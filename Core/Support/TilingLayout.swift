import CoreGraphics
import Foundation

/// Available auto-tiling layout presets (Phase 26b).
enum TilingLayoutPreset: String, CaseIterable, Sendable, Codable {
    /// Binary Space Partitioning: recursive alternating splits.
    case bsp
    /// Master-Stack: primary window on the left, stack on the right.
    case mainStack
    /// Monocle: every window occupies the full work area.
    case monocle
    /// Grid: windows fill rows of near-equal cells.
    case grid
    /// Spiral (dwindle): each window takes half of the space left, alternating direction.
    case spiral
    /// Columns: equal-width full-height slices.
    case columns
    /// Rows: equal-height full-width slices.
    case rows
    /// Centered Main: primary window in the middle, the rest split to either side.
    case centeredMain
    /// Ribbon: a horizontal strip of columns that scrolls to keep the focused one in view.
    case ribbon

    /// Short badge + spelled-out name + the same shape in window managers people arrive from.
    var alias: TilingLayoutAlias {
        switch self {
        case .bsp:
            return TilingLayoutAlias(abbreviation: "BSP", fullName: "Binary Space Partitioning",
                                     aeroSpaceName: "tiles (nested)", amethystName: "Binary Space Partitioning")
        case .mainStack:
            return TilingLayoutAlias(abbreviation: "M+S", fullName: "Main + Stack (Master–Stack)",
                                     aeroSpaceName: nil, amethystName: "Tall / Tall-Right")
        case .monocle:
            return TilingLayoutAlias(abbreviation: "MONO", fullName: "Monocle (Accordion)",
                                     aeroSpaceName: "accordion", amethystName: "Fullscreen")
        case .grid:
            return TilingLayoutAlias(abbreviation: "GRID", fullName: "Grid",
                                     aeroSpaceName: "tiles (grid)", amethystName: "4-Pane / 3-Pane")
        case .spiral:
            return TilingLayoutAlias(abbreviation: "SPIR", fullName: "Spiral (Dwindle)",
                                     aeroSpaceName: nil, amethystName: nil)
        case .columns:
            return TilingLayoutAlias(abbreviation: "COLS", fullName: "Columns",
                                     aeroSpaceName: "h_tiles", amethystName: "Column")
        case .rows:
            return TilingLayoutAlias(abbreviation: "ROWS", fullName: "Rows",
                                     aeroSpaceName: "v_tiles", amethystName: "Row")
        case .centeredMain:
            return TilingLayoutAlias(abbreviation: "CTM", fullName: "Centered Main (Centered Master)",
                                     aeroSpaceName: nil, amethystName: nil)
        case .ribbon:
            return TilingLayoutAlias(abbreviation: "RIB", fullName: "Ribbon (Scrolling Strip)",
                                     aeroSpaceName: nil, amethystName: nil)
        }
    }

    /// "BSP · Binary Space Partitioning" — the badge and the name spelled out together.
    var describedName: String { "\(alias.abbreviation) · \(alias.fullName)" }

    /// The same shape elsewhere, for people switching from AeroSpace or Amethyst. Nil when those
    /// apps have no equivalent.
    var standardNames: String? {
        var parts: [String] = []
        if let aeroSpace = alias.aeroSpaceName { parts.append("AeroSpace \(aeroSpace)") }
        if let amethyst = alias.amethystName { parts.append("Amethyst \(amethyst)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var localizedTitleKey: String {
        switch self {
        case .bsp: return "BSP"
        case .mainStack: return "Main + Stack"
        case .monocle: return "Monocle"
        case .grid: return "Grid"
        case .spiral: return "Spiral"
        case .columns: return "Columns"
        case .rows: return "Rows"
        case .centeredMain: return "Centered Main"
        case .ribbon: return "Ribbon"
        }
    }
}

/// One layout's name in the terms other tiling window managers use. Kept in Core so the Settings
/// picker, the flyout and the docs describe the same shape with the same words.
struct TilingLayoutAlias: Equatable, Sendable {
    /// Two-to-four letter badge printed on the picker tile.
    let abbreviation: String
    /// The name spelled out, e.g. "Binary Space Partitioning".
    let fullName: String
    /// AeroSpace's command name for the same shape, when it has one.
    let aeroSpaceName: String?
    /// Amethyst's layout name for the same shape, when it has one.
    let amethystName: String?
}

/// User tuning for layouts with a main window (Main + Stack, Centered Main).
struct TilingLayoutOptions: Equatable, Sendable {
    /// Share of the work area given to the main window, clamped to `ratioRange`.
    var mainRatio: CGFloat = 0.55
    /// Puts the main window on the right instead of the left.
    var mirrored = false

    static let ratioRange: ClosedRange<CGFloat> = 0.3...0.7
}

/// Geometry solver for auto-tiling presets (Phase 26b).
enum TilingLayout {
    /// Resolves target frames for all windows in `tree` according to `preset`.
    /// Cocoa coordinates (bottom-left origin).
    static func resolve(
        tree: TilingTree,
        preset: TilingLayoutPreset,
        workArea: CGRect,
        gaps: TilingGaps = .default,
        options: TilingLayoutOptions = TilingLayoutOptions()
    ) -> [WindowID: CGRect] {
        guard !tree.isEmpty else { return [:] }

        switch preset {
        case .bsp:
            // The tree is the layout. Inserts split the shallowest leaf, so the axes follow depth
            // (side by side, then stacked, then side by side again) and four windows land in a 2×2
            // grid — where Spiral would keep nesting inside the space that is left.
            return tree.resolveTiles(in: workArea, gaps: gaps)

        case .mainStack:
            return resolveMainStack(tree: tree, workArea: workArea, gaps: gaps, options: options)

        case .monocle:
            return resolveMonocle(tree: tree, workArea: workArea, gaps: gaps)

        case .grid, .spiral, .columns, .rows, .centeredMain:
            return resolveSliced(tree: tree, preset: preset, workArea: workArea, gaps: gaps, options: options)

        case .ribbon:
            // The strip's own geometry needs its column state; without it the closest static shape
            // is a row of equal columns (the engine always passes the state, see `resolveRibbon`).
            return resolveSliced(tree: tree, preset: .columns, workArea: workArea, gaps: gaps, options: options)
        }
    }

    // MARK: - Main + Stack Preset

    private static func resolveMainStack(
        tree: TilingTree,
        workArea: CGRect,
        gaps: TilingGaps,
        options: TilingLayoutOptions
    ) -> [WindowID: CGRect] {
        let windows = tree.allWindowIDs
        guard !windows.isEmpty else { return [:] }

        let outer = gaps.outer
        let contentArea = CGRect(
            x: workArea.minX + outer,
            y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer),
            height: max(0, workArea.height - 2 * outer)
        )

        // Single window fills the content area
        if windows.count == 1 {
            return [windows[0]: pixelAligned(contentArea)]
        }

        var result: [WindowID: CGRect] = [:]
        let inner = gaps.inner
        let mainRatio = options.mainRatio.clamped(to: TilingLayoutOptions.ratioRange)

        let availableWidth = max(0, contentArea.width - inner)
        let mainWidth = (availableWidth * mainRatio).rounded()
        let stackWidth = max(0, availableWidth - mainWidth)

        // Main window (left side)
        let mainX = options.mirrored ? contentArea.maxX - mainWidth : contentArea.minX
        let mainRect = CGRect(
            x: mainX,
            y: contentArea.minY,
            width: mainWidth,
            height: contentArea.height
        )
        result[windows[0]] = pixelAligned(mainRect)

        // Stack windows (right side, divided vertically)
        let stackCount = windows.count - 1
        let totalInnerGaps = CGFloat(stackCount - 1) * inner
        let availableHeight = max(0, contentArea.height - totalInnerGaps)
        let eachHeight = (availableHeight / CGFloat(stackCount)).rounded()

        let stackX = options.mirrored ? contentArea.minX : contentArea.minX + mainWidth + inner
        var currentY = contentArea.minY

        // Traverse stack windows bottom-to-top so top window lands at maxY
        for i in (1...stackCount).reversed() {
            let winID = windows[i]
            let isLast = (i == 1) // topmost window gets any remainder
            let height = isLast ? (contentArea.maxY - currentY) : eachHeight

            let tileRect = CGRect(
                x: stackX,
                y: currentY,
                width: stackWidth,
                height: max(1, height)
            )
            result[winID] = pixelAligned(tileRect)
            currentY += height + inner
        }

        return result
    }

    // MARK: - Monocle Preset

    private static func resolveMonocle(
        tree: TilingTree,
        workArea: CGRect,
        gaps: TilingGaps
    ) -> [WindowID: CGRect] {
        let outer = gaps.outer
        let contentArea = pixelAligned(CGRect(
            x: workArea.minX + outer,
            y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer),
            height: max(0, workArea.height - 2 * outer)
        ))

        var result: [WindowID: CGRect] = [:]
        for id in tree.allWindowIDs {
            result[id] = contentArea
        }
        return result
    }

    // MARK: - Grid / Spiral / Columns / Rows / Centered Main

    private static func resolveSliced(
        tree: TilingTree,
        preset: TilingLayoutPreset,
        workArea: CGRect,
        gaps: TilingGaps,
        options: TilingLayoutOptions
    ) -> [WindowID: CGRect] {
        let windows = tree.allWindowIDs
        let outer = gaps.outer
        let inner = gaps.inner
        let area = CGRect(
            x: workArea.minX + outer, y: workArea.minY + outer,
            width: max(0, workArea.width - 2 * outer), height: max(0, workArea.height - 2 * outer)
        )
        let n = windows.count
        var frames: [CGRect] = []

        switch preset {
        case .columns:
            frames = split(area, count: n, horizontal: true, gap: inner)
        case .rows:
            frames = split(area, count: n, horizontal: false, gap: inner)
        case .grid:
            let cols = Int(ceil(Double(n).squareRoot()))
            let rowCount = Int(ceil(Double(n) / Double(cols)))
            for (r, row) in split(area, count: rowCount, horizontal: false, gap: inner).enumerated() {
                frames += split(row, count: min(cols, n - r * cols), horizontal: true, gap: inner)
            }
        case .spiral:
            // Dwindle: every window takes half of the space that is left, so each split nests inside
            // the previous remainder and the tiles wind around the corner instead of forming a grid.
            var rest = area
            for i in 0..<n {
                if i == n - 1 { frames.append(rest); break }
                let parts = split(rest, count: 2, horizontal: i % 2 == 0, gap: inner)
                frames.append(parts[0])
                rest = parts[1]
            }
        case .centeredMain:
            if n <= 2 {
                frames = split(area, count: n, horizontal: true, gap: inner)
                break
            }
            // Main in the middle (half the width); others alternate right, left.
            let ratio = options.mainRatio.clamped(to: TilingLayoutOptions.ratioRange)
            let sideW = max(0, (area.width - area.width * ratio - 2 * inner) / 2)
            let mainW = max(0, area.width - 2 * sideW - 2 * inner)
            let rightCount = n / 2, leftCount = n - 1 - rightCount
            let left = CGRect(x: area.minX, y: area.minY, width: sideW, height: area.height)
            let mid = CGRect(x: left.maxX + inner, y: area.minY, width: mainW, height: area.height)
            let right = CGRect(x: mid.maxX + inner, y: area.minY, width: sideW, height: area.height)
            let rights = split(right, count: rightCount, horizontal: false, gap: inner)
            let lefts = split(left, count: leftCount, horizontal: false, gap: inner)
            frames = [mid]
            for i in 0..<(n - 1) { frames.append((i % 2 == 0) != options.mirrored ? rights[i / 2] : lefts[i / 2]) }
        default:
            break
        }

        var result: [WindowID: CGRect] = [:]
        for (id, frame) in zip(windows, frames) { result[id] = pixelAligned(frame) }
        return result
    }

    /// Splits `rect` into `count` equal slices: left→right, or top→bottom (Cocoa: top has the highest y).
    private static func split(_ rect: CGRect, count: Int, horizontal: Bool, gap: CGFloat) -> [CGRect] {
        guard count > 0 else { return [] }
        let total = horizontal ? rect.width : rect.height
        let each = max(0, total - gap * CGFloat(count - 1)) / CGFloat(count)
        return (0..<count).map { i in
            let offset = CGFloat(i) * (each + gap)
            return horizontal
                ? CGRect(x: rect.minX + offset, y: rect.minY, width: each, height: rect.height)
                : CGRect(x: rect.minX, y: rect.maxY - offset - each, width: rect.width, height: each)
        }
    }

    private static func pixelAligned(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX.rounded(),
            y: rect.minY.rounded(),
            width: max(1, rect.width.rounded()),
            height: max(1, rect.height.rounded())
        )
    }
}

/// Which windows have to stay floating so every tile remains usable (Phase 26b overflow rule).
enum TilingOverflow {
    /// The newest windows that must leave `ids` for the rest to fit, newest first. Never empties the
    /// set: one window alone keeps its frame whatever the area.
    static func evictions(
        ids: [WindowID],
        preset: TilingLayoutPreset,
        workArea: CGRect,
        gaps: TilingGaps,
        options: TilingLayoutOptions = TilingLayoutOptions()
    ) -> [WindowID] {
        guard ids.count > 1 else { return [] }
        var tree = TilingTree()
        for id in ids { tree.insert(id) }
        var evicted: [WindowID] = []
        while tree.count > 1 {
            let frames = TilingLayout.resolve(tree: tree, preset: preset, workArea: workArea, gaps: gaps, options: options)
            guard !WindowFit.allUsable(Array(frames.values)) else { break }
            guard let newest = tree.allWindowIDs.last else { break }
            tree.remove(newest)
            evicted.append(newest)
        }
        return evicted
    }
}

// MARK: - Ribbon (RT-1)

/// Width of one ribbon column, as a share of the display's work area. Cycling walks the cases in
/// order, so ⌃⌥⇧R steps ¼ → ⅓ → ½ → ⅔ → Full → ¼.
enum ColumnWidthPreset: String, CaseIterable, Sendable, Codable {
    case quarter, third, half, twoThirds, full

    var fraction: CGFloat {
        switch self {
        case .quarter: return 0.25
        case .third: return 1.0 / 3.0
        case .half: return 0.5
        case .twoThirds: return 2.0 / 3.0
        case .full: return 1
        }
    }

    var next: ColumnWidthPreset {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self) else { return .half }
        return all[(i + 1) % all.count]
    }

    /// Compact glyph for the width pickers (¼, ⅓, ½, ⅔, 1). Deliberately language-neutral: the
    /// fraction *is* the label, so no locale should have to invent a word for "two thirds".
    var glyph: String {
        switch self {
        case .quarter: return "¼"
        case .third: return "⅓"
        case .half: return "½"
        case .twoThirds: return "⅔"
        case .full: return "1"
        }
    }
}

/// One column of the scrolling strip. A tabbed column holds several windows and shows its active
/// one; a plain column holds exactly one.
struct StripColumn: Equatable, Sendable {
    var windowIDs: [WindowID]
    var activeIndex: Int
    var width: ColumnWidthPreset

    init(_ id: WindowID, width: ColumnWidthPreset = .half) {
        windowIDs = [id]
        activeIndex = 0
        self.width = width
    }

    init(windowIDs: [WindowID], activeIndex: Int = 0, width: ColumnWidthPreset = .half) {
        self.windowIDs = windowIDs
        self.activeIndex = windowIDs.isEmpty ? 0 : min(max(0, activeIndex), windowIDs.count - 1)
        self.width = width
    }

    var activeID: WindowID? {
        guard !windowIDs.isEmpty else { return nil }
        return windowIDs[min(activeIndex, windowIDs.count - 1)]
    }

    var isTabbed: Bool { windowIDs.count > 1 }
}

/// One screen's ribbon geometry: the columns laid left→right, the camera that shows the focused
/// column, and the windows that ended up outside the viewport.
struct RibbonFrames: Equatable, Sendable {
    var frames: [WindowID: CGRect]
    var camera: CGFloat
    var contentWidth: CGFloat
    /// Windows fully outside the viewport, with the edge they should park against.
    var parked: [WindowID: StripParking.Side]

    static let empty = RibbonFrames(frames: [:], camera: 0, contentWidth: 0, parked: [:])
}

/// Per-display ribbon state: an ordered list of columns and the focused column (RT-1). Order is the
/// strip's left→right order; a new window joins to the right of focus, closing removes the column
/// and closes the gap.
struct ScrollingStripState: Equatable, Sendable {
    private(set) var columns: [StripColumn]
    private(set) var focusedIndex: Int
    /// Width new columns are born with; cycling a column also remembers its width here.
    private(set) var width: ColumnWidthPreset

    init(windowIDs: [WindowID] = [], width: ColumnWidthPreset = .half) {
        self.width = width
        columns = windowIDs.map { StripColumn($0, width: width) }
        focusedIndex = 0
    }

    var windowIDs: [WindowID] { columns.flatMap(\.windowIDs) }

    var focusedColumn: StripColumn? {
        columns.indices.contains(focusedIndex) ? columns[focusedIndex] : nil
    }

    var focusedID: WindowID? { focusedColumn?.activeID }

    /// Adds windows the tree gained and drops ones it lost, keeping the strip's own order.
    mutating func sync(with ids: [WindowID]) {
        let live = Set(ids)
        columns = columns.compactMap { column in
            var c = column
            c.windowIDs = c.windowIDs.filter { live.contains($0) }
            guard !c.windowIDs.isEmpty else { return nil }
            c.activeIndex = min(c.activeIndex, c.windowIDs.count - 1)
            return c
        }
        let known = Set(windowIDs)
        for id in ids where !known.contains(id) { insert(id) }
        focusedIndex = columns.isEmpty ? 0 : min(focusedIndex, columns.count - 1)
        if let focused = focusedID, !ids.contains(focused), let first = columns.first?.activeID {
            focus(first)
        }
    }

    mutating func insert(_ id: WindowID) {
        guard !windowIDs.contains(id) else { focus(id); return }
        let column = StripColumn(id, width: width)
        guard !columns.isEmpty else {
            columns = [column]
            focusedIndex = 0
            return
        }
        let at = min(focusedIndex + 1, columns.count)
        columns.insert(column, at: at)
        focusedIndex = at
    }

    mutating func remove(_ id: WindowID) {
        guard let index = columns.firstIndex(where: { $0.windowIDs.contains(id) }) else { return }
        columns[index].windowIDs.removeAll { $0 == id }
        if columns[index].windowIDs.isEmpty {
            columns.remove(at: index)
            if focusedIndex > index { focusedIndex -= 1 }
            focusedIndex = columns.isEmpty ? 0 : min(focusedIndex, columns.count - 1)
        } else {
            columns[index].activeIndex = min(columns[index].activeIndex, columns[index].windowIDs.count - 1)
        }
    }

    mutating func focus(_ id: WindowID) {
        guard let index = columns.firstIndex(where: { $0.windowIDs.contains(id) }) else { return }
        focusedIndex = index
        if let tab = columns[index].windowIDs.firstIndex(of: id) { columns[index].activeIndex = tab }
    }

    mutating func focusColumn(_ offset: Int) {
        guard !columns.isEmpty else { return }
        focusedIndex = min(max(0, focusedIndex + offset), columns.count - 1)
    }

    mutating func swapFocused(_ offset: Int) {
        let target = focusedIndex + offset
        guard columns.indices.contains(focusedIndex), columns.indices.contains(target) else { return }
        columns.swapAt(focusedIndex, target)
        focusedIndex = target
    }

    mutating func cycleWidth() {
        setWidth((focusedColumn?.width ?? width).next)
    }

    mutating func setWidth(_ new: ColumnWidthPreset) {
        width = new
        guard columns.indices.contains(focusedIndex) else { return }
        columns[focusedIndex].width = new
    }

    /// Merges the focused column into the one on its left as a tab. The leftmost column has
    /// nothing to merge into, so it stays put.
    mutating func stackLeft() {
        guard focusedIndex > 0, columns.indices.contains(focusedIndex) else { return }
        let column = columns.remove(at: focusedIndex)
        let left = focusedIndex - 1
        columns[left].windowIDs += column.windowIDs
        columns[left].activeIndex = columns[left].windowIDs.count - 1
        columns[left].width = column.width
        focusedIndex = left
    }

    /// Toggles tabbing on the focused column: a tabbed column splits back into single columns, a
    /// single column merges into its left neighbour when it has one.
    mutating func toggleTabs() {
        guard columns.indices.contains(focusedIndex) else { return }
        guard columns[focusedIndex].isTabbed else { stackLeft(); return }
        let ids = columns[focusedIndex].windowIDs
        let w = columns[focusedIndex].width
        columns[focusedIndex] = StripColumn(ids[0], width: w)
        for id in ids.dropFirst() {
            columns.insert(StripColumn(id, width: w), at: focusedIndex + 1)
        }
    }

    /// Steps the active window inside a tabbed column; a plain column has nowhere to step.
    mutating func focusTab(_ offset: Int) {
        guard columns.indices.contains(focusedIndex) else { return }
        let count = columns[focusedIndex].windowIDs.count
        guard count > 1 else { return }
        let next = (columns[focusedIndex].activeIndex + offset + count) % count
        columns[focusedIndex].activeIndex = next
    }
}

extension TilingLayout {
    /// Lays the columns out in content coordinates (0 = the strip's first column) and resolves the
    /// camera so the focused column is wholly visible. Every window of a tabbed column shares the
    /// column's frame; the active one is simply the last written into the strip.
    static func resolveRibbon(
        state: ScrollingStripState,
        in content: CGRect,
        gap: CGFloat,
        camera: CGFloat
    ) -> RibbonFrames {
        guard !state.columns.isEmpty, content.width > 0, content.height > 0 else { return .empty }
        let spacing = max(0, gap)

        var x: CGFloat = 0
        var rects: [CGRect] = []
        for column in state.columns {
            let width = max(1, (content.width * column.width.fraction).rounded())
            rects.append(CGRect(x: x, y: 0, width: width, height: content.height))
            x += width + spacing
        }
        let contentWidth = max(0, x - spacing)
        let focused = rects.indices.contains(state.focusedIndex) ? rects[state.focusedIndex] : rects[0]
        let offset = StripCamera.offset(
            focused: focused, viewportWidth: content.width, contentWidth: contentWidth, current: camera
        )

        var frames: [WindowID: CGRect] = [:]
        var parked: [WindowID: StripParking.Side] = [:]
        for (rect, column) in zip(rects, state.columns) {
            var frame = rect
            frame.origin.x += content.minX - offset
            frame.origin.y = content.minY
            let side: StripParking.Side? = frame.maxX <= content.minX
                ? .left
                : (frame.minX >= content.maxX ? .right : nil)
            for id in column.windowIDs {
                frames[id] = frame
                if let side { parked[id] = side }
            }
        }
        return RibbonFrames(frames: frames, camera: offset, contentWidth: contentWidth, parked: parked)
    }
}

/// Sample windows for the settings previews, produced by the same solver tiling uses, so the picture
/// cannot drift from the behaviour it describes. Monocle windows overlap by design, so they are drawn
/// as an offset stack.
enum TilingPreview {
    /// How many windows a picture draws. Four is enough for every preset but BSP, whose balanced
    /// tree is exactly a four-pane Grid at that count; five shows the depth-driven split it actually
    /// makes, so the tile is not mistaken for Grid.
    static func windowCount(for preset: TilingLayoutPreset) -> Int {
        preset == .bsp ? 5 : 4
    }

    static func rects(preset: TilingLayoutPreset, area: CGRect, gap: CGFloat) -> [CGRect] {
        if preset == .monocle {
            return (0..<3).map { i in
                CGRect(x: area.minX + CGFloat(i) * 8, y: area.minY + CGFloat(i) * 8,
                       width: area.width - 16, height: area.height - 16)
            }
        }
        var tree = TilingTree()
        let ids = (0..<windowCount(for: preset)).map { WindowID(rawValue: "preview\($0)") }
        ids.forEach { tree.insert($0) }
        let solved = TilingLayout.resolve(tree: tree, preset: preset, workArea: area,
                                          gaps: TilingGaps(inner: gap, outer: 0))
        // Solver output is bottom-left origin; SwiftUI offsets are top-left.
        return ids.compactMap { solved[$0] }.map {
            CGRect(x: $0.minX, y: area.minY + area.maxY - $0.maxY, width: $0.width, height: $0.height)
        }
    }
}

extension TilingPreview {
    /// The strip's own solver over a synthetic strip, mutated the way the gesture mutates it, so the
    /// preview shows the result a real ribbon would end up with.
    static func stripRects(for mutation: StripPreviewMutation, area: CGRect, gap: CGFloat) -> [CGRect] {
        var state = StripPreviewMutation.seededStrip()
        mutation.apply(to: &state)
        let content = CGRect(origin: .zero, size: area.size)
        let frames = TilingLayout.resolveRibbon(state: state, in: content, gap: gap, camera: 0)
        var drawn: [CGRect] = []
        for column in state.columns {
            guard let id = column.activeID, let frame = frames.frames[id] else { continue }
            // Every window of a tabbed column shares one frame; draw it once.
            guard !drawn.contains(where: { $0.equalTo(frame) }) else { continue }
            drawn.append(frame)
        }
        return drawn.map {
            CGRect(x: area.minX + $0.minX, y: area.minY + $0.minY,
                   width: max(1, $0.width), height: max(1, $0.height))
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

/// What the gesture preview's right-hand pane draws for one resolved action.
enum GesturePreviewArt: Equatable, Sendable {
    /// The preset solver's layout, for the quick-layout picker.
    case tiling
    /// The strip solver over the mutation the action performs.
    case strip(StripPreviewMutation)
    case snap(SnapPosition)
    case symbol(String)
}

enum GesturePreviewPlan {
    /// The art for the action the router actually resolved. `nil` — a disabled or unbound rule, or an
    /// action of `.none` — draws the question mark, so the pane never previews an effect the gesture
    /// would not perform.
    static func art(for resolved: GestureActionTarget?) -> GesturePreviewArt {
        switch resolved {
        case nil, .some(.none):
            return .symbol("questionmark")
        case .some(.snapLeft), .some(.snapCycleLeft):
            return .snap(.leftHalf)
        case .some(.snapRight), .some(.snapCycleRight):
            return .snap(.rightHalf)
        case .some(.maximize):
            return .snap(.maximize)
        case .some(.centerRestore):
            return .snap(.center)
        case .some(.stripNext), .some(.stripPrevious):
            return .strip(.plain)
        case .some(.stripCycleWidth):
            return .strip(.cycleWidth)
        case .some(.stripStack):
            return .strip(.stack)
        case .some(.stripTabs):
            return .strip(.tabs)
        case .some(.stripSwapNext):
            return .strip(.swapNext)
        case .some(.stripSwapPrevious):
            return .strip(.swapPrevious)
        case .some(.quickLayoutPicker):
            return .tiling
        case .some(.toggleTiling):
            return .symbol("square.grid.2x2")
        case .some(.windowSwitcher):
            return .symbol("rectangle.on.rectangle")
        case .some(.nextDisplay), .some(.previousDisplay):
            return .symbol("display.2")
        case .some(.commandBar):
            return .symbol("circle.hexagongrid")
        case .some(.launcher):
            return .symbol("square.grid.3x3")
        case .some(.toggleNotch):
            return .symbol("menubar.rectangle")
        case .some(.spaceLeft), .some(.spaceRight):
            return .symbol("rectangle.split.2x1")
        }
    }
}

/// The strip mutation a gesture performs, as the preview replays it.
enum StripPreviewMutation: String, CaseIterable, Sendable {
    case plain, stack, cycleWidth, tabs, swapNext, swapPrevious

    /// Applies the engine's own mutation to a strip state, so the preview cannot describe a layout the
    /// engine would not produce. Tabs and stacking share one frame on purpose: tabbing changes how many
    /// windows sit behind a frame, not where the frame is.
    func apply(to state: inout ScrollingStripState) {
        switch self {
        case .plain: break
        case .stack: state.stackLeft()
        case .cycleWidth: state.cycleWidth()
        case .tabs: state.stackLeft(); state.focusColumn(-1); state.toggleTabs()
        case .swapNext: state.swapFocused(1)
        case .swapPrevious: state.swapFocused(-1)
        }
    }

    /// A three-column strip with uneven widths, focused in the middle, so a cycle or a swap is visible.
    static func seededStrip() -> ScrollingStripState {
        let ids = (0..<3).map { WindowID(rawValue: "preview\($0)") }
        var state = ScrollingStripState(windowIDs: ids)
        state.setWidth(.quarter)
        state.focusColumn(1); state.setWidth(.half)
        state.focusColumn(1); state.setWidth(.quarter)
        state.focusColumn(-1)
        return state
    }

    /// The focused column's width after the mutation, for callers that want to name the result.
    var resultingWidth: ColumnWidthPreset {
        var state = Self.seededStrip()
        apply(to: &state)
        return state.focusedColumn?.width ?? state.width
    }
}
