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
}
