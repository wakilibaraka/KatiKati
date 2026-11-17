import CoreGraphics
import Foundation

// Phase 33g — Non-Notched Display Fallback Plan
// Pure geometry, placement, and offset solver for external monitors and non-notched displays.
// Dual-compiled in app and test targets. Zero AppKit dependencies.

struct NotchFallbackPlan: Equatable, Sendable {
    // MARK: - Floating Dimensions (Non-Notched)
    static let floatingClosedSize = CGSize(width: 185, height: 28)
    static let floatingClosedCornerRadius: CGFloat = 14.0
    static let floatingOpenCornerRadius: CGFloat = 22.0
    static let floatingTopMargin: CGFloat = 8.0

    /// Detects whether the active display has a physical hardware notch cutout.
    static func isNotchedDisplay(safeAreaTop: CGFloat) -> Bool {
        safeAreaTop > 0
    }

    /// Computes the top Y-offset for positioning the floating island below the menu bar on external displays.
    static func floatingTopOffset(menuBarHeight: CGFloat) -> CGFloat {
        let bar = menuBarHeight > 0 ? menuBarHeight : 24.0
        return bar + floatingTopMargin
    }

    /// Solves the usable horizontal width for activity wings.
    /// Hardware notch: keepout zone occupies 160pt in the center.
    /// Non-notched floating island: keepout is 0pt, allowing symmetric content layout.
    static func usableWingWidth(closedWidth: CGFloat, hasHardwareNotch: Bool) -> CGFloat {
        if hasHardwareNotch {
            let keepout = min(NotchDesignSpec.cameraKeepoutWidth, closedWidth)
            return max(0, (closedWidth - keepout) / 2)
        } else {
            return closedWidth / 2
        }
    }

    /// Solves the target frame for the notch panel window on screen.
    static func panelFrame(
        metrics: NotchMetrics,
        screenBounds: CGRect,
        isOpen: Bool,
        menuBarHeight: CGFloat
    ) -> CGRect {
        let size = isOpen ? NotchDesignSpec.openSize(forScreenWidth: screenBounds.width) : metrics.closedSize
        let x = screenBounds.midX - (size.width / 2)

        if metrics.hasHardwareNotch {
            return CGRect(x: x, y: 0, width: size.width, height: size.height)
        } else {
            let topY = floatingTopOffset(menuBarHeight: menuBarHeight)
            return CGRect(x: x, y: topY, width: size.width, height: size.height)
        }
    }
}

// MARK: - Droppy-Inspired Slice A-Glass: NotchGlassStyle & NotchGlassPolicy

/// Glass style preferences for the Dynamic Island / Notch
enum NotchGlassStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case dynamicGlass
    case liquidClear
    case solidBlack

    var id: String { rawValue }
    static let defaultsKey = "com.katikati.notch.glassStyle"

    static func current(_ d: UserDefaults = .standard) -> NotchGlassStyle {
        NotchGlassStyle(rawValue: d.string(forKey: defaultsKey) ?? "") ?? .dynamicGlass
    }
}

/// Pure evaluation of glass material and plate styling based on user style, power mode, and hardware notch status.
enum NotchGlassPolicy {
    struct ResolvedGlass: Equatable, Sendable {
        let effectiveStyle: NotchGlassStyle
        let plateOpacity: Double
        let blurRadius: CGFloat
        let strokeOpacity: Double
        let isPowerSavingOpaque: Bool
    }

    /// Evaluates effective glass appearance. Low power mode forces solid black to save GPU rendering cost.
    /// Hardware notch display in closed state also stays solid black to blend with the bezel.
    static func resolve(
        style: NotchGlassStyle,
        isLowPowerMode: Bool,
        hasHardwareNotch: Bool,
        isOpen: Bool
    ) -> ResolvedGlass {
        if isLowPowerMode {
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.08,
                isPowerSavingOpaque: true
            )
        }

        if hasHardwareNotch && !isOpen {
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.0,
                isPowerSavingOpaque: false
            )
        }

        switch style {
        case .dynamicGlass:
            return ResolvedGlass(
                effectiveStyle: .dynamicGlass,
                plateOpacity: 0.82,
                blurRadius: 24.0,
                strokeOpacity: 0.16,
                isPowerSavingOpaque: false
            )
        case .liquidClear:
            return ResolvedGlass(
                effectiveStyle: .liquidClear,
                plateOpacity: 0.55,
                blurRadius: 36.0,
                strokeOpacity: 0.22,
                isPowerSavingOpaque: false
            )
        case .solidBlack:
            return ResolvedGlass(
                effectiveStyle: .solidBlack,
                plateOpacity: 1.0,
                blurRadius: 0.0,
                strokeOpacity: 0.10,
                isPowerSavingOpaque: false
            )
        }
    }
}

// MARK: - Slice NS-1: Notch surface appearance (OLED black by default)

/// The notch plate's colour, chosen as a milled material rather than a plain tint. Raw values are stored;
/// never rename them.
enum NotchColorPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case oledBlack
    case graphiteSmoke
    case midnightIndigo
    case obsidianEmerald
    case warmEspresso
    case crimsonVelvet
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oledBlack: return String(localized: "OLED Black")
        case .graphiteSmoke: return String(localized: "Graphite Smoke")
        case .midnightIndigo: return String(localized: "Midnight Indigo")
        case .obsidianEmerald: return String(localized: "Obsidian Emerald")
        case .warmEspresso: return String(localized: "Warm Espresso")
        case .crimsonVelvet: return String(localized: "Crimson Velvet")
        case .custom: return String(localized: "Custom")
        }
    }

    /// The plate fill. `.custom` reads `NotchSurfaceAppearance.customHex` instead; its value here is only
    /// the black a custom surface starts from.
    var baseHex: DockRGBA {
        switch self {
        case .oledBlack: return rgba(0x000000)
        case .graphiteSmoke: return rgba(0x1C1C1E)
        case .midnightIndigo: return rgba(0x0A0F2C)
        case .obsidianEmerald: return rgba(0x03130E)
        case .warmEspresso: return rgba(0x170D08)
        case .crimsonVelvet: return rgba(0x1C0407)
        case .custom: return rgba(0x000000)
        }
    }

    /// The 1 pt rim: a lifted sibling of the base, so the edge reads as milled glass, not a sticker.
    var rimHex: DockRGBA {
        switch self {
        case .oledBlack: return rgba(0x4A4A4E)
        case .graphiteSmoke: return rgba(0x8E8E93)
        case .midnightIndigo: return rgba(0x4E63C8)
        case .obsidianEmerald: return rgba(0x1F8A66)
        case .warmEspresso: return rgba(0xB07A4A)
        case .crimsonVelvet: return rgba(0xB02B42)
        case .custom: return rgba(0x8E8E93)
        }
    }

    /// How hard the rim reads. OLED black barely needs one; the tinted presets lean on it.
    var rimOpacity: Double {
        switch self {
        case .oledBlack: return 0.18
        case .custom: return 0.30
        case .graphiteSmoke, .warmEspresso: return 0.30
        case .midnightIndigo, .obsidianEmerald, .crimsonVelvet: return 0.34
        }
    }

    private func rgba(_ hex: UInt32) -> DockRGBA {
        DockRGBA(r: CGFloat((hex >> 16) & 0xFF) / 255,
                 g: CGFloat((hex >> 8) & 0xFF) / 255,
                 b: CGFloat(hex & 0xFF) / 255,
                 a: 1)
    }
}

/// `#RRGGBB` / `#RRGGBBAA` parsing for the custom swatch. Malformed input falls back to black: a hand-typed
/// or half-written hex must never crash the notch or paint a colour nobody chose.
enum NotchHexColor {
    static func rgba(_ hex: String, alpha: CGFloat = 1) -> DockRGBA {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt32(text, radix: 16) else {
            return DockRGBA(r: 0, g: 0, b: 0, a: alpha)
        }
        let hasAlpha = text.count == 8
        let rgb = hasAlpha ? value >> 8 : value
        let resolvedAlpha = hasAlpha ? CGFloat(value & 0xFF) / 255 : alpha
        return DockRGBA(r: CGFloat((rgb >> 16) & 0xFF) / 255,
                        g: CGFloat((rgb >> 8) & 0xFF) / 255,
                        b: CGFloat(rgb & 0xFF) / 255,
                        a: resolvedAlpha)
    }

    /// A custom plate's rim is the plate lifted toward white, so the edge stays in the same family instead
    /// of arriving as an unrelated grey line.
    static func rim(for base: DockRGBA) -> DockRGBA {
        let lift: CGFloat = 0.55
        return DockRGBA(r: base.r + (1 - base.r) * lift,
                        g: base.g + (1 - base.g) * lift,
                        b: base.b + (1 - base.b) * lift,
                        a: 1)
    }
}

/// What the notch actually draws, after clamping and the Low Power Mode override.
struct ResolvedNotchSurface: Equatable, Sendable {
    let preset: NotchColorPreset
    /// The plate fill at full strength; the view applies `baseOpacity` to it.
    let baseColor: DockRGBA
    let baseOpacity: Double
    let rimColor: DockRGBA
    let rimOpacity: Double
    let transparency: Double
    /// `false` at the default: no vibrancy pass at all, so the opaque plate cannot be seen through.
    let shouldRenderBlurMaterial: Bool
    let isPowerSavingOpaque: Bool
}

/// The notch's stored surface look. Defaults to **fully opaque OLED black**: nothing behind the notch
/// shows through unless the owner asks for it.
struct NotchSurfaceAppearance: Equatable, Sendable {
    static let transparencyRange: ClosedRange<Double> = 0.0...0.85
    static let defaultTransparency = 0.0
    static let defaultCustomHex = "#000000"

    enum StorageKey {
        static let preset = "com.katikati.notch.surface.preset"
        static let customHex = "com.katikati.notch.surface.customHex"
        static let transparency = "com.katikati.notch.surface.transparency"
    }

    var preset: NotchColorPreset
    var customHex: String
    var transparency: Double

    init(preset: NotchColorPreset = .oledBlack,
         customHex: String = NotchSurfaceAppearance.defaultCustomHex,
         transparency: Double = NotchSurfaceAppearance.defaultTransparency) {
        self.preset = preset
        self.customHex = customHex
        self.transparency = transparency
    }

    /// Anything stored, however old or hand-edited, lands inside the slider's own range.
    var clampedTransparency: Double {
        guard transparency.isFinite else { return Self.defaultTransparency }
        return min(max(transparency, Self.transparencyRange.lowerBound), Self.transparencyRange.upperBound)
    }

    /// Low Power Mode is opaque OLED black whatever is stored: no blur pass, no tint. Everything else is
    /// the clamped stored value, with the blur material existing only once the plate is actually
    /// see-through.
    func effectiveAppearance(isLowPowerMode: Bool) -> ResolvedNotchSurface {
        let preset = isLowPowerMode ? NotchColorPreset.oledBlack : self.preset
        let transparency = isLowPowerMode ? Self.defaultTransparency : clampedTransparency
        let base = preset == .custom ? NotchHexColor.rgba(customHex) : preset.baseHex
        let rim = preset == .custom ? NotchHexColor.rim(for: base) : preset.rimHex
        let baseOpacity = 1.0 - transparency
        return ResolvedNotchSurface(
            preset: preset,
            baseColor: DockRGBA(r: base.r, g: base.g, b: base.b, a: 1),
            baseOpacity: baseOpacity,
            rimColor: DockRGBA(r: rim.r, g: rim.g, b: rim.b, a: 1),
            rimOpacity: preset.rimOpacity,
            transparency: transparency,
            shouldRenderBlurMaterial: transparency > 0.001,
            isPowerSavingOpaque: isLowPowerMode
        )
    }

    static func load(_ defaults: UserDefaults = .standard) -> NotchSurfaceAppearance {
        NotchSurfaceAppearance(
            preset: NotchColorPreset(rawValue: defaults.string(forKey: StorageKey.preset) ?? "") ?? .oledBlack,
            customHex: defaults.string(forKey: StorageKey.customHex) ?? defaultCustomHex,
            transparency: defaults.object(forKey: StorageKey.transparency) as? Double ?? defaultTransparency
        )
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(preset.rawValue, forKey: StorageKey.preset)
        defaults.set(customHex, forKey: StorageKey.customHex)
        defaults.set(clampedTransparency, forKey: StorageKey.transparency)
    }
}

extension NotchFallbackPlan {
    /// Evaluates edge clearance for a top-docked bar vs menu bar / notch
    static func topDockOffset(menuBarHeight: CGFloat, screenEdge: DockScreenEdge) -> CGFloat {
        guard screenEdge == .top else { return 0 }
        return floatingTopOffset(menuBarHeight: menuBarHeight)
    }
}

// MARK: - DynamicNotch Priority Queue & Geometry Calculator (Slice DN-1)

/// Priority tiers for DynamicNotch live activities:
/// Critical calls/timers > Media playback > Notifications > System info/downloads.
enum NotchActivityPriority: Int, Comparable, Codable, Sendable {
    case systemInfo = 100
    case notification = 150
    case media = 200
    case critical = 300

    static func < (lhs: NotchActivityPriority, rhs: NotchActivityPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A live activity or transient HUD item queued for the Notch / Dynamic Island.
struct NotchActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    let priority: NotchActivityPriority
    let title: String
    let subtitle: String?
    let icon: String
    var systemImage: String { icon }
    let timeout: TimeInterval?
    let level: Double?
    let createdAt: Date
    let expiresAt: Date?

    init(
        id: String,
        priority: NotchActivityPriority,
        title: String,
        subtitle: String? = nil,
        icon: String,
        timeout: TimeInterval? = nil,
        level: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.priority = priority
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.timeout = timeout
        self.level = level.map { min(1.0, max(0.0, $0)) }
        self.createdAt = createdAt
        self.expiresAt = timeout.map { createdAt.addingTimeInterval(max(0, $0)) }
    }
}

/// Pure reducer managing priority ordering, bounded eviction, and timeout expiration.
struct NotchActivityQueue: Equatable, Sendable {
    private(set) var items: [NotchActivityItem] = []
    let maxItems: Int

    init(maxItems: Int = 8) {
        self.maxItems = max(1, maxItems)
    }

    var current: NotchActivityItem? { items.first }
    var secondary: NotchActivityItem? { items.count > 1 ? items[1] : nil }

    mutating func enqueue(_ item: NotchActivityItem, now: Date = Date()) {
        pruneExpired(at: now)
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id < $1.id
        }
        if items.count > maxItems {
            items = Array(items.prefix(maxItems))
        }
    }

    mutating func dismiss(id: String) {
        items.removeAll { $0.id == id }
    }

    @discardableResult
    mutating func pruneExpired(at now: Date = Date()) -> Bool {
        let before = items.count
        items.removeAll { item in
            guard let expiresAt = item.expiresAt else { return false }
            return now >= expiresAt
        }
        return items.count != before
    }

    func nextExpirationDate(after now: Date) -> Date? {
        items.compactMap(\.expiresAt).filter { $0 > now }.min()
    }
}

/// Computes layout frames and mask geometry for notched MacBooks vs. floating capsule mode (`topInset == 0`).
enum NotchGeometryCalculator {
    enum DisplayMode: Equatable, Sendable {
        case hardwareNotch
        case floatingCapsule
    }

    struct Layout: Equatable, Sendable {
        let mode: DisplayMode
        let panelFrame: CGRect
        let topCornerRadius: CGFloat
        let bottomCornerRadius: CGFloat
        let flaringTopEars: Bool
    }

    static func mode(topInset: CGFloat) -> DisplayMode {
        topInset > 0 ? .hardwareNotch : .floatingCapsule
    }

    /// Computes AppKit bottom-left panel frame and squircle radii for hardware-notched vs. external displays.
    static func calculate(
        screenBounds: CGRect,
        topInset: CGFloat,
        menuBarHeight: CGFloat,
        closedSize: CGSize,
        openSize: CGSize,
        isExpanded: Bool,
        sharpEdges: Bool = false
    ) -> Layout {
        let displayMode = mode(topInset: topInset)
        let size = isExpanded ? openSize : closedSize
        let x = screenBounds.midX - (size.width / 2)

        switch displayMode {
        case .hardwareNotch:
            let frame = CGRect(x: x, y: screenBounds.maxY - size.height, width: size.width, height: size.height)
            if sharpEdges {
                return Layout(mode: .hardwareNotch, panelFrame: frame, topCornerRadius: 0, bottomCornerRadius: 0, flaringTopEars: false)
            }
            let radii = isExpanded ? NotchDesignSpec.openCornerRadii : NotchDesignSpec.closedCornerRadii
            return Layout(mode: .hardwareNotch, panelFrame: frame, topCornerRadius: radii.topFlaring, bottomCornerRadius: radii.bottomSquircle, flaringTopEars: true)

        case .floatingCapsule:
            let topOffset = NotchFallbackPlan.floatingTopOffset(menuBarHeight: menuBarHeight)
            let frame = CGRect(x: x, y: screenBounds.maxY - topOffset - size.height, width: size.width, height: size.height)
            if sharpEdges {
                return Layout(mode: .floatingCapsule, panelFrame: frame, topCornerRadius: 0, bottomCornerRadius: 0, flaringTopEars: false)
            }
            let radius = isExpanded ? NotchFallbackPlan.floatingOpenCornerRadius : NotchFallbackPlan.floatingClosedCornerRadius
            return Layout(mode: .floatingCapsule, panelFrame: frame, topCornerRadius: radius, bottomCornerRadius: radius, flaringTopEars: false)
        }
    }
}
