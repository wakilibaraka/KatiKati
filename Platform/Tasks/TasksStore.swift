import Foundation

/// `tasks.json` in Application Support/KatiKati. A file that fails to decode is moved aside as `.bak` rather than
/// overwritten, so a bad build can never destroy the list.
struct TasksStore {
    let url: URL

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("KatiKati/tasks.json")
    }

    func load() -> TaskList {
        guard let data = try? Data(contentsOf: url) else { return TaskList() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(TaskList.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: url.appendingPathExtension("bak"))
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("bak"))
            return TaskList()
        }
    }

    func save(_ list: TaskList) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(list).write(to: url, options: .atomic)
    }
}
