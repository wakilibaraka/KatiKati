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
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        var buffer = Data()
        var results: [FileEntry] = []
        let handle = output.fileHandleForReading
        let nul = UInt8(0)

        while results.count < limit {
            if Task.isCancelled { break }
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)

            while let nulIndex = buffer.firstIndex(of: nul) {
                let pathData = buffer.subdata(in: 0..<nulIndex)
                buffer.removeSubrange(0...nulIndex)
                if !pathData.isEmpty, let path = String(data: pathData, encoding: .utf8) {
                    let name = (path as NSString).lastPathComponent
                    results.append(FileEntry(path: path, name: name))
                    if results.count >= limit { break }
                }
            }
        }

        if process.isRunning {
            process.terminate()
        }
        try? handle.close()
        process.waitUntilExit()
        return results
    }
}
