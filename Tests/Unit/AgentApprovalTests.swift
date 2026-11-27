import XCTest

/// Claude 审批：解析钩子输入、文件名安全、钩子配置的安装/移除，以及脚本里不能丢的几句。
final class AgentApprovalTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func parse(_ json: String, id: String = "1000-42") -> AgentApprovalRequest? {
        AgentApproval.parse(id: id, data: Data(json.utf8), created: t0)
    }

    // MARK: - 解析

    func testBashShowsTheCommand() {
        let r = parse(#"{"tool_name":"Bash","tool_input":{"command":"rm -rf build"},"cwd":"/p"}"#)
        XCTAssertEqual(r?.toolName, "Bash")
        XCTAssertEqual(r?.summary, "rm -rf build")
        XCTAssertNil(r?.detail, "a short one-line command needs no detail")
        XCTAssertEqual(r?.cwd, "/p")
    }

    func testFileToolsShowThePath() {
        XCTAssertEqual(parse(#"{"tool_name":"Edit","tool_input":{"file_path":"/a/b.swift"}}"#)?.summary, "/a/b.swift")
        XCTAssertEqual(parse(#"{"tool_name":"Write","tool_input":{"file_path":"/a/c.txt","content":"x"}}"#)?.summary, "/a/c.txt")
    }

    func testWebToolsShowUrlOrQuery() {
        XCTAssertEqual(parse(#"{"tool_name":"WebFetch","tool_input":{"url":"https://x.dev"}}"#)?.summary, "https://x.dev")
        XCTAssertEqual(parse(#"{"tool_name":"WebSearch","tool_input":{"query":"swift"}}"#)?.summary, "swift")
    }

    func testUnknownToolFallsBackToFirstTextValueThenToolName() {
        XCTAssertEqual(parse(#"{"tool_name":"mcp__x__go","tool_input":{"b":"two","a":"one"}}"#)?.summary, "one")
        XCTAssertEqual(parse(#"{"tool_name":"mcp__x__go","tool_input":{}}"#)?.summary, "mcp__x__go")
        XCTAssertEqual(parse(#"{"tool_name":"mcp__x__go"}"#)?.summary, "mcp__x__go")
    }

    func testLongMultilineCommandIsCollapsedAndKeepsDetail() {
        let command = (0..<40).map { "echo line\($0)" }.joined(separator: "\\n")
        let r = parse(#"{"tool_name":"Bash","tool_input":{"command":"\#(command)"}}"#)
        XCTAssertFalse(r?.summary.contains("\n") ?? true)
        XCTAssertLessThanOrEqual(r?.summary.count ?? 999, AgentApproval.summaryLimit)
        XCTAssertTrue(r?.summary.hasSuffix("…") ?? false)
        XCTAssertNotNil(r?.detail)
        XCTAssertLessThanOrEqual(r?.detail?.count ?? 9999, AgentApproval.detailLimit)
    }

    func testNotAnApprovalRequest() {
        XCTAssertNil(parse("not json"))
        XCTAssertNil(parse("[]"))
        XCTAssertNil(parse(#"{"tool_input":{}}"#))
        XCTAssertNil(parse(#"{"tool_name":""}"#))
    }

    // MARK: - 文件

    func testCreatedDateComesFromTheIdPrefix() {
        XCTAssertEqual(AgentApproval.created(fromID: "1000-42"), Date(timeIntervalSince1970: 1000))
        XCTAssertNil(AgentApproval.created(fromID: "x-42"))
    }

    func testExpiry() {
        XCTAssertFalse(AgentApproval.isExpired(created: t0, now: t0.addingTimeInterval(60)))
        XCTAssertTrue(AgentApproval.isExpired(created: t0, now: t0.addingTimeInterval(91)))
    }

    func testOnlyPlainIdsAreSafeFileNames() {
        XCTAssertTrue(AgentApproval.isSafeID("1761566400-123"))
        for bad in ["", "../x", "1/2", "1000-4 2", "a-1", String(repeating: "1", count: 65)] {
            XCTAssertFalse(AgentApproval.isSafeID(bad), bad)
        }
    }

    // MARK: - 钩子配置

    private func object(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInstallAddsOnlyThePermissionRequestEntry() throws {
        let out = try ClaudeHookConfig.installApproval(into: Data("{}".utf8))
        let hooks = try XCTUnwrap(object(out)["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["PermissionRequest"])
        let command = try XCTUnwrap(((hooks["PermissionRequest"] as? [[String: Any]])?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertTrue((command["command"] as? String ?? "").contains(ClaudeHookConfig.approvalMarker))
        XCTAssertEqual(command["timeout"] as? Int, ClaudeHookConfig.approvalHookTimeoutSeconds)
    }

    func testInstallTwiceIsIdempotentAndKeepsOthersHooks() throws {
        let theirs = #"{"model":"x","hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"their-hook"}]}]}}"#
        let once = try ClaudeHookConfig.installApproval(into: Data(theirs.utf8))
        let twice = try ClaudeHookConfig.installApproval(into: once)
        XCTAssertEqual(once, twice)
        let root = try object(twice)
        XCTAssertEqual(root["model"] as? String, "x")
        let groups = try XCTUnwrap((root["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 2, "their group plus ours")
    }

    func testRemoveTakesOutOnlyOurs() throws {
        let theirs = #"{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"their-hook"}]}]}}"#
        let installed = try ClaudeHookConfig.installApproval(into: Data(theirs.utf8))
        let removed = try ClaudeHookConfig.removeApproval(from: installed)
        let groups = try XCTUnwrap((try object(removed)["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(removed, try ClaudeHookConfig.removeApproval(from: removed), "second removal changes nothing")
    }

    func testRemoveFromAFileWithoutOursLeavesBytesAlone() throws {
        let data = Data(#"{"a":1}"#.utf8)
        XCTAssertEqual(try ClaudeHookConfig.removeApproval(from: data), data)
    }

    func testStatusAndApprovalHooksDoNotTouchEachOther() throws {
        let both = try ClaudeHookConfig.installApproval(into: ClaudeHookConfig.install(into: Data("{}".utf8)))
        let withoutStatus = try ClaudeHookConfig.remove(from: both)
        let hooks = try XCTUnwrap(object(withoutStatus)["hooks"] as? [String: Any])
        XCTAssertEqual(Set(hooks.keys), ["PermissionRequest"])
        let withoutApproval = try ClaudeHookConfig.removeApproval(from: both)
        let remaining = try XCTUnwrap(object(withoutApproval)["hooks"] as? [String: Any])
        XCTAssertEqual(Set(remaining.keys), ["UserPromptSubmit", "Stop"])
    }

    func testRefusesAFileThatIsNotAnObject() {
        XCTAssertThrowsError(try ClaudeHookConfig.installApproval(into: Data("[]".utf8)))
    }

    // MARK: - 脚本

    func testScriptKeepsItsSafetyProperties() {
        let script = AgentApproval.hookScript
        XCTAssertTrue(script.hasPrefix("#!/bin/sh"))
        XCTAssertTrue(script.contains(#""behavior":"allow""#))
        XCTAssertTrue(script.contains(#""behavior":"deny""#))
        XCTAssertTrue(script.contains("alive"), "must fall through when the app is not running")
        XCTAssertFalse(script.contains("python"), "no interpreter stub that could pop an install dialog")
        XCTAssertTrue(script.contains("trap"), "pending files are cleaned up when the script exits")
        XCTAssertTrue(script.contains(ClaudeHookConfig.approvalMarker))
    }

    // MARK: - SLICE NL-2: Live Session, Swarm & Permission Policy Tests

    func testLiveSessionReducerAndSubagentSwarm() {
        let t1 = Date(timeIntervalSince1970: 2_000)
        var session = AgentLiveSession(provider: .codexCLI, sessionId: "s1", workspaceName: "KatiKati", startedAt: t1, lastUpdated: t1)
        session.apply(.turnStarted(now: t1))
        XCTAssertEqual(session.state, .thinking)
        session.apply(.callingTool(name: "Edit", target: "NotchAIPageView.swift", addedLines: 40, deletedLines: 10, now: t1.addingTimeInterval(5)))
        session.apply(.subagentStarted(id: "sub1", title: "Run tests", now: t1.addingTimeInterval(6)))
        XCTAssertEqual(session.subagents.count, 1)
        session.apply(.subagentStopped(id: "sub1", failed: false, now: t1.addingTimeInterval(15)))
        XCTAssertTrue(session.subagents[0].isCompleted)
        session.apply(.turnCompleted(summary: "Updated UI", now: t1.addingTimeInterval(20)))
        XCTAssertEqual(session.state, .completed(summary: "Updated UI", duration: 20, changedLines: 50))
    }

    func testPermissionPolicyReadOnlySafelistRejectsMutations() {
        let readReq = AgentApprovalRequest(id: "1-1", toolName: "Read", summary: "/a/b.swift", detail: nil, cwd: nil, created: t0, provider: .claudeCode)
        let diffReq = AgentApprovalRequest(id: "1-2", toolName: "Bash", summary: "git status", detail: nil, cwd: nil, created: t0, provider: .codexCLI)
        let writeReq = AgentApprovalRequest(id: "1-3", toolName: "Write", summary: "/a/b.swift", detail: nil, cwd: nil, created: t0)
        let chainReq = AgentApprovalRequest(id: "1-4", toolName: "Bash", summary: "git status && rm -rf /", detail: nil, cwd: nil, created: t0)
        XCTAssertFalse(AgentPermissionPolicy.shouldAutoApprove(readReq, enabled: false))
        XCTAssertTrue(AgentPermissionPolicy.shouldAutoApprove(readReq, enabled: true))
        XCTAssertTrue(AgentPermissionPolicy.shouldAutoApprove(diffReq, enabled: true))
        XCTAssertFalse(AgentPermissionPolicy.shouldAutoApprove(writeReq, enabled: true))
        XCTAssertFalse(AgentPermissionPolicy.shouldAutoApprove(chainReq, enabled: true))
        for bypass in ["ls; rm -rf /", "ls\nrm -rf /", "ls & open .", "ls\t; open .", "lsanything"] {
            XCTAssertFalse(AgentPermissionPolicy.isReadOnlyTool(toolName: "Bash", summary: bypass), bypass)
        }
        XCTAssertTrue(AgentPermissionPolicy.isReadOnlyTool(toolName: "Bash", summary: "git status --short"))
    }

    func testWatchdogMarksStuckSession() {
        let t1 = Date(timeIntervalSince1970: 3_000)
        var session = AgentLiveSession(provider: .claudeCode, sessionId: "s2", workspaceName: "App", startedAt: t1, state: .thinking, lastUpdated: t1)
        session.checkWatchdog(now: t1.addingTimeInterval(120))
        XCTAssertEqual(session.state, .thinking)
        session.checkWatchdog(now: t1.addingTimeInterval(200))
        XCTAssertEqual(session.state, .stuck(idleSeconds: 200))
    }

    // MARK: - Liquid Notch Agent Socket & Hook Installer (LQ-3)

    func testLiquidAgentSocketLineParsingAndResponses() {
        let payload = #"{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/tmp"}"#
        let raw = Data("claude\tPermissionRequest\tcom.anthropic.claudefordesktop\t\(payload)\n".utf8)
        let line = LiquidAgentHookLine.parse(raw)
        XCTAssertNotNil(line)
        XCTAssertEqual(line?.provider, "claude")
        XCTAssertEqual(line?.event, "PermissionRequest")
        XCTAssertTrue(line?.waits ?? false)
        XCTAssertTrue(LiquidAgentHookLine.decisionJSON(allow: true).contains("\"behavior\":\"allow\""))
        XCTAssertTrue(LiquidAgentHookLine.decisionJSON(allow: false).contains("\"behavior\":\"deny\""))
        let ans = LiquidAgentHookLine.answerJSON(input: [:], question: "Proceed?", option: "Yes")
        XCTAssertTrue(ans.contains("\"Proceed?\":\"Yes\""))
    }

    func testLiquidHookInstallerRoundTripPreservesUserHooks() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("lq3-hook-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let claudeDir = tmp.appendingPathComponent(".claude")
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let existing = #"{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"user-hook"}]}]}}"#
        try Data(existing.utf8).write(to: claudeDir.appendingPathComponent("settings.json"))

        XCTAssertFalse(LiquidHookInstaller.installed(home: tmp))
        try LiquidHookInstaller.install(home: tmp)
        XCTAssertTrue(LiquidHookInstaller.installed(home: tmp))
        XCTAssertTrue(FileManager.default.fileExists(atPath: LiquidHookInstaller.scriptURL(home: tmp).path))

        try LiquidHookInstaller.uninstall(home: tmp)
        XCTAssertFalse(LiquidHookInstaller.installed(home: tmp))
        XCTAssertFalse(FileManager.default.fileExists(atPath: LiquidHookInstaller.scriptURL(home: tmp).path))
        let after = try String(contentsOf: claudeDir.appendingPathComponent("settings.json"), encoding: .utf8)
        XCTAssertTrue(after.contains("user-hook"), "existing user hooks must be preserved")
    }
}
