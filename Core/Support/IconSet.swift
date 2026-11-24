import Foundation

/// Chip and menu-bar artwork set (`com.katikati.iconSet`, Phase 6 Appearance tab).
///
/// `system` uses macOS Trash artwork; `modern` and `classic` retain the existing presets.
/// Independent of the theme preset: switching one never touches the other key.
enum IconSet: String, CaseIterable, Sendable {
    case system
    case modern
    case classic

    static let `default`: IconSet = .system

    /// Missing or unknown stored value → `system`.
    init(storedValue: String?) {
        self = storedValue.flatMap(IconSet.init(rawValue:)) ?? .default
    }

    /// SF Symbol for the trash chip in `classic`.
    static func classicTrashSymbol(isFull: Bool) -> String {
        isFull ? "trash.fill" : "trash"
    }

    /// SF Symbol for the menu-bar item in `classic`.
    static let classicMenuBarSymbol = "rectangle.split.3x1"
}

// MARK: - IS-1.1 Pure Core Icon Studio Models

enum IconStudioDefaultsKeys {
    static let enabled = "com.katikati.iconStudio.enabled"
    static let macOSIconsAPIKey = "com.katikati.iconStudio.macOSIconsAPIKey"
}

enum IconArtworkSource: Equatable, Hashable, Codable, Sendable {
    case original
    case localFile(relativePath: String)
    case macOSIcons(id: String, cachedRelativePath: String)
    var isCustom: Bool { self != .original }
}

struct IconRecolorSpec: Equatable, Hashable, Codable, Sendable {
    enum Mode: String, CaseIterable, Codable, Sendable { case original, tint, monochrome, duotone }
    var mode: Mode
    var primaryHex: String?
    var secondaryHex: String?
    var intensity: Double

    init(mode: Mode = .original, primaryHex: String? = nil, secondaryHex: String? = nil, intensity: Double = 0) {
        self.mode = mode; self.primaryHex = primaryHex; self.secondaryHex = secondaryHex
        self.intensity = min(1, max(0, intensity))
    }

    var isIdentity: Bool { mode == .original || intensity <= 0.001 }
}

enum IconAnimationTrigger: String, CaseIterable, Codable, Sendable { case hover, active, off }

enum IconShaderPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, liquidGlass, gloss, gold, lightLeather, tooledLeather, woodInlay
    case carvedMarble, embroidery, brushedMetal, stainedGlass, classicMac
    case holographicFoil, vhs, crt, lavaLamp, neonSign
    var id: String { rawValue }
    var isAnimated: Bool {
        switch self {
        case .holographicFoil, .vhs, .crt, .lavaLamp, .neonSign: return true
        default: return false
        }
    }
    var requiresStaticBake: Bool { self != .none && !isAnimated }
}

struct IconShaderSpec: Equatable, Hashable, Codable, Sendable {
    var preset: IconShaderPreset
    var strength: Double
    var trigger: IconAnimationTrigger

    init(preset: IconShaderPreset = .none, strength: Double = 0.75, trigger: IconAnimationTrigger = .hover) {
        self.preset = preset; self.strength = min(1, max(0, strength)); self.trigger = trigger
    }

    func shouldAnimate(isHovered: Bool, isLiveActive: Bool, reduceMotion: Bool) -> Bool {
        guard !reduceMotion, preset.isAnimated, strength > 0.001 else { return false }
        switch trigger {
        case .hover: return isHovered
        case .active: return isLiveActive
        case .off: return false
        }
    }
}

enum IconDecorationKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case stringLights, pine, snowGlobe
    var id: String { rawValue }
}

struct IconDecoration: Equatable, Hashable, Identifiable, Codable, Sendable {
    var id: UUID
    var kind: IconDecorationKind
    var anchorX: Double
    var anchorY: Double
    var spacing: Double
    var scale: Double

    init(id: UUID = UUID(), kind: IconDecorationKind, anchorX: Double = 0.5, anchorY: Double = 0.5, spacing: Double = 0.5, scale: Double = 1.0) {
        self.id = id; self.kind = kind
        self.anchorX = min(1, max(0, anchorX)); self.anchorY = min(1, max(0, anchorY))
        self.spacing = min(1, max(0, spacing)); self.scale = min(1.8, max(0.4, scale))
    }
}

enum IconBadgeEffectKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, fire, sunlight, waxSeal, glint
    var id: String { rawValue }
}

enum IconUnreadBadgeParser {
    static func parseCount(_ badgeText: String?) -> Int {
        guard let trimmed = badgeText?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return 0 }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "+", with: "")
        var digits = ""
        for scalar in cleaned.unicodeScalars {
            if scalar.isASCII && CharacterSet.decimalDigits.contains(scalar) { digits.unicodeScalars.append(scalar) }
            else if !digits.isEmpty { break }
        }
        return digits.isEmpty ? 1 : max(0, Int(digits) ?? 0)
    }
}

struct IconBadgeEffectSpec: Equatable, Hashable, Codable, Sendable {
    var kind: IconBadgeEffectKind
    var minUnreadCount: Int

    init(kind: IconBadgeEffectKind = .none, minUnreadCount: Int = 1) {
        self.kind = kind; self.minUnreadCount = max(1, minUnreadCount)
    }

    func isTriggered(byBadgeText text: String?) -> Bool {
        kind != .none && IconUnreadBadgeParser.parseCount(text) >= max(1, minUnreadCount)
    }
}

enum LiveIconKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude, codex, cursor, appleMusic, spotify, finder, mail, messages, safari, chrome
    var id: String { rawValue }
    var defaultBundleID: String {
        switch self {
        case .claude: return "com.anthropic.claudefordesktop"
        case .codex: return "com.openai.chat"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .finder: return "com.apple.finder"
        case .mail: return "com.apple.mail"
        case .messages: return "com.apple.MobileSMS"
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        }
    }
    var supportsOptInActivityProbe: Bool {
        switch self {
        case .finder, .mail, .messages, .safari, .chrome: return true
        case .claude, .codex, .cursor, .appleMusic, .spotify: return false
        }
    }
}

enum LiveIconUsageMode: String, CaseIterable, Codable, Sendable { case none, used, remaining }
enum LiveIconUsageStyle: String, CaseIterable, Codable, Sendable { case colorFill, water, fadeTide, glyphTracer }
enum LiveIconMusicStyle: String, CaseIterable, Codable, Sendable { case vinyl, cdJewelCase, prismaticDisc }

struct LiveIconConfig: Equatable, Hashable, Codable, Sendable {
    var kind: LiveIconKind
    var isEnabled: Bool
    var usageMode: LiveIconUsageMode
    var usageStyle: LiveIconUsageStyle
    var showPercentage: Bool
    var showWeeklyReset: Bool
    var musicStyle: LiveIconMusicStyle
    var showCountdown: Bool
    var optInActivityProbe: Bool

    static func `default`(for kind: LiveIconKind) -> LiveIconConfig {
        let usageStyle: LiveIconUsageStyle = kind == .claude ? .fadeTide : (kind == .codex ? .glyphTracer : .water)
        return LiveIconConfig(
            kind: kind, isEnabled: true, usageMode: .used, usageStyle: usageStyle,
            showPercentage: true, showWeeklyReset: false,
            musicStyle: kind == .appleMusic ? .vinyl : .cdJewelCase, showCountdown: true, optInActivityProbe: false
        )
    }
}

enum IconRenderLayer: String, CaseIterable, Equatable, Sendable {
    case baseArtwork, recolor, shader, liveData, decorations, badgeEffect
}

struct IconLook: Equatable, Hashable, Codable, Sendable {
    var artwork: IconArtworkSource = .original
    var recolor: IconRecolorSpec = .init()
    var shader: IconShaderSpec = .init()
    var decorations: [IconDecoration] = []
    var badgeEffect: IconBadgeEffectSpec = .init()
    var live: LiveIconConfig? = nil

    var isOriginal: Bool {
        !artwork.isCustom && recolor.isIdentity && shader.preset == .none
            && decorations.isEmpty && badgeEffect.kind == .none && live == nil
    }

    var needsBadgePolling: Bool {
        badgeEffect.kind != .none || (live?.isEnabled == true && (live?.kind == .mail || live?.kind == .messages))
    }

    var activeLayers: [IconRenderLayer] {
        var layers: [IconRenderLayer] = [.baseArtwork]
        if !recolor.isIdentity { layers.append(.recolor) }
        if shader.preset != .none { layers.append(.shader) }
        if live?.isEnabled == true { layers.append(.liveData) }
        if !decorations.isEmpty { layers.append(.decorations) }
        if badgeEffect.kind != .none { layers.append(.badgeEffect) }
        return layers
    }

    /// Deterministic FNV-1a 64-bit hex digest over static-baked components only.
    func staticBakeFingerprint(bundleID: String, pixelSize: Int) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func feed(_ text: String) {
            for byte in text.utf8 { hash ^= UInt64(byte); hash &*= 1_099_511_628_211 }
            hash ^= 0xFF; hash &*= 1_099_511_628_211
        }
        feed(bundleID); feed("\(pixelSize)")
        switch artwork {
        case .original: feed("orig")
        case .localFile(let path): feed("file:\(path)")
        case .macOSIcons(let id, let path): feed("mi:\(id):\(path)")
        }
        feed(recolor.isIdentity ? "recolor:none" : "recolor:\(recolor.mode.rawValue):\(recolor.primaryHex ?? ""):\(recolor.secondaryHex ?? ""):\(Int((recolor.intensity * 1000).rounded()))")
        feed(shader.preset.requiresStaticBake ? "shader:\(shader.preset.rawValue):\(Int((shader.strength * 1000).rounded()))" : "shader:none")
        return String(format: "%016llx", hash)
    }
}

struct SavedIconLookPreset: Equatable, Hashable, Identifiable, Codable, Sendable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    var look: IconLook
}

struct IconStudioState: Equatable, Codable, Sendable {
    static let currentSchemaVersion = 1
    var schemaVersion: Int = currentSchemaVersion
    var looksByBundleID: [String: IconLook] = [:]
    var savedPresets: [SavedIconLookPreset] = []

    var badgeEligibleBundleIDs: Set<String> {
        Set(looksByBundleID.compactMap { $0.value.needsBadgePolling ? $0.key : nil })
    }

    mutating func setLook(_ look: IconLook, for bundleID: String) {
        guard !bundleID.isEmpty, !look.isOriginal else {
            looksByBundleID.removeValue(forKey: bundleID); return
        }
        looksByBundleID[bundleID] = look
    }

    mutating func restoreOriginal(for bundleID: String) { looksByBundleID.removeValue(forKey: bundleID) }

    @discardableResult
    mutating func savePreset(name: String, from look: IconLook, id: UUID = UUID(), now: Date = Date()) -> SavedIconLookPreset {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var portable = look; portable.live = nil
        let preset = SavedIconLookPreset(id: id, name: trimmed.isEmpty ? "Look" : trimmed, createdAt: now, look: portable)
        savedPresets.append(preset)
        return preset
    }

    mutating func deletePreset(id: UUID) { savedPresets.removeAll { $0.id == id } }

    mutating func applyPreset(_ preset: SavedIconLookPreset, to bundleID: String) {
        guard !bundleID.isEmpty else { return }
        let existing = looksByBundleID[bundleID]
        var next = preset.look
        next.live = existing?.live
        if !next.artwork.isCustom, let existingArtwork = existing?.artwork, existingArtwork.isCustom {
            next.artwork = existingArtwork
        }
        setLook(next, for: bundleID)
    }
}

// MARK: - IS-1.2 JSON Persistence Codec

enum IconStudioPersistence {
    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("KatiKati", isDirectory: true)
            .appendingPathComponent("icon-studio.json", isDirectory: false)
    }

    static func encode(_ state: IconStudioState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) -> IconStudioState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(IconStudioState.self, from: data),
              state.schemaVersion == IconStudioState.currentSchemaVersion else {
            return IconStudioState()
        }
        return state
    }

    static func load(from url: URL) -> IconStudioState {
        guard let data = try? Data(contentsOf: url) else { return IconStudioState() }
        return decode(data)
    }

    static func save(_ state: IconStudioState, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encode(state).write(to: url, options: .atomic)
    }
}

// MARK: - IS-3.1 Live Icon Metrics & Local Estimators

enum LiveIconMetrics {
    static func usageFillFraction(usedPercent: Double?, mode: LiveIconUsageMode) -> Double? {
        guard mode != .none, let usedPercent, usedPercent.isFinite else { return nil }
        let clamped = min(1, max(0, usedPercent / 100.0))
        return mode == .used ? clamped : (1.0 - clamped)
    }

    static func formattedPercentage(_ fraction: Double) -> String {
        let pct = Int((min(1, max(0, fraction)) * 100.0).rounded())
        return "\(pct)%"
    }

    static func weeklyResetFraction(now: Date, resetsAt: Date?, windowSeconds: TimeInterval = 7 * 86_400) -> Double? {
        guard let resetsAt, windowSeconds > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(1, max(0, 1.0 - remaining / windowSeconds))
    }
}

struct VinylAngleAccumulator: Equatable, Sendable {
    var degrees: Double = 0
    var lastTimestamp: Date?

    mutating func advance(to now: Date, isPlaying: Bool, degreesPerSecond: Double = 45.0) -> Double {
        defer { lastTimestamp = isPlaying ? now : nil }
        guard isPlaying, let prev = lastTimestamp else { return degrees }
        let dt = max(0, min(1.0, now.timeIntervalSince(prev)))
        degrees = (degrees + dt * degreesPerSecond).truncatingRemainder(dividingBy: 360.0)
        return degrees
    }
}

enum CursorBudgetEstimator {
    static let defaultDailyBudgetUSD: Double = 5.0

    static func estimatedUsedPercent(todayCostUSD: Double, dailyBudgetUSD: Double = defaultDailyBudgetUSD) -> Double {
        guard dailyBudgetUSD > 0, todayCostUSD.isFinite, todayCostUSD > 0 else { return 0 }
        return min(100.0, (todayCostUSD / dailyBudgetUSD) * 100.0)
    }
}
