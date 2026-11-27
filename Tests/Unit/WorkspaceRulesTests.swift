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

    func testChangingARuleTakesEffectOnTheNextQuery() {
        // The engine caches the ignore set, so this only pins the rules half: a `tile` rule answers
        // `.manage` and an `ignore` rule answers `.ignore`, with nothing sticky in between.
        XCTAssertEqual(WorkspaceRules.parse("\(slack)=ignore").disposition(bundleID: slack, title: nil), .ignore)
        XCTAssertEqual(WorkspaceRules.parse("\(slack)=tile").disposition(bundleID: slack, title: nil), .manage)
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

    // A `=tile` rule has to be distinguishable from "no rule matched": both are `.manage`, but only
    // the first outranks the built-in float list (Calculator et al.) and admits the window.
    func testTileOverrideIsTrueOnlyForAnExplicitTileRule() {
        let rules = WorkspaceRules.parse("com.apple.calculator=tile\n" + slack + "=float\n" + safari + "|~Inbox=tile")

        XCTAssertTrue(rules.tileOverride(bundleID: "com.apple.calculator", title: nil))
        XCTAssertFalse(rules.tileOverride(bundleID: slack, title: nil))
        XCTAssertFalse(rules.tileOverride(bundleID: "com.example.other", title: nil))
        XCTAssertTrue(rules.tileOverride(bundleID: safari, title: "Inbox (3)"))
    }

    func testTileOverrideFollowsTheFirstMatchingRule() {
        let rules = WorkspaceRules.parse("com.apple.calculator=float\ncom.apple.calculator=tile")
        XCTAssertFalse(rules.tileOverride(bundleID: "com.apple.calculator", title: nil),
                       "the first match wins, so the later tile rule cannot lift the float")
    }

    // MARK: - AT-4: categories, display targets and the island rule

    func testMediaCategoryMatchesItsBundleList() {
        XCTAssertTrue(AppRuleCategory.media.matches(bundleID: "org.videolan.vlc"))
        XCTAssertTrue(AppRuleCategory.media.matches(bundleID: "com.colliderli.iina"))
        XCTAssertTrue(AppRuleCategory.media.matches(bundleID: "com.apple.QuickTimePlayerX"))
        XCTAssertFalse(AppRuleCategory.media.matches(bundleID: safari))
        XCTAssertFalse(AppRuleCategory.media.matches(bundleID: nil))
    }

    func testCategoryRuleParsesAndRoundTrips() {
        let rule = WorkspaceRule.parse(line: "@media=hideIsland")
        XCTAssertEqual(rule?.category, .media)
        XCTAssertNil(rule?.bundleID)
        XCTAssertEqual(rule?.action, .hideIsland)
        XCTAssertEqual(rule?.isValid, true)
        XCTAssertEqual(rule?.serialized, "@media=hideIsland")
    }

    func testWatchingIsAnAliasOfMedia() {
        XCTAssertEqual(WorkspaceRule.parse(line: "@watching=float")?.category, .media)
    }

    func testDisplayRuleParsesAndRoundTrips() {
        let rule = WorkspaceRule.parse(line: "com.apple.Safari=display:external")
        XCTAssertEqual(rule?.display, "external")
        XCTAssertEqual(rule?.action, .tile)
        XCTAssertEqual(rule?.serialized, "com.apple.Safari=display:external")

        let byUUID = WorkspaceRule.parse(line: "com.apple.Safari=display:6A565C28-B527-4316-9C88-E604AB4BAF23")
        XCTAssertEqual(byUUID?.display, "6A565C28-B527-4316-9C88-E604AB4BAF23")
    }

    func testDisplayTargetFollowsTheFirstMatchingRule() {
        let rules = WorkspaceRules.parse("@media=display:external\ncom.apple.TV=display:builtin")
        XCTAssertEqual(rules.displayTarget(bundleID: "com.apple.TV", title: nil), "external")
        XCTAssertEqual(rules.displayTarget(bundleID: safari, title: nil), nil)
    }

    func testHideIslandFollowsTheFirstMatchingRule() {
        let rules = WorkspaceRules.parse("@media=hideIsland")
        XCTAssertTrue(rules.hidesIsland(bundleID: "com.colliderli.iina", title: nil))
        XCTAssertFalse(rules.hidesIsland(bundleID: safari, title: nil))
        XCTAssertEqual(rules.disposition(bundleID: "com.colliderli.iina", title: nil), .manage)
    }

    func testIslandMediaPolicyOnlyHidesOnNotchlessDisplays() {
        XCTAssertTrue(IslandMediaVisibility.hidesAtRest(hasNotch: false, profileAllows: true, mediaFullscreen: true))
        XCTAssertFalse(IslandMediaVisibility.hidesAtRest(hasNotch: true, profileAllows: true, mediaFullscreen: true))
        XCTAssertFalse(IslandMediaVisibility.hidesAtRest(hasNotch: false, profileAllows: false, mediaFullscreen: true))
        XCTAssertFalse(IslandMediaVisibility.hidesAtRest(hasNotch: false, profileAllows: true, mediaFullscreen: false))
    }

    // MARK: - AT-5: workspace names

    func testNamesAreScopedPerDisplay() {
        var names = WorkspaceNames()
        names.setName("Code", for: .numbered(2), on: "builtin-uuid")
        XCTAssertEqual(names.name(for: .numbered(2), on: "builtin-uuid"), "Code")
        XCTAssertNil(names.name(for: .numbered(2), on: "lg-uuid"))
        XCTAssertEqual(names.label(for: .numbered(2), on: "lg-uuid"), "2")
    }

    func testBlankNameFallsBackToTheToken() {
        var names = WorkspaceNames()
        names.setName("  Media  ", for: .numbered(3), on: "lg-uuid")
        XCTAssertEqual(names.name(for: .numbered(3), on: "lg-uuid"), "Media")
        names.setName("   ", for: .numbered(3), on: "lg-uuid")
        XCTAssertNil(names.name(for: .numbered(3), on: "lg-uuid"))
        XCTAssertEqual(names.label(for: .numbered(3), on: "lg-uuid"), "3")
    }

    func testNamesRoundTripThroughJSON() throws {
        var names = WorkspaceNames()
        names.setName("Comms", for: .numbered(1), on: "uuid")
        let data = try JSONEncoder().encode(names)
        let decoded = try JSONDecoder().decode(WorkspaceNames.self, from: data)
        XCTAssertEqual(decoded, names)
    }

    func testMigratedRulesSurviveTheTextRoundTrip() {
        let policy = TilingPolicy(floatingBundleIDs: [slack], alwaysTileBundleIDs: [])
        let migrated = WorkspaceRules.migrated(from: policy)
        let reparsed = WorkspaceRules.parse(migrated.serialized)
        XCTAssertEqual(reparsed.disposition(bundleID: slack, title: nil), .float)
    }
}
