import CoreGraphics
import Foundation

/// Keys and bounded defaults for KatiKati's desktop-layer widget canvas (lazy-gated; off by default).
enum DesktopCanvasConfig {
    static let enabledKey = "com.katikati.desktop.enabled"
    static let snapGapKey = "com.katikati.desktop.snapGap"
    static let edgeMarginKey = "com.katikati.desktop.edgeMargin"
    static let doubleClickDesktopKey = "com.katikati.desktop.doubleClickDesktop"
    static let showOnAllSpacesKey = "com.katikati.desktop.showOnAllSpaces"

    static let defaultSnapGap: Double = 12
    static let defaultEdgeMargin: Double = 12
    static let snapGapRange: ClosedRange<Double> = 0...40
    static let edgeMarginRange: ClosedRange<Double> = 0...48
    static let iconSizeRange: ClosedRange<CGFloat> = 24...96
    static let defaultIconSize: CGFloat = 44

    static func clampedSnapGap(_ value: Double) -> Double {
        min(max(value, snapGapRange.lowerBound), snapGapRange.upperBound)
    }

    static func clampedEdgeMargin(_ value: Double) -> Double {
        min(max(value, edgeMarginRange.lowerBound), edgeMarginRange.upperBound)
    }

    static func clampedIconSize(_ value: CGFloat) -> CGFloat {
        min(max(value, iconSizeRange.lowerBound), iconSizeRange.upperBound)
    }
}

enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case folder, todo, quickCapture, glance, weather, music, search
}

enum DesktopFolderViewStyle: String, Codable, CaseIterable, Sendable {
    case iconGrid, compactList
}

enum DesktopFilenameLines: Int, Codable, CaseIterable, Sendable {
    case hidden = 0
    case one = 1
    case two = 2
}

enum DesktopSortMode: Equatable, Codable, Sendable {
    case manual
    case rule(FolderSortOrder)

    private enum CodingKeys: String, CodingKey { case type, order }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? "rule"
        if type == "manual" {
            self = .manual
        } else {
            let rawOrder = try c.decodeIfPresent(String.self, forKey: .order) ?? FolderSortOrder.default.rawValue
            self = .rule(FolderSortOrder(rawValue: rawOrder) ?? .default)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .manual:
            try c.encode("manual", forKey: .type)
        case .rule(let order):
            try c.encode("rule", forKey: .type)
            try c.encode(order.rawValue, forKey: .order)
        }
    }
}

/// Normalized against a display's AppKit `visibleFrame` (0...1 ratios) so resolution/scale switches reflow cleanly.
struct NormalizedWidgetRect: Codable, Equatable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}

/// Explicit frame struct so persistence avoids relying on `CGRect: Codable` availability across SDKs.
private struct CodableFrameRect: Codable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(_ rect: CGRect) {
        self.x = rect.origin.x
        self.y = rect.origin.y
        self.width = rect.size.width
        self.height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct DesktopWidgetItem: Codable, Equatable, Identifiable, Sendable {
    static let minimumSize = CGSize(width: 50, height: 50)
    static let defaultFolderSize = CGSize(width: 300, height: 280)

    let id: UUID
    var kind: DesktopWidgetKind
    var title: String
    var backingPath: String?
    var isManagedFolder: Bool
    var displayUUID: String?
    var followMainDisplay: Bool
    var frame: CGRect
    var normalizedFrame: NormalizedWidgetRect?
    var viewStyle: DesktopFolderViewStyle
    var compactDensity: Bool
    var iconSizeOverride: CGFloat?
    var filenameLines: DesktopFilenameLines
    var sortMode: DesktopSortMode
    var manualOrder: [String]
    var isHidden: Bool
    var zOrder: Int

    init(
        id: UUID = UUID(),
        kind: DesktopWidgetKind = .folder,
        title: String,
        backingPath: String? = nil,
        isManagedFolder: Bool = false,
        displayUUID: String? = nil,
        followMainDisplay: Bool = false,
        frame: CGRect = CGRect(origin: CGPoint(x: 80, y: 120), size: DesktopWidgetItem.defaultFolderSize),
        normalizedFrame: NormalizedWidgetRect? = nil,
        viewStyle: DesktopFolderViewStyle = .iconGrid,
        compactDensity: Bool = false,
        iconSizeOverride: CGFloat? = nil,
        filenameLines: DesktopFilenameLines = .two,
        sortMode: DesktopSortMode = .rule(.dateAdded),
        manualOrder: [String] = [],
        isHidden: Bool = false,
        zOrder: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.backingPath = backingPath.map(FilePathNormalization.normalized)
        self.isManagedFolder = isManagedFolder
        self.displayUUID = displayUUID
        self.followMainDisplay = followMainDisplay
        self.frame = CGRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(Self.minimumSize.width, frame.width),
            height: max(Self.minimumSize.height, frame.height)
        )
        self.normalizedFrame = normalizedFrame
        self.viewStyle = viewStyle
        self.compactDensity = compactDensity
        self.iconSizeOverride = iconSizeOverride.map(DesktopCanvasConfig.clampedIconSize)
        self.filenameLines = filenameLines
        self.sortMode = sortMode
        self.manualOrder = manualOrder
        self.isHidden = isHidden
        self.zOrder = zOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, backingPath, isManagedFolder, displayUUID, followMainDisplay
        case frame, normalizedFrame, viewStyle, compactDensity, iconSizeOverride
        case filenameLines, sortMode, manualOrder, isHidden, zOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decodedFrame = (try c.decodeIfPresent(CodableFrameRect.self, forKey: .frame))?.cgRect
            ?? CGRect(origin: CGPoint(x: 80, y: 120), size: Self.defaultFolderSize)
        let rawIconSize = try c.decodeIfPresent(CGFloat.self, forKey: .iconSizeOverride)

        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            kind: try c.decodeIfPresent(DesktopWidgetKind.self, forKey: .kind) ?? .folder,
            title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
            backingPath: try c.decodeIfPresent(String.self, forKey: .backingPath),
            isManagedFolder: try c.decodeIfPresent(Bool.self, forKey: .isManagedFolder) ?? false,
            displayUUID: try c.decodeIfPresent(String.self, forKey: .displayUUID),
            followMainDisplay: try c.decodeIfPresent(Bool.self, forKey: .followMainDisplay) ?? false,
            frame: decodedFrame,
            normalizedFrame: try c.decodeIfPresent(NormalizedWidgetRect.self, forKey: .normalizedFrame),
            viewStyle: try c.decodeIfPresent(DesktopFolderViewStyle.self, forKey: .viewStyle) ?? .iconGrid,
            compactDensity: try c.decodeIfPresent(Bool.self, forKey: .compactDensity) ?? false,
            iconSizeOverride: rawIconSize,
            filenameLines: try c.decodeIfPresent(DesktopFilenameLines.self, forKey: .filenameLines) ?? .two,
            sortMode: try c.decodeIfPresent(DesktopSortMode.self, forKey: .sortMode) ?? .rule(.dateAdded),
            manualOrder: try c.decodeIfPresent([String].self, forKey: .manualOrder) ?? [],
            isHidden: try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false,
            zOrder: try c.decodeIfPresent(Int.self, forKey: .zOrder) ?? 0
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(backingPath, forKey: .backingPath)
        try c.encode(isManagedFolder, forKey: .isManagedFolder)
        try c.encodeIfPresent(displayUUID, forKey: .displayUUID)
        try c.encode(followMainDisplay, forKey: .followMainDisplay)
        try c.encode(CodableFrameRect(frame), forKey: .frame)
        try c.encodeIfPresent(normalizedFrame, forKey: .normalizedFrame)
        try c.encode(viewStyle, forKey: .viewStyle)
        try c.encode(compactDensity, forKey: .compactDensity)
        try c.encodeIfPresent(iconSizeOverride, forKey: .iconSizeOverride)
        try c.encode(filenameLines, forKey: .filenameLines)
        try c.encode(sortMode, forKey: .sortMode)
        try c.encode(manualOrder, forKey: .manualOrder)
        try c.encode(isHidden, forKey: .isHidden)
        try c.encode(zOrder, forKey: .zOrder)
    }
}
