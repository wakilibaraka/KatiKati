import Combine
import Foundation
import SQLite3

// Phase 33d — AgentUsageService: Local-only, zero-telemetry agent usage aggregator.
// Watches local session logs and Claude app plan limits via FSEvents / DispatchSource.
// Strict zero idle CPU gate: 0 background timers while idle; coalesced 1.0s updates during active turns.
// Phase 48c — reads every AI tool's own usage store (Claude, OpenCode, Codex, Copilot when it keeps
// accounting), off the main thread, read-only, never copied. A tool is counted only when its store
// records tokens or cost; a store with no accounting contributes nothing rather than a converted guess.

/// OpenCode's own store (~/.local/share/opencode/opencode.db): session/session_v2 carry the tool's
/// own cost + token columns. Read with explicit columns (never SELECT *) so a schema without
/// accounting simply fails to prepare and yields nothing.
enum AgentOpenCodeReader {
    static func read(dbPath: String, now: Date = Date(), calendar: Calendar = .current) -> (read: Bool, rows: [AgentStoreRow]) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return (false, [])
        }
        defer { sqlite3_close(db) }

        let startOfDay = calendar.startOfDay(for: now)
        let lo = Int64(startOfDay.timeIntervalSince1970 * 1000)
        let hi = lo + 86_400_000

        var rows: [AgentStoreRow] = []
        var sawAccounting = false
        for table in ["session", "session_v2"] {
            let sql = """
            SELECT cost, tokens_input, tokens_output, tokens_reasoning, tokens_cache_read,
                   tokens_cache_write, model, title, directory, time_updated
            FROM "\(table)" WHERE time_updated >= ? AND time_updated < ?
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
                continue
            }
            defer { sqlite3_finalize(query) }
            sawAccounting = true
            sqlite3_bind_int64(query, 1, lo)
            sqlite3_bind_int64(query, 2, hi)
            while sqlite3_step(query) == SQLITE_ROW {
                let cost = sqlite3_column_double(query, 0)
                let tokens = AgentTokens(
                    input: Int(sqlite3_column_int64(query, 1)),
                    cacheWrite: Int(sqlite3_column_int64(query, 5)),
                    cacheRead: Int(sqlite3_column_int64(query, 4)),
                    output: Int(sqlite3_column_int64(query, 2)),
                    reasoning: Int(sqlite3_column_int64(query, 3))
                )
                let modelRaw = sqlite3_column_text(query, 6).map { String(cString: $0) }
                let title = sqlite3_column_text(query, 7).map { String(cString: $0) } ?? ""
                let directory = sqlite3_column_text(query, 8).map { String(cString: $0) } ?? ""
                let millis = sqlite3_column_int64(query, 9)
                rows.append(AgentStoreRow(
                    tokens: tokens,
                    storeCost: cost,
                    model: AgentOpenCodeParser.modelName(from: modelRaw) ?? AgentProvider.opencode.displayName,
                    project: title.isEmpty ? (directory as NSString).lastPathComponent : title,
                    lastActivity: Date(timeIntervalSince1970: Double(millis) / 1000.0)
                ))
            }
        }
        return (sawAccounting, rows)
    }
}

/// Copilot's chat store: sessions/turns hold ids, cwd and message text — no token or cost
/// columns (witnessed 2026-10-17). Opened to check, never counted. If a future schema gains
/// accounting columns, `hasAccounting` flips and this is where its reader goes.
enum AgentCopilotReader {
    static func read(dbPath: String) -> (read: Bool, rows: [AgentStoreRow]) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            if let handle { sqlite3_close(handle) }
            return (false, [])
        }
        defer { sqlite3_close(db) }

        var columns: [String] = []
        for table in ["sessions", "turns"] {
            let sql = "SELECT name FROM PRAGMA_table_info('\(table)')"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let query = statement else {
                continue
            }
            defer { sqlite3_finalize(query) }
            while sqlite3_step(query) == SQLITE_ROW {
                if let text = sqlite3_column_text(query, 0) {
                    columns.append(String(cString: text))
                }
            }
        }
        // No accounting columns: the store is checked, nothing is counted.
        guard AgentCopilotParser.hasAccounting(columns: columns) else { return (false, []) }
        return (true, [])
    }
}

@MainActor
final class AgentUsageService: ObservableObject {
    static let shared = AgentUsageService()

    @Published public private(set) var snapshot = AgentUsageSnapshot()

    private let backgroundQueue = DispatchQueue(label: "com.katikati.agent-usage", qos: .utility)
    private var fileWatchers: [DispatchSourceFileSystemObject] = []
    private var watchedPaths: Set<String> = []
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
        watchedPaths.removeAll()
        activeTurnWork?.cancel()
        activeTurnWork = nil
    }

    /// Refresh snapshot asynchronously from local disk logs.
    func refreshAsync() {
        backgroundQueue.async { [weak self] in
            let home = FileManager.default.homeDirectoryForCurrentUser
            let calendar = Calendar.current
            let now = Date()
            var newSnapshot = AgentUsageSnapshot()

            // 1. Read Claude Desktop plan limits
            let planURL = home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
            if let data = try? Data(contentsOf: planURL),
               let limits = AgentClaudeParser.parsePlanUsageHistory(data: data) {
                newSnapshot.limits[.claude] = limits
            }

            var totalTokens = AgentTokens()
            var totalCost = 0.0
            var totalSavings = 0.0
            var recentTurns: [AgentLiveTurn] = []
            let isRecent: (Date) -> Bool = { $0.timeIntervalSinceNow > -300 }

            // 2. Read Claude Code project transcripts (today's files, last 64 KB)
            // 52c — the opt-in hook's newest event beats the mtime window: Stop ends a turn at once,
            // UserPromptSubmit keeps it active while Claude works. No usable event keeps the old rule.
            let hookLog = (try? String(contentsOf: ClaudeHookConfig.logURL(home: home), encoding: .utf8)) ?? ""
            let claudeWorking = ClaudeHookStatus.workingOverride(log: hookLog, now: now)
            let claudeProjectsURL = home.appendingPathComponent(".claude/projects")
            let claudeEnumerator = FileManager.default.enumerator(at: claudeProjectsURL, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])
            if claudeEnumerator != nil {
                newSnapshot.sourcesRead.append(.claude)
            }
            if let enumerator = claudeEnumerator {
                var day = AgentProviderDay()
                var hadRows = false
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
                                    hadRows = true
                                    totalTokens += parsed.tokens
                                    day.tokens += parsed.tokens
                                    let modelName = parsed.model ?? "claude-3-7-sonnet"
                                    let (c, s) = AgentPricing.cost(tokens: parsed.tokens, model: modelName)
                                    totalCost += c
                                    day.cost += c
                                    totalSavings += s

                                    let projectName = fileURL.deletingLastPathComponent().lastPathComponent
                                    recentTurns.append(AgentLiveTurn(
                                        id: "\(fileURL.lastPathComponent)-\(modDate.timeIntervalSince1970)",
                                        provider: .claude,
                                        model: AgentPricing.displayName(modelName),
                                        project: projectName,
                                        started: parsed.timestamp ?? modDate,
                                        lastActivity: modDate,
                                        tokens: parsed.tokens,
                                        cost: c,
                                        isActive: claudeWorking ?? isRecent(modDate)
                                    ))
                                }
                            }
                        }
                    }
                }
                if hadRows {
                    day.costIsStoreReported = false
                    newSnapshot.providerToday[.claude] = day
                }
            }

            // 3. Read OpenCode's own store: the cost column is the tool's number, not a price we computed.
            let openCodeDB = home.appendingPathComponent(".local/share/opencode/opencode.db").path
            let openCode = AgentOpenCodeReader.read(dbPath: openCodeDB, now: now, calendar: calendar)
            if openCode.read {
                newSnapshot.sourcesRead.append(.opencode)
            }
            if !openCode.rows.isEmpty {
                var day = AgentProviderDay(costIsStoreReported: true)
                for row in openCode.rows {
                    totalTokens += row.tokens
                    day.tokens += row.tokens
                    totalCost += row.storeCost
                    day.cost += row.storeCost
                    recentTurns.append(AgentLiveTurn(
                        id: "opencode-\(row.project)-\(row.lastActivity.timeIntervalSince1970)",
                        provider: .opencode,
                        model: row.model,
                        project: row.project,
                        started: row.lastActivity,
                        lastActivity: row.lastActivity,
                        tokens: row.tokens,
                        cost: row.storeCost,
                        isActive: isRecent(row.lastActivity)
                    ))
                }
                newSnapshot.providerToday[.opencode] = day
            }

            // 4. Read Codex rollout logs when the home exists (absent on machines without Codex).
            // Cost is never in the log — priced here, marked estimated.
            let codexHome = home.appendingPathComponent(".codex")
            var codexRead = false
            var codexDay = AgentProviderDay()
            var codexHadRows = false
            for subdir in ["sessions", "archived_sessions"] {
                let dir = codexHome.appendingPathComponent(subdir)
                guard let codexFiles = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                    continue
                }
                codexRead = true
                while let fileURL = codexFiles.nextObject() as? URL {
                    guard fileURL.pathExtension == "jsonl" else { continue }
                    guard let fileValues = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
                          let modDate = fileValues.contentModificationDate,
                          calendar.isDateInToday(modDate) else {
                        continue
                    }
                    if let fileHandle = try? FileHandle(forReadingFrom: fileURL) {
                        let fileSize = fileHandle.seekToEndOfFile()
                        let readOffset = max(0, Int64(fileSize) - 64 * 1024)
                        fileHandle.seek(toFileOffset: UInt64(readOffset))
                        let data = fileHandle.readDataToEndOfFile()
                        try? fileHandle.close()
                        if let content = String(data: data, encoding: .utf8) {
                            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                                if let parsed = AgentCodexParser.parseJSONLLine(line) {
                                    codexHadRows = true
                                    totalTokens += parsed.tokens
                                    codexDay.tokens += parsed.tokens
                                    let modelName = parsed.model ?? "codex"
                                    let (c, _) = AgentPricing.cost(tokens: parsed.tokens, model: modelName)
                                    totalCost += c
                                    codexDay.cost += c
                                    recentTurns.append(AgentLiveTurn(
                                        id: "codex-\(fileURL.lastPathComponent)-\(modDate.timeIntervalSince1970)",
                                        provider: .codex,
                                        model: parsed.model ?? AgentProvider.codex.displayName,
                                        project: fileURL.deletingLastPathComponent().lastPathComponent,
                                        started: modDate,
                                        lastActivity: modDate,
                                        tokens: parsed.tokens,
                                        cost: c,
                                        isActive: isRecent(modDate)
                                    ))
                                }
                            }
                        }
                    }
                }
            }
            if codexRead {
                newSnapshot.sourcesRead.append(.codex)
            }
            if codexHadRows {
                codexDay.costIsStoreReported = false
                newSnapshot.providerToday[.codex] = codexDay
            }

            // 5. Check Copilot's store. It keeps message text, not accounting — checked, never counted.
            let copilotDB = home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/github.copilot-chat/session-store.db").path
            let copilot = AgentCopilotReader.read(dbPath: copilotDB)
            if copilot.read {
                newSnapshot.sourcesRead.append(.copilot)
            }
            if !copilot.rows.isEmpty {
                var day = AgentProviderDay(costIsStoreReported: true)
                for row in copilot.rows {
                    totalTokens += row.tokens
                    day.tokens += row.tokens
                    totalCost += row.storeCost
                    day.cost += row.storeCost
                }
                newSnapshot.providerToday[.copilot] = day
            }

            newSnapshot.todayTokens = totalTokens
            newSnapshot.todayCost = totalCost
            newSnapshot.todaySavings = totalSavings
            newSnapshot.recentTurns = recentTurns.sorted(by: { $0.lastActivity > $1.lastActivity })
            newSnapshot.activeTurn = newSnapshot.recentTurns.first(where: { $0.isActive })

            DispatchQueue.main.async { [weak self] in
                self?.snapshot = newSnapshot
            }
        }
    }

    private func setupFileWatchers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let pathsToWatch = [
            home.appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json").path,
            home.appendingPathComponent(".claude/projects").path,
            home.appendingPathComponent(".local/share/opencode/opencode.db").path,
            home.appendingPathComponent(".codex/sessions").path,
            home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/github.copilot-chat/session-store.db").path,
            ClaudeHookConfig.logURL(home: home).path
        ]

        for path in pathsToWatch { addWatcher(path) }
    }

    /// 52c — the hook log only exists after the first hooked turn, so the installer calls this once the
    /// hook is on; the launch pass above covers every later start.
    func watchHookLog() {
        addWatcher(ClaudeHookConfig.logURL().path)
    }

    private func addWatcher(_ path: String) {
        guard !watchedPaths.contains(path) else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedPaths.insert(path)

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
