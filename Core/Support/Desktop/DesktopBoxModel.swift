import CoreGraphics
import Foundation

/// Keys and bounded defaults for KatiKati's desktop-layer widget canvas. On unless the user turns it off;
/// `DOCK_DESKTOP_CANVAS=1` forces it on for the live check.
enum DesktopCanvasConfig {
    static let enabledKey = "com.katikati.desktop.enabled"
    static let snapGapKey = "com.katikati.desktop.snapGap"
    static let edgeMarginKey = "com.katikati.desktop.edgeMargin"
    static let doubleClickDesktopKey = "com.katikati.desktop.doubleClickDesktop"
    static let showOnAllSpacesKey = "com.katikati.desktop.showOnAllSpaces"
    static let materialStyleKey = "com.katikati.desktop.materialStyle"
    static let panoramaEnabledKey = "com.katikati.desktop.panoramaEnabled"
    static let panoramaImagePathKey = "com.katikati.desktop.panoramaImagePath"
    static let panoramaOpacityKey = "com.katikati.desktop.panoramaOpacity"
    static let panoramaBlurKey = "com.katikati.desktop.panoramaBlur"
    static let panoramaScaleModeKey = "com.katikati.desktop.panoramaScaleMode"
    static let seededDefaultsKey = "com.katikati.desktop.seededDefaults"
    static let defaultCapsuleModeKey = "com.katikati.desktop.defaultCapsuleMode"

    static let defaultSnapGap: Double = 12
    static let defaultEdgeMargin: Double = 12
    static let snapGapRange: ClosedRange<Double> = 0...40
    static let edgeMarginRange: ClosedRange<Double> = 0...48
    static let iconSizeRange: ClosedRange<CGFloat> = 24...96
    static let defaultIconSize: CGFloat = 44
    static let defaultPanoramaOpacity: Double = 0.65
    static let defaultPanoramaBlur: Double = 0.0
    static let cornerRadiusRange: ClosedRange<CGFloat> = 6...28

    static func clampedSnapGap(_ value: Double) -> Double {
        min(max(value, snapGapRange.lowerBound), snapGapRange.upperBound)
    }

    static func clampedEdgeMargin(_ value: Double) -> Double {
        min(max(value, edgeMarginRange.lowerBound), edgeMarginRange.upperBound)
    }

    static func clampedIconSize(_ value: CGFloat) -> CGFloat {
        min(max(value, iconSizeRange.lowerBound), iconSizeRange.upperBound)
    }

    static func isFeatureEnabled(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        isEnabledByUser(defaults: defaults) || DebugSwitch.desktopCanvas.isEnabled(in: environment)
    }

    /// Desktop Boxes are on unless the user explicitly turned them off.
    static func isEnabledByUser(defaults: UserDefaults = .standard) -> Bool {
        (defaults.object(forKey: enabledKey) as? Bool) ?? true
    }

    /// First-run starter widgets (To-Do + Quick Capture): once per profile, never over an explicit "off",
    /// never on top of boxes the user already has.
    static func shouldSeedDefaults(defaults: UserDefaults = .standard, hasExistingItems: Bool) -> Bool {
        !defaults.bool(forKey: seededDefaultsKey) && isEnabledByUser(defaults: defaults) && !hasExistingItems
    }

    static let defaultSeedKinds: [DesktopWidgetKind] = [.todo, .quickCapture]
}

/// ML-1: one place for the music-surface preferences, so the card, the wallpaper source, and the Settings
/// rows agree on keys and defaults. Values live in `UserDefaults` (no `AppSettingsStore` wiring until ML-5).
enum MusicSurfaceConfig {
    static let enabledKey = "com.katikati.music.widgetEnabled"
    static let wallpaperEnabledKey = "com.katikati.music.wallpaperEnabled"
    static let desktopEnabledKey = "com.katikati.music.desktopWidgetEnabled"
    static let desktopPresetKey = "com.katikati.music.desktopPreset"
    static let desktopFramesKey = "com.katikati.music.desktopFrames"
    /// Recorded once so a later default flip can never re-enable the wallpaper for someone who chose.
    static let wallpaperDefaultMigratedKey = "com.katikati.music.wallpaperDefaultMigrated"
    static let wallpaperClassicKey = "com.katikati.music.wallpaperClassic"
    static let wallpaperAnimatedKey = "com.katikati.music.wallpaperAnimated"
    static let glassStyleKey = "com.katikati.music.glassStyle"
    static let leftSlotKey = "com.katikati.music.control.left"
    static let rightSlotKey = "com.katikati.music.control.right"
    static let slimKey = "com.katikati.music.widgetSlim"
    static let stashEdgeKey = "com.katikati.music.widgetStashEdge"
    static let favoritesKey = "com.katikati.music.favorites"
    /// Same stored key the notch track uses for its lock-screen extra, so there is one switch in the app.
    static let lockScreenCardKey = "com.katikati.liquid.lockScreenEnabled"
    /// Posted after any of the keys above changes, so the wallpaper source and cards repaint without polling.
    static let didChangeNotification = Notification.Name("com.katikati.music.surfaceDidChange")

    static let defaultGlassStyle: MusicGlassStyle = .semi
    static let defaultSlimHeight: CGFloat = 96
    static let defaultFullHeight: CGFloat = 300

    static func glassStyle(defaults: UserDefaults = .standard) -> MusicGlassStyle {
        defaults.string(forKey: glassStyleKey).flatMap(MusicGlassStyle.init(rawValue:)) ?? defaultGlassStyle
    }

    static func assignment(defaults: UserDefaults = .standard) -> MusicControlAssignment {
        MusicControlAssignment(leftRaw: defaults.string(forKey: leftSlotKey),
                               rightRaw: defaults.string(forKey: rightSlotKey))
    }

    /// The desktop widget is on for fresh installs; the washed album-art wallpaper is not (§10).
    static var isDesktopWidgetEnabled: Bool {
        (UserDefaults.standard.object(forKey: desktopEnabledKey) as? Bool) ?? true
    }

    static func desktopPreset(defaults: UserDefaults = .standard) -> MusicDesktopWidgetPreset {
        defaults.string(forKey: desktopPresetKey).flatMap(MusicDesktopWidgetPreset.init(rawValue:))
            ?? MusicDesktopWidgetPreset.standard
    }

    static func setDesktopPreset(_ preset: MusicDesktopWidgetPreset, defaults: UserDefaults = .standard) {
        if defaults.string(forKey: desktopPresetKey) != preset.rawValue {
            defaults.set(preset.rawValue, forKey: desktopPresetKey)
        }
        notifyChange()
    }

    /// One-time: honour a stored wallpaper choice, otherwise leave the album-art wallpaper off.
    static func ensureWallpaperDefaultMigrated(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: wallpaperDefaultMigratedKey) == nil else { return }
        if defaults.object(forKey: wallpaperEnabledKey) == nil {
            defaults.set(false, forKey: wallpaperEnabledKey)
        }
        defaults.set(true, forKey: wallpaperDefaultMigratedKey)
    }

    static func mode(defaults: UserDefaults = .standard) -> MusicWidgetMode {
        defaults.bool(forKey: slimKey) ? .slim : .full
    }

    static func stashEdge(defaults: UserDefaults = .standard) -> MusicStashEdge? {
        defaults.string(forKey: stashEdgeKey).flatMap(MusicStashEdge.init(rawValue:))
    }

    /// Classic (static, unblurred art) is the default; a missing key must not mean "animated".
    static var isClassicBackdrop: Bool {
        (UserDefaults.standard.object(forKey: wallpaperClassicKey) as? Bool) ?? true
    }

    /// Animated art is opt-in and only meaningful with the wallpaper on; it still yields to Classic.
    static var isAnimatedBackdrop: Bool {
        UserDefaults.standard.bool(forKey: wallpaperAnimatedKey)
    }

    static let styleSelectionKey = "com.katikati.music.styleSelection"
    static let menuBarLyricsKey = "com.katikati.music.menuBarLyrics"
    static let discordPresenceKey = "com.katikati.music.discordPresence"
    static let discordClientIDKey = "com.katikati.music.discordClientId"
    static let edgeVolumeKey = "com.katikati.music.edgeVolume"
    static let viewModeKey = "com.katikati.music.viewMode"
    static let lockVolumeKey = "com.katikati.music.lockVolume"
    static let queueHistoryKey = "com.katikati.music.queueHistory"

    /// §5.7/§5.8 — one persisted selection, decoded once per read. Falls back to the shipped style.
    static func styleSelection(defaults: UserDefaults = .standard) -> MusicStyleSelection {
        guard let data = defaults.data(forKey: styleSelectionKey),
              let selection = try? JSONDecoder().decode(MusicStyleSelection.self, from: data)
        else { return MusicStyleSelection() }
        return selection
    }

    static func saveStyleSelection(_ selection: MusicStyleSelection, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: styleSelectionKey)
        notifyChange()
    }

    /// Atmospheric's Now Playing / Synced Lyrics / Queue-History switcher, remembered per surface.
    static func viewMode(for surface: MusicSurface = .desktop, defaults: UserDefaults = .standard) -> MusicViewMode {
        let raw = defaults.string(forKey: viewModeKey + "." + surface.rawValue)
        return raw.flatMap(MusicViewMode.init(rawValue:)) ?? .nowPlaying
    }

    static func saveViewMode(_ mode: MusicViewMode, for surface: MusicSurface = .desktop,
                             defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: viewModeKey + "." + surface.rawValue)
        notifyChange()
    }

    /// Session history survives launches: it is the only "queue" macOS gives us without Automation.
    static func queueModel(defaults: UserDefaults = .standard) -> MusicQueueModel {
        guard let data = defaults.data(forKey: queueHistoryKey),
              let model = try? JSONDecoder().decode(MusicQueueModel.self, from: data)
        else { return MusicQueueModel() }
        return model
    }

    static func saveQueueModel(_ model: MusicQueueModel, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        defaults.set(data, forKey: queueHistoryKey)
    }

    static func theme(for surface: MusicSurface = .desktop, defaults: UserDefaults = .standard) -> MusicSurfaceTheme {
        let selection = styleSelection(defaults: defaults)
        // A legacy glass choice still drives the shared theme until the user picks a newer preset.
        if selection == MusicStyleSelection(),
           let legacy = defaults.string(forKey: glassStyleKey).flatMap(MusicGlassStyle.init(rawValue:)) {
            return MusicSurfaceTheme(legacy: legacy)
        }
        return selection.theme(for: surface)
    }

    static func scrubber(defaults: UserDefaults = .standard) -> MusicScrubberStyle {
        styleSelection(defaults: defaults).scrubber(for: .desktop)
    }

    static func layout(defaults: UserDefaults = .standard) -> MusicCardLayout {
        styleSelection(defaults: defaults).layout(for: .desktop)
    }

    static func wallpaperStyle(defaults: UserDefaults = .standard) -> MusicWallpaperStyle {
        styleSelection(defaults: defaults).wallpaperStyle(for: .wallpaper)
    }

    /// The lock-screen card shows the volume row unless the user turns it off (the sample lock widget has one).
    static var isLockVolumeEnabled: Bool {
        (UserDefaults.standard.object(forKey: lockVolumeKey) as? Bool) ?? true
    }

    static var isMenuBarLyricsEnabled: Bool {
        UserDefaults.standard.bool(forKey: menuBarLyricsKey)
    }

    static var isDiscordPresenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: discordPresenceKey)
    }

    static var discordClientID: String? {
        let id = UserDefaults.standard.string(forKey: discordClientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (id?.isEmpty ?? true) ? nil : id
    }

    static var isWallpaperEnabled: Bool {
        UserDefaults.standard.bool(forKey: wallpaperEnabledKey)
    }

    static var isWidgetEnabled: Bool {
        (UserDefaults.standard.object(forKey: enabledKey) as? Bool) ?? true
    }

    static func notifyChange() {
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

enum DesktopWidgetKind: String, Codable, CaseIterable, Sendable {
    case folder, todo, quickCapture, glance, weather, music, search, wordOfTheDay,
         yearProgress, keepAwake, habitStreak, storageGlance, pinnedNote, quickPasteClipboard
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
    var stackGroupingMode: DesktopStackGroupingMode
    var stackDisplayMode: DesktopStackDisplayMode
    var manualStacks: [DesktopManualStack]
    var tabGroupID: UUID?
    var tabOrder: Int
    var isActiveTab: Bool
    var appearance: DesktopWidgetAppearance
    var capsuleMode: DesktopCapsuleMode
    var wingPreset: DockWidgetPresetType?

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
        zOrder: Int = 0,
        stackGroupingMode: DesktopStackGroupingMode = .none,
        stackDisplayMode: DesktopStackDisplayMode = .adaptive,
        manualStacks: [DesktopManualStack] = [],
        tabGroupID: UUID? = nil,
        tabOrder: Int = 0,
        isActiveTab: Bool = true,
        appearance: DesktopWidgetAppearance = .standard,
        capsuleMode: DesktopCapsuleMode = .expanded,
        wingPreset: DockWidgetPresetType? = nil
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
        self.stackGroupingMode = stackGroupingMode
        self.stackDisplayMode = stackDisplayMode
        self.manualStacks = manualStacks
        self.tabGroupID = tabGroupID
        self.tabOrder = tabOrder
        self.isActiveTab = isActiveTab
        self.appearance = appearance
        self.capsuleMode = capsuleMode
        self.wingPreset = wingPreset
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, backingPath, isManagedFolder, displayUUID, followMainDisplay
        case frame, normalizedFrame, viewStyle, compactDensity, iconSizeOverride
        case filenameLines, sortMode, manualOrder, isHidden, zOrder
        case stackGroupingMode, stackDisplayMode, manualStacks, tabGroupID, tabOrder, isActiveTab, appearance, capsuleMode
        case wingPreset
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
            zOrder: try c.decodeIfPresent(Int.self, forKey: .zOrder) ?? 0,
            stackGroupingMode: try c.decodeIfPresent(DesktopStackGroupingMode.self, forKey: .stackGroupingMode) ?? .none,
            stackDisplayMode: try c.decodeIfPresent(DesktopStackDisplayMode.self, forKey: .stackDisplayMode) ?? .adaptive,
            manualStacks: try c.decodeIfPresent([DesktopManualStack].self, forKey: .manualStacks) ?? [],
            tabGroupID: try c.decodeIfPresent(UUID.self, forKey: .tabGroupID),
            tabOrder: try c.decodeIfPresent(Int.self, forKey: .tabOrder) ?? 0,
            isActiveTab: try c.decodeIfPresent(Bool.self, forKey: .isActiveTab) ?? true,
            appearance: try c.decodeIfPresent(DesktopWidgetAppearance.self, forKey: .appearance) ?? .standard,
            capsuleMode: try c.decodeIfPresent(DesktopCapsuleMode.self, forKey: .capsuleMode) ?? .expanded,
            wingPreset: try c.decodeIfPresent(DockWidgetPresetType.self, forKey: .wingPreset)
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
        try c.encode(stackGroupingMode, forKey: .stackGroupingMode)
        try c.encode(stackDisplayMode, forKey: .stackDisplayMode)
        try c.encode(manualStacks, forKey: .manualStacks)
        try c.encodeIfPresent(tabGroupID, forKey: .tabGroupID)
        try c.encode(tabOrder, forKey: .tabOrder)
        try c.encode(isActiveTab, forKey: .isActiveTab)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(capsuleMode, forKey: .capsuleMode)
        try c.encodeIfPresent(wingPreset, forKey: .wingPreset)
    }
}
