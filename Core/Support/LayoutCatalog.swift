import CoreGraphics

/// The nine user-facing layouts of the Layouts tab. Each one is an existing `TilingLayoutPreset` plus options
/// and a slot count: windows past `slots` wait out of the way instead of shrinking the tiles.
enum LayoutCatalog: String, CaseIterable, Sendable {
    case staged, fullscreen, halves, twoThirdsOneThird, thirds, quarters, stacked, mainLeft, mainRight

    var preset: TilingLayoutPreset {
        switch self {
        case .staged, .fullscreen: return .monocle
        case .halves, .thirds: return .columns
        case .stacked: return .rows
        case .quarters: return .grid
        case .twoThirdsOneThird, .mainLeft, .mainRight: return .mainStack
        }
    }

    var options: TilingLayoutOptions {
        switch self {
        case .twoThirdsOneThird: return TilingLayoutOptions(mainRatio: 2.0 / 3, mirrored: false)
        case .mainLeft: return TilingLayoutOptions(mainRatio: 0.5, mirrored: false)
        // Mirrored puts the main window on the right; the stack sits on the left.
        case .mainRight: return TilingLayoutOptions(mainRatio: 0.5, mirrored: true)
        default: return TilingLayoutOptions()
        }
    }

    /// Windows that get a slot; the rest are parked.
    var slots: Int {
        switch self {
        case .staged, .fullscreen: return 1
        case .halves, .twoThirdsOneThird, .stacked: return 2
        case .thirds, .mainLeft, .mainRight: return 3
        case .quarters: return 4
        }
    }

    /// Shown under the layout name in the picker.
    var summary: String {
        switch self {
        case .staged: return "One window, centered with space around it"
        case .fullscreen: return "One window filling the display"
        case .halves: return "Two windows side by side"
        case .twoThirdsOneThird: return "Two windows, wider on the left"
        case .thirds: return "Three windows side by side"
        case .quarters: return "Four windows in a grid"
        case .stacked: return "Two windows, top and bottom"
        case .mainLeft: return "One on the left, two on the right"
        case .mainRight: return "Two on the left, one on the right"
        }
    }

    /// Frames for the first `slots` windows of `ids`, in Cocoa coordinates. Parked windows get no frame.
    func frames(for ids: [WindowID], workArea: CGRect, gaps: TilingGaps) -> [WindowID: CGRect] {
        var tree = TilingTree()
        for id in ids.prefix(slots) { tree.insert(id) }
        if self == .staged {
            // shortcut: fixed 80% x 90% inset, make it a setting when someone asks.
            let inset = workArea.insetBy(dx: workArea.width * 0.1, dy: workArea.height * 0.05)
            return TilingLayout.resolve(tree: tree, preset: preset, workArea: inset, gaps: gaps, options: options)
        }
        return TilingLayout.resolve(tree: tree, preset: preset, workArea: workArea, gaps: gaps, options: options)
    }
}
