import Foundation

/// A named widget arrangement (Phase 10a-5). Built-ins are code; user presets are persisted.
struct WidgetPreset: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var layout: WidgetLayout

    var isBuiltIn: Bool { id.hasPrefix(WidgetPresets.builtInPrefix) }

    /// Localized title for built-ins (literal keys so the localization gate sees them); user presets show their name.
    var localizedTitle: String {
        switch id {
        case "builtin.minimal": return String(localized: "Minimal")
        case "builtin.commuter": return String(localized: "Commuter")
        case "builtin.music": return String(localized: "Music")
        case "builtin.focus": return String(localized: "Focus")
        case "builtin.full": return String(localized: "Full")
        case "builtin.agenda": return String(localized: "Agenda")
        case "builtin.monitor": return String(localized: "Monitor")
        default: return name
        }
    }
}

enum WidgetPresets {
    static let builtInPrefix = "builtin."
    static let defaultsKey = "com.katikati.widgets.presets.v1"

    private static func layout(hidden: Set<BarSection> = [], stacks: [BarSection: [BarSection]] = [:],
                               sizes: [BarSection: WidgetSize] = [:]) -> WidgetLayout {
        WidgetLayout(instances: BarSection.canonicalOrder.map {
            WidgetInstance(section: $0, size: sizes[$0] ?? .medium, isVisible: !hidden.contains($0) && !$0.startsHidden,
                           stack: stacks[$0])
        })
    }

    /// `name` is the English key; the UI maps ids to localized titles.
    static let builtIns: [WidgetPreset] = [
        WidgetPreset(id: "builtin.minimal", name: "Minimal",
                     layout: layout(hidden: [.weather, .media, .widgets, .dictionary, .terminal])),
        WidgetPreset(id: "builtin.commuter", name: "Commuter",
                     layout: layout(hidden: [.media, .widgets, .dictionary, .terminal], sizes: [.weather: .small])),
        WidgetPreset(id: "builtin.music", name: "Music",
                     layout: layout(hidden: [.weather, .widgets, .dictionary, .terminal], sizes: [.media: .large, .clock: .small])),
        WidgetPreset(id: "builtin.focus", name: "Focus",
                     layout: layout(hidden: [.weather, .widgets, .dictionary, .terminal], sizes: [.media: .medium, .clock: .small])),
        WidgetPreset(id: "builtin.full", name: "Full", layout: .default),
        WidgetPreset(id: "builtin.agenda", name: "Agenda",
                     layout: layout(hidden: [.media, .widgets, .dictionary, .terminal], stacks: [.clock: [.clock, .calendar, .devices]],
                                    sizes: [.weather: .small])),
        WidgetPreset(id: "builtin.monitor", name: "Monitor",
                     layout: layout(hidden: [.media, .widgets, .dictionary, .terminal], stacks: [.clock: [.clock, .system, .devices]],
                                    sizes: [.weather: .small])),
    ]

    /// Appends a user preset; a blank name is rejected, a duplicate name replaces that preset.
    static func saving(_ layout: WidgetLayout, as name: String, into list: [WidgetPreset],
                       makeID: () -> String = { UUID().uuidString }) -> [WidgetPreset] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return list }
        var result = list
        if let index = result.firstIndex(where: { $0.name == trimmed }) {
            result[index].layout = layout
        } else {
            result.append(WidgetPreset(id: makeID(), name: trimmed, layout: layout))
        }
        return result
    }

    static func removing(id: String, from list: [WidgetPreset]) -> [WidgetPreset] {
        list.filter { $0.id != id }
    }

    static func decode(_ data: Data?) -> [WidgetPreset] {
        guard let data, let list = try? JSONDecoder().decode([WidgetPreset].self, from: data) else { return [] }
        return list.filter { !$0.isBuiltIn }
    }

    static func encode(_ list: [WidgetPreset]) -> Data? { try? JSONEncoder().encode(list) }
}

// MARK: - Slice G: the widget catalog (OpenTaskbar behavior, MIT — see NOTICE)

/// One apps-strip utility the catalog can install or hide. Every case is an existing `show…` preference, so
/// the catalog never owns a second copy of the value: `prefsKey` is the `UserDefaults` key the store writes.
enum WidgetCatalogUtility: String, CaseIterable, Sendable, Equatable {
    case shelf
    case trash
    case drawer
    case backgroundApps

    /// The literals mirror `AppSettingsStore.Keys` (private there); a store round-trip test pins the pair.
    var prefsKey: String {
        switch self {
        case .shelf: return "com.katikati.showShelf"
        case .trash: return "com.katikati.showTrash"
        case .drawer: return "com.katikati.showDrawer"
        case .backgroundApps: return "com.katikati.showBackgroundApps"
        }
    }

    var localizedTitle: String {
        switch self {
        case .shelf: return String(localized: "Shelf")
        case .trash: return String(localized: "Trash")
        case .drawer: return String(localized: "Drawer")
        case .backgroundApps: return String(localized: "Background Apps")
        }
    }

    /// English search terms. The localized title is matched by `WidgetCatalog.search` as well.
    var keywords: [String] {
        switch self {
        case .shelf: return ["shelf", "files", "tray"]
        case .trash: return ["trash", "bin", "delete"]
        case .drawer: return ["drawer", "folder", "apps"]
        case .backgroundApps: return ["background", "running", "hidden"]
        }
    }
}

/// The live state of the four utility preferences; the view fills it from the store, tests fill it by hand.
struct WidgetCatalogUtilities: Equatable, Sendable {
    var shelf = true
    var trash = true
    var drawer = true
    var backgroundApps = true

    subscript(utility: WidgetCatalogUtility) -> Bool {
        switch utility {
        case .shelf: return shelf
        case .trash: return trash
        case .drawer: return drawer
        case .backgroundApps: return backgroundApps
        }
    }
}

/// What a catalog row acts on. The section and utility cases edit the preference the dock already reads; the
/// preset case applies or deletes a `WidgetPreset`.
enum WidgetCatalogTarget: Equatable, Sendable {
    case section(BarSection)
    case utility(WidgetCatalogUtility)
    case preset(String)
}

/// One searchable row: the five fields the catalog is made of, plus the target the row's buttons act on.
struct WidgetCatalogItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var keywords: [String]
    /// The `UserDefaults` key the row's installed state is stored under.
    var prefsKey: String
    var isInstalled: Bool
    var target: WidgetCatalogTarget

    /// Only user presets can be removed; built-ins are code.
    var isRemovable: Bool {
        guard case .preset(let id) = target else { return false }
        return !id.hasPrefix(WidgetPresets.builtInPrefix)
    }

    /// A preset is applied, not hidden — hiding belongs to the widgets it arranged.
    var isHidable: Bool {
        if case .preset = target { return false }
        return true
    }
}

enum WidgetCatalogAction: String, CaseIterable, Sendable, Equatable {
    case install
    case hide
    case remove
}

/// Slice G: a pure catalog over the widgets the bar can show. Modules come from `WidgetLayout`, utilities from
/// the four `show…` preferences, presets from `WidgetPresets`. Search is case-insensitive over the title (both
/// the English keyword and the localized one) and the English keywords, with prefix hits first.
enum WidgetCatalog {
    static func items(layout: WidgetLayout, utilities: WidgetCatalogUtilities,
                      userPresets: [WidgetPreset]) -> [WidgetCatalogItem] {
        var items: [WidgetCatalogItem] = []
        for section in BarSection.canonicalOrder where section != .apps {
            items.append(WidgetCatalogItem(
                id: "section.\(section.rawValue)",
                title: localizedTitle(for: section),
                keywords: keywords(for: section) + [section.rawValue],
                prefsKey: WidgetLayout.defaultsKey,
                isInstalled: layout.instance(for: section).isVisible,
                target: .section(section)))
        }
        for utility in WidgetCatalogUtility.allCases {
            items.append(WidgetCatalogItem(
                id: "utility.\(utility.rawValue)",
                title: utility.localizedTitle,
                keywords: utility.keywords + [utility.rawValue],
                prefsKey: utility.prefsKey,
                isInstalled: utilities[utility],
                target: .utility(utility)))
        }
        for preset in WidgetPresets.builtIns + userPresets {
            items.append(WidgetCatalogItem(
                id: "preset.\(preset.id)",
                title: preset.localizedTitle,
                keywords: ["preset", "layout", preset.name] + preset.layout.visibleOrder.map(\.rawValue),
                prefsKey: WidgetPresets.defaultsKey,
                // A preset is installed when the bar already looks like it — that is what "apply" makes true.
                isInstalled: preset.layout == layout,
                target: .preset(preset.id)))
        }
        return items
    }

    /// Rows for a query. An empty query returns the whole catalog in build order; otherwise title and keyword
    /// hits, prefix matches before the rest, each group in build order.
    static func search(_ query: String, in items: [WidgetCatalogItem]) -> [WidgetCatalogItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return items }
        let ranked: [(Int, Int, WidgetCatalogItem)] = items.enumerated().compactMap { index, item in
            let title = item.title.lowercased()
            let matched = title.contains(needle) || item.keywords.contains { $0.lowercased().contains(needle) }
            guard matched else { return nil }
            return (title.hasPrefix(needle) ? 0 : 1, index, item)
        }
        return ranked.sorted { left, right in
            left.0 != right.0 ? left.0 < right.0 : left.1 < right.1
        }.map(\.2)
    }

    /// The buttons a row offers: hide what is installed, install what is not, and let user presets be removed.
    static func actions(for item: WidgetCatalogItem) -> [WidgetCatalogAction] {
        if case .preset = item.target {
            if item.isInstalled { return item.isRemovable ? [.remove] : [] }
            return item.isRemovable ? [.install, .remove] : [.install]
        }
        return item.isInstalled ? [.hide] : [.install]
    }

    static func localizedTitle(for section: BarSection) -> String {
        switch section {
        case .launcher: return String(localized: "Launcher")
        case .weather: return String(localized: "Weather")
        case .apps: return String(localized: "Apps")
        case .media: return String(localized: "Now Playing")
        case .clock: return String(localized: "Clock")
        case .calendar: return String(localized: "Calendar")
        case .system: return String(localized: "System")
        case .devices: return String(localized: "Devices")
        case .drives: return String(localized: "Drives")
        case .dictionary: return String(localized: "Dictionary")
        case .terminal: return String(localized: "Terminal")
        case .widgets: return String(localized: "Widgets")
        }
    }

    /// English search terms per module; the raw value and the localized title are matched too.
    static func keywords(for section: BarSection) -> [String] {
        switch section {
        case .launcher: return ["launcher", "fab", "start"]
        case .weather: return ["weather", "temperature", "forecast", "degrees"]
        case .apps: return ["apps", "windows", "chips"]
        case .media: return ["media", "music", "player", "now playing"]
        case .clock: return ["clock", "time", "date"]
        case .calendar: return ["calendar", "events", "meetings", "agenda"]
        case .system: return ["system", "cpu", "memory", "ram", "ssd", "sparkline"]
        case .devices: return ["devices", "battery", "airpods", "mouse", "keyboard"]
        case .drives: return ["drives", "disk", "storage", "space"]
        case .dictionary: return ["dictionary", "word", "define", "lookup"]
        case .terminal: return ["terminal", "shell", "console"]
        case .widgets: return ["widgets", "stack", "smart stack"]
        }
    }
}
