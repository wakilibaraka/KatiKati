import XCTest

/// 备份服务的读写：用独立的 UserDefaults suite 和临时目录，不碰真实设置。
final class SettingsBackupServiceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var dir: URL!

    override func setUpWithError() throws {
        suiteName = "katikati.backup.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private func service() -> SettingsBackupService {
        SettingsBackupService(defaults: defaults, domainName: suiteName, supportDirectory: dir, appVersion: "1.0")
    }

    func testBackupCarriesOnlyTickedCategories() {
        defaults.set(true, forKey: "com.katikati.notch.enabled")
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        defaults.set("x", forKey: "com.katikati.ai.apiKey")
        let file = service().makeBackup(categories: [.barAndLauncher])
        XCTAssertEqual(Set(file.defaults.keys), ["keptAppBundleIDsV3"])
    }

    func testRegisteredDefaultsAreNotBackedUp() {
        defaults.register(defaults: ["com.katikati.layout.mode": "registered", "com.katikati.notch.enabled": true])
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        let file = service().makeBackup(categories: [.settingsAndShortcuts, .barAndLauncher])
        XCTAssertEqual(Set(file.defaults.keys), ["keptAppBundleIDsV3"], "only values the person set")
    }

    func testNotesAreLeftOutOfTheBackup() {
        let file = service().makeBackup(categories: [.notes, .tasks])
        XCTAssertEqual(file.categories, [.tasks])
    }

    func testTasksFileTravelsWithTheBackup() throws {
        try Data("[1]".utf8).write(to: dir.appendingPathComponent("tasks.json"))
        XCTAssertEqual(service().makeBackup(categories: [.tasks]).files["tasks.json"], Data("[1]".utf8))
    }

    func testRestoreOverwritesAndRemovesKeysTheBackupLacks() throws {
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        defaults.set("old", forKey: "com.katikati.layout.mode")
        let backup = service().makeBackup(categories: [.barAndLauncher])

        defaults.set(["b"], forKey: "keptAppBundleIDsV3")
        defaults.set("new", forKey: "com.katikati.layout.extra")
        defaults.set(false, forKey: "com.katikati.notch.enabled")

        let summary = try service().restore(backup, categories: [.barAndLauncher])
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDsV3"), ["a"])
        XCTAssertEqual(defaults.string(forKey: "com.katikati.layout.mode"), "old")
        XCTAssertNil(defaults.object(forKey: "com.katikati.layout.extra"))
        XCTAssertEqual(defaults.object(forKey: "com.katikati.notch.enabled") as? Bool, false, "unticked category is untouched")
        XCTAssertEqual(summary.defaultsRemoved, 1)
    }

    func testRestoreFirstWritesARestorableSafetyBackup() throws {
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        let backup = service().makeBackup(categories: [.barAndLauncher])
        defaults.set(["b"], forKey: "keptAppBundleIDsV3")

        let summary = try service().restore(backup, categories: [.barAndLauncher])
        let safety = try XCTUnwrap(summary.safetyBackup)
        XCTAssertTrue(safety.lastPathComponent.hasPrefix("Before restore "))
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDsV3"), ["a"])

        try service().restore(from: safety, categories: [.barAndLauncher])
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDsV3"), ["b"], "the safety copy undoes the restore")
    }

    func testRestoreWritesTasksFileAndIgnoresUnsafeNames() throws {
        var file = SettingsBackupFile(appVersion: "1.0", categories: [.tasks],
                                      files: ["tasks.json": Data("[2]".utf8), "../escape.json": Data([0])])
        file.files["Backups/x"] = Data([0])
        let summary = try service().restore(file, categories: [.tasks])
        XCTAssertEqual(summary.filesWritten, 1)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("tasks.json")), Data("[2]".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.deletingLastPathComponent().appendingPathComponent("escape.json").path))
    }

    func testRestoreSkipsCategoriesTheFileDoesNotHold() throws {
        defaults.set(["keep"], forKey: "keptAppBundleIDsV3")
        let file = SettingsBackupFile(appVersion: "1.0", categories: [.tasks])
        try service().restore(file, categories: [.barAndLauncher])
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDsV3"), ["keep"])
    }

    func testExportThenImportFromDisk() throws {
        defaults.set(true, forKey: "com.katikati.notch.enabled")
        let url = dir.appendingPathComponent("out.katikati")
        try service().export(categories: [.settingsAndShortcuts], to: url)
        defaults.set(false, forKey: "com.katikati.notch.enabled")
        try service().restore(from: url, categories: [.settingsAndShortcuts])
        XCTAssertEqual(defaults.object(forKey: "com.katikati.notch.enabled") as? Bool, true)
    }
}

/// 笔记经密码信封进出备份：不写 note.key、不落明文文件、错误密码时什么都不改。
final class SettingsBackupNotesTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var dir: URL!
    private var stored: [Data] = []
    private var imported: [[Data]] = []

    override func setUpWithError() throws {
        suiteName = "katikati.backup.notes.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        stored = [Data(#"{"id":"n1","body":"hello"}"#.utf8)]
        imported = []
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: dir)
    }

    private func service(withNotes: Bool = true) -> SettingsBackupService {
        let bridge = SettingsBackupService.NotesBridge(
            exportPlaintext: { [unowned self] in stored },
            importPlaintext: { [unowned self] docs in imported.append(docs); return docs.count },
            iterations: 1_000)
        return SettingsBackupService(defaults: defaults, domainName: suiteName, supportDirectory: dir,
                                     appVersion: "1.0", notes: withNotes ? bridge : nil)
    }

    func testNotesNeedAPassword() {
        XCTAssertThrowsError(try service().makeBackup(categories: [.notes], notesPassword: nil)) {
            XCTAssertEqual($0 as? SettingsBackupService.NotesError, .passwordRequired)
        }
        XCTAssertThrowsError(try service().makeBackup(categories: [.notes], notesPassword: "")) {
            XCTAssertEqual($0 as? SettingsBackupService.NotesError, .passwordRequired)
        }
    }

    func testNotesWithoutAStoreAreRefused() {
        XCTAssertThrowsError(try service(withNotes: false).makeBackup(categories: [.notes], notesPassword: "pw")) {
            XCTAssertEqual($0 as? SettingsBackupService.NotesError, .unavailable)
        }
    }

    func testBackupHoldsOnlyTheSealedEnvelope() throws {
        let file = try service().makeBackup(categories: [.notes], notesPassword: "pw")
        XCTAssertTrue(file.notesPasswordProtected)
        XCTAssertEqual(file.categories, [.notes])
        XCTAssertEqual(Set(file.files.keys), [SettingsBackupFile.sealedNotesFileName])
        let json = try file.encoded()
        XCTAssertNil(json.range(of: Data("hello".utf8)), "no plaintext in the file")
    }

    func testRestoreReSavesNotesThroughTheStore() throws {
        let file = try service().makeBackup(categories: [.notes], notesPassword: "pw")
        let summary = try service().restore(file, categories: [.notes], notesPassword: "pw")
        XCTAssertEqual(summary.notesRestored, 1)
        XCTAssertEqual(imported, [stored])
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Notes").path), "no note files written directly")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("note.key").path))
    }

    func testWrongPasswordChangesNothing() throws {
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        var file = try service().makeBackup(categories: [.notes, .barAndLauncher], notesPassword: "right")
        file.defaults["keptAppBundleIDsV3"] = .array([.string("b")])
        XCTAssertThrowsError(try service().restore(file, categories: [.notes, .barAndLauncher], notesPassword: "wrong")) {
            XCTAssertEqual($0 as? SettingsBackupService.NotesError, .wrongPassword)
        }
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDsV3"), ["a"])
        XCTAssertTrue(imported.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: service().backupsDirectory.path), "stopped before the safety copy")
    }

    func testRestoringNotesWithoutAPasswordIsRefused() throws {
        let file = try service().makeBackup(categories: [.notes], notesPassword: "pw")
        XCTAssertThrowsError(try service().restore(file, categories: [.notes])) {
            XCTAssertEqual($0 as? SettingsBackupService.NotesError, .passwordRequired)
        }
    }

    func testUntickedNotesAreLeftAloneEvenIfTheFileHoldsThem() throws {
        defaults.set(["a"], forKey: "keptAppBundleIDsV3")
        let file = try service().makeBackup(categories: [.notes, .barAndLauncher], notesPassword: "pw")
        let summary = try service().restore(file, categories: [.barAndLauncher])
        XCTAssertEqual(summary.notesRestored, 0)
        XCTAssertTrue(imported.isEmpty)
    }

    func testSafetyCopyOfARestoreWithNotesIsSealedUnderTheSamePassword() throws {
        let file = try service().makeBackup(categories: [.notes], notesPassword: "pw")
        let summary = try service().restore(file, categories: [.notes], notesPassword: "pw")
        let safety = try SettingsBackupFile.decode(Data(contentsOf: try XCTUnwrap(summary.safetyBackup)))
        XCTAssertTrue(safety.notesPasswordProtected)
        XCTAssertNotNil(safety.files[SettingsBackupFile.sealedNotesFileName])
    }

    func testAHostileFileCannotWriteTheNoteKey() throws {
        let file = SettingsBackupFile(appVersion: "1.0", categories: [.notes], files: ["note.key": Data(repeating: 1, count: 32)])
        XCTAssertTrue(file.restorableFiles(categories: [.notes]).isEmpty)
    }
}
