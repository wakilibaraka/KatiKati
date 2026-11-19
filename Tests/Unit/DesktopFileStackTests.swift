import XCTest

final class DesktopFileStackTests: XCTestCase {
    private func entry(_ name: String, isDirectory: Bool = false) -> FolderContentsLoader.Entry {
        FolderContentsLoader.Entry(
            url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: isDirectory),
            name: name,
            isDirectory: isDirectory,
            dateAdded: nil,
            dateModified: nil
        )
    }

    func testAutoClassifierCoversAllCategoriesAndCaseInsensitivity() {
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Report.PDF", isDirectory: false), .documents)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Shot.PNG", isDirectory: false), .images)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Clip.mov", isDirectory: false), .videos)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Track.mp3", isDirectory: false), .audio)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Bundle.zip", isDirectory: false), .archives)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "App.swift", isDirectory: false), .code)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Safari.app", isDirectory: true), .apps)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "Projects", isDirectory: true), .folders)
        XCTAssertEqual(DesktopAutoStackClassifier.category(forFileName: "blob.unknownext", isDirectory: false), .other)
    }

    func testAutoByKindGroupsPairsAndLeavesSingletonsInline() {
        let entries = [
            entry("a.png"),
            entry("b.jpg"),
            entry("notes.md"),
            entry("movie.mp4"),
            entry("clip.mov")
        ]
        let cells = DesktopStackProjection.project(entries: entries, mode: .autoByKind, manualStacks: [])
        XCTAssertEqual(cells.count, 3)
        guard case .stack(let images) = cells[0], case .stack(let videos) = cells[1], case .file(let singleton) = cells[2] else {
            return XCTFail("Expected images stack, videos stack, and singleton markdown file")
        }
        XCTAssertEqual(images.category, .images)
        XCTAssertEqual(images.entries.map(\.name), ["a.png", "b.jpg"])
        XCTAssertEqual(videos.category, .videos)
        XCTAssertEqual(videos.entries.map(\.name), ["movie.mp4", "clip.mov"])
        XCTAssertEqual(singleton.name, "notes.md")
    }

    func testManualStacksCreateMovePruneUngroupAndPreserveOfflineMembership() {
        var stacks = DesktopStackProjection.createStack(title: "Design", filenames: ["a.png", "b.png"], in: [])
        XCTAssertEqual(stacks.count, 1)
        let designID = stacks[0].id

        stacks = DesktopStackProjection.createStack(title: "Archive", filenames: ["b.png", "c.zip"], in: stacks)
        XCTAssertEqual(stacks.first { $0.id == designID }?.filenames, ["a.png"])
        XCTAssertEqual(stacks.count, 2)

        let archiveID = stacks[1].id
        stacks = DesktopStackProjection.addFiles(["a.png"], toStackID: archiveID, in: stacks)
        XCTAssertEqual(stacks.count, 1, "moving the last file out of Design auto-prunes it")
        XCTAssertEqual(stacks[0].filenames, ["b.png", "c.zip", "a.png"])

        // When c.zip is absent from directory entries, projection omits it without destroying stacks config.
        let projected = DesktopStackProjection.project(
            entries: [entry("a.png"), entry("b.png"), entry("extra.txt")],
            mode: .manual,
            manualStacks: stacks
        )
        guard case .stack(let archive) = projected[0], case .file(let extra) = projected[1] else {
            return XCTFail("Expected 1 manual stack + 1 loose file")
        }
        XCTAssertEqual(archive.entries.map(\.name), ["b.png", "a.png"])
        XCTAssertEqual(extra.name, "extra.txt")

        stacks = DesktopStackProjection.removeFiles(["a.png"], fromStackID: archiveID, in: stacks)
        XCTAssertEqual(stacks[0].filenames, ["b.png", "c.zip"])
        stacks = DesktopStackProjection.ungroup(stackID: archiveID, in: stacks)
        XCTAssertTrue(stacks.isEmpty)
    }

    func testPopoverLayoutMetricsModes() {
        let adaptiveSmall = DesktopStackPopoverLayout.metrics(itemCount: 4, mode: .adaptive)
        XCTAssertEqual(adaptiveSmall.columns, 2)
        let adaptiveLarge = DesktopStackPopoverLayout.metrics(itemCount: 24, mode: .adaptive)
        XCTAssertEqual(adaptiveLarge.columns, 5)
        XCTAssertEqual(DesktopStackPopoverLayout.metrics(itemCount: 2, mode: .grid3x3).columns, 3)
        XCTAssertEqual(DesktopStackPopoverLayout.metrics(itemCount: 2, mode: .grid5x5).columns, 5)
    }

    func testLegacyPhase60JSONDecodesCleanlyWithPhase61Defaults() throws {
        let legacyJSON = #"{"title":"Downloads","frame":{"x":10,"y":20,"width":280,"height":240}}"#
        let item = try JSONDecoder().decode(DesktopWidgetItem.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(item.title, "Downloads")
        XCTAssertEqual(item.stackGroupingMode, .none)
        XCTAssertEqual(item.stackDisplayMode, .adaptive)
        XCTAssertTrue(item.manualStacks.isEmpty)
        XCTAssertNil(item.tabGroupID)
        XCTAssertEqual(item.tabOrder, 0)
        XCTAssertTrue(item.isActiveTab)
    }
}
