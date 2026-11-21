import XCTest
@testable import KatiKati

/// Ported from Spacewalk (MIT, © 2026 InsaneArts) along with the code, so the index arithmetic and
/// the fixed-point sign rules are pinned rather than assumed.
final class SpaceSwitchPlanTests: XCTestCase {
    // MARK: Plan

    func testStepsForwardOneSpace() {
        let plan = SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .right, wrap: false)
        XCTAssertEqual(plan, SpaceSwitchPlan(fromIndex: 0, toIndex: 1))
        XCTAssertEqual(plan?.steps, 1)
        XCTAssertEqual(plan?.direction, .right)
    }

    func testStepsBackwardCrossesEverySpaceBetween() {
        // 2 → 4 is two rightward Dock swipes, not one.
        let plan = SpaceSwitchPlan.plan(currentIndex: 1, spaceCount: 5, direction: .right, wrap: false)
        XCTAssertEqual(plan?.toIndex, 2)
        XCTAssertEqual(plan?.steps, 1)
        let far = SpaceSwitchPlan(fromIndex: 1, toIndex: 4)
        XCTAssertEqual(far.steps, 3)
        XCTAssertEqual(far.direction, .right)
        XCTAssertEqual(SpaceSwitchPlan(fromIndex: 4, toIndex: 1).direction, .left)
    }

    func testEdgesRefuseWithoutWrapAndWrapAroundWith() {
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 2, spaceCount: 3, direction: .right, wrap: false))
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .left, wrap: false))
        XCTAssertEqual(SpaceSwitchPlan.plan(currentIndex: 2, spaceCount: 3, direction: .right, wrap: true)?.toIndex, 0)
        XCTAssertEqual(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 3, direction: .left, wrap: true)?.toIndex, 2)
    }

    func testNowhereToGo() {
        // One Space: wrapping to yourself is not a switch.
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 0, spaceCount: 1, direction: .right, wrap: true))
        // The current id is not a desktop (a fullscreen Space, or the layout moved under us).
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: 3, spaceCount: 3, direction: .right, wrap: true))
        XCTAssertNil(SpaceSwitchPlan.plan(currentIndex: -1, spaceCount: 3, direction: .left, wrap: true))
    }

    // MARK: Settings

    func testSettingsDefaultsAndClamping() {
        let defaults = UserDefaults(suiteName: "SpaceSwitchPlanTests.\(UUID().uuidString)")!
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .fade)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.defaultDuration)

        defaults.set("instant", forKey: SpaceTransitionSettings.effectKey)
        defaults.set(5.0, forKey: SpaceTransitionSettings.durationKey)
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .instant)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.durationRange.upperBound)

        // A hand-edited key cannot leave the slider's range, and an unknown effect falls back to fade.
        defaults.set(0.0, forKey: SpaceTransitionSettings.durationKey)
        defaults.set("cube", forKey: SpaceTransitionSettings.effectKey)
        XCTAssertEqual(SpaceTransitionSettings.duration(from: defaults), SpaceTransitionSettings.durationRange.lowerBound)
        XCTAssertEqual(SpaceTransitionSettings.effect(from: defaults), .fade)
    }

    // MARK: Swipe events

    func testFixedPointNeverRoundsTheSignAway() {
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(1), 65_536)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0.5), 32_768)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0), 0)
        // The near-zero travel is what makes the Dock commit instantly; subnormal-rounded-to-zero would
        // lose the direction, so the smallest non-zero values must survive as ±1.
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(0.00001), 1)
        XCTAssertEqual(DockSwipeEventPoster.fixed1616(-0.00001), -1)
    }

    func testRightwardSwipeMovesForward() {
        XCTAssertTrue(DockSwipeEventPoster.isRightward(1e-4))
        XCTAssertFalse(DockSwipeEventPoster.isRightward(-1e-4))
        XCTAssertFalse(DockSwipeEventPoster.isRightward(0))
    }
}

/// MC-1: the Mission Control models are synchronous and pure, so precedence, filtering, naming and
/// the Codable surface are pinned here rather than inferred from the overlay.
final class MissionControlModelTests: XCTestCase {
    private func window(
        _ id: UInt32,
        bundle: String? = "com.apple.Safari",
        app: String = "Safari",
        title: String? = "Docs",
        rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100),
        state: MissionControlWindowState = .standard,
        focused: Bool = false
    ) -> MissionControlWindowFrame {
        MissionControlWindowFrame(
            id: id, bundleID: bundle, appName: app, title: title,
            frame: rect, state: state, isFocused: focused
        )
    }

    // MARK: Naming

    func testSpaceLabelTrimsAndFallsBackToNumberedDesktop() {
        let naming = MissionControlNaming(spaceLabels: ["A": "  Coding  ", "B": "   "])
        XCTAssertEqual(naming.spaceLabel(forSpaceID: "A"), "Coding")
        XCTAssertNil(naming.spaceLabel(forSpaceID: "B"))
        XCTAssertNil(naming.spaceLabel(forSpaceID: "missing"))
        XCTAssertEqual(naming.spaceTitle(forSpaceID: "A", index: 2), "Coding · Desktop 2")
        XCTAssertEqual(naming.spaceTitle(forSpaceID: "missing", index: 3), "Desktop 3")
        XCTAssertNil(MissionControlNaming(showsSpaceTitles: false).spaceTitle(forSpaceID: "A", index: 1))
    }

    func testBadgeTitleFollowsItsTwoSwitches() {
        let both = MissionControlNaming()
        XCTAssertEqual(both.badgeTitle(app: "Safari", title: "Docs"), "Safari — Docs")
        XCTAssertEqual(both.badgeTitle(app: "Safari", title: "  "), "Safari")
        XCTAssertEqual(both.badgeTitle(app: "", title: "Docs"), "Docs")
        XCTAssertNil(both.badgeTitle(app: " ", title: nil))
        XCTAssertEqual(MissionControlNaming(showsWindowTitle: false).badgeTitle(app: "Safari", title: "Docs"), "Safari")
        XCTAssertEqual(MissionControlNaming(showsAppIcon: false).badgeTitle(app: "Safari", title: "Docs"), "Docs")
        XCTAssertNil(MissionControlNaming(showsWindowBadges: false).badgeTitle(app: "Safari", title: "Docs"))
        XCTAssertNil(MissionControlNaming(showsAppIcon: false, showsWindowTitle: false).badgeTitle(app: "a", title: "b"))
    }

    // MARK: Filter

    func testFilterNeedsEveryTokenAndDimmingIsBinary() {
        XCTAssertTrue(MissionControlFilter.matches(query: "", title: nil, app: nil))
        XCTAssertTrue(MissionControlFilter.matches(query: "  ", title: "x", app: "y"))
        XCTAssertTrue(MissionControlFilter.matches(query: "saf docs", title: "Docs — plan", app: "Safari"))
        XCTAssertFalse(MissionControlFilter.matches(query: "saf chrome", title: "Docs", app: "Safari"))
        XCTAssertTrue(MissionControlFilter.matches(query: "DOCS", title: "docs", app: "Notes"))
        XCTAssertEqual(MissionControlFilter.opacity(query: "", title: "Docs", app: "Safari"), 1)
        XCTAssertEqual(MissionControlFilter.opacity(query: "term", title: "Docs", app: "Safari"), 0.28)
        XCTAssertEqual(MissionControlFilter.opacity(query: "docs", title: "Docs", app: "Safari"), 1)
    }

    // MARK: Colouring

    func testColourPrecedenceIsCustomThenAppThenCategoryThenDefault() {
        let colouring = MissionControlColouring(
            rules: [
                MissionControlColorRule(match: .category(.browser), color: .purple),
                MissionControlColorRule(match: .bundleID("com.apple.Safari"), color: .orange)
            ],
            defaultColor: .neutral
        )
        // A bundle rule outranks a category rule even when the category rule is stored first.
        XCTAssertEqual(colouring.color(forBundleID: "com.apple.safari", category: .browser), .orange)
        // Another browser takes the category rule.
        XCTAssertEqual(colouring.color(forBundleID: "com.google.Chrome", category: .browser), .purple)
        // A category with no rule falls through to its auto-assigned colour.
        XCTAssertEqual(colouring.color(forBundleID: "com.apple.Terminal", category: .code), .green)
        // Unknown apps land on the neutral default.
        XCTAssertEqual(colouring.color(forBundleID: "com.example.thing", category: .other), .neutral)

        var autoOff = colouring
        autoOff.autoAssignCategories = false
        XCTAssertEqual(autoOff.color(forBundleID: "com.apple.Terminal", category: .code), .neutral)

        var disabled = colouring
        disabled.isEnabled = false
        XCTAssertEqual(disabled.color(forBundleID: "com.apple.Safari", category: .browser), .neutral)
    }

    func testCategoryInferenceCoversTheShippedPrefixes() {
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "com.google.Chrome"), .browser)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "com.apple.dt.Xcode"), .code)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "com.tinyspeck.slackmacgap"), .comms)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "md.obsidian"), .notes)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "com.spotify.client"), .media)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: "com.acme.editor"), .other)
        XCTAssertEqual(MissionControlAppCategory.inferred(fromBundleID: nil), .other)
    }

    func testTintAndSpaceAccentsRespectTheirSwitches() {
        let colouring = MissionControlColouring(
            tintOpacity: 0.08,
            spaceAccents: ["1": .blue]
        )
        XCTAssertEqual(colouring.tint(forBundleID: "com.apple.Safari", category: .browser), 0.10)
        XCTAssertEqual(colouring.tint(forBundleID: "com.acme.thing", category: .other), 0.08)
        XCTAssertEqual(colouring.accent(forSpaceID: "1"), .blue)
        XCTAssertNil(colouring.accent(forSpaceID: "2"))
        XCTAssertNil(colouring.accent(forSpaceID: ""))

        var off = colouring
        off.showsSpaceAccents = false
        XCTAssertNil(off.accent(forSpaceID: "1"))
        off.showsSpaceAccents = true
        off.isEnabled = false
        XCTAssertNil(off.accent(forSpaceID: "1"))
        XCTAssertEqual(off.tint(forBundleID: "com.apple.Safari", category: .browser), 0)
    }

    // MARK: Framing

    func testFramingPrefersFocusThenHoverThenState() {
        let framing = MissionControlFraming()
        XCTAssertEqual(framing.style(isFocused: true, isHovered: false, state: .standard), .solid)
        XCTAssertEqual(framing.style(isFocused: true, isHovered: true, state: .standard), .solid)
        XCTAssertEqual(framing.style(isFocused: false, isHovered: true, state: .minimized), .hairline)
        XCTAssertEqual(framing.style(isFocused: false, isHovered: false, state: .fullscreen), .glow)
        XCTAssertEqual(framing.style(isFocused: false, isHovered: false, state: .hidden), .dashed)

        // A focused window with the focus frame off keeps its state border instead of drawing nothing.
        let noFocus = MissionControlFraming(showsFocusFrame: false)
        XCTAssertEqual(noFocus.style(isFocused: true, isHovered: false, state: .standard), .hairline)

        var off = framing
        off.isEnabled = false
        XCTAssertEqual(off.style(isFocused: true, isHovered: true, state: .standard), .none)
        XCTAssertNil(off.groupBorder())
        XCTAssertNil(framing.groupBorder())
        XCTAssertEqual(MissionControlFraming(showsGroupFrame: true).groupBorder(), .dashed)
    }

    // MARK: Actions

    func testButtonsHideWithoutReorderingTheRest() {
        var buttons = MissionControlButtons()
        XCTAssertEqual(buttons.shownActions, MissionControlWindowAction.allCases)
        buttons.visible[.hide] = false
        XCTAssertFalse(buttons.isVisible(.hide))
        XCTAssertEqual(buttons.shownActions, [.close, .minimize, .zoom, .quit])
        XCTAssertTrue(buttons.isVisible(.quit), "missing keys default to visible")
    }

    func testHoverKeysNeedTheExactModifierSet() {
        let keys = MissionControlHoverKeys()
        XCTAssertEqual(keys.action(forKey: "W", modifiers: [.command]), .close)
        XCTAssertEqual(keys.action(forKey: "m", modifiers: [.command]), .minimize)
        XCTAssertNil(keys.action(forKey: "w", modifiers: [.command, .shift]))
        XCTAssertNil(keys.action(forKey: "w", modifiers: []))
        var off = keys
        off.isEnabled = false
        XCTAssertNil(off.action(forKey: "w", modifiers: [.command]))
    }

    func testMouseBindingsMapToActionsAndNoneIsSilent() {
        var mouse = MissionControlMouseBindings(rightClick: .close, middleClick: .zoom)
        XCTAssertEqual(mouse.action(for: .right), .close)
        XCTAssertEqual(mouse.action(for: .middle), .zoom)
        mouse.rightClick = .none
        XCTAssertNil(mouse.action(for: .right))
        XCTAssertEqual(mouse.binding(for: .middle), .zoom)
    }

    // MARK: Readiness

    func testReadinessNamesTheFirstBlockerAndDetectionIsSeparate() {
        XCTAssertEqual(
            MissionControlReadiness(accessibility: .denied, screenRecording: .granted, detection: .granted).blocker,
            .accessibility
        )
        let captureOff = MissionControlReadiness(
            accessibility: .granted, screenRecording: .denied, detection: .granted
        )
        XCTAssertNil(captureOff.blocker, "Screen Recording only gates the thumbnail wash")
        XCTAssertFalse(captureOff.canTintThumbnails)
        XCTAssertEqual(
            MissionControlReadiness(accessibility: .granted, screenRecording: .granted, detection: .unsupported).blocker,
            .detectionUnavailable
        )
        XCTAssertTrue(captureOff.isReady)
        XCTAssertNil(MissionControlReadiness(accessibility: .unknown, screenRecording: .unknown, detection: .unknown).blocker)
    }

    // MARK: Target ranking

    func testPointerTargetIsTheFrontmostContainingWindow() {
        let windows = [
            window(1, rect: CGRect(x: 120, y: 0, width: 100, height: 100)),
            window(2, rect: CGRect(x: 0, y: 0, width: 200, height: 100))
        ]
        XCTAssertEqual(MissionControlTargetRanker.target(at: CGPoint(x: 150, y: 50), in: windows)?.id, 1)
        XCTAssertEqual(MissionControlTargetRanker.target(at: CGPoint(x: 20, y: 50), in: windows)?.id, 2)
        XCTAssertNil(MissionControlTargetRanker.target(at: CGPoint(x: 50, y: 300), in: windows))
    }

    func testKeyboardTargetCyclesAndSkipsDimmedWindows() {
        let windows = [window(1), window(2, app: "Mail", title: "Mail"), window(3)]
        let query = MissionControlFilter.matches(query: "safari", title: windows[0].title, app: windows[0].appName)
        XCTAssertTrue(query)
        XCTAssertEqual(MissionControlTargetRanker.next(after: 1, step: 1, in: windows)?.id, 2)
        XCTAssertEqual(MissionControlTargetRanker.next(after: 3, step: 1, in: windows)?.id, 1, "wraps forward")
        XCTAssertEqual(MissionControlTargetRanker.next(after: 1, step: -1, in: windows)?.id, 3, "wraps backward")
        XCTAssertEqual(
            MissionControlTargetRanker.next(after: 1, step: 1, in: windows, visible: { $0.id != 2 })?.id,
            3,
            "a dimmed window is skipped"
        )
        XCTAssertNil(MissionControlTargetRanker.next(after: 1, step: 1, in: windows, visible: { _ in false }))
    }

    // MARK: Persistence

    func testConfigurationRoundTripsThroughJSON() throws {
        let config = MissionControlConfiguration(
            naming: MissionControlNaming(spaceLabels: ["S": "Coding"], showsWindowTitle: false),
            framing: MissionControlFraming(
                focusStyle: .glow, hoverStyle: .dashed, showsGroupFrame: true,
                stateStyles: [.standard: .solid, .minimized: .none]
            ),
            colouring: MissionControlColouring(
                autoAssignCategories: false,
                rules: [MissionControlColorRule(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                                match: .bundleID("com.apple.Safari"), color: .orange)],
                tintOpacity: 0.2,
                spaceAccents: ["S": .purple]
            ),
            actions: MissionControlActions(
                buttons: MissionControlButtons(visible: [.close: true, .hide: false], showsOnHover: false),
                hoverKeys: MissionControlHoverKeys(isEnabled: false, modifiers: [.option], keys: [.close: "k"]),
                mouse: MissionControlMouseBindings(rightClick: .minimize, middleClick: .none)
            )
        )
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(MissionControlConfiguration.self, from: data), config)
    }

    func testSettingsPersistEachBlobSeparately() {
        let suite = "katikati.missioncontrol.\\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(MissionControlSettings.isEnabled(from: defaults))
        MissionControlSettings.setEnabled(true, in: defaults)
        XCTAssertTrue(MissionControlSettings.isEnabled(from: defaults))

        var config = MissionControlSettings.load(from: defaults)
        config.naming.spaceLabels = ["1": "Comms"]
        MissionControlSettings.save(config, in: defaults)
        XCTAssertEqual(MissionControlSettings.load(from: defaults).naming.spaceLabels["1"], "Comms")

        // A fresh collection of defaults still loads the shipped defaults, not empty values.
        let other = UserDefaults(suiteName: suite + ".other")!
        defer { other.removePersistentDomain(forName: suite + ".other") }
        XCTAssertEqual(MissionControlSettings.load(from: other).actions.buttons.shownActions,
                       MissionControlWindowAction.allCases)
    }
}

/// MC-5: the presentation knobs, state colour overrides and app groups the richer renderer reads.
final class MissionControlPresentationTests: XCTestCase {
    private func window(
        _ id: UInt32, bundle: String?, app: String, state: MissionControlWindowState = .standard,
        rect: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)
    ) -> MissionControlWindowFrame {
        MissionControlWindowFrame(id: id, bundleID: bundle, appName: app, title: nil,
                                  frame: rect, state: state, isFocused: false)
    }

    func testPresentationClampsEveryDimension() {
        let loose = MissionControlPresentation(
            borderWidth: 99, cornerRadius: -4, badgeOpacity: 0.01, groupPadding: 400
        )
        XCTAssertEqual(loose.borderWidth, 6)
        XCTAssertEqual(loose.cornerRadius, 0)
        XCTAssertEqual(loose.badgeOpacity, 0.2)
        XCTAssertEqual(loose.groupPadding, 32)
        let defaults = MissionControlPresentation()
        XCTAssertEqual(defaults.borderWidth, 2.5)
        XCTAssertEqual(defaults.spaceTitlePlacement, .top)
        XCTAssertTrue(defaults.showsFilterChip)
    }

    func testStateColourBeatsTheAppRule() {
        var colouring = MissionControlColouring()
        colouring.stateColors[.fullscreen] = .green
        XCTAssertEqual(
            colouring.borderColor(forBundleID: "com.apple.Safari", category: .browser, state: .fullscreen),
            .green
        )
        XCTAssertEqual(
            colouring.borderColor(forBundleID: "com.apple.Safari", category: .browser, state: .standard),
            .blue
        )
        colouring.isEnabled = false
        XCTAssertEqual(
            colouring.borderColor(forBundleID: "com.apple.Safari", category: .browser, state: .fullscreen),
            .neutral
        )
    }

    func testGroupsOnlyIncludeAppsWithTwoWindowsAndUnionTheirFrames() {
        let windows = [
            window(1, bundle: "com.apple.Safari", app: "Safari",
                   rect: CGRect(x: 0, y: 0, width: 100, height: 100)),
            window(2, bundle: "com.apple.Safari", app: "Safari",
                   rect: CGRect(x: 200, y: 50, width: 100, height: 100)),
            window(3, bundle: "com.apple.Terminal", app: "Terminal")
        ]
        let groups = MissionControlGrouping.groups(for: windows, padding: 8)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].appName, "Safari")
        XCTAssertEqual(groups[0].windowIDs, [1, 2])
        XCTAssertEqual(groups[0].frame, CGRect(x: -8, y: -8, width: 316, height: 166))
        XCTAssertTrue(MissionControlGrouping.groups(for: windows, padding: 0).count == 1)
        XCTAssertTrue(MissionControlGrouping.groups(for: [windows[2]], padding: 8).isEmpty)
    }

    func testGroupingFallsBackToAppNameWithoutABundleID() {
        let groups = MissionControlGrouping.groups(
            for: [window(1, bundle: nil, app: "Notes"), window(2, bundle: nil, app: "notes")],
            padding: 0
        )
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].windowIDs, [1, 2])
    }

    func testConfigurationRoundTripsPresentationAndDecodesOldFourBlobJSON() throws {
        var config = MissionControlConfiguration()
        config.presentation = MissionControlPresentation(
            borderWidth: 4, cornerRadius: 20, badgeOpacity: 0.9, groupPadding: 14,
            spaceTitlePlacement: .bottom, badgePlacement: .trailing,
            showsFilterChip: false, accentFallback: .purple
        )
        let data = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(MissionControlConfiguration.self, from: data), config)

        // A build from before MC-5 wrote four blobs; the missing presentation must decode as defaults.
        let old = """
        {"naming":{"spaceLabels":{},"showsSpaceTitles":true,"showsWindowBadges":true,
        "showsAppIcon":true,"showsWindowTitle":true,"filterEnabled":true},
        "framing":{"isEnabled":true,"showsFocusFrame":true,"focusStyle":"solid","hoverStyle":"hairline",
        "showsGroupFrame":false,"groupStyle":"dashed","stateStyles":[]},
        "colouring":{"isEnabled":true,"autoAssignCategories":true,"rules":[],
        "defaultColor":{"red":0.6,"green":0.6,"blue":0.6,"alpha":1},"tintOpacity":0.08,
        "showsSpaceAccents":true,"spaceAccents":{}},
        "actions":{"buttons":{"visible":[],"showsOnHover":true},"hoverKeys":{"isEnabled":true,
        "modifiers":["command"],"keys":[]},"mouse":{"rightClick":"none","middleClick":"none"}}}
        """
        let decoded = try JSONDecoder().decode(MissionControlConfiguration.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.presentation, MissionControlPresentation())
    }
}
