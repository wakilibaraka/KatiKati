import CoreGraphics
import Foundation

/// Available Dock II flanking wing widget presets.
enum DockWidgetPresetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case spotify
    case controlCenter
    case vpn
    case friends
    case telemetry
    case ram
    case network
    case disk
    case battery
    case ai

    var id: String { rawValue }

    var isAssigned: Bool { self != .none }

    /// SF Symbol representing this preset in settings pickers and compact fallback badges.
    var symbolName: String {
        switch self {
        case .none: return "minus.circle"
        case .spotify: return "music.note"
        case .controlCenter: return "switch.2"
        case .vpn: return "lock.shield"
        case .friends: return "person.2.fill"
        case .telemetry: return "waveform.path.ecg"
        case .ram: return "memorychip"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .battery: return "battery.75percent"
        case .ai: return "sparkles"
        }
    }

    var localizedTitle: String {
        switch self {
        case .none: return String(localized: "Off")
        case .spotify: return String(localized: "Now Playing Card")
        case .controlCenter: return String(localized: "Control Center")
        case .vpn: return String(localized: "VPN Status")
        case .friends: return String(localized: "Friends HUD")
        case .telemetry: return String(localized: "System Telemetry")
        case .ram: return String(localized: "RAM Usage")
        case .network: return String(localized: "Network Traffic")
        case .disk: return String(localized: "Disk & I/O")
        case .battery: return String(localized: "Battery & Thermal")
        case .ai: return String(localized: "AI")
        }
    }
}

/// Per-display wing preset pair keyed by persistent display UUID.
struct DockWingPair: Codable, Equatable, Sendable {
    var left: DockWingSlotConfig = DockWingSlotConfig()
    var right: DockWingSlotConfig = DockWingSlotConfig()
}

/// Which flank of the main dock strip hosts a Dock II wing widget.
enum DockWingPlacement: String, Codable, CaseIterable, Sendable {
    case leftWing
    case rightWing
}

/// Configuration for one Dock II wing slot.
struct DockWingSlotConfig: Codable, Equatable, Sendable {
    var preset: DockWidgetPresetType = .none
    var size: WidgetSize = .medium
}

/// Persisted left & right Dock II wing configuration (with optional per-display UUID overrides).
struct DockWingsConfiguration: Codable, Equatable, Sendable {
    static let defaultsKey = "com.katikati.dockII.wings.v1"
    static let defaultGap: CGFloat = 10
    static let minGap: CGFloat = 4
    static let maxGap: CGFloat = 24

    var left: DockWingSlotConfig
    var right: DockWingSlotConfig
    var gap: CGFloat
    var perDisplay: [String: DockWingPair]

    enum CodingKeys: String, CodingKey {
        case left, right, gap, perDisplay
    }

    init(
        left: DockWingSlotConfig = DockWingSlotConfig(),
        right: DockWingSlotConfig = DockWingSlotConfig(),
        gap: CGFloat = defaultGap,
        perDisplay: [String: DockWingPair] = [:]
    ) {
        self.left = left
        self.right = right
        self.gap = Self.clampedGap(gap)
        self.perDisplay = perDisplay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        left = try c.decodeIfPresent(DockWingSlotConfig.self, forKey: .left) ?? DockWingSlotConfig()
        right = try c.decodeIfPresent(DockWingSlotConfig.self, forKey: .right) ?? DockWingSlotConfig()
        gap = Self.clampedGap(try c.decodeIfPresent(CGFloat.self, forKey: .gap) ?? Self.defaultGap)
        perDisplay = try c.decodeIfPresent([String: DockWingPair].self, forKey: .perDisplay) ?? [:]
    }

    static let `default` = DockWingsConfiguration()
    static let recommendedDefault = DockWingsConfiguration(
        left: DockWingSlotConfig(preset: .telemetry, size: .medium),
        right: DockWingSlotConfig(preset: .ram, size: .medium)
    )
    static let cpuRamMigrationKey = "com.katikati.dockII.wings.defaultCpuRamMigrated.v1"

    var hasAnyActiveWing: Bool {
        left.preset.isAssigned || right.preset.isAssigned
    }

    /// Resolves effective wing configuration for a display UUID, falling back to legacy displayID then global.
    func resolved(displayUUID: String?, displayID: String? = nil) -> DockWingsConfiguration {
        if let displayUUID, !displayUUID.isEmpty, let pair = perDisplay[displayUUID] {
            return DockWingsConfiguration(left: pair.left, right: pair.right, gap: gap, perDisplay: perDisplay)
        }
        if let displayID, !displayID.isEmpty, let pair = perDisplay[displayID] {
            return DockWingsConfiguration(left: pair.left, right: pair.right, gap: gap, perDisplay: perDisplay)
        }
        return self
    }

    func slot(for placement: DockWingPlacement) -> DockWingSlotConfig {
        switch placement {
        case .leftWing: return left
        case .rightWing: return right
        }
    }

    func assigning(
        _ preset: DockWidgetPresetType,
        size: WidgetSize? = nil,
        to placement: DockWingPlacement,
        forDisplay displayUUID: String? = nil
    ) -> DockWingsConfiguration {
        var copy = self
        if let displayUUID, !displayUUID.isEmpty {
            let base = resolved(displayUUID: displayUUID)
            var pair = DockWingPair(left: base.left, right: base.right)
            switch placement {
            case .leftWing:
                pair.left.preset = preset
                if let size { pair.left.size = size }
            case .rightWing:
                pair.right.preset = preset
                if let size { pair.right.size = size }
            }
            copy.perDisplay[displayUUID] = pair
            return copy
        }
        switch placement {
        case .leftWing:
            copy.left.preset = preset
            if let size { copy.left.size = size }
        case .rightWing:
            copy.right.preset = preset
            if let size { copy.right.size = size }
        }
        return copy
    }

    func updatingSize(
        _ size: WidgetSize,
        for placement: DockWingPlacement,
        forDisplay displayUUID: String? = nil
    ) -> DockWingsConfiguration {
        var copy = self
        if let displayUUID, !displayUUID.isEmpty {
            let base = resolved(displayUUID: displayUUID)
            var pair = DockWingPair(left: base.left, right: base.right)
            switch placement {
            case .leftWing: pair.left.size = size
            case .rightWing: pair.right.size = size
            }
            copy.perDisplay[displayUUID] = pair
            return copy
        }
        switch placement {
        case .leftWing: copy.left.size = size
        case .rightWing: copy.right.size = size
        }
        return copy
    }

    func updatingGap(_ newGap: CGFloat) -> DockWingsConfiguration {
        var copy = self
        copy.gap = Self.clampedGap(newGap)
        return copy
    }

    static func clampedGap(_ gap: CGFloat) -> CGFloat {
        guard gap.isFinite else { return defaultGap }
        return min(max(gap, minGap), maxGap)
    }

    static func decode(_ data: Data?) -> DockWingsConfiguration? {
        guard let data else { return nil }
        guard var decoded = try? JSONDecoder().decode(DockWingsConfiguration.self, from: data) else {
            return nil
        }
        decoded.gap = clampedGap(decoded.gap)
        return decoded
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

/// Native-scale (`panelHeight == 54 pt`) widths for each Dock II preset and `WidgetSize` tier.
enum DockWingDimensions {
    static let nativeCornerRadius: CGFloat = 18

    static func nativeWidth(for preset: DockWidgetPresetType, size: WidgetSize) -> CGFloat {
        switch (preset, size) {
        case (.none, _): return 0
        case (.spotify, .small): return 112
        case (.spotify, .medium): return 188
        case (.spotify, .large): return 248
        case (.controlCenter, .small): return 124
        case (.controlCenter, .medium): return 188
        case (.controlCenter, .large): return 240
        case (.vpn, .small): return 116
        case (.vpn, .medium): return 184
        case (.vpn, .large): return 244
        case (.friends, .small): return 104
        case (.friends, .medium): return 176
        case (.friends, .large): return 232
        case (.telemetry, .small): return 112
        case (.telemetry, .medium): return 180
        case (.telemetry, .large): return 240
        case (.ram, .small): return 112
        case (.ram, .medium): return 180
        case (.ram, .large): return 240
        case (.network, .small): return 116
        case (.network, .medium): return 184
        case (.network, .large): return 240
        case (.disk, .small): return 108
        case (.disk, .medium): return 172
        case (.disk, .large): return 228
        case (.battery, .small): return 108
        case (.battery, .medium): return 168
        case (.battery, .large): return 220
        case (.ai, .small): return 112
        case (.ai, .medium): return 184
        case (.ai, .large): return 244
        }
    }

    static func scaledWidth(for preset: DockWidgetPresetType, size: WidgetSize, scale: CGFloat) -> CGFloat {
        nativeWidth(for: preset, size: size) * max(scale, 0.5)
    }
}

/// Pure auto-degrade planner (`L -> M -> S`) when total screen span cannot host both wings at requested sizes.
enum DockWingLayoutPlanner {
    struct ResolvedSizes: Equatable, Sendable {
        var left: WidgetSize
        var right: WidgetSize
    }

    static func resolveSizes(
        config: DockWingsConfiguration,
        availableWingBudget: CGFloat,
        scale: CGFloat = 1
    ) -> ResolvedSizes {
        var leftSize = config.left.size
        var rightSize = config.right.size

        func width(for placement: DockWingPlacement, size: WidgetSize) -> CGFloat {
            let slot = config.slot(for: placement)
            guard slot.preset.isAssigned else { return 0 }
            return DockWingDimensions.scaledWidth(for: slot.preset, size: size, scale: scale)
        }

        func totalWidth() -> CGFloat {
            width(for: .leftWing, size: leftSize) + width(for: .rightWing, size: rightSize)
        }

        while totalWidth() > availableWingBudget {
            let leftW = config.left.preset.isAssigned && leftSize > .small ? width(for: .leftWing, size: leftSize) : -1
            let rightW = config.right.preset.isAssigned && rightSize > .small ? width(for: .rightWing, size: rightSize) : -1
            if leftW < 0 && rightW < 0 { break }
            if leftW >= rightW {
                leftSize = steppedDown(leftSize)
            } else {
                rightSize = steppedDown(rightSize)
            }
        }

        return ResolvedSizes(left: leftSize, right: rightSize)
    }

    private static func steppedDown(_ size: WidgetSize) -> WidgetSize {
        switch size {
        case .large: return .medium
        case .medium, .small: return .small
        }
    }
}

/// Pure telemetry & byte-rate formatting for the Dock II VPN and Telemetry cards.
enum DockVpnRateFormat {
    static func formatted(_ bytesPerSecond: Double) -> String {
        let clamped = max(0, bytesPerSecond.isFinite ? bytesPerSecond : 0)
        if clamped < 1_000 {
            return String(format: "%.0f B/s", clamped)
        } else if clamped < 1_000_000 {
            return String(format: "%.1f KB/s", clamped / 1_000)
        } else if clamped < 1_000_000_000 {
            return String(format: "%.1f MB/s", clamped / 1_000_000)
        } else {
            return String(format: "%.2f GB/s", clamped / 1_000_000_000)
        }
    }
}

/// Messaging target for a friend contact in the Dock II Friends HUD.
enum DockFriendAppKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case messages
    case facetime
    case slack
    case discord
    case customURL

    var id: String { rawValue }

    var bundleIdentifier: String? {
        switch self {
        case .messages: return "com.apple.MobileSMS"
        case .facetime: return "com.apple.FaceTime"
        case .slack: return "com.tinyspeck.slackmacgap"
        case .discord: return "com.hnc.Discord"
        case .customURL: return nil
        }
    }

    var localizedTitle: String {
        switch self {
        case .messages: return String(localized: "Messages")
        case .facetime: return String(localized: "FaceTime")
        case .slack: return String(localized: "Slack")
        case .discord: return String(localized: "Discord")
        case .customURL: return String(localized: "Custom URL")
        }
    }

    /// Deep-link URL when `handle` is provided; falls back cleanly to nil when empty.
    func launchURL(handle: String) -> URL? {
        let trimmed = handle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch self {
        case .messages:
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
            return URL(string: "sms://open?addresses=\(encoded)")
        case .facetime:
            let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? trimmed
            return URL(string: "facetime://\(encoded)")
        case .slack, .discord:
            return URL(string: trimmed)
        case .customURL:
            return URL(string: trimmed)
        }
    }
}

/// One contact entry displayed in the Dock II Friends HUD.
struct DockFriendContact: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var displayName: String
    var handle: String
    var avatarSymbol: String
    var avatarImageFilename: String?
    var preferredApp: DockFriendAppKind
    var unreadOverride: Int?
    var isSpeaking: Bool
    var accentIndex: Int

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String = "",
        avatarSymbol: String = "person.crop.circle.fill",
        avatarImageFilename: String? = nil,
        preferredApp: DockFriendAppKind = .messages,
        unreadOverride: Int? = nil,
        isSpeaking: Bool = false,
        accentIndex: Int = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.avatarSymbol = avatarSymbol
        self.avatarImageFilename = avatarImageFilename
        self.preferredApp = preferredApp
        self.unreadOverride = unreadOverride
        self.isSpeaking = isSpeaking
        self.accentIndex = accentIndex
    }

    static func decodeList(_ data: Data?) -> [DockFriendContact] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([DockFriendContact].self, from: data)) ?? []
    }

    static func encodeList(_ list: [DockFriendContact]) -> Data? {
        try? JSONEncoder().encode(list)
    }
}

/// Pure snapshot structs used by the Dock II views and unit tests.
struct DockVpnStatusState: Equatable, Sendable {
    var isConnected: Bool = false
    var profileName: String = ""
    var cityLabel: String? = nil
    var countryCode: String? = nil
    var uploadBytesPerSec: Double = 0
    var downloadBytesPerSec: Double = 0

    var displayLocation: String {
        if let city = cityLabel, !city.isEmpty {
            return city
        }
        if !profileName.isEmpty {
            return profileName
        }
        return isConnected ? String(localized: "VPN Active") : String(localized: "Disconnected")
    }
}

struct DockTelemetryState: Equatable, Sendable {
    var cpuUsage: Double = 0
    var frequencyGHz: Double? = nil
    var temperatureCelsius: Double? = nil
    var thermalState: PowerThermal = .nominal
    var cpuHistory: [Double] = []
    var memoryFraction: Double = 0
    var gpuUsage: Double? = nil
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
}

enum DockSpotifyTrackKey {
    static func make(title: String?, artist: String?) -> String? {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let a = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "\(t.lowercased())|\(a.lowercased())"
    }
}

// MARK: - DWP-1: Universal Multi-Surface Widget Container

/// Surfaces across KatiKati capable of hosting modular Dock II widget presets.
enum WidgetSurfaceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case dockWing
    case drawer
    case shelfCard
    case backgroundAppsPopup
    case floatingStack

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .dockWing: return String(localized: "Dock Wings")
        case .drawer: return String(localized: "Drawer")
        case .shelfCard: return String(localized: "Shelf")
        case .backgroundAppsPopup: return String(localized: "Background Apps")
        case .floatingStack: return String(localized: "Floating Stack")
        }
    }
}

/// Universal modular widget attachment model shared across Drawer, Shelf, Background Apps,
/// Dock Wings, and the tear-off Floating Card Stack.
struct UniversalWidgetModel: Codable, Equatable, Identifiable, Sendable {
    var preset: DockWidgetPresetType
    var surface: WidgetSurfaceKind
    var size: WidgetSize
    var isCollapsed: Bool

    var id: String { "\(surface.rawValue).\(preset.rawValue)" }

    init(
        preset: DockWidgetPresetType,
        surface: WidgetSurfaceKind,
        size: WidgetSize = .medium,
        isCollapsed: Bool = false
    ) {
        self.preset = preset
        self.surface = surface
        self.size = size
        self.isCollapsed = isCollapsed
    }

    /// Card height in points when rendered inside vertical stack surfaces (Drawer, Shelf, Background Apps, Floating Stack).
    var stackCardHeight: CGFloat {
        guard !isCollapsed else { return 38 }
        switch (preset, size) {
        case (.none, _): return 0
        case (_, .small): return 46
        case (_, .medium): return 56
        case (_, .large): return 68
        }
    }
}

/// Pure multi-surface widget layout & attachment state. Persisted in `AppSettingsStore` under `defaultsKey`.
struct DockWidgetConfigStore: Codable, Equatable, Sendable {
    static let defaultsKey = "com.katikati.dockII.surfaceWidgets.v1"
    static let maxPerSurface = 4
    static let defaultStackWidth: CGFloat = 264

    private(set) var attachments: [UniversalWidgetModel]

    static let `default` = DockWidgetConfigStore(attachments: [])

    init(attachments: [UniversalWidgetModel] = []) {
        var seen = Set<String>()
        var counts: [WidgetSurfaceKind: Int] = [:]
        var filtered: [UniversalWidgetModel] = []
        for item in attachments where item.preset.isAssigned {
            guard seen.insert(item.id).inserted else { continue }
            let count = counts[item.surface, default: 0]
            guard count < Self.maxPerSurface else { continue }
            counts[item.surface] = count + 1
            filtered.append(item)
        }
        self.attachments = filtered
    }

    func attachments(for surface: WidgetSurfaceKind) -> [UniversalWidgetModel] {
        attachments.filter { $0.surface == surface }
    }

    func isPinned(_ preset: DockWidgetPresetType, on surface: WidgetSurfaceKind) -> Bool {
        attachments.contains { $0.preset == preset && $0.surface == surface }
    }

    func attachment(_ preset: DockWidgetPresetType, on surface: WidgetSurfaceKind) -> UniversalWidgetModel? {
        attachments.first { $0.preset == preset && $0.surface == surface }
    }

    func pinning(
        _ preset: DockWidgetPresetType,
        size: WidgetSize = .medium,
        to surface: WidgetSurfaceKind
    ) -> DockWidgetConfigStore {
        guard preset.isAssigned else { return self }
        var list = attachments
        if let idx = list.firstIndex(where: { $0.preset == preset && $0.surface == surface }) {
            list[idx].size = size
            list[idx].isCollapsed = false
            return DockWidgetConfigStore(attachments: list)
        }
        guard attachments(for: surface).count < Self.maxPerSurface else { return self }
        list.append(UniversalWidgetModel(preset: preset, surface: surface, size: size))
        return DockWidgetConfigStore(attachments: list)
    }

    func unpinning(_ preset: DockWidgetPresetType, from surface: WidgetSurfaceKind) -> DockWidgetConfigStore {
        DockWidgetConfigStore(attachments: attachments.filter { !($0.preset == preset && $0.surface == surface) })
    }

    func updatingSize(
        _ size: WidgetSize,
        for preset: DockWidgetPresetType,
        on surface: WidgetSurfaceKind
    ) -> DockWidgetConfigStore {
        let updated = attachments.map { item -> UniversalWidgetModel in
            guard item.preset == preset, item.surface == surface else { return item }
            var copy = item
            copy.size = size
            return copy
        }
        return DockWidgetConfigStore(attachments: updated)
    }

    func togglingCollapsed(
        for preset: DockWidgetPresetType,
        on surface: WidgetSurfaceKind
    ) -> DockWidgetConfigStore {
        let updated = attachments.map { item -> UniversalWidgetModel in
            guard item.preset == preset, item.surface == surface else { return item }
            var copy = item
            copy.isCollapsed.toggle()
            return copy
        }
        return DockWidgetConfigStore(attachments: updated)
    }

    /// Tears off a preset from `source` into `.floatingStack` (preserving its size).
    /// When `removeFromSource` is true, unpins from `source` as well.
    func tearingOff(
        _ preset: DockWidgetPresetType,
        from source: WidgetSurfaceKind,
        size: WidgetSize? = nil,
        removeFromSource: Bool = false
    ) -> DockWidgetConfigStore {
        guard preset.isAssigned else { return self }
        let inheritedSize = size ?? attachment(preset, on: source)?.size ?? .medium
        var next = pinning(preset, size: inheritedSize, to: .floatingStack)
        if removeFromSource && source != .floatingStack {
            next = next.unpinning(preset, from: source)
        }
        return next
    }

    /// Reorders attachments within `surface` using SwiftUI `onMove` index semantics.
    func moving(
        on surface: WidgetSurfaceKind,
        from source: IndexSet,
        to destination: Int
    ) -> DockWidgetConfigStore {
        var surfaceItems = attachments(for: surface)
        guard !surfaceItems.isEmpty else { return self }
        let moved = source.sorted().compactMap { surfaceItems.indices.contains($0) ? surfaceItems[$0] : nil }
        let before = source.filter { $0 < destination }.count
        for idx in source.sorted().reversed() where surfaceItems.indices.contains(idx) {
            surfaceItems.remove(at: idx)
        }
        let targetIndex = min(max(0, destination - before), surfaceItems.count)
        surfaceItems.insert(contentsOf: moved, at: targetIndex)

        var others = attachments.filter { $0.surface != surface }
        others.append(contentsOf: surfaceItems)
        return DockWidgetConfigStore(attachments: others)
    }

    func clearing(surface: WidgetSurfaceKind) -> DockWidgetConfigStore {
        DockWidgetConfigStore(attachments: attachments.filter { $0.surface != surface })
    }

    /// Extra vertical points a popup plate reserves for its embedded pinned widget section.
    static func popupSectionExtraHeight(
        for items: [UniversalWidgetModel],
        cardSpacing: CGFloat = 8,
        sectionRuleHeight: CGFloat = 18,
        bottomPadding: CGFloat = 8
    ) -> CGFloat {
        guard !items.isEmpty else { return 0 }
        let cardsHeight = items.reduce(CGFloat(0)) { $0 + $1.stackCardHeight }
        let gaps = CGFloat(max(0, items.count - 1)) * cardSpacing
        return sectionRuleHeight + cardsHeight + gaps + bottomPadding
    }

    static func decode(_ data: Data?) -> DockWidgetConfigStore? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(DockWidgetConfigStore.self, from: data)
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
