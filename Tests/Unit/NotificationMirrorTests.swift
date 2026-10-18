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

    /// The notifications page exists only while its switch is on, after the camera mirror.
    func testTheNotificationsPageJoinsTheGalleryOnlyWhenItIsSwitchedOn() {
        XCTAssertEqual(NotchPage.visible(teleprompter: false).count, 4)
        XCTAssertEqual(NotchPage.visible(teleprompter: false, mirror: true, notifications: true).last, .notifications)
        XCTAssertEqual(NotchPage.visible(teleprompter: true, mirror: true, notifications: true).count, 7)
        XCTAssertFalse(NotchPage.visible(teleprompter: true, mirror: true).contains(.notifications))
    }
}
