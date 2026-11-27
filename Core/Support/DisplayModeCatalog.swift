import CoreGraphics
import Foundation

/// SN-6: one selectable display mode, reduced to what a person actually chooses between — how many
/// points the desktop lays out, how many pixels back them, and at what refresh. The pixel/point pair is
/// what makes a mode "HiDPI": the same desktop at twice the density, not a smaller one.
struct DisplayModeOption: Identifiable, Equatable, Sendable {
    /// Stable across reads of the same mode list: pixel size, point size and refresh.
    let id: String
    let pixelWidth: Int
    let pixelHeight: Int
    let pointWidth: Int
    let pointHeight: Int
    let refresh: Double

    init(pixelWidth: Int, pixelHeight: Int, pointWidth: Int, pointHeight: Int, refresh: Double) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.refresh = refresh
        self.id = "\(pointWidth)x\(pointHeight)@\(Int(refresh.rounded()))-\(pixelWidth)x\(pixelHeight)"
    }

    /// Backing-store pixels per point.
    var scale: Double {
        pointWidth > 0 ? Double(pixelWidth) / Double(pointWidth) : 1
    }

    /// Retina-class. 1.5 rather than 2 because a few panels advertise 1.6× backing stores; anything
    /// below that is a plain low-resolution mode wearing a bigger number.
    var isHiDPI: Bool { scale >= 1.5 }

    /// Built for `Text(verbatim:)`: "1440 × 900 HiDPI · 60 Hz".
    var label: String {
        let hz = refresh > 0 ? String(format: " · %.0f Hz", refresh) : ""
        return "\(pointWidth) × \(pointHeight)\(isHiDPI ? " HiDPI" : "")\(hz)"
    }
}

/// The decisions the mode list has to make, kept pure so they are testable without touching a display.
enum DisplayModeCatalog {
    /// Drops duplicates and orders the list the way the menu should read: HiDPI first, then the most
    /// desktop area, then the fastest refresh. A 4K panel advertises dozens of modes; most of them are
    /// the same three choices in different colour depths.
    static func sorted(_ modes: [DisplayModeOption]) -> [DisplayModeOption] {
        var seen = Set<String>()
        return modes
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in
                if a.isHiDPI != b.isHiDPI { return a.isHiDPI }
                let areaA = a.pointWidth * a.pointHeight
                let areaB = b.pointWidth * b.pointHeight
                if areaA != areaB { return areaA > areaB }
                if a.refresh != b.refresh { return a.refresh > b.refresh }
                return a.pixelWidth > b.pixelWidth
            }
    }

    /// "The sharp version of what I have": same desktop size, twice the pixels. Returns nil when the
    /// current mode is already sharp or the panel has no such mode, so the caller can hide the action
    /// instead of offering a switch that changes nothing visible.
    static func sharpestAtCurrentSize(current: DisplayModeOption, in modes: [DisplayModeOption]) -> DisplayModeOption? {
        guard !current.isHiDPI else { return nil }
        return modes
            .filter { $0.pointWidth == current.pointWidth && $0.pointHeight == current.pointHeight && $0.isHiDPI }
            .max { $0.refresh < $1.refresh }
    }

    /// Whether two options describe the same picture; used to mark the current row in a menu.
    static func isSamePicture(_ a: DisplayModeOption, _ b: DisplayModeOption) -> Bool {
        a.pointWidth == b.pointWidth && a.pointHeight == b.pointHeight
            && a.pixelWidth == b.pixelWidth && a.pixelHeight == b.pixelHeight
    }
}
