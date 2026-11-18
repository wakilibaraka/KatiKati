import XCTest
@testable import KatiKati

final class AgentProcessScanTests: XCTestCase {
    private let ps = """
      100     1   0:01.50 /usr/local/bin/claude --resume
      101   100   0:02.00 /bin/zsh -c npm test
      102   100   0:00.10 /usr/local/bin/claude mcp serve
      200     1   1:00:00.00 node /opt/bin/gemini -p summarize
      300     1   0:00.20 /Applications/Claude.app/Contents/MacOS/Claude
      400     1   0:00.20 grep claude
      500     1   0:00.30 /usr/local/bin/codex exec fix
    garbage line
    """

    func testParseSkipsGarbageAndReadsCPU() {
        let rows = AgentProcessScan.parse(ps)
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows.first { $0.pid == 200 }?.cpuSeconds, 3600)
    }

    func testAgentsMatchKindsAndFoldChildren() {
        let found = AgentProcessScan.agents(AgentProcessScan.parse(ps))
        XCTAssertEqual(found.map(\.name), ["claude", "gemini", "codex"], "desktop app, grep and MCP helper are not agents")
        XCTAssertEqual(found[0].cpuSeconds, 1.5 + 2.0 + 0.1, accuracy: 0.001, "tool calls fold into the agent")
        XCTAssertEqual(found.map(\.background), [false, true, true])
    }

    func testCustomNamesAndWorkingRule() {
        let rows = AgentProcessScan.parse("  7  1  0:05.00 /bin/mybot --go")
        let found = AgentProcessScan.agents(rows, extraNames: ["MyBot"])
        XCTAssertEqual(found.count, 1)
        XCTAssertFalse(AgentProcessScan.isWorking(found[0], previousCPU: [:]))
        XCTAssertFalse(AgentProcessScan.isWorking(found[0], previousCPU: [7: 4.9]))
        XCTAssertTrue(AgentProcessScan.isWorking(found[0], previousCPU: [7: 3.0]))
    }

    // MARK: - SLICE NL-1: Universal Loadout Engine Tests

    func testLoadoutJSONRoundTripPreservesUnknownKeys() throws {
        let json = #"{"customFlag":true,"mcpServers":{"github":{"command":"npx"},"slack":{"command":"npx"}}}"#
        let parsed = LoadoutConfigCodec.parseJSONServers(data: Data(json.utf8), provider: .cursor, scope: .global)
        XCTAssertEqual(parsed.map(\.name), ["github", "slack"])
        let disabledData = try LoadoutConfigCodec.toggleJSONServer(data: Data(json.utf8), name: "github", enabled: false)
        let reparsed = LoadoutConfigCodec.parseJSONServers(data: disabledData, provider: .cursor, scope: .global)
        XCTAssertEqual(reparsed.first { $0.name == "github" }?.isEnabled, false)
        XCTAssertEqual(reparsed.first { $0.name == "slack" }?.isEnabled, true)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: disabledData) as? [String: Any])
        XCTAssertEqual(root["customFlag"] as? Bool, true)
        let reEnabled = try LoadoutConfigCodec.toggleJSONServer(data: disabledData, name: "github", enabled: true)
        XCTAssertTrue(LoadoutConfigCodec.parseJSONServers(data: reEnabled, provider: .cursor, scope: .global).allSatisfy(\.isEnabled))
    }

    func testLoadoutTOMLLinePreservingToggle() {
        let toml = """
        # Codex global config
        model = "gpt-5"

        [mcp_servers.filesystem]
        command = "npx"
        """
        XCTAssertEqual(LoadoutConfigCodec.parseTOMLServers(text: toml, scope: .global).first?.isEnabled, true)
        let disabled = LoadoutConfigCodec.toggleTOMLServer(text: toml, name: "filesystem", enabled: false)
        XCTAssertTrue(disabled.contains("# Codex global config"))
        XCTAssertEqual(LoadoutConfigCodec.parseTOMLServers(text: disabled, scope: .global).first?.isEnabled, false)
        let enabled = LoadoutConfigCodec.toggleTOMLServer(text: disabled, name: "filesystem", enabled: true)
        XCTAssertEqual(LoadoutConfigCodec.parseTOMLServers(text: enabled, scope: .global).first?.isEnabled, true)
    }

    func testSkillTokenEstimationAndContextBloat() {
        let md = "---\nname: swift\ndescription: \(String(repeating: "a", count: 400))\n---\nBody"
        XCTAssertEqual(LoadoutConfigCodec.estimateSkillTokens(markdown: md), 100)
        let heavy = LoadoutItem(id: "1", name: "big", kind: .mcpServer, provider: .claudeCode, scope: .global, isEnabled: true, estimatedTokens: 25_000)
        let summary = LoadoutConfigCodec.contextOverhead(items: [heavy])
        XCTAssertTrue(summary.isBloated)
        XCTAssertEqual(summary.percent, 12.5, accuracy: 0.01)
    }

    func testLoadoutProfileApplication() {
        let mcp = LoadoutItem(id: "m", name: "web", kind: .mcpServer, provider: .cursor, scope: .global, isEnabled: true, estimatedTokens: 320)
        let rule = LoadoutItem(id: "r", name: "rules", kind: .ruleFile, provider: .claudeCode, scope: .global, isEnabled: true, estimatedTokens: 200)
        let local = LoadoutItem(id: "o", name: "llama", kind: .skill, provider: .ollama, scope: .global, isEnabled: true, estimatedTokens: 100)
        XCTAssertFalse(LoadoutProfile.leanCoding.applies(to: mcp))
        XCTAssertTrue(LoadoutProfile.leanCoding.applies(to: rule))
        XCTAssertTrue(LoadoutProfile.offlineLocal.applies(to: local))
        XCTAssertFalse(LoadoutProfile.offlineLocal.applies(to: mcp))
    }
}
