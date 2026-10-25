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
                     layout: layout(hidden: [.weather, .media, .widgets])),
        WidgetPreset(id: "builtin.commuter", name: "Commuter",
                     layout: layout(hidden: [.media, .widgets], sizes: [.weather: .small])),
        WidgetPreset(id: "builtin.music", name: "Music",
                     layout: layout(hidden: [.weather, .widgets], sizes: [.media: .large, .clock: .small])),
        WidgetPreset(id: "builtin.focus", name: "Focus",
                     layout: layout(hidden: [.weather, .widgets], sizes: [.media: .medium, .clock: .small])),
        WidgetPreset(id: "builtin.full", name: "Full", layout: .default),
        WidgetPreset(id: "builtin.agenda", name: "Agenda",
                     layout: layout(hidden: [.media, .widgets], stacks: [.clock: [.clock, .calendar, .devices]],
                                    sizes: [.weather: .small])),
        WidgetPreset(id: "builtin.monitor", name: "Monitor",
                     layout: layout(hidden: [.media, .widgets], stacks: [.clock: [.clock, .system, .devices]],
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
