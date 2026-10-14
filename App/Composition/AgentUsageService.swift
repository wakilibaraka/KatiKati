import Combine
import Foundation

// Phase 33d — AgentUsageService: Local-only, zero-telemetry agent usage aggregator.
// Watches local session logs and Claude app plan limits via FSEvents / DispatchSource.
// Strict zero idle CPU gate: 0 background timers while idle; coalesced 1.0s updates during active turns.

@MainActor
final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published public private(set) var snapshot = AgentUsageSnapshot()

    private let backgroundQueue = DispatchQueue(label: "com.katikati.agent-usage", qos: .utility)
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var isMonitoring = false
    private var activeTurnWork: DispatchWorkItem?

    private init() {
        refreshAsync()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        setupFileWatchers()
    }

    func stopMonitoring() {
        isMonitoring = false
        fileWatchers.forEach { $0.cancel() }
        fileWatchers.removeAll()
        activeTurnWork?.cancel()
        activeTurnWork = nil
    }

    /// Refresh snapshot asynchronously from local disk logs.
    func refreshAsync() {
        backgroundQueue.async { [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            var newSnapshot = AgentUsageSnapshot()

            // 1. Read Claude Desktop plan limits
            let planURL = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
            if let data = try? Data(contentsOf: planURL),
               let limits = AgentClaudeParser.parsePlanUsageHistory(data: data) {
                newSnapshot.limits[.claude] = limits
            }

            // 2. Read Claude Code project transcripts
            let claudeProjectsURL = home.appendingPathComponent(".claude/projects")
            if let enumerator = FileManager.default.enumerator(at: claudeProjectsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var totalTokens = AgentTokens()
                var totalCost = 0.0
                var totalSavings = 0.0
                var recentTurns: [AgentLiveTurn] = []

                let calendar = Calendar.current
                let today = Date()

                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.pathExtension == "jsonl" else { continue }
                    guard let fileValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                          let modDate = fileValues.contentModificationDate,
                          calendar.isDateInToday(modDate) else {
                        continue
                    }

                    // Read last 64KB of the active file to get recent turn data
                    if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
                        let fileSize = fileHandle.seekToEndOfFile()
                        let readOffset = max(0, Int64(fileSize) - 64 * 1024)
                        fileHandle.seek(toFileOffset: UInt64(readOffset))
                        let data = fileHandle.readDataToEndOfFile()
                        try? fileHandle.close()

                        if let content = String(data: data, encoding: .utf8) {
                            let lines = content.components(separatedBy: .newlines)
                            for line in lines where !line.isEmpty {
                                if let parsed = AgentClaudeParser.parseJSONLLine(line) {
                                    totalTokens += parsed.tokens
                                    let modelName = parsed.model ?? "claude-3-7-sonnet"
                                    let (c, s) = AgentPricing.cost(tokens: parsed.tokens, model: modelName)
                                    totalCost += c
                                    totalSavings += s

                                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                                    let isRecent = modDate.timeIntervalSinceNow > -300
                                    recentTurns.append(AgentLiveTurn(
                                        id: "\(fileURL.lastPathComponent)-\(modDate.timeIntervalSince1970)",
                                        provider: .claude,
                                        model: AgentPricing.displayName(modelName),
                                        project: projectName,
                                        started: parsed.timestamp ?? modDate,
                                        lastActivity: modDate,
                                        tokens: parsed.tokens,
                                        cost: c,
                                        isActive: isRecent
                                    ))
                                }
                            }
                        }
                    }
                }

                newSnapshot.todayTokens = totalTokens
                newSnapshot.todayCost = totalCost
                newSnapshot.todaySavings = totalSavings
                newSnapshot.recentTurns = recentTurns.sorted(by: { $0.lastActivity > $1.lastActivity })
                newSnapshot.activeTurn = newSnapshot.recentTurns.first(where: { $0.isActive })
            }

            DispatchQueue.main.async { [weak self] in
                self?.snapshot = newSnapshot
            }
        }
    }

    private func setupFileWatchers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathsToWatch = [
            home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json").path,
            home.appendingPathComponent(".claude/projects").path
        ]

        for path in pathsToWatch {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .attrib], queue: backgroundQueue)
            source.setEventHandler { [weak self] in
                self?.scheduleCoalescedRefresh()
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            fileWatchers.append(source)
        }
    }

    private func scheduleCoalescedRefresh() {
        activeTurnWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refreshAsync()
            }
        }
        activeTurnWork = work
        backgroundQueue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }
}
