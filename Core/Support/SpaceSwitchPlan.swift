import Foundation

/// Which Space a request lands on, and how the Dock is asked to get there.
///
/// Ported from Spacewalk (MIT, © 2026 InsaneArts) — the pure half of its `SpaceEngine.Plan`. The
/// switching itself is the Dock's own, driven by `DockSwipeEventPoster`; nothing here touches the OS.
enum SpaceTransitionEffect: String, CaseIterable, Sendable {
    case instant, fade
}

/// Where Settings › Appearance keeps the two Space-transition knobs. Read straight from the
/// defaults on every switch, so the controller and the pane need no shared object.
enum SpaceTransitionSettings {
    static let effectKey = "com.katikati.spaces.effect"
    static let durationKey = "com.katikati.spaces.duration"
    static let defaultDuration: Double = 0.24
    static let durationRange: ClosedRange<Double> = 0.1 ... 0.6

    static func effect(from defaults: UserDefaults = .standard) -> SpaceTransitionEffect {
        SpaceTransitionEffect(rawValue: defaults.string(forKey: effectKey) ?? "") ?? .fade
    }

    /// Clamped: a hand-edited key cannot leave the slider's range.
    static func duration(from defaults: UserDefaults = .standard) -> Double {
        guard defaults.object(forKey: durationKey) != nil else { return defaultDuration }
        return min(max(defaults.double(forKey: durationKey), durationRange.lowerBound), durationRange.upperBound)
    }
}

struct SpaceSwitchPlan: Equatable, Sendable {
    let fromIndex: Int
    let toIndex: Int

    /// Dock swipes it takes: one per Space crossed, so 2→4 is two rightward swipes.
    var steps: Int { abs(toIndex - fromIndex) }

    /// A rightward swipe, in the same sense the fullscreen-intent code uses (`SpaceSwitchDirection.right`
    /// is the next Space in Mission Control order). `DockSwipeEventPoster` flips the sign on the macOS 27
    /// path, where direction is relative to natural scrolling.
    var direction: SpaceSwitchDirection { toIndex > fromIndex ? .right : .left }

    /// `nil` when there is nowhere to go: one Space, no wrap, or an index that is not in the list.
    /// Indices are positions in the desktop-only list — fullscreen Spaces are not switchable this way.
    static func plan(
        currentIndex: Int,
        spaceCount: Int,
        direction: SpaceSwitchDirection,
        wrap: Bool
    ) -> SpaceSwitchPlan? {
        guard spaceCount > 1, (0 ..< spaceCount).contains(currentIndex) else { return nil }
        let raw = direction == .right ? currentIndex + 1 : currentIndex - 1
        guard raw < 0 || raw >= spaceCount else {
            return SpaceSwitchPlan(fromIndex: currentIndex, toIndex: raw)
        }
        guard wrap else { return nil }
        return SpaceSwitchPlan(fromIndex: currentIndex, toIndex: raw >= spaceCount ? 0 : spaceCount - 1)
    }
}

// MARK: - Mission Control (MC-1: pure naming, framing, colouring and action models)

// Mission Control is macOS's own overview; there is no public API for it. These types are the pure
// half of KatiKati's overlays: names, borders, colours and the OpenMissionControl-style hover
// actions. Nothing here imports AppKit, reads Accessibility or draws anything — the session
// detector and overlay host in App/Entry and the executor in Platform/Accessibility consume them.

/// What a window is doing, which decides its border when it is neither hovered nor focused.
enum MissionControlWindowState: String, Codable, CaseIterable, Sendable {
    case standard, minimized, hidden, fullscreen
}

enum MissionControlBorderStyle: String, Codable, CaseIterable, Sendable {
    case none, hairline, solid, dashed, glow
}

/// sRGB, clamped on the way in so a hand-edited rule cannot emit an invalid colour.
struct MissionControlColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    static let blue = MissionControlColor(red: 0.22, green: 0.55, blue: 0.98)
    static let neutral = MissionControlColor(red: 0.62, green: 0.64, blue: 0.68)
    static let green = MissionControlColor(red: 0.28, green: 0.78, blue: 0.52)
    static let orange = MissionControlColor(red: 0.98, green: 0.58, blue: 0.20)
    static let pink = MissionControlColor(red: 0.94, green: 0.40, blue: 0.70)
    static let yellow = MissionControlColor(red: 0.95, green: 0.78, blue: 0.24)
    static let purple = MissionControlColor(red: 0.62, green: 0.48, blue: 0.96)
}

/// The categories a window is auto-assigned to when `autoAssignCategories` is on. The assignment is
/// only a starting colour: every category can be re-coloured, and a bundle-ID rule outranks it.
enum MissionControlAppCategory: String, Codable, CaseIterable, Sendable {
    case browser, code, comms, notes, media, other

    var defaultColor: MissionControlColor {
        switch self {
        case .browser: return .blue
        case .code: return .green
        case .comms: return .orange
        case .notes: return .yellow
        case .media: return .pink
        case .other: return .neutral
        }
    }

    var defaultTintOpacity: Double {
        switch self {
        case .other: return 0
        default: return 0.10
        }
    }

    /// Bundle-ID prefixes KatiKati recognises without the user writing a rule. Matched
    /// case-insensitively; anything unrecognised is `.other`.
    static func inferred(fromBundleID bundleID: String?) -> MissionControlAppCategory {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }
        let prefixes: [(String, MissionControlAppCategory)] = [
            ("com.apple.safari", .browser), ("com.google.chrome", .browser),
            ("org.mozilla.firefox", .browser), ("com.microsoft.edgemac", .browser),
            ("com.brave.browser", .browser), ("company.thebrowser", .browser),
            ("com.apple.terminal", .code), ("com.googlecode.iterm2", .code),
            ("dev.warp", .code), ("com.mitchellh.ghostty", .code),
            ("com.microsoft.vscode", .code), ("com.apple.dt.xcode", .code),
            ("com.todesktop", .code), ("com.jetbrains", .code), ("dev.zed", .code),
            ("com.apple.mail", .comms), ("com.microsoft.outlook", .comms),
            ("com.tinyspeck.slackmacgap", .comms), ("com.hnc.discord", .comms),
            ("ru.keepcoder.telegram", .comms), ("com.apple.messages", .comms),
            ("us.zoom.xos", .comms), ("com.apple.notes", .notes), ("notion.id", .notes),
            ("md.obsidian", .notes), ("com.apple.preview", .media),
            ("com.spotify.client", .media), ("com.apple.music", .media),
            ("com.apple.quicktimeplayerx", .media), ("com.apple.tv", .media)
        ]
        return prefixes.first { id.hasPrefix($0.0) }?.1 ?? .other
    }
}

/// One user rule. `bundleID` is an exact, case-insensitive match; `category` recolours every window
/// in that category. Rules are stored in the user's order and resolve in that order.
struct MissionControlColorRule: Codable, Equatable, Identifiable, Sendable {
    enum Match: Codable, Equatable, Sendable {
        case bundleID(String)
        case category(MissionControlAppCategory)
    }

    var id: UUID
    var match: Match
    var color: MissionControlColor

    init(id: UUID = UUID(), match: Match, color: MissionControlColor) {
        self.id = id
        self.match = match
        self.color = color
    }

    func matches(bundleID: String?, category: MissionControlAppCategory) -> Bool {
        switch match {
        case .bundleID(let wanted):
            guard let bundleID else { return false }
            return bundleID.caseInsensitiveCompare(wanted) == .orderedSame
        case .category(let wanted):
            return wanted == category
        }
    }
}

/// Naming, framing and colouring in one value: the settings pane, the overlay renderer and the tests
/// all resolve through these functions, so the preview cannot disagree with the live overlay.
struct MissionControlColouring: Codable, Equatable, Sendable {
    var isEnabled: Bool
    /// On by default (the product choice): categories start coloured, every rule stays editable.
    var autoAssignCategories: Bool
    var rules: [MissionControlColorRule]
    var defaultColor: MissionControlColor
    var tintOpacity: Double
    var showsSpaceAccents: Bool
    var spaceAccents: [String: MissionControlColor]

    init(
        isEnabled: Bool = true,
        autoAssignCategories: Bool = true,
        rules: [MissionControlColorRule] = [],
        defaultColor: MissionControlColor = .neutral,
        tintOpacity: Double = 0.08,
        showsSpaceAccents: Bool = true,
        spaceAccents: [String: MissionControlColor] = [:]
    ) {
        self.isEnabled = isEnabled
        self.autoAssignCategories = autoAssignCategories
        self.rules = rules
        self.defaultColor = defaultColor
        self.tintOpacity = min(max(tintOpacity, 0), 0.5)
        self.showsSpaceAccents = showsSpaceAccents
        self.spaceAccents = spaceAccents
    }

    /// Custom bundle rules first, then category overrides, then the auto-assigned category colour,
    /// then the neutral default: exactly the `custom > app > category > default` order the pane
    /// documents.
    func color(forBundleID bundleID: String?, category: MissionControlAppCategory) -> MissionControlColor {
        guard isEnabled else { return defaultColor }
        let bundleRule = rules.first {
            if case .bundleID = $0.match { return $0.matches(bundleID: bundleID, category: category) }
            return false
        }
        if let bundleRule { return bundleRule.color }
        if let categoryRule = rules.first(where: { $0.matches(bundleID: bundleID, category: category) }) {
            return categoryRule.color
        }
        return autoAssignCategories ? category.defaultColor : defaultColor
    }

    /// The wash under a thumbnail. A rule's own category wash wins; otherwise the shared opacity.
    func tint(forBundleID bundleID: String?, category: MissionControlAppCategory) -> Double {
        guard isEnabled else { return 0 }
        if color(forBundleID: bundleID, category: category) != defaultColor || autoAssignCategories {
            return autoAssignCategories ? max(tintOpacity, category.defaultTintOpacity) : tintOpacity
        }
        return tintOpacity
    }

    func accent(forSpaceID spaceID: String) -> MissionControlColor? {
        guard isEnabled, showsSpaceAccents, !spaceID.isEmpty else { return nil }
        return spaceAccents[spaceID]
    }
}

struct MissionControlNaming: Codable, Equatable, Sendable {
    var spaceLabels: [String: String]
    var showsSpaceTitles: Bool
    var showsWindowBadges: Bool
    var showsAppIcon: Bool
    var showsWindowTitle: Bool
    /// Type-to-filter inside the overview: plain letters narrow the grid, Escape clears it.
    var filterEnabled: Bool

    init(
        spaceLabels: [String: String] = [:],
        showsSpaceTitles: Bool = true,
        showsWindowBadges: Bool = true,
        showsAppIcon: Bool = true,
        showsWindowTitle: Bool = true,
        filterEnabled: Bool = true
    ) {
        self.spaceLabels = spaceLabels
        self.showsSpaceTitles = showsSpaceTitles
        self.showsWindowBadges = showsWindowBadges
        self.showsAppIcon = showsAppIcon
        self.showsWindowTitle = showsWindowTitle
        self.filterEnabled = filterEnabled
    }

    /// The user's name for a Space, trimmed; `nil` means "no custom name" and the caller falls back
    /// to the numbered desktop title.
    func spaceLabel(forSpaceID spaceID: String) -> String? {
        guard let raw = spaceLabels[spaceID] else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "Coding · Desktop 2" when named, "Desktop 2" otherwise. `index` is the 1-based Mission Control
    /// position; the Space ID is the stable key that survives a reboot.
    func spaceTitle(forSpaceID spaceID: String, index: Int) -> String? {
        guard showsSpaceTitles else { return nil }
        let desktop = String(format: String(localized: "Desktop %lld"), index)
        guard let label = spaceLabel(forSpaceID: spaceID) else { return desktop }
        return "\(label) · \(desktop)"
    }

    /// The pill over a thumbnail: the document title with the app name, or whichever exists. Returns
    /// `nil` when the badge is off or both fields are empty, so the renderer draws nothing.
    func badgeTitle(app: String?, title: String?) -> String? {
        guard showsWindowBadges else { return nil }
        let app = app?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (showsAppIcon, showsWindowTitle) {
        case (true, true):
            if title.isEmpty { return app.isEmpty ? nil : app }
            return app.isEmpty ? title : "\(app) — \(title)"
        case (true, false):
            return app.isEmpty ? nil : app
        case (false, true):
            return title.isEmpty ? nil : title
        case (false, false):
            return nil
        }
    }
}

/// Type-to-filter: every whitespace-separated token must appear in the title or the app name, so
/// "saf docs" narrows to Safari windows rather than matching either word alone.
enum MissionControlFilter {
    static func matches(query: String, title: String?, app: String?) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let haystack = "\(title ?? "") \(app ?? "")".lowercased()
        return tokens.allSatisfy { haystack.contains($0) }
    }

    /// What the renderer draws: no query = everything at full opacity; a non-match dims.
    static func opacity(query: String, title: String?, app: String?) -> Double {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1 }
        return matches(query: trimmed, title: title, app: app) ? 1 : 0.28
    }
}

struct MissionControlFraming: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var showsFocusFrame: Bool
    var focusStyle: MissionControlBorderStyle
    var hoverStyle: MissionControlBorderStyle
    var showsGroupFrame: Bool
    var groupStyle: MissionControlBorderStyle
    var stateStyles: [MissionControlWindowState: MissionControlBorderStyle]

    init(
        isEnabled: Bool = true,
        showsFocusFrame: Bool = true,
        focusStyle: MissionControlBorderStyle = .solid,
        hoverStyle: MissionControlBorderStyle = .hairline,
        showsGroupFrame: Bool = false,
        groupStyle: MissionControlBorderStyle = .dashed,
        stateStyles: [MissionControlWindowState: MissionControlBorderStyle] = [
            .standard: .hairline, .minimized: .dashed, .hidden: .dashed, .fullscreen: .glow
        ]
    ) {
        self.isEnabled = isEnabled
        self.showsFocusFrame = showsFocusFrame
        self.focusStyle = focusStyle
        self.hoverStyle = hoverStyle
        self.showsGroupFrame = showsGroupFrame
        self.groupStyle = groupStyle
        self.stateStyles = stateStyles
    }

    /// Focused beats hovered beats the window's own state. A focused window whose focus frame is off
    /// still falls back to its state border, never to nothing, so a deliberate state border shows.
    func style(isFocused: Bool, isHovered: Bool, state: MissionControlWindowState) -> MissionControlBorderStyle {
        guard isEnabled else { return .none }
        if isFocused, showsFocusFrame { return focusStyle }
        if isHovered { return hoverStyle }
        return stateStyles[state] ?? .none
    }

    func groupBorder() -> MissionControlBorderStyle? {
        isEnabled && showsGroupFrame ? groupStyle : nil
    }
}

enum MissionControlWindowAction: String, Codable, CaseIterable, Sendable {
    case close, minimize, zoom, hide, quit

    var defaultKey: String {
        switch self {
        case .close: return "w"
        case .minimize: return "m"
        case .zoom: return "f"
        case .hide: return "h"
        case .quit: return "q"
        }
    }
}

struct MissionControlButtons: Codable, Equatable, Sendable {
    var visible: [MissionControlWindowAction: Bool]
    var showsOnHover: Bool

    init(
        visible: [MissionControlWindowAction: Bool] = Dictionary(
            uniqueKeysWithValues: MissionControlWindowAction.allCases.map { ($0, true) }
        ),
        showsOnHover: Bool = true
    ) {
        self.visible = visible
        self.showsOnHover = showsOnHover
    }

    func isVisible(_ action: MissionControlWindowAction) -> Bool {
        visible[action] ?? true
    }

    /// In the order the cluster draws them; hidden buttons are removed, not blanked.
    var shownActions: [MissionControlWindowAction] {
        MissionControlWindowAction.allCases.filter(isVisible)
    }
}

enum MissionControlModifier: String, Codable, CaseIterable, Sendable {
    case command, option, control, shift
}

struct MissionControlHoverKeys: Codable, Equatable, Sendable {
    var isEnabled: Bool
    var modifiers: Set<MissionControlModifier>
    var keys: [MissionControlWindowAction: String]

    init(
        isEnabled: Bool = true,
        modifiers: Set<MissionControlModifier> = [.command],
        keys: [MissionControlWindowAction: String] = Dictionary(
            uniqueKeysWithValues: MissionControlWindowAction.allCases.map { ($0, $0.defaultKey) }
        )
    ) {
        self.isEnabled = isEnabled
        self.modifiers = modifiers
        self.keys = keys
    }

    /// One character, lowercased. A key is only taken when the modifier set is exactly the configured
    /// one, so ⌘⇧W stays the app's own shortcut while ⌘W acts on the hovered window.
    func action(forKey key: String, modifiers: Set<MissionControlModifier>) -> MissionControlWindowAction? {
        guard isEnabled, modifiers == self.modifiers else { return nil }
        let pressed = key.lowercased()
        return keys.first { $0.value.lowercased() == pressed }?.key
    }
}

enum MissionControlMouseButton: String, Codable, CaseIterable, Sendable {
    case right, middle
}

struct MissionControlMouseBindings: Codable, Equatable, Sendable {
    enum Binding: String, Codable, CaseIterable, Sendable {
        case none, close, minimize, zoom, quit
    }

    var rightClick: Binding
    var middleClick: Binding

    init(rightClick: Binding = .none, middleClick: Binding = .none) {
        self.rightClick = rightClick
        self.middleClick = middleClick
    }

    func binding(for button: MissionControlMouseButton) -> Binding {
        button == .right ? rightClick : middleClick
    }

    func action(for button: MissionControlMouseButton) -> MissionControlWindowAction? {
        switch binding(for: button) {
        case .none: return nil
        case .close: return .close
        case .minimize: return .minimize
        case .zoom: return .zoom
        case .quit: return .quit
        }
    }
}

struct MissionControlActions: Codable, Equatable, Sendable {
    var buttons: MissionControlButtons
    var hoverKeys: MissionControlHoverKeys
    var mouse: MissionControlMouseBindings

    init(
        buttons: MissionControlButtons = MissionControlButtons(),
        hoverKeys: MissionControlHoverKeys = MissionControlHoverKeys(),
        mouse: MissionControlMouseBindings = MissionControlMouseBindings()
    ) {
        self.buttons = buttons
        self.hoverKeys = hoverKeys
        self.mouse = mouse
    }
}

enum MissionControlPermission: String, Codable, Sendable {
    case granted, denied, unknown, unsupported
}

enum MissionControlBlocker: String, Codable, Equatable, Sendable {
    case accessibility, screenRecording, detectionUnavailable
}

/// What the overlay can actually do right now. The pane and the stage render this instead of
/// assuming success: a missing permission names itself, and an unobservable Dock says so.
struct MissionControlReadiness: Codable, Equatable, Sendable {
    var accessibility: MissionControlPermission
    var screenRecording: MissionControlPermission
    var detection: MissionControlPermission

    static let unknown = MissionControlReadiness(
        accessibility: .unknown, screenRecording: .unknown, detection: .unknown
    )

    /// Only what an action needs blocks: labels, borders and AX actions work without Screen
    /// Recording, which merely enables the thumbnail wash, so it is reported, never fatal.
    var blocker: MissionControlBlocker? {
        if detection == .unsupported { return .detectionUnavailable }
        if accessibility == .denied { return .accessibility }
        return nil
    }

    var canTintThumbnails: Bool { screenRecording == .granted }

    var isReady: Bool { blocker == nil && accessibility == .granted && detection == .granted }
}

/// A window the overlay knows about, in screen coordinates (Mission Control's own thumbnails are
/// top-left origin, so callers convert once).
struct MissionControlWindowFrame: Identifiable, Equatable, Sendable {
    let id: UInt32
    let bundleID: String?
    let appName: String
    let title: String?
    let frame: CGRect
    let state: MissionControlWindowState
    let isFocused: Bool

    var category: MissionControlAppCategory { .inferred(fromBundleID: bundleID) }
}

/// Resolves the window under the pointer and the keyboard's next target. `windows` is front-to-back,
/// index 0 topmost, which is the order Mission Control draws its thumbnails in.
enum MissionControlTargetRanker {
    static func target(at point: CGPoint, in windows: [MissionControlWindowFrame]) -> MissionControlWindowFrame? {
        windows.first { $0.frame.contains(point) }
    }

    static func next(
        after current: MissionControlWindowFrame.ID?,
        step: Int,
        in windows: [MissionControlWindowFrame],
        visible: (MissionControlWindowFrame) -> Bool = { _ in true }
    ) -> MissionControlWindowFrame? {
        let candidates = windows.filter(visible)
        guard !candidates.isEmpty else { return nil }
        guard let current, let index = candidates.firstIndex(where: { $0.id == current }) else {
            return step < 0 ? candidates.last : candidates.first
        }
        let count = candidates.count
        let offset = ((index + step) % count + count) % count
        return candidates[offset]
    }
}

/// Everything the Mission Control section owns, persisted as four JSON blobs so a new field never
/// invalidates the others. Read on demand (session start, pane appearance), never polled.
struct MissionControlConfiguration: Codable, Equatable, Sendable {
    var naming: MissionControlNaming
    var framing: MissionControlFraming
    var colouring: MissionControlColouring
    var actions: MissionControlActions

    init(
        naming: MissionControlNaming = MissionControlNaming(),
        framing: MissionControlFraming = MissionControlFraming(),
        colouring: MissionControlColouring = MissionControlColouring(),
        actions: MissionControlActions = MissionControlActions()
    ) {
        self.naming = naming
        self.framing = framing
        self.colouring = colouring
        self.actions = actions
    }
}

enum MissionControlSettings {
    /// Posted when the section's master switch changes. The pane is dual-compiled (the test target
    /// has no session), so it announces the change instead of calling the App-only session.
    static let changedNotification = Notification.Name("com.katikati.missioncontrol.changed")

    static let enabledKey = "com.katikati.missioncontrol.enabled"
    static let namingKey = "com.katikati.missioncontrol.naming"
    static let framingKey = "com.katikati.missioncontrol.framing"
    static let colouringKey = "com.katikati.missioncontrol.colouring"
    static let actionsKey = "com.katikati.missioncontrol.actions"

    /// Off by default: the overlays only exist while the user asks for them, which keeps idle CPU at
    /// zero for every install that never opens the section.
    static func isEnabled(from defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> MissionControlConfiguration {
        func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
            guard let data = defaults.data(forKey: key) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        return MissionControlConfiguration(
            naming: decode(MissionControlNaming.self, key: namingKey) ?? MissionControlNaming(),
            framing: decode(MissionControlFraming.self, key: framingKey) ?? MissionControlFraming(),
            colouring: decode(MissionControlColouring.self, key: colouringKey) ?? MissionControlColouring(),
            actions: decode(MissionControlActions.self, key: actionsKey) ?? MissionControlActions()
        )
    }

    static func save(_ configuration: MissionControlConfiguration, in defaults: UserDefaults = .standard) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(configuration.naming) { defaults.set(data, forKey: namingKey) }
        if let data = try? encoder.encode(configuration.framing) { defaults.set(data, forKey: framingKey) }
        if let data = try? encoder.encode(configuration.colouring) { defaults.set(data, forKey: colouringKey) }
        if let data = try? encoder.encode(configuration.actions) { defaults.set(data, forKey: actionsKey) }
    }
}
