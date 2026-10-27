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
}
