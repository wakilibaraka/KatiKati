import XCTest
@testable import KatiKati

/// SD-7: grouping, counts and the digest's previews, tested without Notification Center or an inbox.
final class NotificationDigestTests: XCTestCase {
    private func entry(_ title: String, app: String?, minutesAgo: Double, read: Bool = false) -> NotificationHistoryEntry {
        NotificationHistoryEntry(timestamp: Date(timeIntervalSince1970: 1_000_000 - minutesAgo * 60),
                                 title: title, appBundleId: app, isRead: read)
    }

    func testGroupsFollowTheirNewestEntryAndKeepNewestFirst() {
        let entries = [
            entry("mail old", app: "com.apple.Mail", minutesAgo: 30),
            entry("safari new", app: "com.apple.Safari", minutesAgo: 1),
            entry("mail new", app: "com.apple.Mail", minutesAgo: 5),
            entry("safari old", app: "com.apple.Safari", minutesAgo: 20),
        ]
        let groups = NotificationDigest.groups(entries)
        XCTAssertEqual(groups.map(\.bundleID), ["com.apple.Safari", "com.apple.Mail"],
                       "the app that spoke last comes first")
        XCTAssertEqual(groups[0].entries.map(\.title), ["safari new", "safari old"])
        XCTAssertEqual(groups[1].entries.map(\.title), ["mail new", "mail old"])
    }

    func testAnEntryWithoutAnAppGetsItsOwnGroup() {
        let groups = NotificationDigest.groups([
            entry("a", app: nil, minutesAgo: 1),
            entry("b", app: "com.apple.Mail", minutesAgo: 2),
            entry("c", app: nil, minutesAgo: 3),
        ])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].bundleID, nil)
        XCTAssertEqual(groups[0].entries.map(\.title), ["a", "c"])
    }

    func testUnreadCountsArePerGroupAndOverall() {
        let groups = NotificationDigest.groups([
            entry("a", app: "com.apple.Mail", minutesAgo: 1),
            entry("b", app: "com.apple.Mail", minutesAgo: 2, read: true),
            entry("c", app: "com.apple.Safari", minutesAgo: 3),
        ])
        XCTAssertEqual(groups.map(\.unreadCount), [1, 1])
        XCTAssertEqual(NotificationDigest.unreadCount([
            entry("a", app: nil, minutesAgo: 1),
            entry("b", app: nil, minutesAgo: 2, read: true),
        ]), 1)
    }

    func testPreviewsAreTheNewestFewInOrder() {
        let entries = [
            entry("old", app: nil, minutesAgo: 40),
            entry("newest", app: nil, minutesAgo: 1),
            entry("middle", app: nil, minutesAgo: 10),
            entry("older", app: nil, minutesAgo: 20),
        ]
        XCTAssertEqual(NotificationDigest.previews(entries).map(\.title), ["newest", "middle", "older"])
        XCTAssertEqual(NotificationDigest.previews(entries, limit: 1).map(\.title), ["newest"])
        XCTAssertTrue(NotificationDigest.previews(entries, limit: 0).isEmpty)
        XCTAssertTrue(NotificationDigest.previews([]).isEmpty)
    }

    func testGroupLabelsReadAsAppNames() {
        XCTAssertEqual(NotificationDigest.label(for: "com.apple.Safari"), "Safari")
        XCTAssertEqual(NotificationDigest.label(for: "com.tinyspeck.slackmacgap"), "slackmacgap")
        XCTAssertEqual(NotificationDigest.label(for: nil), "Other")
        XCTAssertEqual(NotificationDigest.label(for: ""), "Other")
    }
}
