import XCTest
@testable import KatiKati

final class WidgetPresetTests: XCTestCase {
    func testBuiltInsAreStableAndFullIsDefault() {
        XCTAssertEqual(WidgetPresets.builtIns.map(\.id),
                       ["builtin.minimal", "builtin.commuter", "builtin.music", "builtin.focus", "builtin.full", "builtin.agenda", "builtin.monitor"])
        XCTAssertEqual(WidgetPresets.builtIns.first { $0.id == "builtin.full" }?.layout, .default)
        XCTAssertTrue(WidgetPresets.builtIns.allSatisfy(\.isBuiltIn))
    }

    func testBuiltInsKeepAppsVisibleAndClockShown() {
        for preset in WidgetPresets.builtIns {
            XCTAssertTrue(preset.layout.visibleOrder.contains(.apps), preset.id)
            XCTAssertTrue(preset.layout.visibleOrder.contains(.clock), preset.id)
        }
        let music = WidgetPresets.builtIns[2].layout
        XCTAssertEqual(WidgetPresets.builtIns[3].layout.visibleOrder, [.launcher, .apps, .media, .utilities, .clock])
        XCTAssertEqual(music.instance(for: .media).size, .large)
        XCTAssertFalse(music.visibleOrder.contains(.weather))
    }

    func testSaveReplacesSameNameRejectsBlankAndRemoves() {
        var n = 0
        let id = { n += 1; return "u\(n)" }
        var list = WidgetPresets.saving(.default, as: "  Work ", into: [], makeID: id)
        XCTAssertEqual(list.map(\.name), ["Work"])
        let hidden = WidgetLayout.default.updating(.weather) { $0.isVisible = false }
        list = WidgetPresets.saving(hidden, as: "Work", into: list, makeID: id)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].layout, hidden)
        XCTAssertEqual(WidgetPresets.saving(.default, as: "   ", into: list, makeID: id), list)
        XCTAssertTrue(WidgetPresets.removing(id: "u1", from: list).isEmpty)
    }

    func testCodableRoundTripDropsBuiltInIDs() {
        let user = WidgetPreset(id: "u1", name: "A", layout: .default)
        let data = WidgetPresets.encode([user, WidgetPresets.builtIns[0]])
        XCTAssertEqual(WidgetPresets.decode(data), [user])
        XCTAssertEqual(WidgetPresets.decode(Data("x".utf8)), [])
    }
}

/// Slice G: the catalog reads the existing `show…` preferences and the presets, never a copy of them.
final class WidgetCatalogTests: XCTestCase {
    private var weatherHidden: WidgetLayout {
        WidgetLayout.default.updating(.weather) { $0.isVisible = false }
    }

    private func targetKind(_ items: [WidgetCatalogItem], _ predicate: (WidgetCatalogTarget) -> Bool) -> Int {
        items.filter { predicate($0.target) }.count
    }

    func testCatalogCoversEveryModuleUtilityAndPreset() {
        let user = WidgetPreset(id: "u1", name: "Mine", layout: weatherHidden)
        let items = WidgetCatalog.items(layout: .default, utilities: WidgetCatalogUtilities(), userPresets: [user])
        // Every module but Apps: Apps is fixed on the bar and has no visibility switch.
        XCTAssertEqual(targetKind(items) { if case .section = $0 { return true } else { return false } },
                       BarSection.canonicalOrder.count - 1)
        XCTAssertFalse(items.contains { $0.target == .section(.apps) })
        XCTAssertEqual(targetKind(items) { if case .utility = $0 { return true } else { return false } }, 4)
        XCTAssertEqual(targetKind(items) { if case .preset = $0 { return true } else { return false } },
                       WidgetPresets.builtIns.count + 1)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        XCTAssertTrue(items.allSatisfy { !$0.title.isEmpty && !$0.keywords.isEmpty && !$0.prefsKey.isEmpty })
        XCTAssertEqual(items.first { $0.target == .section(.weather) }?.prefsKey, WidgetLayout.defaultsKey)
        XCTAssertEqual(items.first { $0.target == .utility(.shelf) }?.prefsKey, "com.katikati.showShelf")
        XCTAssertEqual(items.first { $0.target == .preset("builtin.full") }?.prefsKey, WidgetPresets.defaultsKey)
    }

    func testInstalledReadsTheExistingPreferences() {
        let utilities = WidgetCatalogUtilities(shelf: false, trash: true, drawer: false, backgroundApps: true)
        let items = WidgetCatalog.items(layout: weatherHidden, utilities: utilities, userPresets: [])
        XCTAssertEqual(items.first { $0.target == .section(.weather) }?.isInstalled, false)
        XCTAssertEqual(items.first { $0.target == .section(.clock) }?.isInstalled, true)
        XCTAssertEqual(items.first { $0.target == .utility(.shelf) }?.isInstalled, false)
        XCTAssertEqual(items.first { $0.target == .utility(.trash) }?.isInstalled, true)
        // A preset is installed when the bar already looks like it: "Full" is the default layout.
        XCTAssertEqual(items.first { $0.target == .preset("builtin.full") }?.isInstalled, false)
        let defaultItems = WidgetCatalog.items(layout: .default, utilities: utilities, userPresets: [])
        XCTAssertEqual(defaultItems.first { $0.target == .preset("builtin.full") }?.isInstalled, true)
        XCTAssertEqual(defaultItems.first { $0.target == .preset("builtin.minimal") }?.isInstalled, false)
    }

    func testSearchMatchesTitlesAndKeywordsAndRanksPrefixesFirst() {
        let items = WidgetCatalog.items(layout: .default, utilities: WidgetCatalogUtilities(), userPresets: [])
        XCTAssertEqual(WidgetCatalog.search("", in: items), items)
        XCTAssertEqual(WidgetCatalog.search("   ", in: items), items)
        XCTAssertEqual(WidgetCatalog.search("  WEAther ", in: items).first?.target, .section(.weather))
        XCTAssertEqual(WidgetCatalog.search("cpu", in: items).map(\.target), [.section(.system)])
        XCTAssertEqual(WidgetCatalog.search("trash", in: items).first?.target, .utility(.trash))
        XCTAssertEqual(WidgetCatalog.search("airpods", in: items).map(\.target), [.section(.devices)])
        // "widget" prefix-matches the Widgets module before the presets whose keywords list it.
        XCTAssertEqual(WidgetCatalog.search("widget", in: items).first?.target, .section(.widgets))
        XCTAssertTrue(WidgetCatalog.search("zzzz", in: items).isEmpty)
    }

    func testSearchFindsPresetsByTheirKeywords() {
        let user = WidgetPreset(id: "u1", name: "Mine", layout: weatherHidden)
        let items = WidgetCatalog.items(layout: .default, utilities: WidgetCatalogUtilities(), userPresets: [user])
        // A user preset is found by the name it was saved under, and every row for "preset" is a preset.
        XCTAssertEqual(WidgetCatalog.search("mine", in: items).map(\.target), [.preset("u1")])
        XCTAssertTrue(WidgetCatalog.search("preset", in: items).allSatisfy { if case .preset = $0.target { return true } else { return false } })
        XCTAssertTrue(WidgetCatalog.search("agenda", in: items).contains { $0.target == .preset("builtin.agenda") })
    }

    func testActionsInstallHideAndRemove() {
        func item(_ target: WidgetCatalogTarget, installed: Bool, userPreset: Bool = false) -> WidgetCatalogItem {
            WidgetCatalogItem(id: "x", title: "X", keywords: ["x"], prefsKey: "k", isInstalled: installed, target: target)
        }
        XCTAssertEqual(WidgetCatalog.actions(for: item(.section(.weather), installed: true)), [.hide])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.section(.weather), installed: false)), [.install])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.utility(.shelf), installed: true)), [.hide])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.preset("builtin.full"), installed: true)), [])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.preset("builtin.full"), installed: false)), [.install])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.preset("u1"), installed: false)), [.install, .remove])
        XCTAssertEqual(WidgetCatalog.actions(for: item(.preset("u1"), installed: true)), [.remove])
        XCTAssertTrue(item(.preset("u1"), installed: false).isRemovable)
        XCTAssertFalse(item(.preset("builtin.full"), installed: false).isRemovable)
        XCTAssertFalse(item(.preset("u1"), installed: false).isHidable)
    }

    /// The utility keys are literals in `WidgetCatalogUtility`; the store writes the same ones.
    @MainActor
    func testUtilityPrefsKeysAreTheKeysTheStoreWrites() {
        let suite = "katikati.widgetCatalog.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppSettingsStore(defaults: defaults)
        for utility in WidgetCatalogUtility.allCases {
            let initial = store.showShelf
            let flipped = !WidgetCatalogUtilities()[utility]
            switch utility {
            case .shelf: store.setShowShelf(flipped)
            case .trash: store.setShowTrash(flipped)
            case .drawer: store.setShowDrawer(flipped)
            case .backgroundApps: store.setShowBackgroundApps(flipped)
            }
            XCTAssertEqual(defaults.object(forKey: utility.prefsKey) as? Bool, flipped, utility.rawValue)
            XCTAssertEqual(AppSettingsStore(defaults: defaults).showShelf, utility == .shelf ? flipped : initial)
        }
    }
}
