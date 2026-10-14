import Foundation

/// Phase 29g: runs a `FileQuery` through Spotlight (`mdfind`). Fail-closed; NUL-separated output so
/// paths with spaces survive. Kept off the main thread by the caller.
enum FileSearchService {
    static func search(_ query: FileQuery, limit: Int = 25) -> [FileEntry] {
        let predicate = query.predicate()
        guard !predicate.isEmpty else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        var arguments = ["-0"]
        if let path = query.path, !path.isEmpty { arguments += ["-onlyin", path] }
        arguments.append(predicate)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(separator: "\0", omittingEmptySubsequences: true).prefix(limit).map { path in
            let value = String(path)
            return FileEntry(path: value, name: (value as NSString).lastPathComponent)
        }
    }
}
