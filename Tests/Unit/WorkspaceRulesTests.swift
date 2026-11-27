import XCTest
@testable import KatiKati

/// W-2: ordered first-match rules, their text form, and the migration from `TilingPolicy`.
final class WorkspaceRulesTests: XCTestCase {
    private let slack = "com.tinyspeck.slackmacgap"
    private let safari = "com.apple.Safari"

    // MARK: - Parsing

    func testBareBundleIDMeansFloatLikeTheOldFormat() {
        let rule = WorkspaceRule.parse(line: slack)
        XCTAssertEqual(rule?.bundleID, slack)
        XCTAssertEqual(rule?.action, .float)
        XCTAssertEqual(rule?.isValid, true)
    }

    func testEveryActionParses() {
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=float")?.action, .float)
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=tile")?.action, .tile)
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=pin")?.action, .pin)
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=ignore")?.action, .ignore)
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=route:2")?.workspace, .numbered(2))
        XCTAssertEqual(WorkspaceRule.parse(line: "\(slack)=route:D")?.workspace, .named("D"))
    }

    func testRouteNeedsAValidWorkspace() {
        let rule = WorkspaceRule.parse(line: "\(slack)=route:99")
        XCTAssertNil(rule)
        XCTAssertEqual(WorkspaceRule(action: .route, workspace: nil).isValid, false)
    }

    func testRouteWithAWorkspaceIsValidAndOtherActionsRejectOne() {
        XCTAssertTrue(WorkspaceRule(bundleID: slack, action: .route, workspace: .numbered(3)).isValid)
        XCTAssertFalse(WorkspaceRule(bundleID: slack, action: .float, workspace: .numbered(3)).isValid)
    }

    func testTitleAndContainsMatchersParse() {
        let exact = WorkspaceRule.parse(line: "\(safari)|Preferences=float")
        XCTAssertEqual(exact?.bundleID, safari)
        XCTAssertEqual(exact?.title, "Preferences")

        let contains = WorkspaceRule.parse(line: "\(safari)|~Work —=route:3")
        XCTAssertEqual(contains?.titleContains, "Work —")
        XCTAssertEqual(contains?.workspace, .numbered(3))

        let titleOnly = WorkspaceRule.parse(line: "|~Zoom Meeting=pin")
        XCTAssertNil(titleOnly?.bundleID)
        XCTAssertEqual(titleOnly?.titleContains, "Zoom Meeting")
        XCTAssertTrue(titleOnly?.isValid == true)
    }

    func testCommentsAndJunkAreDropped() {
        XCTAssertNil(WorkspaceRule.parse(line: "   "))
        XCTAssertNil(WorkspaceRule.parse(line: "# a comment"))
        XCTAssertNil(WorkspaceRule.parse(line: "\(slack)=nonsense"))
    }

    func testSerializedRoundTrips() {
        let lines = [
            "\(slack)=float",
            "\(safari)|Preferences=float",
            "\(safari)|~Work —=route:3",
            "\(slack)=route:D",
        ]
        for line in lines {
            guard let rule = WorkspaceRule.parse(line: line) else {
                return XCTFail("did not parse \(line)")
            }
            XCTAssertEqual(rule.serialized, line)
        }
    }

    func testRuleWithoutAMatcherIsInvalidAndNeverMatches() {
        let rule = WorkspaceRule(action: .float)
        XCTAssertFalse(rule.isValid)
        XCTAssertFalse(rule.matches(bundleID: slack, title: "anything"))
    }

    // MARK: - Matching

    func testFirstMatchWins() {
        let rules = WorkspaceRules.parse("""
        \(slack)=float
        \(slack)=route:2
        """)
        XCTAssertEqual(rules.rules.count, 2)
        XCTAssertEqual(rules.disposition(bundleID: slack, title: nil), .float)
    }

    func testUnmatchedWindowIsManagedNormally() {
        XCTAssertEqual(WorkspaceRules.default.disposition(bundleID: safari, title: "x"), .manage)
    }

    func testTitleContainsIsCaseInsensitive() {
        let rules = WorkspaceRules(rules: [
            WorkspaceRule(bundleID: safari, titleContains: "work —", action: .route, workspace: .numbered(3)),
        ])
        XCTAssertEqual(rules.disposition(bundleID: safari, title: "WORK — Q4 plan"), .route(.numbered(3)))
        XCTAssertEqual(rules.disposition(bundleID: safari, title: "Personal"), .manage)
    }

    func testBothMatchersMustMatch() {
        let rules = WorkspaceRules(rules: [
            WorkspaceRule(bundleID: safari, title: "Preferences", action: .float),
        ])
        XCTAssertEqual(rules.disposition(bundleID: safari, title: "Preferences"), .float)
        XCTAssertEqual(rules.disposition(bundleID: safari, title: "Other"), .manage)
        XCTAssertEqual(rules.disposition(bundleID: "com.google.Chrome", title: "Preferences"), .manage)
    }

    func testRoutesAllWindowsIsReadFromTheMatchedRouteRule() {
        let all = WorkspaceRules(rules: [
            WorkspaceRule(bundleID: slack, action: .route, workspace: .numbered(2), windows: .all),
        ])
        XCTAssertTrue(all.routesAllWindows(bundleID: slack, title: nil))

        let first = WorkspaceRules(rules: [
            WorkspaceRule(bundleID: slack, action: .route, workspace: .numbered(2)),
        ])
        XCTAssertFalse(first.routesAllWindows(bundleID: slack, title: nil))
    }

    // MARK: - Migration

    func testMigrationPreservesTheOldFloatAndTileLists() {
        let policy = TilingPolicy(
            floatingBundleIDs: ["com.apple.calculator", slack],
            alwaysTileBundleIDs: ["com.apple.Stickies"],
            pinnedDisplays: [safari: "Built-in"]
        )
        let migrated = WorkspaceRules.migrated(from: policy)

        XCTAssertEqual(migrated.disposition(bundleID: slack, title: nil), .float)
        XCTAssertEqual(migrated.disposition(bundleID: "com.apple.calculator", title: nil), .float)
        XCTAssertEqual(migrated.disposition(bundleID: "com.apple.Stickies", title: nil), .manage)
        XCTAssertEqual(migrated.disposition(bundleID: "com.example.other", title: nil), .manage)
        // A display pin is not a workspace, so it stays in TilingPolicy rather than becoming a rule.
        XCTAssertTrue(migrated.rules.allSatisfy { $0.action == .float || $0.action == .tile })
    }

    func testMigratedRulesSurviveTheTextRoundTrip() {
        let policy = TilingPolicy(floatingBundleIDs: [slack], alwaysTileBundleIDs: [])
        let migrated = WorkspaceRules.migrated(from: policy)
        let reparsed = WorkspaceRules.parse(migrated.serialized)
        XCTAssertEqual(reparsed.disposition(bundleID: slack, title: nil), .float)
    }
}
