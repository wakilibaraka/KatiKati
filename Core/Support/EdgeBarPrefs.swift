import Foundation

/// Phase 13: edge-bar (deck) feel and look beyond the older per-key settings. One JSON blob in `com.katikati.edge.prefs`.

/// 13c: how much the button under the pointer grows. Raw values are stored; never rename them.
enum EdgeMagnifyAmount: String, CaseIterable, Codable, Sendable {
    case subtle, standard, bold
    var peak: Double {
        switch self {
        case .subtle: return 1.25
        case .standard: return 1.55
        case .bold: return 1.85
        }
    }
}

/// 13l: the edge bar's button artwork. `classic` is the original look.
enum EdgeIconSet: String, CaseIterable, Codable, Sendable { case classic, modern, realistic }

/// 13l: the plate behind every edge-bar flyout. `modern` is the default; `glass` is the earlier frosted look as a preset.
enum EdgeFlyoutStyle: String, CaseIterable, Codable, Sendable { case modern, glass }

/// The one look the whole edge bar wears: tabs, buttons, flyout plates, tile content and note sheets. `paper` is the
/// original coloured-paper design; `liquidGlass` is the translucent one (frosted on macOS < 26); `fluid` is the
/// poured body (`FluidRailBody`) the dock's fluid preset also wears. Raw values are stored.
enum EdgeBarStyle: String, CaseIterable, Codable, Sendable { case paper, liquidGlass, fluid, bezelDock }

struct EdgeBarPrefs: Equatable, Codable, Sendable {
    static let key = "com.katikati.edge.prefs"
    static let openDelayRange: ClosedRange<Double> = 0...1.5
    static let defaultOpenDelay = 0.4
    static let defaultSensitivity = 0.25

    /// Seconds the pointer must stay on the edge pill before the bar opens (13a).
    var openDelay = EdgeBarPrefs.defaultOpenDelay
    /// 0…1 — how generous the edge hot zone is (13j).
    var sensitivity = EdgeBarPrefs.defaultSensitivity
    var magnifyAmount = EdgeMagnifyAmount.standard
    var iconSet = EdgeIconSet.classic
    var flyoutStyle = EdgeFlyoutStyle.modern
    /// 13d: open only on a deliberate pointer-down on the pill, never on hover.
    var openOnClick = false
    /// 13b: a small name bubble beside the button under the pointer.
    var hoverLabels = true
    /// Whole-bar look. Older blobs have no key and keep `paper`.
    var barStyle = EdgeBarStyle.paper
    /// ExtraDock: show only running applications (true) or pinned + running applications (false).
    var appsRunningOnly = true
    /// ExtraDock: show a green running indicator dot on the screen-edge side of running apps.
    var showRunningDots = true
    /// ExtraDock: collapse the resting pill into a compact single-ear bezel button when idle.
    var collapseToButton = false
    /// ExtraDock: also show running/pinned apps in non-ExtraDock presets when toggled on.
    var showAppsInBar = false
    /// Sydedock: enabled glanceable card identifiers
    var sydedockCards: [String] = ["focus", "clock", "batteryWifi", "habits", "hydration", "food", "notesPreview"]
    /// Sydedock: hydration reminder interval (minutes)
    var hydrationIntervalMinutes: Int = 45
    /// Sydedock: daily hydration goal in glasses
    var hydrationDailyGoal: Int = 8
    /// Sydedock: intermittent fasting protocol identifier ("none", "16:8", "18:6", "14:10", "custom")
    var foodFastingProtocol: String = "16:8"
    /// Sydedock: meal cadence interval (hours)
    var foodMealIntervalHours: Double = 3.5
    /// Sydedock: daily calorie goal
    var foodDailyCalorieGoal: Int = 2000
    /// Sydedock: 24-hour clock format toggle
    var clockIs24Hour: Bool = false
    /// Sydedock: show seconds on clock card
    var clockShowSeconds: Bool = false
    /// Sydedock: show date on clock card
    var clockShowDate: Bool = true
    /// Sydedock: show percentage on battery card
    var batteryShowPercentage: Bool = true
    /// Sydedock: show Wi-Fi info on battery card
    var batteryShowWifi: Bool = true
    /// Sydedock: sound effects (water pour, timer chime) enabled
    var edgeSoundEffectsEnabled: Bool = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = EdgeBarPrefs()
        openDelay = try c.decodeIfPresent(Double.self, forKey: .openDelay) ?? d.openDelay
        sensitivity = try c.decodeIfPresent(Double.self, forKey: .sensitivity) ?? d.sensitivity
        magnifyAmount = try c.decodeIfPresent(EdgeMagnifyAmount.self, forKey: .magnifyAmount) ?? d.magnifyAmount
        iconSet = try c.decodeIfPresent(EdgeIconSet.self, forKey: .iconSet) ?? d.iconSet
        flyoutStyle = try c.decodeIfPresent(EdgeFlyoutStyle.self, forKey: .flyoutStyle) ?? d.flyoutStyle
        openOnClick = try c.decodeIfPresent(Bool.self, forKey: .openOnClick) ?? d.openOnClick
        hoverLabels = try c.decodeIfPresent(Bool.self, forKey: .hoverLabels) ?? d.hoverLabels
        barStyle = try c.decodeIfPresent(EdgeBarStyle.self, forKey: .barStyle) ?? d.barStyle
        appsRunningOnly = try c.decodeIfPresent(Bool.self, forKey: .appsRunningOnly) ?? d.appsRunningOnly
        showRunningDots = try c.decodeIfPresent(Bool.self, forKey: .showRunningDots) ?? d.showRunningDots
        collapseToButton = try c.decodeIfPresent(Bool.self, forKey: .collapseToButton) ?? d.collapseToButton
        showAppsInBar = try c.decodeIfPresent(Bool.self, forKey: .showAppsInBar) ?? d.showAppsInBar
        sydedockCards = try c.decodeIfPresent([String].self, forKey: .sydedockCards) ?? d.sydedockCards
        hydrationIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .hydrationIntervalMinutes) ?? d.hydrationIntervalMinutes
        hydrationDailyGoal = try c.decodeIfPresent(Int.self, forKey: .hydrationDailyGoal) ?? d.hydrationDailyGoal
        foodFastingProtocol = try c.decodeIfPresent(String.self, forKey: .foodFastingProtocol) ?? d.foodFastingProtocol
        foodMealIntervalHours = try c.decodeIfPresent(Double.self, forKey: .foodMealIntervalHours) ?? d.foodMealIntervalHours
        foodDailyCalorieGoal = try c.decodeIfPresent(Int.self, forKey: .foodDailyCalorieGoal) ?? d.foodDailyCalorieGoal
        clockIs24Hour = try c.decodeIfPresent(Bool.self, forKey: .clockIs24Hour) ?? d.clockIs24Hour
        clockShowSeconds = try c.decodeIfPresent(Bool.self, forKey: .clockShowSeconds) ?? d.clockShowSeconds
        clockShowDate = try c.decodeIfPresent(Bool.self, forKey: .clockShowDate) ?? d.clockShowDate
        batteryShowPercentage = try c.decodeIfPresent(Bool.self, forKey: .batteryShowPercentage) ?? d.batteryShowPercentage
        batteryShowWifi = try c.decodeIfPresent(Bool.self, forKey: .batteryShowWifi) ?? d.batteryShowWifi
        edgeSoundEffectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .edgeSoundEffectsEnabled) ?? d.edgeSoundEffectsEnabled
    }

    func clamped() -> EdgeBarPrefs {
        var p = self
        p.openDelay = openDelay.isFinite ? min(max(openDelay, Self.openDelayRange.lowerBound), Self.openDelayRange.upperBound) : Self.defaultOpenDelay
        p.sensitivity = sensitivity.isFinite ? min(max(sensitivity, 0), 1) : Self.defaultSensitivity
        return p
    }

    /// Extra hot-zone padding around the resting pill. The default sensitivity reproduces the older fixed (2, 6) inset.
    var zoneInset: (dx: Double, dy: Double) {
        let s = clamped().sensitivity
        return (dx: 8 * s, dy: 24 * s)
    }

    static func load(_ defaults: UserDefaults = .standard) -> EdgeBarPrefs {
        guard let data = defaults.data(forKey: key), let p = try? JSONDecoder().decode(EdgeBarPrefs.self, from: data) else { return EdgeBarPrefs() }
        return p.clamped()
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(clamped()) { defaults.set(data, forKey: Self.key) }
    }
}

/// 13a/13d: the pointer must rest on the pill for `delay` before the bar opens (or, in click-only mode, press on it), and a
/// pointer left sitting on the pill after the bar folded does nothing until it leaves and comes back. A button already held
/// when the pointer arrives (dragging something across the edge) never opens the bar.
struct EdgeDwell: Equatable, Sendable {
    private var enteredAt: Date?
    private var wasInside = false
    private var ignoreUntilRelease = false
    private(set) var armed = true

    /// Feed one poll. Returns true exactly when the bar should open.
    mutating func update(inside: Bool, pressed: Bool = false, now: Date, delay: TimeInterval, clickOnly: Bool = false) -> Bool {
        defer { wasInside = inside }
        if !pressed { ignoreUntilRelease = false }
        else if inside, !wasInside { ignoreUntilRelease = true }
        guard inside else { enteredAt = nil; armed = true; return false }
        guard armed, !ignoreUntilRelease else { enteredAt = nil; return false }
        if clickOnly { return pressed }
        let start = enteredAt ?? now
        enteredAt = start
        guard now.timeIntervalSince(start) >= delay else { return false }
        enteredAt = nil
        return true
    }

    /// The bar is open (or folding): ignore the pointer until it leaves the zone.
    mutating func disarm() { enteredAt = nil; armed = false }
}

/// 13e: the copy-to-clipboard screenshot. `-i` lets the user select an area, `-c` sends it to the clipboard — there is no
/// file argument, so nothing is ever saved.
enum ScreenshotCommand {
    static let launchPath = "/usr/sbin/screencapture"
    static let arguments = ["-i", "-c"]

    /// Phase 16h: select an area; the image goes to the clipboard and nowhere else.
    static func run() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        try? task.run()
    }
}

// MARK: - Slice T-1: Tendedero Hanging Utility Model & Physics Reducer

enum TendederoCaptureMode: String, CaseIterable, Codable, Sendable {
    case screenshotsAndAutoClipboard
    case screenshotsAndManualClipboard
}

enum TendederoCapacityMode: Equatable, Codable, Sendable {
    case capped(maxUnpinned: Int, expireAfter: TimeInterval?)
    case unlimited

    static let `default`: TendederoCapacityMode = .capped(maxUnpinned: 20, expireAfter: 86_400)
}

enum TendederoItemKind: Equatable, Codable, Sendable {
    case screenshot(url: URL)
    case imageData(Data)
    case link(URL)
    case text(String)
}

struct TendederoItem: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var kind: TendederoItemKind
    var title: String
    var createdAt: Date
    var isPinned: Bool
    var isUnread: Bool
    var swingAngleDegrees: Double
    var swingVelocity: Double

    init(
        id: UUID = UUID(),
        kind: TendederoItemKind,
        title: String,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        isUnread: Bool = true,
        swingAngleDegrees: Double = 0,
        swingVelocity: Double = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.isUnread = isUnread
        self.swingAngleDegrees = swingAngleDegrees
        self.swingVelocity = swingVelocity
    }
}

enum TendederoSpringPhysics {
    static let defaultStiffness: Double = 140
    static let defaultDamping: Double = 10

    static func step(
        angle: Double,
        velocity: Double,
        dt: TimeInterval,
        stiffness: Double = defaultStiffness,
        damping: Double = defaultDamping
    ) -> (angle: Double, velocity: Double) {
        let clampedDT = min(max(dt, 0), 0.05)
        guard clampedDT > 0 else { return (angle, velocity) }
        let accel = (-stiffness * angle) - (damping * velocity)
        let nextVelocity = velocity + accel * clampedDT
        let nextAngle = angle + nextVelocity * clampedDT
        if abs(nextAngle) < 0.05 && abs(nextVelocity) < 0.1 {
            return (0, 0)
        }
        return (min(max(nextAngle, -24), 24), nextVelocity)
    }
}

struct TendederoStore: Equatable, Codable, Sendable {
    private(set) var items: [TendederoItem] = []
    var capacityMode: TendederoCapacityMode = .default

    var unreadCount: Int { items.filter(\.isUnread).count }

    @discardableResult
    mutating func add(
        kind: TendederoItemKind,
        title: String,
        now: Date = Date(),
        initialSwing: Double = 10
    ) -> TendederoItem {
        if let existingIndex = items.firstIndex(where: { $0.kind == kind }) {
            var existing = items.remove(at: existingIndex)
            existing.createdAt = now
            existing.isUnread = true
            existing.swingAngleDegrees = initialSwing
            items.insert(existing, at: 0)
            return existing
        }
        let item = TendederoItem(
            kind: kind,
            title: title,
            createdAt: now,
            isPinned: false,
            isUnread: true,
            swingAngleDegrees: initialSwing,
            swingVelocity: 0
        )
        items.insert(item, at: 0)
        enforceConstraints(now: now)
        return item
    }

    mutating func togglePin(id: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].isPinned.toggle()
        items[idx].swingAngleDegrees = items[idx].isPinned ? -6 : 6
    }

    mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    mutating func clearUnpinned() {
        items.removeAll { !$0.isPinned }
    }

    mutating func markAllRead() {
        for idx in items.indices { items[idx].isUnread = false }
    }

    mutating func applyImpulse(id: UUID, degrees: Double) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].swingVelocity += degrees * 8
    }

    mutating func tickPhysics(dt: TimeInterval) {
        for idx in items.indices {
            guard items[idx].swingAngleDegrees != 0 || items[idx].swingVelocity != 0 else { continue }
            let next = TendederoSpringPhysics.step(
                angle: items[idx].swingAngleDegrees,
                velocity: items[idx].swingVelocity,
                dt: dt
            )
            items[idx].swingAngleDegrees = next.angle
            items[idx].swingVelocity = next.velocity
        }
    }

    mutating func pruneExpired(now: Date = Date()) {
        enforceConstraints(now: now)
    }

    private mutating func enforceConstraints(now: Date) {
        guard case let .capped(maxUnpinned, expireAfter) = capacityMode else { return }
        if let expireAfter, expireAfter > 0 {
            items.removeAll { !$0.isPinned && now.timeIntervalSince($0.createdAt) > expireAfter }
        }
        let unpinnedIndices = items.indices.filter { !items[$0].isPinned }
        if unpinnedIndices.count > maxUnpinned {
            let overflow = unpinnedIndices.count - maxUnpinned
            let indicesToDrop = Set(unpinnedIndices.suffix(overflow))
            items = items.enumerated().filter { !indicesToDrop.contains($0.offset) }.map(\.element)
        }
    }
}
