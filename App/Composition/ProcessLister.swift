import Foundation

/// Phase 28e: lists running processes for the `!` process-killer route. Reads `ps` once at summon; the
/// per-keystroke filtering is pure (`CommandBarResults`).
enum ProcessLister {
    static func list() -> [ProcessEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap(parse)
    }

    private static func parse(_ line: Substring) -> ProcessEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else { return nil }
        guard let pid = Int32(trimmed[..<space]) else { return nil }
        let path = trimmed[trimmed.index(after: space)...].trimmingCharacters(in: .whitespaces)
        let name = (path as NSString).lastPathComponent
        guard !name.isEmpty else { return nil }
        return ProcessEntry(pid: pid, name: name, path: path)
    }
}
