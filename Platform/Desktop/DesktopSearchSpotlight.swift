import Foundation

/// Spotlight file provider for desktop search. `mdfind` with NUL-separated output so spaces survive;
/// results pass through `SearchPathFilter` before they reach the UI.
enum DesktopSearchSpotlight {
    static func search(
        query: String,
        filter: SearchPathFilter,
        limit: Int
    ) -> [DesktopSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let escaped = trimmed.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let predicate = "kMDItemFSName == \"*\(escaped)*\"cd"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["-0", predicate]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        let handle = output.fileHandleForReading
        let nul = UInt8(0)
        var buffer = Data()
        var results: [DesktopSearchResult] = []
        let scanLimit = max(limit * 6, limit + 40)

        while results.count < limit {
            if Task.isCancelled { break }
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let index = buffer.firstIndex(of: nul) {
                let pathData = buffer.subdata(in: 0..<index)
                buffer.removeSubrange(0...index)
                guard !pathData.isEmpty, let path = String(data: pathData, encoding: .utf8) else { continue }
                guard filter.allows(path) else { continue }
                let name = (path as NSString).lastPathComponent
                results.append(DesktopSearchResult(
                    id: "file:\(path)",
                    provider: .file,
                    title: name.isEmpty ? path : name,
                    subtitle: (path as NSString).deletingLastPathComponent,
                    path: path,
                    symbol: "doc"
                ))
                if results.count >= limit { break }
            }
            if buffer.count > 1_000_000 { buffer.removeAll(keepingCapacity: true) }
            if results.count >= scanLimit { break }
        }

        if process.isRunning { process.terminate() }
        try? handle.close()
        process.waitUntilExit()
        return results
    }
}
