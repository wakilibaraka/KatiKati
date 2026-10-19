import XCTest
@testable import KatiKati

final class TilingLayoutTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 40, width: 1440, height: 860)
    private let defaultGaps = TilingGaps(inner: 8, outer: 8)

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

    // MARK: - Sliced presets

    func testSlicedPresetsTileInsideWorkAreaWithoutOverlap() {
        for preset in [TilingLayoutPreset.grid, .spiral, .columns, .rows, .centeredMain] {
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
}
