import XCTest
@testable import KatiKati

// Phase 47c — the notification mirror's pure half: the store's record layout and the banner fold.
// Built from synthesised input on purpose: the real records are the owner's own notifications.

final class NotificationMirrorTests: XCTestCase {
    private func record(title: String? = "Deploy finished", subtitle: String? = "ci",
                        body: String? = "All checks green", uuid: Data? = Data(repeating: 0xAB, count: 3),
                        date: Double? = 813_814_483) -> [String: Any] {
        var request: [String: Any] = ["iden": "req-1"]
        if let title { request["titl"] = title }
        if let subtitle { request["subt"] = subtitle }
        if let body { request["body"] = body }
        var record: [String: Any] = ["req": request, "app": "com.example.ci"]
        if let uuid { record["uuid"] = uuid }
        if let date { record["date"] = date }
        return record
    }

    /// The store's field names, read the way they are actually stored: the title, subtitle and body live
    /// under `req`, the bundle id on the record, and the date is Unix seconds.
    func testRecordFieldsBecomeTheRowThePageShows() {
        let parsed = NotificationRecord.notification(fromRecord: record(), bundleIdentifier: "com.example.app")
        XCTAssertEqual(parsed?.title, "Deploy finished")
        XCTAssertEqual(parsed?.subtitle, "ci")
        XCTAssertEqual(parsed?.body, "All checks green")
        XCTAssertEqual(parsed?.bundleIdentifier, "com.example.app")
        XCTAssertEqual(parsed?.detail, "All checks green")
        XCTAssertEqual(parsed?.date, Date(timeIntervalSince1970: 813_814_483))
        XCTAssertEqual(parsed?.id, "ababab")
    }

    /// A record with no title has nothing to show: no row, rather than a blank one.
    func testARecordWithoutATitleIsNotARow() {
        XCTAssertNil(NotificationRecord.notification(fromRecord: record(title: nil), bundleIdentifier: nil))
        XCTAssertNil(NotificationRecord.notification(fromRecord: record(title: "   "), bundleIdentifier: nil))
        XCTAssertNil(NotificationRecord.notification(fromRecord: ["app": "com.example.app"], bundleIdentifier: nil))
    }

    /// The bundle id on the record is the fallback when the join found no app row, and a missing date is
    /// left missing instead of being guessed from now.
    func testBundleIDFallsBackToTheRecordAndAMissingDateStaysMissing() {
        let parsed = NotificationRecord.notification(fromRecord: record(date: nil), bundleIdentifier: nil)
        XCTAssertEqual(parsed?.bundleIdentifier, "com.example.ci")
        XCTAssertNil(parsed?.date)
    }

    /// A banner's strings: blanks and repeats dropped, first is the title, last is the body.
    func testBannerTextFoldsToATitleAndABody() {
        let folded = NotificationBannerText.fold(["  Deploy finished ", "", "ci", "ci", "All checks green"])
        XCTAssertEqual(folded?.title, "Deploy finished")
        XCTAssertEqual(folded?.body, "All checks green")

        // One string is a title with no body; nothing readable is no notification at all.
        XCTAssertEqual(NotificationBannerText.fold(["Deploy finished"])?.title, "Deploy finished")
        XCTAssertNil(NotificationBannerText.fold(["Deploy finished"])?.body)
        XCTAssertNil(NotificationBannerText.fold(["", "   "]))
        XCTAssertNil(NotificationBannerText.fold([]))
    }

    /// SD-1: the inbox lives in the Side Deck now. The notch gallery keeps its compact core pages and has
    /// no notification page left to cycle to.
    func testTheNotificationsInboxIsInTheSideDeckNotTheNotch() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false).count, 5)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: true).count, 7)
        XCTAssertFalse(NotchPage.visible(teleprompter: true, mirror: true).contains { $0.symbol == "bell.fill" })
        XCTAssertTrue(SideDeckTab.allCases.contains(.notifications))
        XCTAssertEqual(SideDeckTab.notifications.symbol, "bell.fill")
        XCTAssertEqual(SideDeckSearch.placeholder(for: .notifications), "Search notifications")
    }

    // MARK: - NotificationHistoryStore (Slice N-1)

    func testHistoryStoreRingBufferEvictsOldestBeyondCapacity() {
        var store = NotificationHistoryStore(maxCapacity: 3)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        for i in 1...5 {
            store.append(NotificationHistoryEntry(
                id: "n-\(i)",
                timestamp: base.addingTimeInterval(Double(i * 10)),
                title: "Event \(i)",
                body: "Body \(i)",
                appBundleId: "com.example.app"
            ))
        }

        XCTAssertEqual(store.entries.map(\.id), ["n-5", "n-4", "n-3"])
        XCTAssertEqual(store.unreadCount, 3)

        store.setMaxCapacity(2)
        XCTAssertEqual(store.entries.map(\.id), ["n-5", "n-4"])
    }

    func testHistoryStoreUnreadMutationsAndSearchFilter() {
        var store = NotificationHistoryStore(maxCapacity: 50)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        store.append(NotificationHistoryEntry(
            id: "1",
            timestamp: base,
            title: "Café Receipt",
            body: "Order #42 ready",
            appBundleId: "com.example.coffee"
        ))
        store.append(NotificationHistoryEntry(
            id: "2",
            timestamp: base.addingTimeInterval(30),
            title: "Build Succeeded",
            body: "KatiKati.app",
            appBundleId: "com.apple.dt.Xcode",
            isRead: true
        ))
        store.append(NotificationHistoryEntry(
            id: "3",
            timestamp: base.addingTimeInterval(60),
            title: "Direct Message",
            body: "See you at 5pm",
            appBundleId: "com.tinyspeck.slackmacgap"
        ))

        XCTAssertEqual(store.unreadCount, 2)
        XCTAssertEqual(store.filtered(query: "", unreadOnly: true).map(\.id), ["3", "1"])
        XCTAssertEqual(store.filtered(query: "cafe", unreadOnly: false).map(\.id), ["1"])
        XCTAssertEqual(store.filtered(query: "xcode", unreadOnly: false).map(\.id), ["2"])

        store.markRead(id: "1")
        XCTAssertEqual(store.unreadCount, 1)
        XCTAssertEqual(store.filtered(query: "", unreadOnly: true).map(\.id), ["3"])

        store.markAllRead()
        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.filtered(query: "", unreadOnly: true).isEmpty)

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testHistoryStoreRedactsSensitiveBundlesBeforeFiltering() {
        var store = NotificationHistoryStore(maxCapacity: 50)
        let base = Date(timeIntervalSince1970: 1_700_000_000)

        store.append(NotificationHistoryEntry(
            id: "secret",
            timestamp: base.addingTimeInterval(20),
            title: "One-Time Code 994120",
            body: "Use this to sign in",
            appBundleId: "com.apple.MobileSMS"
        ))
        store.append(NotificationHistoryEntry(
            id: "public",
            timestamp: base.addingTimeInterval(10),
            title: "Deploy Finished",
            body: "All checks green",
            appBundleId: "com.example.ci"
        ))

        let sensitive: Set<String> = ["com.apple.MobileSMS"]
        let redacted = store.redacted(sensitiveBundleIDs: sensitive, placeholder: "Hidden")
        XCTAssertEqual(redacted.first?.title, "Hidden")
        XCTAssertNil(redacted.first?.body)
        XCTAssertEqual(redacted.first?.appBundleId, "com.apple.MobileSMS")
        XCTAssertEqual(redacted.last?.title, "Deploy Finished")

        // Searching for sensitive body/title must not match redacted notifications.
        let searchLeakCheck = store.visibleEntries(
            query: "994120",
            unreadOnly: false,
            sensitiveBundleIDs: sensitive,
            placeholder: "Hidden"
        )
        XCTAssertTrue(searchLeakCheck.isEmpty)
    }
}
