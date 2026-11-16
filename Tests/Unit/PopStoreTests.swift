import XCTest
@testable import KatiKati

@MainActor
final class PopStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        TestDefaults.make("test-pop-store", for: self)
    }

    func testFirstLaunchMigratesLegacyDrawerInDisplayOrderAndKeepsLegacyKeys() {
        let defaults = makeDefaults()
        defaults.set(["com.a", "com.b", "com.c"], forKey: "drawerBundleIDs")
        defaults.set(["com.c", "com.a"], forKey: "drawerDisplayOrder")

        let store = PopStore(defaults: defaults)

        XCTAssertEqual(store.items, [.app("com.c"), .app("com.a"), .app("com.b")])
        XCTAssertEqual(defaults.stringArray(forKey: "drawerBundleIDs"), ["com.a", "com.b", "com.c"])
    }

    func testStoredItemsWinOverLegacyKeysOnLaterLaunches() {
        let defaults = makeDefaults()
        let store = PopStore(defaults: defaults)
        store.add([.folder("/Users/me/Projects")])
        defaults.set(["com.late"], forKey: "drawerBundleIDs")

        XCTAssertEqual(PopStore(defaults: defaults).items, [.folder("/Users/me/Projects")])
    }

    func testAddRemoveReorderPersist() {
        let defaults = makeDefaults()
        let store = PopStore(defaults: defaults)
        store.add([.app("com.a"), .file("/x.pdf"), .folder("/y")])
        store.reorder(draggedID: PopItem.folder("/y").id, relativeTo: PopItem.app("com.a").id, after: false)
        store.remove(PopItem.file("/x.pdf").id)

        XCTAssertEqual(PopStore(defaults: defaults).items, [.folder("/y"), .app("com.a")])
    }

    func testViewModeAndThemePersistAcrossLaunches() {
        let defaults = makeDefaults()
        let store = PopStore(defaults: defaults)
        XCTAssertEqual(store.viewMode, .grid)
        XCTAssertNil(store.theme)

        store.setViewMode(.tiles)
        store.setTheme(.deepOcean)

        let reloaded = PopStore(defaults: defaults)
        XCTAssertEqual(reloaded.viewMode, .tiles)
        XCTAssertEqual(reloaded.theme, .deepOcean)

        // Match App clears the override instead of storing a copy of it.
        reloaded.setTheme(nil)
        XCTAssertNil(PopStore(defaults: defaults).theme)
    }

    func testAddPastCapacityReportsRejectedCount() {
        let store = PopStore(defaults: makeDefaults())
        store.add((0..<26).map { PopItem.file("/f\($0)") })

        XCTAssertTrue(store.isFull)
        XCTAssertEqual(store.items.count, PopPolicy.capacity)
        XCTAssertEqual(store.lastRejectedForCapacity, 1)
    }

    // MARK: - Slice D-1 Pure Layout & Drop Policy Tests

    func testDrawerLayoutStyleTogglesBetweenGridAndList() {
        XCTAssertEqual(DrawerLayoutStyle.grid.toggled, .list)
        XCTAssertEqual(DrawerLayoutStyle.list.toggled, .grid)
    }

    func testDrawerItemPayloadClassifiesAppsFilesFoldersAndShortcuts() {
        let appURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let folderURL = URL(fileURLWithPath: "/Users/me/Projects", isDirectory: true)
        let fileURL = URL(fileURLWithPath: "/Users/me/notes.txt")
        let emptyURL = URL(string: "empty://")!

        XCTAssertEqual(DrawerItemPayload.classify(url: appURL, isDirectory: true, isApplication: true, bundleID: "com.apple.Safari")?.popItem,
                       .app("com.apple.Safari"))
        // Missing bundleID degrades safely to a file item rather than a browsable folder.
        XCTAssertEqual(DrawerItemPayload.classify(url: appURL, isDirectory: true, isApplication: true, bundleID: nil)?.popItem,
                       .file("/Applications/Safari.app"))
        XCTAssertEqual(DrawerItemPayload.classify(url: folderURL, isDirectory: true, isApplication: false, bundleID: nil)?.popItem,
                       .folder("/Users/me/Projects"))
        XCTAssertEqual(DrawerItemPayload.classify(url: fileURL, isDirectory: false, isApplication: false, bundleID: nil)?.popItem,
                       .file("/Users/me/notes.txt"))
        XCTAssertEqual(DrawerItemPayload.customShortcut(name: "Docs", target: folderURL).popItem, .folder("/Users/me/Projects"))
        XCTAssertNil(DrawerItemPayload.customShortcut(name: "Empty", target: emptyURL).popItem)
        XCTAssertNil(DrawerItemPayload.classify(url: emptyURL, isDirectory: false, isApplication: false, bundleID: nil))
    }

    func testDrawerDropTargetPolicyPreventsDuplicatesAndEnforcesCapacity() {
        let existing: [PopItem] = [.app("com.apple.Safari"), .file("/Users/me/a.txt")]
            + (0..<21).map { PopItem.file("/Users/me/fill\($0).txt") }
        let payloads: [DrawerItemPayload] = [
            .application(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari"),
            .file(url: URL(fileURLWithPath: "/Users/me/new1.txt")),
            .file(url: URL(fileURLWithPath: "/Users/me/new1.txt")),
            .folder(url: URL(fileURLWithPath: "/Users/me/Docs", isDirectory: true)),
            .file(url: URL(fileURLWithPath: "/Users/me/overflow.txt")),
            .customShortcut(name: "Empty", target: URL(string: "empty://")!)
        ]

        let result = DrawerDropTargetPolicy.validateDrop(payloads: payloads, existing: existing)
        XCTAssertEqual(result.accepted, [.file("/Users/me/new1.txt"), .folder("/Users/me/Docs")])
        XCTAssertEqual(result.duplicatesSkipped, 2)
        XCTAssertEqual(result.rejectedForCapacity, 1)
        XCTAssertEqual(result.invalidSkipped, 1)
    }

    func testDrawerDropTargetPolicyGroupingAndSorting() {
        let items: [PopItem] = [.file("/tmp/zeta.txt"), .app("com.b.app"), .folder("/tmp/Work"), .app("com.a.app"), .folder("/tmp/Archive")]
        let names: (PopItem) -> String = { item in
            switch item.kind {
            case .app: return item.reference == "com.a.app" ? "Alpha" : "Beta"
            case .folder, .file: return URL(fileURLWithPath: item.reference).lastPathComponent
            }
        }
        let grouped = DrawerDropTargetPolicy.groupItems(items)
        XCTAssertEqual(grouped.folders, [.folder("/tmp/Work"), .folder("/tmp/Archive")])
        XCTAssertEqual(grouped.apps, [.app("com.b.app"), .app("com.a.app")])
        XCTAssertEqual(grouped.files, [.file("/tmp/zeta.txt")])

        XCTAssertEqual(DrawerDropTargetPolicy.sort(items, by: .nameAscending, displayName: names),
                       [.app("com.a.app"), .folder("/tmp/Archive"), .app("com.b.app"), .folder("/tmp/Work"), .file("/tmp/zeta.txt")])
        XCTAssertEqual(DrawerDropTargetPolicy.sort(items, by: .groupedFoldersFirst, displayName: names),
                       [.folder("/tmp/Archive"), .folder("/tmp/Work"), .app("com.a.app"), .app("com.b.app"), .file("/tmp/zeta.txt")])
    }

    func testDrawerLayoutMathAdaptiveListWidthAndGridColumns() {
        let shortWidth = DrawerLayoutMath.adaptiveListCellWidth(labels: ["OpenCode", "TwinDesk"])
        XCTAssertEqual(shortWidth, DrawerLayoutMath.listMinWidth)
        XCTAssertLessThan(shortWidth, 300)

        XCTAssertEqual(DrawerLayoutMath.adaptiveListCellWidth(labels: [String(repeating: "A", count: 60)]),
                       DrawerLayoutMath.listMaxWidth)

        let mediumWidth = DrawerLayoutMath.adaptiveListCellWidth(labels: [String(repeating: "M", count: 30)])
        XCTAssertGreaterThan(mediumWidth, DrawerLayoutMath.listMinWidth)
        XCTAssertLessThan(mediumWidth, DrawerLayoutMath.listMaxWidth)

        let limits = StackGridLayout.Limits(maxColumns: 7, nominalRows: 4, fitRows: 5, fitRowsWithNote: 5)
        XCTAssertEqual(DrawerLayoutMath.resolveLayout(itemCount: 10, style: .list, limits: limits, hasNote: false),
                       .init(columns: 1, visibleRows: 8, scrolls: true))
        XCTAssertEqual(DrawerLayoutMath.resolveLayout(itemCount: 9, style: .grid, limits: limits, hasNote: false),
                       .init(columns: 3, visibleRows: 3, scrolls: false))
        XCTAssertEqual(DrawerLayoutMath.resolveLayout(itemCount: 0, style: .list, limits: limits, hasNote: true),
                       .init(columns: StackGridLayout.noteMinColumns, visibleRows: 0, scrolls: false))
    }
}
