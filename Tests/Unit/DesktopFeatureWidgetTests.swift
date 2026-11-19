import Foundation
import XCTest

final class DesktopFeatureWidgetTests: XCTestCase {
    func testCaptureLogTrimsClampsAndCaps() {
        var log = DesktopCaptureLog()
        XCTAssertNil(log.add("   \n"))
        XCTAssertNotNil(log.add("  hello  "))
        XCTAssertEqual(log.entries.first?.text, "hello")
        log.add(String(repeating: "x", count: 9000))
        XCTAssertEqual(log.entries.first?.text.count, DesktopCaptureLog.maxEntryLength)
        for i in 0..<300 { log.add("n\(i)") }
        XCTAssertEqual(log.entries.count, DesktopCaptureLog.capacity)
        XCTAssertEqual(log.entries.first?.text, "n299")
    }

    func testCaptureLogDeleteAndLenientDecode() throws {
        var log = DesktopCaptureLog()
        let id = log.add("a")!
        log.delete(id)
        XCTAssertTrue(log.entries.isEmpty)
        let decoded = try JSONDecoder().decode(DesktopCaptureLog.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.entries.isEmpty)
    }

    @MainActor
    func testCaptureStorePersistsAcrossInstances() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("desktop-capture.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DesktopQuickCaptureStore(url: url)
        store.add("remember")
        XCTAssertEqual(DesktopQuickCaptureStore(url: url).log.entries.first?.text, "remember")
    }

    @MainActor
    func testCaptureFileTravelsWithSettingsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let suiteName = "katikati.capture.backup.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: dir)
        }

        let captureURL = dir.appendingPathComponent("desktop-capture.json", isDirectory: false)
        let store = DesktopQuickCaptureStore(url: captureURL)
        store.add("backup-note")

        let service = SettingsBackupService(defaults: defaults, domainName: suiteName, supportDirectory: dir, appVersion: "1.0")
        let backup = service.makeBackup(categories: [.settingsAndShortcuts])
        XCTAssertNotNil(backup.files["desktop-capture.json"], "desktop-capture.json should be present in backup")

        try FileManager.default.removeItem(at: captureURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: captureURL.path))

        try service.restore(backup, categories: [.settingsAndShortcuts])
        XCTAssertTrue(FileManager.default.fileExists(atPath: captureURL.path))
        let restoredStore = DesktopQuickCaptureStore(url: captureURL)
        XCTAssertEqual(restoredStore.log.entries.first?.text, "backup-note")
    }

    func testGlanceNamesCoverEveryFactAndFallBackToEnglish() {
        for term in DesktopSolarTerm.allCases {
            XCTAssertFalse(DesktopGlanceNames.name(of: term, languageCode: "en").isEmpty)
            XCTAssertFalse(DesktopGlanceNames.name(of: term, languageCode: "zh").isEmpty)
        }
        for festival in DesktopFestival.allCases {
            XCTAssertFalse(DesktopGlanceNames.name(of: festival, languageCode: "ko").isEmpty)
        }
        XCTAssertEqual(DesktopGlanceNames.name(of: .springEquinox, languageCode: "zh"), "春分")
        XCTAssertEqual(DesktopGlanceNames.name(of: .springEquinox, languageCode: "de"), "Spring Equinox")
        XCTAssertEqual(DesktopGlanceNames.name(of: .grainBuds, languageCode: "zh", script: "Hant"), "小滿")
    }
}
