import XCTest
@testable import KatiKati

final class TilingLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)
    private let defaultGaps = TilingGaps(inner: 8, outer: 8)

    // MARK: - Overflow (too many windows for the space)

    /// Three equal columns in 1000 pt are ~323 pt wide, under `WindowFit.usableTile`; two are ~488.
    private var narrowArea: CGRect { CGRect(x: 0, y: 0, width: 1000, height: 400) }

    func testOverflowEvictsOnlyTheNewestWindowThatDoesNotFit() {
        let ids = (1...3).map { WindowID(rawValue: "of\($0)") }
        let evicted = TilingOverflow.evictions(
            ids: ids, preset: .columns, workArea: narrowArea, gaps: defaultGaps
        )
        XCTAssertEqual(evicted, [ids[2]])
        XCTAssertEqual(ids.count - evicted.count, 2)
    }

    func testOverflowReadmitsAWindowOnceOneLeaves() {
        let ids = (1...3).map { WindowID(rawValue: "of\($0)") }
        let two = Array(ids.prefix(2))
        XCTAssertEqual(
            TilingOverflow.evictions(ids: two, preset: .columns, workArea: narrowArea, gaps: defaultGaps),
            []
        )
    }

    // MARK: - TilingPolicy Tests

    func testTilingPolicyDefaultFloatingApps() {
        let policy = TilingPolicy()
        XCTAssertTrue(policy.shouldFloat(bundleIdentifier: "com.apple.systempreferences"))
        XCTAssertTrue(policy.shouldFloat(bundleIdentifier: "com.apple.calculator"))
        XCTAssertTrue(policy.shouldFloat(bundleIdentifier: "com.apple.archiveutility"))
        XCTAssertFalse(policy.shouldFloat(bundleIdentifier: "com.apple.Safari"))
        XCTAssertFalse(policy.shouldFloat(bundleIdentifier: "com.apple.Terminal"))
        XCTAssertFalse(policy.shouldFloat(bundleIdentifier: nil))
        XCTAssertFalse(policy.shouldFloat(bundleIdentifier: ""))
    }

    func testTilingPolicySerializationRoundtrip() {
        let original = TilingPolicy(floatingBundleIDs: ["com.example.app1", "com.example.app2"])
        let serialized = original.serializedPatterns
        let parsed = TilingPolicy.parse(patterns: serialized)
        XCTAssertEqual(original, parsed)
    }

    // MARK: - Layout Presets: BSP

    func testBSPDelegation() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        let resolved = TilingLayout.resolve(tree: tree, preset: .bsp, workArea: screen, gaps: defaultGaps)
        let direct = tree.resolveTiles(in: screen, gaps: defaultGaps)
        XCTAssertEqual(resolved, direct)
    }

    /// BSP's depth-driven tree and Spiral's remainder-slicing must not draw the same picture: four
    /// BSP windows sit in a 2×2 grid, four Spiral windows wind around the corner.
    func testBSPAndSpiralDifferAtFourWindows() {
        var tree = TilingTree()
        let ids = (0..<4).map { WindowID(rawValue: "w\($0)") }
        ids.forEach { tree.insert($0) }

        let bsp = TilingLayout.resolve(tree: tree, preset: .bsp, workArea: screen, gaps: defaultGaps)
        let spiral = TilingLayout.resolve(tree: tree, preset: .spiral, workArea: screen, gaps: defaultGaps)

        XCTAssertNotEqual(bsp, spiral, "the picker must not show the same picture twice")

        // BSP: two columns, two rows, all four tiles the same size.
        XCTAssertEqual(Set(bsp.values.map { "\($0.width)x\($0.height)" }).count, 1)
        XCTAssertEqual(Set(bsp.values.map(\.minX)).count, 2)
        XCTAssertEqual(Set(bsp.values.map(\.minY)).count, 2)

        // Spiral: the second window only gets half of the right side, so it is shorter than the first.
        XCTAssertEqual(spiral[ids[0]]?.height, screen.height - 16)
        XCTAssertLessThan(spiral[ids[1]]!.height, spiral[ids[0]]!.height)
    }

    /// The BSP tile draws five windows, so its depth-driven grid cannot be mistaken for Grid's four
    /// panes; every other picture keeps four.
    func testBSPPreviewDrawsFiveWindowsAndDiffersFromItsNeighbours() {
        XCTAssertEqual(TilingPreview.windowCount(for: .bsp), 5)
        XCTAssertEqual(TilingPreview.windowCount(for: .spiral), 4)

        let area = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bsp = TilingPreview.rects(preset: .bsp, area: area, gap: 2)
        let grid = TilingPreview.rects(preset: .grid, area: area, gap: 2)
        let spiral = TilingPreview.rects(preset: .spiral, area: area, gap: 2)

        XCTAssertEqual(bsp.count, 5)
        XCTAssertEqual(grid.count, 4)
        XCTAssertNotEqual(bsp, grid)
        XCTAssertNotEqual(bsp, spiral)
    }

    // MARK: - Layout Presets: Main + Stack

    func testMainStackSingleWindow() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        tree.insert(w1)

        let resolved = TilingLayout.resolve(tree: tree, preset: .mainStack, workArea: screen, gaps: defaultGaps)
        let expected = CGRect(
            x: screen.minX + 8,
            y: screen.minY + 8,
            width: screen.width - 16,
            height: screen.height - 16
        )
        XCTAssertEqual(resolved[w1], expected)
    }

    func testMainStackTwoWindows() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        let resolved = TilingLayout.resolve(tree: tree, preset: .mainStack, workArea: screen, gaps: defaultGaps)
        XCTAssertEqual(resolved.count, 2)

        guard let r1 = resolved[w1], let r2 = resolved[w2] else {
            XCTFail("Missing windows")
            return
        }

        XCTAssertFalse(r1.intersects(r2))
        XCTAssertEqual(r1.minX, screen.minX + 8)
        XCTAssertEqual(r2.maxX, screen.maxX - 8)
        XCTAssertEqual(r1.maxX + 8, r2.minX)
        XCTAssertEqual(r1.height, screen.height - 16)
        XCTAssertEqual(r2.height, screen.height - 16)
    }

    func testMainStackThreeWindows() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        let w3 = WindowID(rawValue: "w3")
        tree.insert(w1)
        tree.insert(w2)
        tree.insert(w3)

        let resolved = TilingLayout.resolve(tree: tree, preset: .mainStack, workArea: screen, gaps: defaultGaps)
        XCTAssertEqual(resolved.count, 3)

        guard let r1 = resolved[w1], let r2 = resolved[w2], let r3 = resolved[w3] else {
            XCTFail("Missing windows")
            return
        }

        // Main is on left
        XCTAssertEqual(r1.minX, screen.minX + 8)
        // Stack windows share the same right-column X coordinate and width
        XCTAssertEqual(r2.minX, r3.minX)
        XCTAssertEqual(r2.width, r3.width)

        // Neither stack window overlaps the other
        XCTAssertFalse(r2.intersects(r3))
        XCTAssertFalse(r1.intersects(r2))
        XCTAssertFalse(r1.intersects(r3))
    }

    // MARK: - Layout Presets: Monocle

    func testMonocleAllWindowsGetSameFullArea() {
        var tree = TilingTree()
        let w1 = WindowID(rawValue: "w1")
        let w2 = WindowID(rawValue: "w2")
        tree.insert(w1)
        tree.insert(w2)

        let resolved = TilingLayout.resolve(tree: tree, preset: .monocle, workArea: screen, gaps: defaultGaps)
        let expected = CGRect(
            x: screen.minX + 8,
            y: screen.minY + 8,
            width: screen.width - 16,
            height: screen.height - 16
        )

        XCTAssertEqual(resolved[w1], expected)
        XCTAssertEqual(resolved[w2], expected)
    }

    func testEmptyTreeResolvesEmptyAcrossAllPresets() {
        let tree = TilingTree()
        for preset in TilingLayoutPreset.allCases {
            let res = TilingLayout.resolve(tree: tree, preset: preset, workArea: screen, gaps: defaultGaps)
            XCTAssertTrue(res.isEmpty, "Preset \(preset) must return empty for empty tree")
        }
    }

    func testDockReserveCutsTheNearestEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 780)
        XCTAssertEqual(DockReserve.workArea(visible: visible, screen: screen, dock: CGRect(x: 900, y: 200, width: 90, height: 400)),
                       CGRect(x: 0, y: 0, width: 900, height: 780))
        XCTAssertEqual(DockReserve.workArea(visible: visible, screen: screen, dock: CGRect(x: 10, y: 200, width: 90, height: 400)),
                       CGRect(x: 100, y: 0, width: 900, height: 780))
        XCTAssertEqual(DockReserve.workArea(visible: visible, screen: screen, dock: CGRect(x: 300, y: 8, width: 400, height: 80)),
                       CGRect(x: 0, y: 88, width: 1000, height: 692))
        XCTAssertEqual(DockReserve.workArea(visible: visible, screen: screen, dock: nil), visible)
    }

    func testShiftedKeepsWindowInsideArea() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        XCTAssertEqual(WindowFit.shifted(CGRect(x: 800, y: 700, width: 400, height: 300), into: area),
                       CGRect(x: 600, y: 500, width: 400, height: 300))
        XCTAssertEqual(WindowFit.shifted(CGRect(x: -50, y: 10, width: 1200, height: 100), into: area).minX, 0)
    }

    /// A layout-restore frame must fit the area tiling uses today: same size area is a no-op, an
    /// oversize frame shrinks, and one hanging off an edge shifts fully inside.
    func testFittedFitsRestoredFrameIntoWorkArea() {
        let area = CGRect(x: 0, y: 88, width: 1000, height: 692)
        XCTAssertEqual(WindowFit.fitted(area, into: area), area)
        XCTAssertEqual(WindowFit.fitted(CGRect(x: 900, y: 700, width: 400, height: 300), into: area),
                       CGRect(x: 600, y: 480, width: 400, height: 300))
        XCTAssertEqual(WindowFit.fitted(CGRect(x: -120, y: 0, width: 1400, height: 1000), into: area),
                       CGRect(x: 0, y: 88, width: 1000, height: 692))
        XCTAssertEqual(WindowFit.fitted(CGRect(x: 100, y: 200, width: 300, height: 200), into: area),
                       CGRect(x: 100, y: 200, width: 300, height: 200))
    }

    func testAllUsableRejectsTinyTiles() {
        XCTAssertTrue(WindowFit.allUsable([CGRect(x: 0, y: 0, width: 400, height: 300)]))
        XCTAssertFalse(WindowFit.allUsable([CGRect(x: 0, y: 0, width: 400, height: 110)]))
    }

    func testNativeTileDetection() {
        let area = CGRect(x: 0, y: 38, width: 1600, height: 1000)
        XCTAssertTrue(WindowFit.isNativeTile(CGRect(x: 0, y: 38, width: 800, height: 1000), in: area))
        XCTAssertTrue(WindowFit.isNativeTile(CGRect(x: 800, y: 538, width: 800, height: 500), in: area))
        XCTAssertFalse(WindowFit.isNativeTile(area, in: area))
        XCTAssertFalse(WindowFit.isNativeTile(CGRect(x: 300, y: 200, width: 800, height: 500), in: area))
    }

    // MARK: - Ribbon strip state (RT-1) and camera/parking (RT-2)

    private func w(_ n: Int) -> WindowID { WindowID(rawValue: "\(n)") }

    func testStripInsertsRightOfFocusAndClosesGaps() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)])
        XCTAssertEqual(strip.windowIDs, [w(1), w(2), w(3)])

        strip.focus(w(2))
        strip.insert(w(4))
        XCTAssertEqual(strip.windowIDs, [w(1), w(2), w(4), w(3)], "a new window joins right of focus")
        XCTAssertEqual(strip.focusedID, w(4))

        strip.remove(w(2))
        XCTAssertEqual(strip.windowIDs, [w(1), w(4), w(3)], "closing leaves no gap")
        XCTAssertEqual(strip.focusedID, w(4))

        strip.remove(w(4))
        XCTAssertEqual(strip.windowIDs, [w(1), w(3)])
    }

    func testStripWidthCyclesInPlace() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2)])
        strip.focus(w(1))
        XCTAssertEqual(strip.focusedColumn?.width, .half)
        strip.cycleWidth()
        XCTAssertEqual(strip.focusedColumn?.width, .twoThirds)
        strip.cycleWidth()
        XCTAssertEqual(strip.focusedColumn?.width, .full)
        strip.cycleWidth()
        XCTAssertEqual(strip.focusedColumn?.width, .quarter, "cycling wraps")
        XCTAssertEqual(strip.columns[1].width, .half, "only the focused column changes")
        XCTAssertEqual(strip.width, .quarter, "the strip remembers the width for new columns")
        strip.insert(w(3))
        XCTAssertEqual(strip.focusedColumn?.width, .quarter)
    }

    func testStripStacksLeftAndUntabs() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)])
        strip.focus(w(2))
        strip.stackLeft()
        XCTAssertEqual(strip.columns.map(\.windowIDs), [[w(1), w(2)], [w(3)]])
        XCTAssertEqual(strip.focusedColumn?.windowIDs, [w(1), w(2)])
        XCTAssertTrue(strip.focusedColumn?.isTabbed == true)
        XCTAssertEqual(strip.focusedID, w(2))

        strip.toggleTabs()
        XCTAssertEqual(strip.columns.map(\.windowIDs), [[w(1)], [w(2)], [w(3)]], "untabbing splits the tab back out")
        XCTAssertEqual(strip.focusedIndex, 0)
    }

    func testStripTabsStepInsideTheColumn() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)])
        strip.focus(w(2))
        strip.stackLeft()
        strip.focusTab(1)
        XCTAssertEqual(strip.focusedID, w(1))
        strip.focusTab(1)
        XCTAssertEqual(strip.focusedID, w(2), "tab focus wraps inside the column")
        strip.focusTab(-2)
        XCTAssertEqual(strip.focusedID, w(2))
    }

    func testStripSyncKeepsOrderAndAdoptsNewWindows() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)])
        strip.focus(w(2))
        strip.swapFocused(1)
        XCTAssertEqual(strip.windowIDs, [w(1), w(3), w(2)])
        strip.sync(with: [w(1), w(3), w(2), w(4)])
        XCTAssertEqual(strip.windowIDs, [w(1), w(3), w(2), w(4)], "sync appends newcomers without reordering")
        strip.sync(with: [w(4), w(1)])
        XCTAssertEqual(strip.windowIDs, [w(1), w(4)], "vanished windows are dropped")
    }

    func testCameraMovesOnlyAsFarAsTheFocusNeeds() {
        let viewport: CGFloat = 1000
        let content: CGFloat = 3000
        // Focus already fully visible: no movement.
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 100, y: 0, width: 500, height: 800), viewportWidth: viewport, contentWidth: content, current: 0), 0)
        // Focus past the right edge: scroll just enough to reveal it.
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 1300, y: 0, width: 500, height: 800), viewportWidth: viewport, contentWidth: content, current: 0), 800)
        // Focus before the left edge: scroll back to its leading edge.
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 400, y: 0, width: 500, height: 800), viewportWidth: viewport, contentWidth: content, current: 1200), 400)
        // Never scrolls past either end.
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 2800, y: 0, width: 500, height: 800), viewportWidth: viewport, contentWidth: content, current: 0), 2000)
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 0, y: 0, width: 500, height: 800), viewportWidth: viewport, contentWidth: content, current: 900), 0)
        // Content narrower than the viewport has nothing to scroll.
        XCTAssertEqual(StripCamera.offset(focused: CGRect(x: 0, y: 0, width: 900, height: 800), viewportWidth: viewport, contentWidth: 900, current: 400), 0)
    }

    func testParkingLeavesTheOnePointPeekMacOSAllows() {
        let area = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let column = CGRect(x: 0, y: 0, width: 500, height: 1000)
        XCTAssertEqual(StripParking.parked(column, in: area, side: .left).minX, -499)
        XCTAssertEqual(StripParking.parked(column, in: area, side: .right).minX, 1599)
        XCTAssertEqual(StripParking.parked(column, in: area, side: .bottom).minY, -999)
        XCTAssertEqual(StripParking.parked(column, in: area, side: .left).width, column.width)
        XCTAssertEqual(StripParking.side(forEdge: .left, neighbourOnEdge: false), .left)
        XCTAssertEqual(StripParking.side(forEdge: .left, neighbourOnEdge: true), .bottom, "a neighbour makes the column park below")
        XCTAssertEqual(StripParking.side(forEdge: .right, neighbourOnEdge: true), .bottom)
    }

    func testRibbonColumnsScrollToTheFocusedColumn() {
        let strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)], width: .half)
        let content = CGRect(x: 100, y: 40, width: 1000, height: 800)
        let start = TilingLayout.resolveRibbon(state: strip, in: content, gap: 8, camera: 0)
        XCTAssertEqual(start.frames[w(1)]?.minX, 100)
        XCTAssertEqual(start.frames[w(2)]?.minX, 608)
        XCTAssertEqual(start.frames[w(3)]?.minX, 1116)
        XCTAssertEqual(start.parked[w(3)], .right, "a column past the right edge parks there")
        XCTAssertNil(start.parked[w(1)])

        var focused = strip
        focused.focus(w(3))
        let scrolled = TilingLayout.resolveRibbon(state: focused, in: content, gap: 8, camera: 0)
        XCTAssertEqual(scrolled.camera, 516, "the camera stops when the last column is flush right")
        XCTAssertEqual(scrolled.frames[w(3)]?.maxX, 1100)
        XCTAssertEqual(scrolled.parked[w(1)], .left, "the column pushed out on the left parks there")
        XCTAssertNil(scrolled.parked[w(3)])
    }

    func testRibbonTabsShareTheirColumnFrame() {
        var strip = ScrollingStripState(windowIDs: [w(1), w(2), w(3)])
        strip.focus(w(2))
        strip.stackLeft()
        let laid = TilingLayout.resolveRibbon(state: strip, in: CGRect(x: 0, y: 0, width: 1000, height: 800), gap: 8, camera: 0)
        XCTAssertEqual(laid.frames[w(1)], laid.frames[w(2)], "both tabs sit in the same column")
        XCTAssertEqual(laid.frames[w(1)]?.width, 500)
    }

    // MARK: - Ribbon pictures (RT-3)

    func testRibbonPicturesMapOntoExistingGeometry() {
        XCTAssertEqual(RibbonQuickLayout.allCases.count, 8)
        XCTAssertEqual(RibbonQuickLayout.allCases.first, .chain, "Chain leads the visual order")
        XCTAssertNil(RibbonQuickLayout.chain.catalog)
        XCTAssertEqual(RibbonQuickLayout.chain.slots, 0, "the strip itself has no slot cap")
        for picture in RibbonQuickLayout.allCases where picture != .chain {
            guard let catalog = picture.catalog else {
                XCTFail("\(picture) must map to a catalog picture")
                continue
            }
            XCTAssertEqual(picture.slots, catalog.slots, "picture and catalog agree on \(picture)")
            let ids = (0..<6).map { WindowID(rawValue: "p\($0)") }
            let area = CGRect(x: 0, y: 0, width: 1440, height: 860)
            let frames = catalog.frames(for: ids, workArea: area, gaps: TilingGaps(inner: 8, outer: 8))
            XCTAssertEqual(frames.count, catalog.slots, "\(picture) shows exactly its slots")
            for frame in frames.values {
                XCTAssertTrue(area.contains(frame), "\(picture) stays inside the work area")
            }
        }
        XCTAssertEqual(RibbonQuickLayout.fiveUp.slots, 5)
        XCTAssertEqual(RibbonQuickLayout.sixUp.slots, 6)
        XCTAssertEqual(RibbonQuickLayout.twoPlusOne.catalog, .mainRight)
        XCTAssertEqual(RibbonQuickLayout.onePlusTwo.catalog, .mainLeft)
    }

    // MARK: - Sliced presets

    func testSlicedPresetsTileInsideWorkAreaWithoutOverlap() {
        // BSP is tree-based rather than sliced, but it owes the same invariants.
        for preset in [TilingLayoutPreset.bsp, .grid, .spiral, .columns, .rows, .centeredMain] {
            for n in 1...6 {
                var tree = TilingTree()
                for i in 0..<n { tree.insert(WindowID(rawValue: "w\(i)")) }
                let frames = Array(TilingLayout.resolve(tree: tree, preset: preset, workArea: screen, gaps: defaultGaps).values)
                XCTAssertEqual(frames.count, n, "\(preset) n=\(n)")
                for (i, a) in frames.enumerated() {
                    XCTAssertTrue(screen.insetBy(dx: -1, dy: -1).contains(a), "\(preset) n=\(n) outside")
                    for b in frames[(i + 1)...] {
                        XCTAssertTrue(a.intersection(b).width < 1 || a.intersection(b).height < 1, "\(preset) n=\(n) overlap")
                    }
                }
            }
        }
    }

    func testMainStackRatioAndMirror() {
        var tree = TilingTree()
        let a = WindowID(rawValue: "a"), b = WindowID(rawValue: "b")
        tree.insert(a); tree.insert(b)
        let wide = TilingLayout.resolve(tree: tree, preset: .mainStack, workArea: screen, gaps: defaultGaps,
                                        options: TilingLayoutOptions(mainRatio: 0.7, mirrored: true))
        XCTAssertGreaterThan(wide[a]!.width, wide[b]!.width)
        XCTAssertGreaterThan(wide[a]!.minX, wide[b]!.minX)
    }

    func testPolicyRulesRoundTripAndLegacyLines() {
        let policy = TilingPolicy.parse(patterns: "com.a\ncom.b=tile\ncom.c=display:LG UltraFine\ncom.d=float")
        XCTAssertTrue(policy.shouldFloat(bundleIdentifier: "com.a"))
        XCTAssertTrue(policy.shouldFloat(bundleIdentifier: "com.d"))
        XCTAssertTrue(policy.alwaysTiles(bundleIdentifier: "com.b"))
        XCTAssertEqual(policy.pinnedDisplay(bundleIdentifier: "com.c"), "LG UltraFine")
        XCTAssertEqual(TilingPolicy.parse(patterns: policy.serializedPatterns), policy)
    }

    func testWindowFitNearlyEqualAndQuartzToCocoaCenter() {
        let a = CGRect(x: 100, y: 200, width: 500, height: 400)
        let b = CGRect(x: 101.5, y: 198.5, width: 501, height: 399)
        let c = CGRect(x: 105, y: 200, width: 500, height: 400)
        XCTAssertTrue(WindowFit.isNearlyEqual(a, b, tolerance: 2))
        XCTAssertFalse(WindowFit.isNearlyEqual(a, c, tolerance: 2))

        // Primary screen height 900: Quartz y=100..300 (midY=200) -> Cocoa midY = 900 - 200 = 700
        let quartz = CGRect(x: 50, y: 100, width: 200, height: 200)
        let center = WindowFit.cocoaCenter(ofQuartzFrame: quartz, primaryMaxY: 900)
        XCTAssertEqual(center, CGPoint(x: 150, y: 700))
    }

    // MARK: - Industry names (AeroSpace / Amethyst)

    /// Every preset has to be sayable: a badge the picker can print and a name spelled out, so no
    /// layout is only a code word.
    func testEveryPresetHasABadgeAndAFullName() {
        for preset in TilingLayoutPreset.allCases {
            XCTAssertFalse(preset.alias.abbreviation.isEmpty, "\(preset) has no badge")
            XCTAssertLessThanOrEqual(preset.alias.abbreviation.count, 4, "\(preset)'s badge is too long")
            XCTAssertFalse(preset.alias.fullName.isEmpty, "\(preset) has no full name")
            XCTAssertTrue(preset.describedName.contains(preset.alias.abbreviation))
            XCTAssertTrue(preset.describedName.contains(preset.alias.fullName))
        }
    }

    /// The mapping people arriving from other tiling managers rely on.
    func testPresetsNameTheirEquivalentInOtherWindowManagers() {
        XCTAssertEqual(TilingLayoutPreset.bsp.alias.fullName, "Binary Space Partitioning")
        XCTAssertEqual(TilingLayoutPreset.bsp.describedName, "BSP · Binary Space Partitioning")
        XCTAssertEqual(TilingLayoutPreset.columns.standardNames, "AeroSpace h_tiles · Amethyst Column")
        XCTAssertEqual(TilingLayoutPreset.rows.standardNames, "AeroSpace v_tiles · Amethyst Row")
        XCTAssertEqual(TilingLayoutPreset.monocle.standardNames, "AeroSpace accordion · Amethyst Fullscreen")
        XCTAssertEqual(TilingLayoutPreset.mainStack.standardNames, "Amethyst Tall / Tall-Right")
        XCTAssertNil(TilingLayoutPreset.ribbon.standardNames, "the strip has no equivalent to name")
        XCTAssertNil(TilingLayoutPreset.spiral.standardNames)
    }
}
