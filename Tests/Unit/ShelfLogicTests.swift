import XCTest

/// 中转格列表操作的纯函数（ShelfStore 静态逻辑,不碰 UserDefaults/文件系统）。
final class ShelfLogicTests: XCTestCase {
    func testStashingPrependsNewestFirst() {
        let result = ShelfStore.stashing(["/old"], adding: ["/new1", "/new2"])
        XCTAssertEqual(result, ["/new1", "/new2", "/old"])
    }

    func testStashingDedupesIncomingAndDropsEmpty() {
        let result = ShelfStore.stashing([], adding: ["/a", "/a", "", "/b"])
        XCTAssertEqual(result, ["/a", "/b"])
    }

    func testStashingMovesExistingToFront() {
        let result = ShelfStore.stashing(["/a", "/b", "/c"], adding: ["/c"])
        XCTAssertEqual(result, ["/c", "/a", "/b"])
    }

    func testStashingNothingReturnsCurrent() {
        let result = ShelfStore.stashing(["/a"], adding: [""])
        XCTAssertEqual(result, ["/a"])
    }

    func testPrunedKeepsOnlyExisting() {
        let result = ShelfStore.pruned(["/keep", "/gone", "/keep2"]) { $0 != "/gone" }
        XCTAssertEqual(result, ["/keep", "/keep2"])
    }

    func testNormalizedStripsTrailingSlashAndStandardizes() {
        XCTAssertEqual(ShelfStore.normalized("/tmp/dir/"), "/tmp/dir")
        XCTAssertEqual(ShelfStore.normalized("/tmp/a/../b"), "/tmp/b")
        XCTAssertEqual(ShelfStore.normalized("/"), "/")
    }

    func testCardPresentationClassifiesTextMediaAndDocuments() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-card-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let noteURL = dir.appendingPathComponent("Streisand effect.md")
        try "# Streisand effect\nThe Streisand effect is a phenomenon where an attempt to hide information increases awareness.".write(to: noteURL, atomically: true, encoding: .utf8)

        let snippetURL = dir.appendingPathComponent("Snippet 18-49.txt")
        try "Going offline for a bit in 23 minutes.\nLet's keep queries in source control.".write(to: snippetURL, atomically: true, encoding: .utf8)

        let imgURL = dir.appendingPathComponent("board.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: imgURL)

        let zipURL = dir.appendingPathComponent("bundle.zip")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: zipURL)

        let wikiCard = ShelfCardPresentation.classify(url: noteURL, index: 0, showTextExcerpt: true)
        XCTAssertEqual(wikiCard.archetype, .richTextOrWikiCard)
        XCTAssertTrue(wikiCard.usesLightCardSurface)
        XCTAssertEqual(wikiCard.title, "Streisand effect")
        XCTAssertTrue(wikiCard.excerpt?.contains("phenomenon") ?? false)

        let hiddenExcerptCard = ShelfCardPresentation.classify(url: noteURL, index: 0, showTextExcerpt: false)
        XCTAssertNil(hiddenExcerptCard.excerpt)

        let chatCard = ShelfCardPresentation.classify(url: snippetURL, index: 1, showTextExcerpt: true)
        XCTAssertEqual(chatCard.archetype, .chatOrSnippetCard)
        XCTAssertTrue(chatCard.usesLightCardSurface)
        XCTAssertEqual(chatCard.badgeText, "NOTE")

        let mediaCard = ShelfCardPresentation.classify(url: imgURL, index: 2)
        XCTAssertEqual(mediaCard.archetype, .mediaCanvasCard)
        XCTAssertFalse(mediaCard.usesLightCardSurface)
        XCTAssertEqual(mediaCard.badgeText, "PNG")

        let docCard = ShelfCardPresentation.classify(url: zipURL, index: 3)
        XCTAssertEqual(docCard.archetype, .fileDocumentCard)
        XCTAssertFalse(docCard.usesLightCardSurface)
        XCTAssertEqual(docCard.badgeText, "ZIP")
    }

    func testBatchTransformActionsEligibility() {
        XCTAssertEqual(ShelfBatchTransformAction.eligibleActions(for: []), [])

        let png = URL(fileURLWithPath: "/tmp/shot.png")
        let pdf = URL(fileURLWithPath: "/tmp/doc.pdf")
        let zip = URL(fileURLWithPath: "/tmp/archive.zip")

        let imageActions = ShelfBatchTransformAction.eligibleActions(for: [png])
        XCTAssertTrue(imageActions.contains(.zipItems))
        XCTAssertTrue(imageActions.contains(.mergeToPDF))
        XCTAssertTrue(imageActions.contains(.removeBackground))
        XCTAssertTrue(imageActions.contains(.convertImages(format: .webp)))
        XCTAssertTrue(imageActions.contains(.copyAllPaths))
        XCTAssertTrue(imageActions.contains(.airDropShare))

        let pdfActions = ShelfBatchTransformAction.eligibleActions(for: [pdf])
        XCTAssertTrue(pdfActions.contains(.mergeToPDF))
        XCTAssertFalse(pdfActions.contains(.removeBackground))
        XCTAssertFalse(pdfActions.contains(.convertImages(format: .png)))

        let zipActions = ShelfBatchTransformAction.eligibleActions(for: [zip])
        XCTAssertEqual(zipActions, [.zipItems, .copyAllPaths, .airDropShare])
    }

    func testExampleURLDetection() {
        XCTAssertTrue(ShelfPolicy.isExampleURL(URL(fileURLWithPath: "/tmp/Example_Wiki_Note.md")))
        XCTAssertTrue(ShelfPolicy.isExampleURL(URL(fileURLWithPath: "/Users/me/Library/Application Support/KatiKati/ShelfExamples/note.txt")))
        XCTAssertFalse(ShelfPolicy.isExampleURL(URL(fileURLWithPath: "/Users/me/Desktop/notes.md")))
    }
}
