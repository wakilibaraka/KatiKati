import XCTest

@MainActor
final class DockWingServicesTests: XCTestCase {
    func testGeoIPLocationFormattingAndFlags() {
        let miami = GeoIPLocation(city: "Miami", countryCode: "US", ip: "1.2.3.4")
        XCTAssertEqual(miami.formattedPlace, "Miami, US")
        XCTAssertEqual(miami.flagEmoji, "🇺🇸")

        let onlyCountry = GeoIPLocation(city: "", countryCode: "JP", ip: nil)
        XCTAssertEqual(onlyCountry.formattedPlace, "JP")
        XCTAssertEqual(onlyCountry.flagEmoji, "🇯🇵")

        let invalid = GeoIPLocation(city: nil, countryCode: "USA", ip: nil)
        XCTAssertEqual(invalid.formattedPlace, "USA")
        XCTAssertNil(invalid.flagEmoji)

        let blank = GeoIPLocation(city: nil, countryCode: nil, ip: nil)
        XCTAssertNil(blank.formattedPlace)
    }

    func testSpotifyTrackKeyNormalization() {
        XCTAssertNil(DockSpotifyTrackKey.make(title: "   ", artist: "Artist"))
        XCTAssertEqual(
            DockSpotifyTrackKey.make(title: "  Come On, Let's Go ", artist: " Tyler, the Creator "),
            "come on, let's go|tyler, the creator"
        )
    }

    func testFriendsStoreCrudAndBadges() throws {
        let suite = "com.katikati.tests.friends.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("katikati-friends-\(UUID().uuidString)")
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: tempDir)
        }

        let store = DockFriendsStore(defaults: defaults, avatarsDirectory: tempDir)
        XCTAssertTrue(store.friends.isEmpty)

        let amir = DockFriendContact(
            displayName: "Amir",
            handle: "+15550001",
            preferredApp: .messages,
            unreadOverride: 69
        )
        let sara = DockFriendContact(
            displayName: "Sara",
            handle: "sara@example.com",
            preferredApp: .facetime,
            isSpeaking: true
        )
        store.addFriend(amir, avatarData: Data([0x89, 0x50, 0x4E, 0x47]))
        store.addFriend(sara)

        XCTAssertEqual(store.friends.count, 2)
        XCTAssertEqual(store.badgeText(for: store.friends[0], badgesByBundleID: [:]), "69")
        XCTAssertEqual(
            store.badgeText(for: store.friends[1], badgesByBundleID: ["com.apple.FaceTime": "3"]),
            "3"
        )

        let reloaded = DockFriendsStore(defaults: defaults, avatarsDirectory: tempDir)
        XCTAssertEqual(reloaded.friends.map(\.displayName), ["Amir", "Sara"])
        XCTAssertNotNil(reloaded.friends[0].avatarImageFilename)

        reloaded.removeFriend(id: amir.id)
        XCTAssertEqual(reloaded.friends.map(\.displayName), ["Sara"])
    }
}
