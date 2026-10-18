import Foundation
import SQLite3
import XCTest
@testable import KatiKati

final class AgentUsageTests: XCTestCase {

    func testTokenAggregationAndHitRate() {
        var t1 = AgentTokens(input: 1000, cacheWrite: 200, cacheRead: 800, output: 500, reasoning: 100)
        let t2 = AgentTokens(input: 500, cacheWrite: 100, cacheRead: 400, output: 250, reasoning: 50)

        t1 += t2
        XCTAssertEqual(t1.input, 1500)
        XCTAssertEqual(t1.cacheWrite, 300)
        XCTAssertEqual(t1.cacheRead, 1200)
        XCTAssertEqual(t1.output, 750)
        XCTAssertEqual(t1.reasoning, 150)
        XCTAssertEqual(t1.total, 3750)
        XCTAssertEqual(t1.prompt, 3000)

        // Cache hit rate = cacheRead / prompt = 1200 / 3000 = 0.40 (40%)
        XCTAssertEqual(t1.cacheHitRate, 0.4, accuracy: 0.001)
    }

    func testPricingCalculationForClaude37Sonnet() {
        // 1,000,000 input ($3.00), 100,000 output ($1.50), 500,000 cache read ($0.15)
        let tokens = AgentTokens(input: 1_000_000, cacheWrite: 0, cacheRead: 500_000, output: 100_000, reasoning: 0)
        let (cost, savings) = AgentPricing.cost(tokens: tokens, model: "claude-3-7-sonnet-20250219")

        // Expected cost: $3.00 + $1.50 + $0.15 = $4.65
        XCTAssertEqual(cost, 4.65, accuracy: 0.01)
        // Savings on cache read: 500k * ($3.00 - $0.30) / 1M = 0.5 * $2.70 = $1.35
        XCTAssertEqual(savings, 1.35, accuracy: 0.01)
    }

    func testModelDisplayNameFormatting() {
        XCTAssertEqual(AgentPricing.displayName("claude-3-7-sonnet-20250219"), "Claude 3.7 Sonnet")
        XCTAssertEqual(AgentPricing.displayName("claude-3-5-haiku-20241022"), "Claude 3.5 Haiku")
        XCTAssertEqual(AgentPricing.displayName("claude-3-opus-20240229"), "Claude 3 Opus")
        XCTAssertEqual(AgentPricing.displayName("gpt-4o-2024-08-06"), "GPT-4o")
        XCTAssertEqual(AgentPricing.displayName("gpt-4o-mini"), "GPT-4o mini")
    }

    func testPlanUsageHistoryParsing() {
        let sampleJSON = """
        {
            "version": 2,
            "samples": [
                {
                    "t": 1791961064981,
                    "org": "f9512503-5c71-4dd0-b375-640a3129750a",
                    "u": {
                        "fh": 25.0,
                        "sd": 80.0
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let limits = AgentClaudeParser.parsePlanUsageHistory(data: sampleJSON, now: Date(timeIntervalSince1970: 1791961064.981))
        XCTAssertNotNil(limits)
        XCTAssertEqual(limits?.provider, .claude)
        XCTAssertEqual(limits?.windows.count, 2)

        guard let sessionWindow = limits?.windows.first(where: { $0.kind == .session }),
              let weeklyWindow = limits?.windows.first(where: { $0.kind == .weekly }) else {
            XCTFail("Expected session and weekly windows")
            return
        }
        XCTAssertEqual(sessionWindow.usedPercent, 25.0)
        XCTAssertEqual(sessionWindow.usedFraction, 0.25, accuracy: 0.001)
        XCTAssertEqual(sessionWindow.remainingFraction, 0.75, accuracy: 0.001)

        XCTAssertEqual(weeklyWindow.usedPercent, 80.0)
        XCTAssertEqual(weeklyWindow.usedFraction, 0.80, accuracy: 0.001)
    }

    func testJSONLTranscriptLineParsing() {
        let line = """
        {"type":"assistant","message":{"model":"claude-3-7-sonnet","usage":{"input_tokens":1200,"output_tokens":350,"cache_read_input_tokens":800,"cache_creation_input_tokens":100}},"timestamp":"2026-10-15T00:00:00Z"}
        """

        let result = AgentClaudeParser.parseJSONLLine(line)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.model, "claude-3-7-sonnet")
        XCTAssertEqual(result?.tokens.input, 1200)
        XCTAssertEqual(result?.tokens.output, 350)
        XCTAssertEqual(result?.tokens.cacheRead, 800)
        XCTAssertEqual(result?.tokens.cacheWrite, 100)
    }

    // Phase 48c — OpenCode session times are unix milliseconds, not seconds.
    func testOpenCodeMillisDayBoundary() {
        let now = Date()
        let todayMillis = Int64(now.timeIntervalSince1970 * 1000)
        XCTAssertTrue(AgentOpenCodeParser.isToday(millis: todayMillis, now: now))
        // The same digits read as seconds would land in 1970 — never today.
        XCTAssertFalse(AgentOpenCodeParser.isToday(millis: Int64(now.timeIntervalSince1970), now: now))
        let yesterdayMillis = todayMillis - 86_400_000
        XCTAssertFalse(AgentOpenCodeParser.isToday(millis: yesterdayMillis, now: now))
    }

    func testOpenCodeModelBlobUnpacksToId() {
        XCTAssertEqual(
            AgentOpenCodeParser.modelName(from: #"{"id":"space-bunny-free","providerID":"opencode"}"#),
            "space-bunny-free"
        )
        XCTAssertEqual(AgentOpenCodeParser.modelName(from: "gpt-4o"), "gpt-4o")
        XCTAssertNil(AgentOpenCodeParser.modelName(from: nil))
        XCTAssertNil(AgentOpenCodeParser.modelName(from: ""))
    }

    // Phase 48c — the reader against a real (temporary) store: today's rows counted,
    // older rows ignored, explicit columns only.
    func testOpenCodeReaderCountsTodayOnly() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        var setup: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &setup), SQLITE_OK)
        guard let db = setup else { XCTFail("could not create temp db"); return }
        defer { sqlite3_close(db) }
        let create = """
        CREATE TABLE session (cost REAL DEFAULT 0 NOT NULL, tokens_input INTEGER DEFAULT 0 NOT NULL,
        tokens_output INTEGER DEFAULT 0 NOT NULL, tokens_reasoning INTEGER DEFAULT 0 NOT NULL,
        tokens_cache_read INTEGER DEFAULT 0 NOT NULL, tokens_cache_write INTEGER DEFAULT 0 NOT NULL,
        model TEXT, title TEXT, directory TEXT, time_updated INTEGER NOT NULL)
        """
        XCTAssertEqual(sqlite3_exec(db, create, nil, nil, nil), SQLITE_OK)
        let now = Date()
        let todayMillis = Int64(now.timeIntervalSince1970 * 1000)
        let oldMillis = todayMillis - 3 * 86_400_000
        let insert = "INSERT INTO session VALUES (1.5, 100, 50, 0, 0, 0, 'm', 'Proj', '/tmp', \(todayMillis));" +
            "INSERT INTO session VALUES (9.0, 900, 900, 0, 0, 0, 'm', 'Old', '/tmp', \(oldMillis));"
        XCTAssertEqual(sqlite3_exec(db, insert, nil, nil, nil), SQLITE_OK)

        let result = AgentOpenCodeReader.read(dbPath: dbPath, now: now)
        XCTAssertTrue(result.read)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows.first?.tokens.input, 100)
        XCTAssertEqual(result.rows.first?.storeCost ?? -1, 1.5, accuracy: 0.001)
        XCTAssertEqual(result.rows.first?.project, "Proj")
    }

    func testOpenCodeReaderReportsUnreadableStore() {
        let result = AgentOpenCodeReader.read(dbPath: "/nonexistent-\(UUID().uuidString)/opencode.db")
        XCTAssertFalse(result.read)
        XCTAssertTrue(result.rows.isEmpty)
    }

    // Phase 48c — Copilot's sessions/turns carry ids and message text, no token or cost
    // columns: checked, never counted. A schema that actually records accounting flips the gate.
    func testCopilotGateRejectsMessageTextSchema() {
        XCTAssertFalse(AgentCopilotParser.hasAccounting(columns: [
            "id", "cwd", "repository", "summary", "session_id", "turn_index",
            "user_message", "assistant_response", "timestamp"
        ]))
        XCTAssertTrue(AgentCopilotParser.hasAccounting(columns: ["session_id", "input_tokens", "output_tokens"]))
    }

    func testCopilotReaderYieldsNothingForCurrentStore() throws {
        let dbPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db").path
        defer { try? FileManager.default.removeItem(atPath: dbPath) }
        var setup: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &setup), SQLITE_OK)
        guard let db = setup else { XCTFail("could not create temp db"); return }
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE turns (id INTEGER PRIMARY KEY, session_id TEXT, user_message TEXT)", nil, nil, nil), SQLITE_OK)
        let result = AgentCopilotReader.read(dbPath: dbPath)
        XCTAssertFalse(result.read)
        XCTAssertTrue(result.rows.isEmpty)
    }

    // Phase 48c — Codex rollout scan is tolerant: the token_count envelope evolves,
    // so any nested usage object counts; a line without one does not.
    func testCodexTokenCountLine() {
        let line = #"{"timestamp":"2026-10-17T10:00:00Z","payload":{"type":"token_count","info":{"input_tokens":60,"output_tokens":40,"model":"gpt-5.6"}}}"#
        let parsed = AgentCodexParser.parseJSONLLine(line)
        XCTAssertEqual(parsed?.tokens.input, 60)
        XCTAssertEqual(parsed?.tokens.output, 40)
        XCTAssertEqual(parsed?.model, "gpt-5.6")
    }

    func testCodexLineWithoutUsageYieldsNothing() {
        XCTAssertNil(AgentCodexParser.parseJSONLLine(#"{"type":"session_meta","model":"gpt-5.6"}"#))
        XCTAssertNil(AgentCodexParser.parseJSONLLine("not json at all"))
    }

    // Phase 48c — the page names exactly the stores read and says which cost is whose.
    func testSnapshotSourceAttribution() {
        var snapshot = AgentUsageSnapshot()
        XCTAssertEqual(snapshot.sourceNames, "")
        XCTAssertEqual(snapshot.costBasisLine, "")
        XCTAssertNil(snapshot.lastMeasuredModel)

        snapshot.sourcesRead = [.claude, .opencode]
        snapshot.providerToday = [
            .claude: AgentProviderDay(tokens: AgentTokens(input: 10, output: 5), cost: 0.01, costIsStoreReported: false),
            .opencode: AgentProviderDay(tokens: AgentTokens(input: 20, output: 1), cost: 0.0, costIsStoreReported: true)
        ]
        snapshot.recentTurns = [AgentLiveTurn(id: "1", provider: .opencode, model: "space-bunny-free",
                                              project: "p", started: Date(), lastActivity: Date(),
                                              tokens: AgentTokens(), cost: 0, isActive: false)]
        XCTAssertEqual(snapshot.sourceNames, "Claude · OpenCode")
        XCTAssertEqual(snapshot.costBasisLine, "Claude estimated · OpenCode reported")
        XCTAssertEqual(snapshot.lastMeasuredModel, "space-bunny-free")
    }

    func testSnapshotFormatting() {
        var snapshot = AgentUsageSnapshot()
        snapshot.todayTokens = AgentTokens(input: 120_000, cacheWrite: 10_000, cacheRead: 50_000, output: 25_000, reasoning: 0)
        snapshot.todayCost = 1.42

        XCTAssertEqual(snapshot.formattedTodayCost, "$1.42")
        XCTAssertEqual(snapshot.formattedTodayTokens, "205.0k")
    }
}
