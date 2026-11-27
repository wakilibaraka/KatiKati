import XCTest
@testable import KatiKati

final class ClipboardHistoryTests: XCTestCase {
    func testRememberTrimsIgnoresBlankAndPutsNewestFirst() {
        var h = ClipboardHistory()
        h.remember("  \n ")
        h.remember(" one \n")
        h.remember("two")
        XCTAssertEqual(h.entries.map(\.text), ["two", "one"])
    }

    func testDuplicateMovesToTopKeepingItsPin() {
        var h = ClipboardHistory()
        h.remember("alpha", originBundleID: "com.apple.dt.Xcode")
        h.remember("beta", originBundleID: "com.apple.Safari")
        h.togglePin(h.entries[1].id)         // pin alpha
        h.remember("ALPHA")
        XCTAssertEqual(h.entries.map(\.text), ["ALPHA", "beta"])
        XCTAssertTrue(h.entries[0].pinned)
        XCTAssertEqual(h.entries[0].originBundleID, "com.apple.dt.Xcode", "re-copying without a new origin preserves the recorded origin bundle ID")
    }

    func testGrowingTextReplacesTheNewestEntry() {
        var h = ClipboardHistory()
        h.remember("hello")
        h.remember("hello wor")
        h.remember("hello world")
        XCTAssertEqual(h.entries.map(\.text), ["hello world"])
        h.remember("Hello World")
        XCTAssertEqual(h.entries.map(\.text), ["Hello World"], "case-only change updates in place")
    }

    func testCapPrunesOldUnpinnedButNeverPinned() {
        var h = ClipboardHistory()
        h.remember("keep me")
        h.togglePin(h.entries[0].id)
        for i in 0..<(ClipboardHistory.maxUnpinned + 10) { h.remember("item \(i) x") }
        XCTAssertEqual(h.entries.filter { !$0.pinned }.count, ClipboardHistory.maxUnpinned)
        XCTAssertTrue(h.entries.contains { $0.text == "keep me" && $0.pinned })
        XCTAssertEqual(h.displayOrder.first?.text, "keep me", "pinned lead the list")
    }

    func testClearKeepsPinnedUnlessAsked() {
        var h = ClipboardHistory()
        h.remember("a1"); h.remember("b2")
        h.togglePin(h.entries[0].id)
        h.clear()
        XCTAssertEqual(h.entries.map(\.text), ["b2"])
        h.clear(keepingPinned: false)
        XCTAssertTrue(h.entries.isEmpty)
    }

    func testLongTextIsCappedAndSecretTypesAreSkipped() {
        var h = ClipboardHistory()
        h.remember(String(repeating: "x", count: ClipboardHistory.maxLength + 500))
        XCTAssertEqual(h.entries[0].text.count, ClipboardHistory.maxLength)
        XCTAssertFalse(ClipboardHistory.shouldRecord(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardHistory.shouldRecord(types: ["public.utf8-plain-text"]))
    }

    func testPreviewLineCollapsesWhitespaceAndTruncates() {
        XCTAssertEqual(ClipboardHistory.previewLine("a\n\nb\tc"), "a b c")
        XCTAssertEqual(ClipboardHistory.previewLine("  a  "), "a")
        XCTAssertEqual(ClipboardHistory.previewLine(String(repeating: "y", count: 500)).count, ClipboardHistory.previewLength)
        XCTAssertEqual(ClipboardHistory.previewLine("\n\n"), "")
    }
}

/// 55g: pinned entries never expire; 0 keeps everything.
final class ClipboardRetentionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func entry(_ text: String, daysOld: Double, pinned: Bool = false) -> ClipEntry {
        ClipEntry(text: text, pinned: pinned, date: now.addingTimeInterval(-daysOld * 86_400))
    }

    func testOffKeepsEverything() {
        let entries = [entry("old", daysOld: 365)]
        XCTAssertEqual(ClipboardRetention.prune(entries, now: now, days: 0), entries)
    }

    func testUnpinnedExpireAndPinnedStay() {
        let entries = [entry("old", daysOld: 40), entry("new", daysOld: 2), entry("pin", daysOld: 400, pinned: true)]
        XCTAssertEqual(ClipboardRetention.prune(entries, now: now, days: 30).map(\.text), ["new", "pin"])
    }

    func testHistoryPruneUsesTheSameRule() {
        var history = ClipboardHistory()
        history.remember("old", now: now.addingTimeInterval(-40 * 86_400))
        history.remember("new", now: now)
        history.prune(olderThanDays: 30, now: now)
        XCTAssertEqual(history.entries.map(\.text), ["new"])
    }
}

@MainActor
final class ClipboardMonitorPrivacyTests: XCTestCase {
    func testHandleExternalPasteSkipsConcealedAndIgnoredText() {
        let suite = "com.katikati.test.clip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("secret-token", forKey: ClipboardMonitor.ignorePatternsKey)

        let pasteboard = NSPasteboard(name: .init("com.katikati.test.pb.\(UUID().uuidString)"))
        let monitor = ClipboardMonitor(defaults: defaults, pasteboard: pasteboard)
        var pasted: [String] = []
        monitor.onPasted = { pasted.append($0) }

        pasteboard.clearContents()
        pasteboard.setString("hunter2", forType: .string)
        pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        monitor.handleExternalPaste()
        XCTAssertTrue(pasted.isEmpty, "concealed pasteboard entries must never trigger onPasted")

        pasteboard.clearContents()
        pasteboard.setString("my secret-token value", forType: .string)
        monitor.handleExternalPaste()
        XCTAssertTrue(pasted.isEmpty, "ignored pattern entries must never trigger onPasted")

        pasteboard.clearContents()
        pasteboard.setString("normal text", forType: .string)
        monitor.handleExternalPaste()
        XCTAssertEqual(pasted, ["normal text"])
    }
}
