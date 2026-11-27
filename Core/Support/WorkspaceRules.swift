import Foundation

/// What a matching rule does with a window (W-2).
enum WorkspaceRuleAction: String, Codable, Equatable, Sendable, CaseIterable {
    /// Keep the window tiled even when the built-in float defaults or a window trait would float it.
    case tile
    /// Leave the window floating at its own frame, owned by the workspace where it first appeared.
    case float
    /// Float it and show it on every workspace of its display.
    case pin
    /// Send a new window to a workspace without following it.
    case route
    /// Never tile it, never own it, never move it.
    case ignore
}

/// How many windows of the matched application a `route` rule claims (W-2).
enum WorkspaceRuleScope: String, Codable, Equatable, Sendable {
    /// Only the application's first window; later ones stay on the active workspace.
    case first
    /// Every new window of the application.
    case all
}

/// One ordered rule. Every matcher present must match; the first matching rule wins (W-2).
struct WorkspaceRule: Codable, Equatable, Sendable {
    var bundleID: String?
    var title: String?
    var titleContains: String?
    var action: WorkspaceRuleAction
    /// Required for `route`, forbidden otherwise (same contract as spaceman's config).
    var workspace: WorkspaceID?
    var windows: WorkspaceRuleScope

    init(
        bundleID: String? = nil,
        title: String? = nil,
        titleContains: String? = nil,
        action: WorkspaceRuleAction,
        workspace: WorkspaceID? = nil,
        windows: WorkspaceRuleScope = .first
    ) {
        self.bundleID = bundleID
        self.title = title
        self.titleContains = titleContains
        self.action = action
        self.workspace = workspace
        self.windows = windows
    }

    /// A rule needs at least one matcher, a workspace if and only if it routes, and no scope key
    /// anywhere else. An invalid rule is reported by the settings editor instead of being guessed at.
    var isValid: Bool {
        let hasMatcher = !(bundleID ?? "").isEmpty || !(title ?? "").isEmpty || !(titleContains ?? "").isEmpty
        guard hasMatcher else { return false }
        switch action {
        case .route: return workspace != nil
        case .float, .tile, .pin, .ignore: return workspace == nil
        }
    }

    func matches(bundleID candidateBundleID: String?, title candidateTitle: String?) -> Bool {
        guard isValid else { return false }
        if let bundleID, !bundleID.isEmpty {
            guard candidateBundleID == bundleID else { return false }
        }
        if let title, !title.isEmpty {
            guard candidateTitle == title else { return false }
        }
        if let titleContains, !titleContains.isEmpty {
            guard let candidateTitle,
                  candidateTitle.range(of: titleContains, options: [.caseInsensitive]) != nil
            else { return false }
        }
        return true
    }

    /// One line of the rules text field: `com.foo`, `com.foo=float`, `com.foo=tile`,
    /// `com.foo=pin`, `com.foo=ignore`, `com.foo=route:2` / `com.foo=route:D`.
    /// A title matcher follows the bundle id after `|`: `com.foo|Preferences=float`,
    /// and a case-insensitive fragment follows `~`: `com.foo|~Work —=route:3`.
    /// A rule may also be title-only: `|~Zoom Meeting=pin`.
    static func parse(line rawLine: String) -> WorkspaceRule? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

        let matcher: String
        let rule: String
        if let equals = line.firstIndex(of: "=") {
            matcher = String(line[..<equals])
            rule = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        } else {
            matcher = line
            rule = "float"
        }

        var bundleID: String?
        var title: String?
        var titleContains: String?
        for (index, part) in matcher.split(separator: "|", omittingEmptySubsequences: false).enumerated() {
            let value = part.trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            if index == 0 {
                bundleID = value
            } else if value.hasPrefix("~") {
                titleContains = String(value.dropFirst())
            } else {
                title = value
            }
        }

        func makeRule(_ action: WorkspaceRuleAction, workspace: WorkspaceID? = nil, scope: WorkspaceRuleScope = .first) -> WorkspaceRule {
            WorkspaceRule(
                bundleID: bundleID,
                title: title,
                titleContains: titleContains,
                action: action,
                workspace: workspace,
                windows: scope
            )
        }

        switch rule {
        case "float": return makeRule(.float)
        case "tile": return makeRule(.tile)
        case "pin": return makeRule(.pin)
        case "ignore": return makeRule(.ignore)
        case "route", "": return nil
        default:
            guard rule.hasPrefix("route:") else { return nil }
            guard let workspace = WorkspaceID(token: String(rule.dropFirst("route:".count))) else { return nil }
            return makeRule(.route, workspace: workspace)
        }
    }

    /// The inverse of `parse`, in the same order the fields are read.
    var serialized: String {
        var matcher = bundleID ?? ""
        if let title { matcher += "|\(title)" }
        if let titleContains { matcher += "|~\(titleContains)" }
        switch action {
        case .route: return "\(matcher)=route:\(workspace?.token ?? "")"
        default: return "\(matcher)=\(action.rawValue)"
        }
    }
}

/// What should happen to one window, after the rule list has been consulted (W-2).
enum WorkspaceDisposition: Equatable, Sendable {
    /// Tile it, on the workspace it is already in (or the active one for a new window).
    case manage
    case float
    case pin
    case ignore
    case route(WorkspaceID)

    var workspace: WorkspaceID? {
        if case .route(let workspace) = self { return workspace }
        return nil
    }
}

/// The ordered rule list (W-2).
struct WorkspaceRules: Equatable, Sendable, Codable {
    var rules: [WorkspaceRule]

    init(rules: [WorkspaceRule] = []) {
        self.rules = rules
    }

    static let `default` = WorkspaceRules()

    /// First match wins. A window that matches nothing is managed normally, which is spaceman's rule
    /// and the only safe default: an unmatched window must keep behaving exactly as it did before
    /// workspaces existed.
    func disposition(bundleID: String?, title: String?) -> WorkspaceDisposition {
        for rule in rules where rule.matches(bundleID: bundleID, title: title) {
            switch rule.action {
            case .tile: return .manage
            case .float: return .float
            case .pin: return .pin
            case .ignore: return .ignore
            case .route:
                guard let workspace = rule.workspace else { continue }
                return .route(workspace)
            }
        }
        return .manage
    }

    /// Whether the matched rule claims *every* new window of the application, not only its first.
    func routesAllWindows(bundleID: String?, title: String?) -> Bool {
        for rule in rules where rule.matches(bundleID: bundleID, title: title) {
            guard rule.action == .route else { return false }
            return rule.windows == .all
        }
        return false
    }

    var serialized: String {
        rules.map(\.serialized).joined(separator: "\n")
    }

    /// Reads the rules text field. Lines that do not parse are dropped rather than guessed at; the
    /// editor shows the count so a typo is visible instead of silently ignored.
    static func parse(_ text: String) -> WorkspaceRules {
        WorkspaceRules(rules: text.split(whereSeparator: \.isNewline).compactMap { WorkspaceRule.parse(line: String($0)) })
    }

    /// One-way migration from the pre-workspace `TilingPolicy` text (W-2).
    ///
    /// The float list, the always-tile list and both become rules with the same effect, in the same
    /// order, so an existing configuration keeps behaving identically the first time workspaces are
    /// switched on. Display pinning has no rule action (a display is not a workspace), so
    /// `pinnedDisplays` stays in `TilingPolicy` and keeps being read by the engine.
    static func migrated(from policy: TilingPolicy) -> WorkspaceRules {
        var rules: [WorkspaceRule] = policy.floatingBundleIDs.sorted().map { WorkspaceRule(bundleID: $0, action: .float) }
        rules += policy.alwaysTileBundleIDs.sorted().map { WorkspaceRule(bundleID: $0, action: .tile) }
        return WorkspaceRules(rules: rules)
    }
}
