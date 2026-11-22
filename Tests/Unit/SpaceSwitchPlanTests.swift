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
        XCTAssertEqual(groups[0].id, "com.apple.Safari")
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
        XCTAssertEqual(groups[0].id, "name:notes")
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

/// The Mission Control overview's interaction rules, extracted from the AppKit session so a filter,
/// Tab navigation, Return, Escape and pointer commands are proven without the Dock or AX.
final class MissionControlInteractionTests: XCTestCase {
    private func window(
        _ id: MissionControlWindowFrame.ID,
        app: String = "App",
        title: String,
        bundle: String? = nil
    ) -> MissionControlWindowFrame {
        MissionControlWindowFrame(
            id: id,
            bundleID: bundle,
            appName: app,
            title: title,
            frame: CGRect(x: CGFloat(id) * 40, y: 0, width: 100, height: 100),
            state: .standard,
            isFocused: false
        )
    }

    private func windows() -> [MissionControlWindowFrame] {
        [
            window(1, app: "Safari", title: "Release notes", bundle: "com.apple.Safari"),
            window(2, app: "Xcode", title: "KatiKati", bundle: "com.apple.dt.Xcode"),
            window(3, app: "Terminal", title: "swift test", bundle: "com.apple.Terminal")
        ]
    }

    func testOpeningTargetsTheFirstWindowAndReturnRaisesIt() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        XCTAssertEqual(interaction.focusedID, 1)
        XCTAssertEqual(interaction.handle(.raise), [.raise(1)])
    }

    func testTabAndArrowNavigationCycleAndClampToVisibleWindows() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        XCTAssertEqual(interaction.handle(.moveFocus(step: 1)), [.render])
        XCTAssertEqual(interaction.focusedID, 2)
        XCTAssertEqual(interaction.handle(.moveFocus(step: 1)), [.render])
        XCTAssertEqual(interaction.focusedID, 3)
        XCTAssertEqual(interaction.handle(.moveFocus(step: 1)), [.render])
        XCTAssertEqual(interaction.focusedID, 1, "forward wraps")
        XCTAssertEqual(interaction.handle(.moveFocus(step: -1)), [.render])
        XCTAssertEqual(interaction.focusedID, 3, "backward wraps")
    }

    func testFilterRetargetsAndNavigationSkipsDimmedWindows() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        XCTAssertEqual(interaction.handle(.text("term")), [.render])
        XCTAssertEqual(interaction.focusedID, 3, "Terminal / swift test matches, others do not")

        // Navigating from a match stays on the only match instead of jumping to a dimmed window.
        XCTAssertEqual(interaction.handle(.moveFocus(step: 1)), [])
        XCTAssertEqual(interaction.focusedID, 3)
        XCTAssertEqual(interaction.handle(.raise), [.raise(3)])
    }

    func testSpaceAndPunctuationTypeIntoTheFilter() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        _ = interaction.handle(.text("kati"))
        _ = interaction.handle(.text(" "))
        _ = interaction.handle(.text("kati"))
        XCTAssertEqual(interaction.query, "kati kati")
        XCTAssertEqual(interaction.visibleWindows.map(\.id), [2])
        XCTAssertEqual(interaction.focusedID, 2)
    }

    func testEscapeClearsTheFilterThenDismisses() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        _ = interaction.handle(.text("saf"))
        XCTAssertEqual(interaction.focusedID, 1)
        XCTAssertEqual(interaction.handle(.escape), [.render])
        XCTAssertTrue(interaction.query.isEmpty)
        XCTAssertEqual(interaction.focusedID, 1)
        XCTAssertEqual(interaction.handle(.escape), [.dismiss])
    }

    func testBackspaceWidensTheFilterAndEmptyBackspaceIsANoOp() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        _ = interaction.handle(.text("ka"))
        XCTAssertEqual(interaction.visibleWindows.map(\.id), [2])
        XCTAssertEqual(interaction.handle(.deleteBackward), [.render])
        XCTAssertEqual(interaction.query, "k")
        XCTAssertEqual(interaction.visibleWindows.map(\.id), [2])
        _ = interaction.handle(.deleteBackward)
        XCTAssertEqual(interaction.query, "")
        XCTAssertEqual(interaction.visibleWindows.map(\.id), [1, 2, 3])
        XCTAssertEqual(interaction.handle(.deleteBackward), [])
    }

    func testKeyboardAndPointerResolveDifferentTargets() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        interaction.hover(2)
        // Tab moves the keyboard target; the pointer still rests on window 2.
        _ = interaction.handle(.moveFocus(step: 1))
        XCTAssertEqual(interaction.focusedID, 2)
        XCTAssertEqual(interaction.target(for: .keyboard)?.id, 2)
        XCTAssertEqual(interaction.target(for: .pointer)?.id, 2)
        _ = interaction.handle(.moveFocus(step: 1))
        XCTAssertEqual(interaction.focusedID, 3)
        XCTAssertEqual(interaction.target(for: .keyboard)?.id, 3)
        XCTAssertEqual(interaction.target(for: .pointer)?.id, 2, "a right-click acts under the cursor")
        XCTAssertEqual(interaction.handle(.raise), [.raise(3)], "Return acts on the keyboard target")
    }

    func testKeyboardFallsBackToHoveredAndPointerFallsBackToFocused() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        interaction.hover(2)
        XCTAssertEqual(interaction.target(for: .keyboard)?.id, 1, "keyboard target wins")
        interaction.hover(nil)
        XCTAssertEqual(interaction.target(for: .pointer)?.id, 1, "focus is the pointer fallback")

        interaction.close()
        interaction.open(with: [])
        XCTAssertNil(interaction.handle(.raise).first)
        XCTAssertNil(interaction.target(for: .keyboard))
    }

    func testRefreshKeepsFilterAndTargetAndReplacesClosedWindows() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        _ = interaction.handle(.text("ka"))
        XCTAssertEqual(interaction.focusedID, 2)

        // The matching window is still there: nothing about the filter or target changes.
        interaction.update(frames: windows())
        XCTAssertEqual(interaction.query, "ka")
        XCTAssertEqual(interaction.focusedID, 2)

        // Its window closed: the target moves to the first remaining match, and no match empties it.
        let remaining = [windows()[0], windows()[2]]
        interaction.update(frames: remaining)
        XCTAssertEqual(interaction.query, "ka")
        XCTAssertNil(interaction.focusedID)
        XCTAssertNil(interaction.handle(.raise).first)
    }

    func testHoverClearsWhenTheWindowDisappears() {
        var interaction = MissionControlInteraction()
        interaction.open(with: windows())
        interaction.hover(3)
        interaction.update(frames: [windows()[0]])
        XCTAssertNil(interaction.hoveredID)
        interaction.hover(1)
        interaction.update(frames: windows())
        XCTAssertEqual(interaction.hoveredID, 1)
    }

    func testKeyboardReadinessTracksInputMonitoringWithoutBlockingTheOverlay() {
        let ready = MissionControlReadiness(
            accessibility: .granted, screenRecording: .denied, detection: .granted, inputMonitoring: .granted
        )
        XCTAssertTrue(ready.isReady)
        XCTAssertTrue(ready.keyboardReady)

        let noKeyboard = MissionControlReadiness(
            accessibility: .granted, screenRecording: .denied, detection: .granted, inputMonitoring: .denied
        )
        XCTAssertTrue(noKeyboard.isReady, "mouse overlay and AX actions work without Input Monitoring")
        XCTAssertFalse(noKeyboard.keyboardReady)

        XCTAssertFalse(MissionControlReadiness.unknown.keyboardReady)
    }

    func testPlacementOppositesKeepTheFilterReadoutAwayFromThePill() {
        XCTAssertEqual(MissionControlPlacement.top.opposite, .bottom)
        XCTAssertEqual(MissionControlPlacement.bottom.opposite, .top)
        XCTAssertEqual(MissionControlPlacement.leading.opposite, .trailing)
        XCTAssertEqual(MissionControlPlacement.trailing.opposite, .leading)
    }
}

/// Multi-display and Stage Manager geometry: Cocoa screen frames, the WindowServer's top-left window
/// frames and the panels' local spaces have to agree on every display, at any scale.
final class MissionControlScreenGeometryTests: XCTestCase {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    private let right = CGRect(x: 1440, y: 0, width: 2560, height: 1440)

    private func frame(_ id: UInt32, _ rect: CGRect) -> MissionControlWindowFrame {
        MissionControlWindowFrame(
            id: id, bundleID: "com.example.app", appName: "App", title: "Window",
            frame: rect, state: .standard, isFocused: false
        )
    }

    func testScreenFramesConvertBetweenCocoaAndTopLeftCoordinates() {
        let screens = [main, above, left, right]
        let height = MissionControlScreenGeometry.primaryHeight(screens)
        XCTAssertEqual(height, 900)

        XCTAssertEqual(MissionControlScreenGeometry.cgFrame(of: main, primaryHeight: height),
                       CGRect(x: 0, y: 0, width: 1440, height: 900))
        XCTAssertEqual(MissionControlScreenGeometry.cgFrame(of: above, primaryHeight: height),
                       CGRect(x: 0, y: -900, width: 1440, height: 900))
        XCTAssertEqual(MissionControlScreenGeometry.cgFrame(of: left, primaryHeight: height),
                       CGRect(x: -1920, y: -180, width: 1920, height: 1080))
        XCTAssertEqual(MissionControlScreenGeometry.cgFrame(of: right, primaryHeight: height),
                       CGRect(x: 1440, y: -540, width: 2560, height: 1440))
    }

    func testWindowFramesBecomePanelLocalOnEveryDisplay() {
        let height: CGFloat = 900
        XCTAssertEqual(
            MissionControlScreenGeometry.local(CGRect(x: 100, y: 50, width: 300, height: 200),
                                               on: main, primaryHeight: height),
            CGRect(x: 100, y: 50, width: 300, height: 200)
        )
        // A display above the main one has a negative top-left Y; local coordinates start at 0.
        XCTAssertEqual(
            MissionControlScreenGeometry.local(CGRect(x: 100, y: -850, width: 300, height: 200),
                                               on: above, primaryHeight: height),
            CGRect(x: 100, y: 50, width: 300, height: 200)
        )
        // A display to the left has a negative X, and its top is above the main display's origin.
        XCTAssertEqual(
            MissionControlScreenGeometry.local(CGRect(x: -1800, y: -100, width: 300, height: 200),
                                               on: left, primaryHeight: height),
            CGRect(x: 120, y: 80, width: 300, height: 200)
        )
        // A 2× display uses the same point geometry; the backing scale never changes the numbers.
        XCTAssertEqual(
            MissionControlScreenGeometry.local(CGRect(x: 1500, y: -500, width: 400, height: 300),
                                               on: right, primaryHeight: height),
            CGRect(x: 60, y: 40, width: 400, height: 300)
        )
    }

    func testEachWindowIsAssignedToTheDisplayItMostlyOccupies() throws {
        let screens = [main, above, left, right]
        let height = MissionControlScreenGeometry.primaryHeight(screens)
        let groups = MissionControlScreenGeometry.framesByScreen(
            [
                frame(1, CGRect(x: 100, y: 100, width: 300, height: 200)),
                frame(2, CGRect(x: -1000, y: 100, width: 300, height: 200)),
                frame(3, CGRect(x: 300, y: -800, width: 300, height: 200)),
                frame(4, CGRect(x: 1350, y: 100, width: 300, height: 200))
            ],
            screens: screens,
            primaryHeight: height
        )
        XCTAssertEqual(groups[0].map(\.id), [1])
        XCTAssertEqual(groups[1].map(\.id), [3])
        XCTAssertEqual(groups[2].map(\.id), [2])
        XCTAssertEqual(groups[3].map(\.id), [4], "a window across the seam goes to the larger share")
        XCTAssertEqual(groups[3][0].frame.origin.x, -90, "and is local to that display")

        // A window mostly on the main display but crossing into the right one stays on the main one.
        let seam = MissionControlScreenGeometry.framesByScreen(
            [frame(5, CGRect(x: 1200, y: 100, width: 300, height: 200))],
            screens: [main, right], primaryHeight: height
        )
        XCTAssertEqual(seam[0].map(\.id), [5])
        XCTAssertTrue(seam[1].isEmpty)
    }

    func testStageManagerWindowsOutsideEveryDisplayAreNotThumbnails() {
        let screens = [main]
        let height = MissionControlScreenGeometry.primaryHeight(screens)
        XCTAssertFalse(MissionControlScreenGeometry.isVisibleThumbnail(
            CGRect(x: -300, y: 100, width: 280, height: 400), screens: screens, primaryHeight: height
        ), "a parked stage is not drawn")
        XCTAssertFalse(MissionControlScreenGeometry.isVisibleThumbnail(
            CGRect(x: -60, y: 100, width: 100, height: 200), screens: screens, primaryHeight: height
        ), "only 40% visible")
        XCTAssertTrue(MissionControlScreenGeometry.isVisibleThumbnail(
            CGRect(x: -50, y: 100, width: 100, height: 200), screens: screens, primaryHeight: height
        ), "50% visible is a thumbnail")
        XCTAssertTrue(MissionControlScreenGeometry.isVisibleThumbnail(
            CGRect(x: 100, y: 100, width: 300, height: 200), screens: screens, primaryHeight: height
        ))
    }

    func testDisplayBelowTheMainOneHasAPositiveTopLeftOrigin() {
        let below = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let height = MissionControlScreenGeometry.primaryHeight([main, below])
        XCTAssertEqual(MissionControlScreenGeometry.cgFrame(of: below, primaryHeight: height),
                       CGRect(x: 0, y: 900, width: 1920, height: 1080))
        XCTAssertEqual(
            MissionControlScreenGeometry.local(CGRect(x: 100, y: 950, width: 300, height: 200),
                                               on: below, primaryHeight: height),
            CGRect(x: 100, y: 50, width: 300, height: 200)
        )
        XCTAssertTrue(MissionControlScreenGeometry.isVisibleThumbnail(
            CGRect(x: 100, y: 950, width: 300, height: 200),
            screens: [main, below], primaryHeight: height
        ))
    }

    func testScreenAssignmentIgnoresDisplaysThatAreNotThere() {
        let height = MissionControlScreenGeometry.primaryHeight([main])
        XCTAssertNil(MissionControlScreenGeometry.screenIndex(
            containing: CGRect(x: 3000, y: 0, width: 200, height: 200),
            screens: [main], primaryHeight: height
        ))
        XCTAssertEqual(MissionControlScreenGeometry.screenIndex(
            containing: CGRect(x: -10, y: 0, width: 200, height: 200),
            screens: [main], primaryHeight: height
        ), 0)
    }
}
