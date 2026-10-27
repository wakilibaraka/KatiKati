import XCTest

/// 设置备份的纯模型：哪些键进哪个分类、值如何无损往返、备份文件如何解码与过滤。
final class SettingsBackupTests: XCTestCase {

    // MARK: - 分类

    func testBarKeysAreBarAndLauncher() {
        XCTAssertEqual(SettingsBackupKeys.category(of: "keptAppBundleIDsV3"), .barAndLauncher)
        XCTAssertEqual(SettingsBackupKeys.category(of: "pinnedFolderPaths"), .barAndLauncher)
        XCTAssertEqual(SettingsBackupKeys.category(of: "com.katikati.layout.mode"), .barAndLauncher)
        XCTAssertEqual(SettingsBackupKeys.category(of: "com.katikati.launcher.order"), .barAndLauncher)
    }

    func testOtherKatiKatiKeysAreSettings() {
        XCTAssertEqual(SettingsBackupKeys.category(of: "com.katikati.notch.enabled"), .settingsAndShortcuts)
        XCTAssertEqual(SettingsBackupKeys.category(of: "com.katikati.commandbar.hotkey"), .settingsAndShortcuts)
    }

    func testStampsMigrationsAndWelcomeAreExcluded() {
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.migration.dockV2"))
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.hasSeenWelcome"))
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.notch.intro.stamp"))
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.weather.cache"))
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.launchAtLogin"))
    }

    func testSecretLookingKeysAreExcludedEverywhere() {
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.ai.apiKey"))
        XCTAssertNil(SettingsBackupKeys.category(of: "com.katikati.tools.GitHubToken"))
        XCTAssertNil(SettingsBackupKeys.category(of: "keptAppBundleIDsV3.password"))
    }

    func testForeignKeysAreNotOurs() {
        XCTAssertNil(SettingsBackupKeys.category(of: "NSWindow Frame Foo"))
        XCTAssertNil(SettingsBackupKeys.category(of: "AppleLanguages"))
    }

    func testKeysSelectionFiltersByCategoryAndSorts() {
        let all = ["com.katikati.notch.enabled", "keptAppBundleIDsV3", "AppleLanguages", "com.katikati.layout.mode"]
        XCTAssertEqual(SettingsBackupKeys.keys(in: [.barAndLauncher], from: all),
                       ["com.katikati.layout.mode", "keptAppBundleIDsV3"])
        XCTAssertEqual(SettingsBackupKeys.keys(in: [.settingsAndShortcuts], from: all), ["com.katikati.notch.enabled"])
        XCTAssertTrue(SettingsBackupKeys.keys(in: [.tasks], from: all).isEmpty)
    }

    // MARK: - 值往返

    func testValueRoundTripKeepsTypes() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1234)
        let values: [BackupValue] = [
            .string("a"), .integer(3), .double(1.5), .bool(true), .date(date), .data(Data([1, 2, 3])),
            .array([.integer(1), .string("x")]), .dictionary(["k": .bool(false)]),
        ]
        for value in values {
            let data = try JSONEncoder().encode(value)
            XCTAssertEqual(try JSONDecoder().decode(BackupValue.self, from: data), value)
        }
    }

    func testIntegerAndBoolStayDistinctFromPropertyList() {
        XCTAssertEqual(BackupValue(propertyList: NSNumber(value: true)), .bool(true))
        XCTAssertEqual(BackupValue(propertyList: NSNumber(value: 7)), .integer(7))
        XCTAssertEqual(BackupValue(propertyList: NSNumber(value: 1.5)), .double(1.5))
        XCTAssertEqual(BackupValue(propertyList: ["a", "b"]), .array([.string("a"), .string("b")]))
    }

    func testUnsupportedPropertyListIsRejectedWholesale() {
        XCTAssertNil(BackupValue(propertyList: ["ok", NSObject()]))
        XCTAssertNil(BackupValue(propertyList: ["k": NSObject()]))
    }

    func testUnknownValueTypeFailsToDecode() {
        let json = Data(#"{"type":"mystery","value":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BackupValue.self, from: json))
    }

    // MARK: - 文件

    private func sample() -> SettingsBackupFile {
        SettingsBackupFile(
            appVersion: "1.0", created: Date(timeIntervalSinceReferenceDate: 10),
            categories: [.settingsAndShortcuts, .barAndLauncher, .tasks],
            defaults: [
                "com.katikati.notch.enabled": .bool(true),
                "keptAppBundleIDsV3": .array([.string("com.apple.Safari")]),
                "com.katikati.migration.x": .bool(true),
                "AppleLanguages": .array([.string("en")]),
            ],
            files: ["tasks.json": Data("[]".utf8), "../evil": Data([0]), "Notes/a": Data([1])])
    }

    func testEncodeDecodeRoundTrip() throws {
        let file = sample()
        XCTAssertEqual(try SettingsBackupFile.decode(file.encoded()), file)
    }

    func testGarbageIsNotABackup() {
        XCTAssertThrowsError(try SettingsBackupFile.decode(Data("hello".utf8))) {
            XCTAssertEqual($0 as? SettingsBackupFile.DecodeError, .notABackup)
        }
        XCTAssertThrowsError(try SettingsBackupFile.decode(Data(#"{"format":1}"#.utf8))) {
            XCTAssertEqual($0 as? SettingsBackupFile.DecodeError, .notABackup)
        }
    }

    func testNewerFormatIsRefused() {
        XCTAssertThrowsError(try SettingsBackupFile.decode(Data(#"{"format":99}"#.utf8))) {
            XCTAssertEqual($0 as? SettingsBackupFile.DecodeError, .newerFormat(99))
        }
    }

    func testRestorableDefaultsDropsExcludedForeignAndUntickedKeys() {
        let all = sample().restorableDefaults(categories: [.settingsAndShortcuts, .barAndLauncher])
        XCTAssertEqual(Set(all.keys), ["com.katikati.notch.enabled", "keptAppBundleIDsV3"])
        let barOnly = sample().restorableDefaults(categories: [.barAndLauncher])
        XCTAssertEqual(Set(barOnly.keys), ["keptAppBundleIDsV3"])
    }

    func testRestorableDefaultsIgnoresCategoriesTheFileDoesNotHold() {
        var file = sample()
        file.categories = [.settingsAndShortcuts]
        XCTAssertTrue(file.restorableDefaults(categories: [.barAndLauncher]).isEmpty)
    }

    func testRestorableFilesOnlyTickedAndSafe() {
        let tasks = sample().restorableFiles(categories: [.tasks, .notes])
        XCTAssertEqual(Set(tasks.keys), ["tasks.json"], "notes is not in the file's categories; ../evil is unsafe")
        XCTAssertTrue(sample().restorableFiles(categories: [.settingsAndShortcuts]).isEmpty)
    }

    func testSafeFileNames() {
        XCTAssertTrue(SettingsBackupFile.isSafeFileName("tasks.json"))
        XCTAssertTrue(SettingsBackupFile.isSafeFileName("Notes/abc.enc"))
        for bad in ["", "/etc/passwd", "../x", "a/../b", "a//b", "./a", "a\\b"] {
            XCTAssertFalse(SettingsBackupFile.isSafeFileName(bad), bad)
        }
    }

    func testFileCategories() {
        XCTAssertEqual(SettingsBackupFile.category(ofFile: "tasks.json"), .tasks)
        XCTAssertEqual(SettingsBackupFile.category(ofFile: "Notes/x"), .notes)
        XCTAssertNil(SettingsBackupFile.category(ofFile: "other.bin"))
        XCTAssertNil(SettingsBackupFile.category(ofFile: "note.key"), "a backup must never replace the notes key")
    }
}
