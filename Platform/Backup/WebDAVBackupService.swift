import Foundation

enum WebDAVBackupStatus: Equatable {
    case idle
    case checking
    case backingUp
    case restoring
    case success(String)
    case failure(String)

    var isWorking: Bool {
        self == .checking || self == .backingUp || self == .restoring
    }
}

/// Scheduled WebDAV backup and restore (Phase 67A–C). Passwords live only in
/// `WebDAVCredentialStore`; remote snapshots are ordinary `WebDAVSyncEnvelope` JSON files.
@MainActor
final class WebDAVBackupService: ObservableObject {
    static let shared = WebDAVBackupService()

    enum ServiceError: Error, LocalizedError, Equatable {
        case notConfigured
        case noPassword
        case noRemoteData
        case badPayload
        case missingSystemSettingsFile

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Enter the WebDAV server address first."
            case .noPassword: return "Enter the password for this WebDAV server."
            case .noRemoteData: return "No KatiKati sync files were found on the server."
            case .badPayload: return "A sync file on the server is damaged."
            case .missingSystemSettingsFile: return "A KatiKati backup inside the sync file is missing."
            }
        }
    }

    @Published var settings: WebDAVSyncSettings {
        didSet { settings.save(defaults: defaults) }
    }
    @Published var serverURL: String {
        didSet { defaults.set(serverURL, forKey: WebDAVSyncKeys.serverURL) }
    }
    @Published var username: String {
        didSet { defaults.set(username, forKey: WebDAVSyncKeys.username) }
    }
    @Published private(set) var status: WebDAVBackupStatus = .idle
    @Published private(set) var lastRun: Date?

    let supportDirectory: URL
    private let defaults: UserDefaults
    private var scheduler: Timer?
    private var isRunning = false

    init(
        defaults: UserDefaults = .standard,
        supportDirectory: URL? = nil,
        startScheduler: Bool = false
    ) {
        self.defaults = defaults
        let base = supportDirectory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                .map { $0.appendingPathComponent("KatiKati", isDirectory: true) }
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.supportDirectory = base
        self.settings = .load(defaults: defaults)
        self.serverURL = defaults.string(forKey: WebDAVSyncKeys.serverURL) ?? ""
        self.username = defaults.string(forKey: WebDAVSyncKeys.username) ?? ""
        self.lastRun = defaults.object(forKey: WebDAVSyncKeys.lastRun) as? Date
        if startScheduler { self.startScheduler() }
    }

    // MARK: - Credentials

    func savePassword(_ password: String) throws {
        try WebDAVCredentialStore.save(password: password, server: serverURL)
    }

    func deletePassword() {
        WebDAVCredentialStore.delete(server: serverURL)
    }

    func storedPassword() -> String? {
        WebDAVCredentialStore.password(server: serverURL)
    }

    private func makeClient() throws -> WebDAVClient {
        let address = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { throw ServiceError.notConfigured }
        guard let password = storedPassword() else { throw ServiceError.noPassword }
        guard let client = WebDAVClient(
            serverURL: address,
            credentials: WebDAVCredentials(username: username, password: password)
        ) else { throw ServiceError.notConfigured }
        return client
    }

    private var backupService: SettingsBackupService {
        SettingsBackupService(
            defaults: defaults,
            supportDirectory: supportDirectory,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        )
    }

    // MARK: - Operations

    func testConnection() async {
        guard !isRunning else { return }
        isRunning = true
        status = .checking
        defer { isRunning = false }
        do {
            try await makeClient().checkConnection()
            status = .success(String(localized: "Connected to the WebDAV server."))
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    func backupNow() async {
        guard !isRunning else { return }
        isRunning = true
        status = .backingUp
        defer { isRunning = false }
        do {
            let client = try makeClient()
            let plan = WebDAVSyncPlan.upload(settings)
            try await client.ensureDirectory(plan.remoteRoot)
            try await client.ensureDirectory(WebDAVSyncPlanner.join(plan.remoteRoot, plan.deviceSlug))
            var uploaded = 0
            for item in plan.items {
                let envelope = try makeEnvelope(for: item.domain)
                let data = try JSONEncoder().encode(envelope)
                try await client.put(data, to: item.remotePath)
                uploaded += 1
            }
            let manifest = WebDAVSyncManifest(
                schema: WebDAVSyncEnvelope.currentSchema,
                deviceName: settings.deviceName,
                homeDirectory: NSHomeDirectory(),
                savedAt: Date(),
                domains: plan.items.map(\.domain)
            )
            try await client.put(JSONEncoder().encode(manifest), to: plan.manifestPath)
            defaults.set(Date(), forKey: WebDAVSyncKeys.lastRun)
            lastRun = Date()
            status = .success(String(
                format: String(localized: "Backed up %lld parts to the WebDAV server."),
                uploaded
            ))
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    func restoreNow() async {
        guard !isRunning else { return }
        isRunning = true
        status = .restoring
        defer { isRunning = false }
        do {
            let client = try makeClient()
            let plan = WebDAVSyncPlan.restore(settings)
            // Download everything before touching local data, so a dropped connection changes nothing.
            var envelopes: [WebDAVSyncDomain: WebDAVSyncEnvelope] = [:]
            for item in plan.items {
                do {
                    let data = try await client.get(item.remotePath)
                    let envelope = try JSONDecoder().decode(WebDAVSyncEnvelope.self, from: data)
                    guard envelope.schema <= WebDAVSyncEnvelope.currentSchema else { throw ServiceError.badPayload }
                    envelopes[item.domain] = envelope
                } catch WebDAVError.notFound {
                    continue
                } catch WebDAVError.status(404) {
                    continue
                }
            }
            guard !envelopes.isEmpty else { throw ServiceError.noRemoteData }
            // Automatic local safety backup before anything is overwritten.
            _ = try backupService.writeSafetyBackup(
                categories: [.settingsAndShortcuts, .barAndLauncher, .tasks],
                notesPassword: nil
            )
            for (domain, envelope) in envelopes {
                try apply(envelope, domain: domain)
            }
            status = .success(String(localized: "Restored from the WebDAV server. Restart KatiKati to finish applying the settings."))
        } catch {
            status = .failure(error.localizedDescription)
        }
    }

    // MARK: - Scheduling

    func startScheduler() {
        scheduler?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.runIfDue() }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        scheduler = timer
    }

    func stopScheduler() {
        scheduler?.invalidate()
        scheduler = nil
    }

    private func runIfDue() async {
        guard settings.schedule != .off, !isRunning,
              let interval = settings.schedule.interval,
              !serverURL.isEmpty,
              storedPassword() != nil
        else { return }
        if let lastRun, Date().timeIntervalSince(lastRun) < interval { return }
        await backupNow()
    }

    // MARK: - Envelopes

    func makeEnvelope(for domain: WebDAVSyncDomain) throws -> WebDAVSyncEnvelope {
        var envelope = WebDAVSyncEnvelope(domain: domain, deviceName: settings.deviceName)
        switch domain {
        case .desktopBoxesAndStyles:
            if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("desktop-boxes.json")) {
                envelope.files["desktop-boxes.json"] = data
            }
            envelope.defaults = desktopDefaults()
        case .todos:
            if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("tasks.json")) {
                envelope.files["tasks.json"] = data
            }
        case .quickCaptureAndNotes:
            if let data = try? Data(contentsOf: supportDirectory.appendingPathComponent("desktop-capture.json")) {
                envelope.files["desktop-capture.json"] = data
            }
            for note in noteFiles() {
                envelope.files["Notes/" + note.lastPathComponent] = try? Data(contentsOf: note)
            }
        case .settingsAndShortcuts:
            var backup = backupService.makeBackup(categories: [.settingsAndShortcuts, .barAndLauncher])
            // Desktop boxes/capture and desktop appearance are their own domains; keep them out of the
            // settings payload so disabling one of those toggles really leaves it untouched.
            backup.files = [:]
            backup.defaults = backup.defaults.filter { !$0.key.hasPrefix("com.katikati.desktop.") }
            envelope.files["settings.katikati"] = try backup.encoded()
            envelope.defaults = backup.defaults
        }
        return envelope
    }

    private func desktopDefaults() -> [String: BackupValue] {
        let domain = Bundle.main.bundleIdentifier ?? "com.katikati.app"
        let all = defaults.persistentDomain(forName: domain) ?? [:]
        var values: [String: BackupValue] = [:]
        for (key, value) in all where key.hasPrefix("com.katikati.desktop.") {
            guard !SettingsBackupKeys.isExcluded(key), let converted = BackupValue(propertyList: value) else { continue }
            values[key] = converted
        }
        return values
    }

    private func noteFiles() -> [URL] {
        let directory = NotesStore.defaultDirectory()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries.filter { url in
            let name = url.lastPathComponent
            guard name != "note.key", !name.hasSuffix(".key") else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }
    }

    // MARK: - Applying

    private func apply(_ envelope: WebDAVSyncEnvelope, domain: WebDAVSyncDomain) throws {
        let home = NSHomeDirectory()
        switch domain {
        case .desktopBoxesAndStyles:
            if let raw = envelope.files["desktop-boxes.json"] {
                let remapped = WebDAVSyncPlanner.remapHomePaths(
                    in: raw, from: envelope.homeDirectory, to: home
                ) ?? raw
                let local = try? Data(contentsOf: supportDirectory.appendingPathComponent("desktop-boxes.json"))
                if let data = WebDAVSyncPlanner.mergedFileData(local: local, remote: remapped, mode: settings.restoreMode) {
                    try write(data, name: "desktop-boxes.json")
                }
            }
            applyDefaults(envelope.defaults, prefixes: ["com.katikati.desktop."])
        case .todos:
            guard let remote = envelope.files["tasks.json"] else { return }
            let local = try? Data(contentsOf: supportDirectory.appendingPathComponent("tasks.json"))
            if let data = WebDAVSyncPlanner.mergedFileData(local: local, remote: remote, mode: settings.restoreMode) {
                try write(data, name: "tasks.json")
            }
        case .quickCaptureAndNotes:
            if let remote = envelope.files["desktop-capture.json"] {
                let local = try? Data(contentsOf: supportDirectory.appendingPathComponent("desktop-capture.json"))
                if let data = WebDAVSyncPlanner.mergedFileData(local: local, remote: remote, mode: settings.restoreMode) {
                    try write(data, name: "desktop-capture.json")
                }
            }
            for (name, data) in envelope.files where name.hasPrefix("Notes/") {
                guard SettingsBackupFile.isSafeFileName(name) else { continue }
                let target = supportDirectory.appendingPathComponent(name)
                if settings.restoreMode == .merge, FileManager.default.fileExists(atPath: target.path) { continue }
                try write(data, name: name)
            }
        case .settingsAndShortcuts:
            guard let data = envelope.files["settings.katikati"] else { throw ServiceError.missingSystemSettingsFile }
            var backup = try SettingsBackupFile.decode(data)
            // `settingsAndShortcuts` also classifies `com.katikati.desktop.*` keys. Carry the current
            // desktop values through both restore modes so the Desktop Boxes domain stays authoritative.
            for (key, value) in desktopDefaults() { backup.defaults[key] = value }
            let categories: Set<BackupCategory> = [.settingsAndShortcuts, .barAndLauncher]
            switch settings.restoreMode {
            case .merge:
                try backupService.merge(backup, categories: categories)
            case .snapshotFaithful:
                try backupService.restore(backup, categories: categories, notesPassword: nil)
            }
        }
    }

    private func applyDefaults(_ incoming: [String: BackupValue], prefixes: [String]) {
        let domain = Bundle.main.bundleIdentifier ?? "com.katikati.app"
        let existing = defaults.persistentDomain(forName: domain) ?? [:]
        let remote = incoming.filter { key, _ in
            prefixes.contains(where: key.hasPrefix) && !SettingsBackupKeys.isExcluded(key)
        }
        if settings.restoreMode == .snapshotFaithful {
            for key in existing.keys where prefixes.contains(where: key.hasPrefix) && !SettingsBackupKeys.isExcluded(key) {
                if remote[key] == nil { defaults.removeObject(forKey: key) }
            }
        }
        for (key, value) in remote { defaults.set(value.propertyList, forKey: key) }
    }

    private func write(_ data: Data, name: String) throws {
        guard SettingsBackupFile.isSafeFileName(name) else { throw ServiceError.badPayload }
        let target = supportDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }
}

extension WebDAVSyncDomain {
    /// User-facing name used by the WebDAV settings card.
    var displayName: String {
        switch self {
        case .desktopBoxesAndStyles: return String(localized: "Desktop Boxes & Styles")
        case .todos: return String(localized: "Todos")
        case .quickCaptureAndNotes: return String(localized: "Quick Capture & Notes")
        case .settingsAndShortcuts: return String(localized: "Settings & Shortcuts")
        }
    }
}
