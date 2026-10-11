import Foundation

/// `screentime.json` in Application Support/KatiKati: bundle ids, display names and seconds per day, nothing else.
/// Local only (never synced or sent anywhere). A file that fails to decode is moved aside as `.bak`.
struct ScreenTimeStore {
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KatiKati/screentime.json")
    }

    func load() -> ScreenTimeLedger {
        guard let data = try? Data(contentsOf: url) else { return ScreenTimeLedger() }
        do { return try JSONDecoder().decode(ScreenTimeLedger.self, from: data) } catch {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
            return ScreenTimeLedger()
        }
    }

    func save(_ ledger: ScreenTimeLedger) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }

    func deleteAll() { try? FileManager.default.removeItem(at: url) }
}
