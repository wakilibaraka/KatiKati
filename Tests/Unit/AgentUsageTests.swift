import Foundation
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

    func testSnapshotFormatting() {
        var snapshot = AgentUsageSnapshot()
        snapshot.todayTokens = AgentTokens(input: 120_000, cacheWrite: 10_000, cacheRead: 50_000, output: 25_000, reasoning: 0)
        snapshot.todayCost = 1.42

        XCTAssertEqual(snapshot.formattedTodayCost, "$1.42")
        XCTAssertEqual(snapshot.formattedTodayTokens, "205.0k")
    }
}
