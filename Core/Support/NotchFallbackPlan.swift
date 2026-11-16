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

extension NotchFallbackPlan {
    /// Evaluates edge clearance for a top-docked bar vs menu bar / notch
    static func topDockOffset(menuBarHeight: CGFloat, screenEdge: DockScreenEdge) -> CGFloat {
        guard screenEdge == .top else { return 0 }
        return floatingTopOffset(menuBarHeight: menuBarHeight)
    }
}

// MARK: - DynamicNotch Priority Queue & Geometry Calculator (Slice DN-1)

/// Priority tiers for DynamicNotch live activities:
/// Critical calls/timers > Media playback > System info/downloads.
enum NotchActivityPriority: Int, Comparable, Codable, Sendable {
    case systemInfo = 100
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
