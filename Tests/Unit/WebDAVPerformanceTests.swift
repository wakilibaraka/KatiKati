import Foundation
import XCTest

final class WebDAVPerformanceTests: XCTestCase {
    // MARK: - Remote paths

    func testDeviceSlugIsSafeAndStable() {
        XCTAssertEqual(WebDAVSyncPlanner.deviceSlug("Baraka's MacBook Pro"), "baraka-s-macbook-pro")
        XCTAssertEqual(WebDAVSyncPlanner.deviceSlug("  "), "mac")
        XCTAssertEqual(WebDAVSyncPlanner.deviceSlug("A/B\\C"), "a-b-c")
    }

    func testPlanUsesEnabledDomainsAndCanonicalPaths() {
        var settings = WebDAVSyncSettings.defaults(deviceName: "Studio Mac", remoteRoot: "dav/KatiKatiSync/")
        settings.enabledDomains = [.desktopBoxesAndStyles, .todos]
        let plan = WebDAVSyncPlan.upload(settings)
        XCTAssertEqual(plan.remoteRoot, "/dav/KatiKatiSync")
        XCTAssertEqual(plan.deviceSlug, "studio-mac")
        XCTAssertEqual(plan.items.map(\.domain), [.desktopBoxesAndStyles, .todos])
        XCTAssertEqual(plan.items[0].remotePath, "/dav/KatiKatiSync/studio-mac/desktop.json")
        XCTAssertEqual(plan.items[1].remotePath, "/dav/KatiKatiSync/studio-mac/todos.json")
        XCTAssertEqual(plan.manifestPath, "/dav/KatiKatiSync/studio-mac/manifest.json")
    }

    func testPlanExcludesDisabledDomains() {
        var settings = WebDAVSyncSettings.defaults()
        settings.enabledDomains = [.settingsAndShortcuts]
        XCTAssertEqual(WebDAVSyncPlan.upload(settings).items.map(\.domain), [.settingsAndShortcuts])
    }

    // MARK: - Cross-Mac paths

    func testHomePathsAreRemappedRecursively() throws {
        let payload = """
        {"items":[{"id":"1","backingPath":"/Users/alice/Desktop/Work","frame":"not-a-path"},
        {"id":"2","backingPath":"/Volumes/Shared/Team"}],"home":"/Users/alice"}
        """
        let data = try XCTUnwrap(WebDAVSyncPlanner.remapHomePaths(
            in: Data(payload.utf8),
            from: "/Users/alice/",
            to: "/Users/bob"
        ))
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("/Users/bob/Desktop/Work"))
        XCTAssertTrue(text.contains("/Users/bob"))
        XCTAssertFalse(text.contains("/Users/alice/Desktop/Work"))
        XCTAssertTrue(text.contains("/Volumes/Shared/Team"))
    }

    func testSameHomeLeavesDataUntouched() throws {
        let data = Data(#"{"path":"/Users/alice/Documents"}"#.utf8)
        XCTAssertEqual(WebDAVSyncPlanner.remapHomePaths(in: data, from: "/Users/alice", to: "/Users/alice"), data)
    }

    // MARK: - Merge

    func testMergeKeepsLocalRowsAndAppendsRemoteOnlyRows() throws {
        let local = Data(#"[{"id":"a","name":"Local A"},{"id":"b","name":"Local B"}]"#.utf8)
        let remote = Data(#"[{"id":"a","name":"Remote A"},{"id":"c","name":"Remote C"}]"#.utf8)
        let merged = try XCTUnwrap(WebDAVSyncPlanner.mergeIdentifiedJSON(local: local, remote: remote))
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: merged) as? [[String: Any]])
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.first?["name"] as? String, "Local A")
        XCTAssertEqual(rows.last?["id"] as? String, "c")
    }

    func testSnapshotFaithfulIgnoresLocalRows() throws {
        let local = Data(#"[{"id":"a","name":"Local A"}]"#.utf8)
        let remote = Data(#"[{"id":"c","name":"Remote C"}]"#.utf8)
        let merged = try XCTUnwrap(WebDAVSyncPlanner.mergedFileData(local: local, remote: remote, mode: .snapshotFaithful))
        XCTAssertEqual(merged, remote)
    }

    func testMergeCombinesTaskAndCaptureRowsInsideObjects() throws {
        let local = Data(#"{"items":[{"id":"a","text":"local"}],"localOnly":true}"#.utf8)
        let remote = Data(#"{"items":[{"id":"a","text":"remote"},{"id":"b","text":"new"}],"remoteOnly":2}"#.utf8)
        let data = try XCTUnwrap(WebDAVSyncPlanner.mergedFileData(local: local, remote: remote, mode: .merge))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try XCTUnwrap(object["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?["text"] as? String, "local")
        XCTAssertEqual(items.last?["id"] as? String, "b")
        XCTAssertEqual(object["localOnly"] as? Bool, true)
        XCTAssertEqual(object["remoteOnly"] as? Int, 2)

        let localCapture = Data(#"{"entries":[{"id":"x","text":"kept"}]}"#.utf8)
        let remoteCapture = Data(#"{"entries":[{"id":"y","text":"added"}]}"#.utf8)
        let capture = try XCTUnwrap(WebDAVSyncPlanner.mergedFileData(local: localCapture, remote: remoteCapture, mode: .merge))
        let captureObject = try XCTUnwrap(JSONSerialization.jsonObject(with: capture) as? [String: Any])
        let entries = try XCTUnwrap(captureObject["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.compactMap { $0["id"] as? String }, ["x", "y"])
    }

    func testMergeDefaultsIncomingWinsLocalOnlySurvives() {
        let merged = WebDAVSyncPlanner.mergeDefaults(
            local: ["a": .integer(1), "b": .integer(2)],
            remote: ["b": .integer(20), "c": .integer(30)]
        )
        XCTAssertEqual(merged["a"], .integer(1))
        XCTAssertEqual(merged["b"], .integer(20))
        XCTAssertEqual(merged["c"], .integer(30))
    }

    // MARK: - Settings & envelope

    func testSyncSettingsRoundTripThroughDefaults() {
        let suite = UserDefaults(suiteName: "WebDAVPerformanceTests.settings")!
        suite.removePersistentDomain(forName: "WebDAVPerformanceTests.settings")
        var settings = WebDAVSyncSettings.defaults(deviceName: "Test Mac")
        settings.enabledDomains = [.todos, .quickCaptureAndNotes]
        settings.restoreMode = .snapshotFaithful
        settings.schedule = .weekly
        settings.save(defaults: suite)
        let loaded = WebDAVSyncSettings.load(defaults: suite)
        XCTAssertEqual(loaded.enabledDomains, [.todos, .quickCaptureAndNotes])
        XCTAssertEqual(loaded.restoreMode, .snapshotFaithful)
        XCTAssertEqual(loaded.schedule, .weekly)
        XCTAssertEqual(loaded.deviceName, "Test Mac")
        XCTAssertEqual(WebDAVSyncKeys.serverURL, "com.katikati.backup.webdav.serverURL")
    }

    func testEnvelopeRoundTrip() throws {
        let envelope = WebDAVSyncEnvelope(
            domain: .todos,
            deviceName: "Test Mac",
            homeDirectory: "/Users/alice",
            files: ["tasks.json": Data("[]".utf8)],
            defaults: ["com.katikati.desktop.align": .bool(true)]
        )
        let decoded = try JSONDecoder().decode(WebDAVSyncEnvelope.self, from: JSONEncoder().encode(envelope))
        XCTAssertEqual(decoded, envelope)
        XCTAssertEqual(decoded.schema, WebDAVSyncEnvelope.currentSchema)
    }

    // MARK: - Performance

    func testBalancedProfileEnablesEverything() {
        let settings = DesktopPerformanceSettings.defaults(for: .balanced)
        XCTAssertTrue(settings.releasesHiddenSurfaces)
        XCTAssertEqual(settings.thumbnailCacheMegabytes, 64)
        for animation in DesktopPerformanceAnimation.allCases {
            XCTAssertTrue(settings.allowsAnimation(animation))
        }
    }

    func testResourceSaverDisablesAnimationsAndShrinksBudgets() {
        let settings = DesktopPerformanceSettings.defaults(for: .resourceSaver)
        XCTAssertEqual(settings.visibleIdleCleanupSeconds, 20)
        XCTAssertEqual(settings.thumbnailCacheMegabytes, 16)
        XCTAssertEqual(settings.imageCacheMegabytes, 32)
        for animation in DesktopPerformanceAnimation.allCases {
            XCTAssertFalse(settings.allowsAnimation(animation))
        }
    }

    func testPerformanceValuesAreClamped() {
        XCTAssertEqual(DesktopPerformanceConfig.clampedIdleSeconds(-4), 0)
        XCTAssertEqual(DesktopPerformanceConfig.clampedIdleSeconds(9_999), 600)
        XCTAssertEqual(DesktopPerformanceConfig.clampedThumbnailMB(1), 8)
        XCTAssertEqual(DesktopPerformanceConfig.clampedImageMB(4_000), 1_024)
    }

    func testPerformanceSettingsRoundTrip() {
        let suite = UserDefaults(suiteName: "WebDAVPerformanceTests.performance")!
        suite.removePersistentDomain(forName: "WebDAVPerformanceTests.performance")
        var settings = DesktopPerformanceSettings.defaults(for: .balanced)
        settings.mode = .custom
        settings.animations[.vinylSpin] = false
        settings.thumbnailCacheMegabytes = 96
        DesktopPerformanceConfig.save(settings, defaults: suite)
        let loaded = DesktopPerformanceConfig.settings(defaults: suite)
        XCTAssertEqual(loaded.mode, .custom)
        XCTAssertFalse(loaded.allowsAnimation(.vinylSpin))
        XCTAssertTrue(loaded.allowsAnimation(.marquee))
        XCTAssertEqual(loaded.thumbnailCacheMegabytes, 96)
        XCTAssertEqual(DesktopPerformanceConfig.modeKey, "com.katikati.desktop.performance.mode")
    }
}
