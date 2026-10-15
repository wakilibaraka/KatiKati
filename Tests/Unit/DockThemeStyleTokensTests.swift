import XCTest
@testable import KatiKati

final class DockThemeStyleTokensTests: XCTestCase {

    func testPresetsAreValueFrozen() {
        let roseLight = DockThemeStyleTokens.resolve(style: .roseQuartz, appearance: .light)
        XCTAssertEqual(roseLight.baseTint.r, 0.95)
        XCTAssertEqual(roseLight.baseTint.g, 0.85)
        XCTAssertEqual(roseLight.baseTint.b, 0.88)
        XCTAssertEqual(roseLight.prefersDarkContent, true)

        let obsDark = DockThemeStyleTokens.resolve(style: .obsidianDark, appearance: .dark)
        XCTAssertEqual(obsDark.baseTint.r, 0.05)
        XCTAssertEqual(obsDark.baseTint.g, 0.05)
        XCTAssertEqual(obsDark.baseTint.b, 0.05)
        XCTAssertEqual(obsDark.prefersDarkContent, false)

        let deepOceanLight = DockThemeStyleTokens.resolve(style: .deepOcean, appearance: .light)
        XCTAssertEqual(deepOceanLight.baseTint.r, 0.80)
        XCTAssertEqual(deepOceanLight.baseTint.g, 0.88)
        XCTAssertEqual(deepOceanLight.baseTint.b, 0.98)

        let emberSunsetDark = DockThemeStyleTokens.resolve(style: .emberSunset, appearance: .dark)
        XCTAssertEqual(emberSunsetDark.baseTint.r, 0.25)
        XCTAssertEqual(emberSunsetDark.baseTint.g, 0.12)
        XCTAssertEqual(emberSunsetDark.baseTint.b, 0.08)
    }

    func testAutoResolvesToRoseAndObsidian() {
        let autoLight = DockThemeStyleTokens.resolve(style: .auto, appearance: .light)
        let roseLight = DockThemeStyleTokens.resolve(style: .roseQuartz, appearance: .light)
        XCTAssertEqual(autoLight, roseLight)

        let autoDark = DockThemeStyleTokens.resolve(style: .auto, appearance: .dark)
        let obsDark = DockThemeStyleTokens.resolve(style: .obsidianDark, appearance: .dark)
        XCTAssertEqual(autoDark, obsDark)
    }

    // MARK: - 4b — preset data (every preset × appearance column frozen, all fields finite,
    // all 12 columns distinct)

    private typealias RGBA = (CGFloat, CGFloat, CGFloat, CGFloat)

    private static func column(_ baseTint: RGBA, _ sheen: RGBA, _ glow: RGBA, _ rim: RGBA,
                               _ blur: CGFloat, _ prefersDarkContent: Bool,
                               bottom: RGBA? = nil) -> DockThemeStyleTokens {
        DockThemeStyleTokens(
            baseTint: DockRGBA(r: baseTint.0, g: baseTint.1, b: baseTint.2, a: baseTint.3),
            gradientSheen: DockRGBA(r: sheen.0, g: sheen.1, b: sheen.2, a: sheen.3),
            glow: DockRGBA(r: glow.0, g: glow.1, b: glow.2, a: glow.3),
            rim: DockRGBA(r: rim.0, g: rim.1, b: rim.2, a: rim.3),
            blurRadius: blur,
            prefersDarkContent: prefersDarkContent,
            baseTintBottom: bottom.map { DockRGBA(r: $0.0, g: $0.1, b: $0.2, a: $0.3) }
        )
    }

    /// The 12 presets × light/dark, all six fields, frozen as literals. Witness for the 4h
    /// rework (before it every column held the same white-tint values) and for any later drift.
    func testEveryPresetColumnIsValueFrozen() {
        let frozen: [(DockThemeStyle, AppearanceMode, DockThemeStyleTokens)] = [
            (.system, .light, Self.column((0.9, 0.9, 0.9, 0.5), (1, 1, 1, 0.3), (1, 1, 1, 0.2), (1, 1, 1, 0.4), 30, true)),
            (.system, .dark, Self.column((0.1, 0.1, 0.1, 0.6), (1, 1, 1, 0.05), (1, 1, 1, 0.0), (1, 1, 1, 0.15), 30, false)),
            (.translucent, .light, Self.column((0.95, 0.95, 0.95, 0.3), (1, 1, 1, 0.4), (1, 1, 1, 0.3), (1, 1, 1, 0.5), 20, true)),
            (.translucent, .dark, Self.column((0.15, 0.15, 0.15, 0.4), (1, 1, 1, 0.1), (1, 1, 1, 0.05), (1, 1, 1, 0.2), 20, false)),
            (.crystalClear, .light, Self.column((1, 1, 1, 0.1), (1, 1, 1, 0.5), (1, 1, 1, 0.4), (1, 1, 1, 0.6), 10, true)),
            (.crystalClear, .dark, Self.column((0, 0, 0, 0.2), (1, 1, 1, 0.2), (1, 1, 1, 0.1), (1, 1, 1, 0.3), 10, false)),
            (.obsidianDark, .light, Self.column((0.2, 0.2, 0.25, 0.8), (1, 1, 1, 0.1), (1, 1, 1, 0.0), (1, 1, 1, 0.2), 30, false)),
            (.obsidianDark, .dark, Self.column((0.05, 0.05, 0.05, 0.85), (1, 1, 1, 0.05), (1, 1, 1, 0.0), (1, 1, 1, 0.15), 30, false)),
            (.monochrome, .light, Self.column((0.95, 0.95, 0.95, 0.6), (1, 1, 1, 0.4), (1, 1, 1, 0.3), (0.8, 0.8, 0.8, 0.5), 30, true)),
            (.monochrome, .dark, Self.column((0.12, 0.12, 0.12, 0.7), (1, 1, 1, 0.1), (1, 1, 1, 0.05), (0.3, 0.3, 0.3, 0.4), 30, false)),
            (.titaniumFrost, .light, Self.column((0.88, 0.90, 0.92, 0.55), (1, 1, 1, 0.45), (1, 1, 1, 0.25), (0.9, 0.92, 0.95, 0.6), 35, true)),
            (.titaniumFrost, .dark, Self.column((0.15, 0.16, 0.18, 0.65), (0.9, 0.95, 1.0, 0.15), (0.8, 0.9, 1.0, 0.05), (0.4, 0.45, 0.5, 0.3), 35, false)),
            (.auroraGlow, .light, Self.column((0.85, 0.95, 0.90, 0.5), (0.7, 1.0, 0.8, 0.4), (0.4, 1.0, 0.6, 0.2), (0.6, 0.9, 0.7, 0.5), 30, true, bottom: (0.66, 0.90, 0.80, 0.50))),
            (.auroraGlow, .dark, Self.column((0.1, 0.2, 0.15, 0.65), (0.3, 0.8, 0.5, 0.2), (0.2, 0.9, 0.4, 0.15), (0.2, 0.6, 0.4, 0.4), 30, false, bottom: (0.06, 0.32, 0.24, 0.65))),
            (.deepOcean, .light, Self.column((0.80, 0.88, 0.98, 0.55), (0.7, 0.85, 1.0, 0.35), (0.4, 0.6, 1.0, 0.2), (0.5, 0.7, 0.95, 0.45), 30, true, bottom: (0.62, 0.78, 0.98, 0.55))),
            (.deepOcean, .dark, Self.column((0.05, 0.15, 0.25, 0.7), (0.2, 0.4, 0.8, 0.15), (0.1, 0.3, 0.7, 0.1), (0.2, 0.35, 0.6, 0.3), 30, false, bottom: (0.02, 0.07, 0.22, 0.70))),
            (.forestMoss, .light, Self.column((0.85, 0.92, 0.85, 0.55), (0.8, 1.0, 0.8, 0.3), (0.6, 0.9, 0.6, 0.15), (0.7, 0.9, 0.7, 0.4), 30, true, bottom: (0.72, 0.88, 0.70, 0.55))),
            (.forestMoss, .dark, Self.column((0.1, 0.2, 0.1, 0.7), (0.2, 0.5, 0.2, 0.15), (0.1, 0.4, 0.1, 0.1), (0.2, 0.4, 0.2, 0.3), 30, false, bottom: (0.05, 0.17, 0.07, 0.70))),
            (.cyberpunkGlass, .light, Self.column((0.95, 0.85, 0.95, 0.6), (1.0, 0.6, 0.9, 0.4), (0.9, 0.2, 0.8, 0.25), (1.0, 0.4, 0.8, 0.5), 25, true, bottom: (0.80, 0.62, 0.96, 0.60))),
            (.cyberpunkGlass, .dark, Self.column((0.15, 0.05, 0.20, 0.75), (0.8, 0.2, 0.9, 0.25), (0.7, 0.0, 0.8, 0.2), (0.6, 0.1, 0.7, 0.4), 25, false, bottom: (0.30, 0.03, 0.38, 0.75))),
            (.emberSunset, .light, Self.column((0.98, 0.88, 0.82, 0.55), (1.0, 0.75, 0.5, 0.4), (1.0, 0.5, 0.2, 0.25), (1.0, 0.6, 0.4, 0.45), 30, true, bottom: (0.98, 0.72, 0.60, 0.55))),
            (.emberSunset, .dark, Self.column((0.25, 0.12, 0.08, 0.7), (0.9, 0.4, 0.2, 0.2), (0.8, 0.3, 0.1, 0.15), (0.7, 0.3, 0.15, 0.35), 30, false, bottom: (0.40, 0.10, 0.06, 0.70))),
            (.roseQuartz, .light, Self.column((0.95, 0.85, 0.88, 0.6), (1.0, 0.9, 0.95, 0.35), (1.0, 0.8, 0.9, 0.2), (1.0, 0.7, 0.85, 0.4), 30, true, bottom: (0.90, 0.72, 0.82, 0.60))),
            (.roseQuartz, .dark, Self.column((0.25, 0.15, 0.18, 0.7), (0.9, 0.6, 0.7, 0.15), (0.8, 0.4, 0.5, 0.1), (0.6, 0.3, 0.4, 0.25), 30, false, bottom: (0.30, 0.12, 0.20, 0.70))),
        ]
        XCTAssertEqual(frozen.count, 24, "12 presets × 2 appearances")
        for (style, appearance, expected) in frozen {
            XCTAssertEqual(DockThemeStyleTokens.resolve(style: style, appearance: appearance), expected,
                           "\(style.token) / \(appearance.rawValue) column drifted")
        }
    }

    /// Every field of every resolved column — all four channels of all four colours, plus the
    /// blur — must be a finite number, in every appearance and for the computed paths too.
    func testAllFieldsFinite() {
        var styles: [DockThemeStyle] = [
            .system, .translucent, .crystalClear, .obsidianDark, .monochrome, .titaniumFrost,
            .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass, .emberSunset, .roseQuartz,
            .auto, .customRGBA(r: 0.3, g: 0.5, b: 0.7, a: 0.9),
        ]
        for style in styles {
            for appearance in AppearanceMode.allCases {
                let token = DockThemeStyleTokens.resolve(style: style, appearance: appearance)
                for channel in [token.baseTint, token.gradientSheen, token.glow, token.rim]
                    + (token.baseTintBottom.map { [$0] } ?? []) {
                    XCTAssertTrue(channel.r.isFinite && channel.g.isFinite
                        && channel.b.isFinite && channel.a.isFinite,
                                  "\(style.token) / \(appearance.rawValue): non-finite channel \(channel)")
                }
                XCTAssertTrue(token.blurRadius.isFinite,
                              "\(style.token) / \(appearance.rawValue): non-finite blur")
            }
        }
        for token in [DockThemeStyleTokens.systemLight, .systemDark,
                      .translucentLight, .translucentDark,
                      .crystalClearLight, .crystalClearDark,
                      .obsidianDarkLight, .obsidianDarkDark,
                      .monochromeLight, .monochromeDark,
                      .titaniumFrostLight, .titaniumFrostDark,
                      .auroraGlowLight, .auroraGlowDark,
                      .deepOceanLight, .deepOceanDark,
                      .forestMossLight, .forestMossDark,
                      .cyberpunkGlassLight, .cyberpunkGlassDark,
                      .emberSunsetLight, .emberSunsetDark,
                      .roseQuartzLight, .roseQuartzDark] {
            XCTAssertTrue(token.baseTint.r.isFinite)
            XCTAssertTrue(token.gradientSheen.r.isFinite)
            XCTAssertTrue(token.glow.r.isFinite)
            XCTAssertTrue(token.rim.r.isFinite)
            XCTAssertTrue(token.blurRadius.isFinite)
        }
    }

    /// The 4h rework defect: all 12 preset columns collapsed to the same white-tint values.
    /// Each preset must hold a column nobody else holds, per appearance.
    func testAllTwelvePresetColumnsAreDistinct() {
        let presets: [DockThemeStyle] = [
            .system, .translucent, .crystalClear, .obsidianDark, .monochrome, .titaniumFrost,
            .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass, .emberSunset, .roseQuartz,
        ]
        XCTAssertEqual(presets.count, 12)
        for appearance in [AppearanceMode.light, .dark] {
            let columns = presets.map { DockThemeStyleTokens.resolve(style: $0, appearance: appearance) }
            for i in columns.indices {
                for j in columns.indices where j > i {
                    XCTAssertNotEqual(columns[i], columns[j],
                                      "\(presets[i].token) and \(presets[j].token) share a column in \(appearance.rawValue)")
                }
            }
        }
    }

    // MARK: - Phase 12: the gradient stop

    /// The gradient set is deliberately small, and it is enumerated here: a preset that gains a
    /// gradient (or loses one) has to say so in this test, not slip into a screenshot.
    func testOnlyTheGradientStylesCarryASecondStop() {
        let withGradient: Set<DockGradientPreset> = [.aurora, .ocean, .forest, .neon, .sunset, .rose]
        let presets: [DockThemeStyle] = [
            .system, .translucent, .crystalClear, .obsidianDark, .monochrome, .titaniumFrost,
            .auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass, .emberSunset, .roseQuartz,
            .customRGBA(r: 0.3, g: 0.5, b: 0.7, a: 0.9),
        ]
        for style in presets {
            let expectsGradient = withGradient.contains(DockGradientPreset.forStyle(style))
            for appearance in AppearanceMode.allCases {
                let column = DockThemeStyleTokens.resolve(style: style, appearance: appearance)
                XCTAssertEqual(column.baseTintBottom != nil, expectsGradient,
                               "\(style.token) / \(appearance.rawValue): gradient stop presence drifted")
            }
        }
        XCTAssertEqual(DockGradientPreset.forStyle(.auto), .solid, "auto must not tint the plate")
        XCTAssertEqual(DockGradientPreset.forStyle(.roseQuartz), .rose, "auto's light half resolves to roseQuartz")
    }

    /// A stop that equals the top stop is not a gradient (and a `nil` stop beside a non-nil one is a
    /// half-drawn plate), so both go through one check per gradient family × appearance.
    func testEachGradientRunsFromItsTopStopToADifferentBottomStop() {
        for style in [DockThemeStyle.auroraGlow, .deepOcean, .forestMoss, .cyberpunkGlass, .emberSunset, .roseQuartz] {
            for appearance in AppearanceMode.allCases {
                let column = DockThemeStyleTokens.resolve(style: style, appearance: appearance)
                guard let bottom = column.baseTintBottom else {
                    XCTFail("\(style.token) / \(appearance.rawValue): no gradient stop")
                    continue
                }
                XCTAssertNotEqual(bottom, column.baseTint,
                                  "\(style.token) / \(appearance.rawValue): the two stops are the same colour")
                for channel in [bottom.r, bottom.g, bottom.b, bottom.a] {
                    XCTAssertTrue(channel.isFinite && channel >= 0 && channel <= 1,
                                  "\(style.token) / \(appearance.rawValue): stop channel out of range")
                }
            }
        }
    }

    /// The Appearance page's identity points: a user who never touches the two sliders gets the plate
    /// this file has always drawn.
    func testAppearanceTuningIdentityLeavesTheResolvedPlateAlone() {
        XCTAssertEqual(DockThemeStyle.identityVibrancy, DockThemeStyle.plateOverlayStrength)
        XCTAssertEqual(DockThemeStyle.vibrancyRange, 0.1 ... 1.0)
        XCTAssertEqual(DockThemeStyle.contrastRange, 0.5 ... 2.0)
        let tint = DockRGBA(r: 0.05, g: 0.15, b: 0.25, a: 0.7)
        XCTAssertEqual(DockThemeStyle.deepOcean.plateOverlay(baseTint: tint),
                       DockThemeStyle.deepOcean.plateOverlay(baseTint: tint,
                                                             vibrancy: DockThemeStyle.identityVibrancy,
                                                             contrast: 1))
        XCTAssertEqual(DockThemeStyle.deepOcean.plateOverlay(baseTint: tint),
                       DockRGBA(r: 0.05, g: 0.15, b: 0.25, a: 0.7 * DockThemeStyle.plateOverlayStrength))
    }

    /// The gradient stop is only drawn by a style that tints at all, and it takes the same
    /// vibrancy/contrast pass as the top stop.
    func testGradientStopIsDroppedWhereThePlateIsUntinted() {
        let bottom = DockRGBA(r: 0.3, g: 0.1, b: 0.2, a: 0.7)
        XCTAssertNil(DockThemeStyle.auto.plateOverlayBottom(baseTintBottom: bottom))
        XCTAssertNil(DockThemeStyle.system.plateOverlayBottom(baseTintBottom: bottom))
        XCTAssertNil(DockThemeStyle.deepOcean.plateOverlayBottom(baseTintBottom: nil))
        XCTAssertEqual(DockThemeStyle.deepOcean.plateOverlayBottom(baseTintBottom: bottom, vibrancy: 0.5),
                       DockRGBA(r: 0.3, g: 0.1, b: 0.2, a: 0.35))
    }

    /// Raising contrast pushes a channel away from mid-grey — the sweep's "the twelve presets are
    /// almost indistinguishable" finding — and the alpha is left to vibrancy alone.
    func testContrastPushesChannelsAwayFromMidGreyAndLeavesAlphaToVibrancy() {
        let tint = DockRGBA(r: 0.2, g: 0.5, b: 0.8, a: 0.7)
        func overlay(_ contrast: CGFloat) -> DockRGBA? {
            DockThemeStyle.deepOcean.plateOverlay(baseTint: tint, vibrancy: 1, contrast: contrast)
        }
        XCTAssertEqual(overlay(2), DockRGBA(r: 0, g: 0.5, b: 1, a: 0.7))
        XCTAssertEqual(overlay(0.5)?.r ?? -1, 0.35, accuracy: 0.000_001)
        XCTAssertEqual(overlay(0.5)?.g ?? -1, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(overlay(0.5)?.b ?? -1, 0.65, accuracy: 0.000_001)
        XCTAssertEqual(overlay(1.5)?.a, 0.7, "contrast must not touch the alpha")
        XCTAssertEqual(DockThemeStyle.deepOcean.plateOverlay(baseTint: tint, vibrancy: 0.5)?.a,
                       0.35, "vibrancy is the alpha's only knob")
    }

    // MARK: - Phase 33f: Dock Shapes & Edge Presets Tests

    func testDockShapeTokensGeometryAndTokens() {
        XCTAssertEqual(DockShapeToken.allCases.count, 4)
        XCTAssertEqual(DockShapeToken.beveledWell.cornerRadius(for: 54), 16)
        XCTAssertEqual(DockShapeToken.liquidSquircle.cornerRadius(for: 54), 20)
        XCTAssertEqual(DockShapeToken.pill.cornerRadius(for: 54), 27)
        XCTAssertEqual(DockShapeToken.segmentedTile.cornerRadius(for: 54), 12)

        XCTAssertTrue(DockShapeToken.beveledWell.hasDebossedBevel)
        XCTAssertFalse(DockShapeToken.liquidSquircle.hasDebossedBevel)
        XCTAssertFalse(DockShapeToken.pill.hasDebossedBevel)
        XCTAssertFalse(DockShapeToken.segmentedTile.hasDebossedBevel)

        XCTAssertTrue(DockShapeToken.segmentedTile.isSegmented)
        XCTAssertFalse(DockShapeToken.beveledWell.isSegmented)

        XCTAssertEqual(DockShapeToken.beveledWell.innerShadowRadius, 3.0)
        XCTAssertEqual(DockShapeToken.liquidSquircle.innerShadowRadius, 1.5)
        XCTAssertEqual(DockShapeToken.pill.innerShadowRadius, 0.0)
        XCTAssertEqual(DockShapeToken.segmentedTile.innerShadowRadius, 1.0)

        XCTAssertGreaterThan(DockShapeToken.beveledWell.rimHighlightOpacity, DockShapeToken.pill.rimHighlightOpacity)
    }

    func testDockEdgePresetsPlacementAndGap() {
        XCTAssertEqual(DockEdgePreset.allCases.count, 4)
        XCTAssertEqual(DockEdgePreset.bottomFloating.placement, .bottom)
        XCTAssertEqual(DockEdgePreset.bottomEdgeAnchored.placement, .bottom)
        XCTAssertEqual(DockEdgePreset.sideVerticalRail.placement, .left)

        XCTAssertTrue(DockEdgePreset.bottomFloating.isFloating)
        XCTAssertFalse(DockEdgePreset.bottomEdgeAnchored.isFloating)
        XCTAssertTrue(DockEdgePreset.topNotchCompanion.isFloating)
        XCTAssertTrue(DockEdgePreset.sideVerticalRail.isFloating)

        XCTAssertEqual(DockEdgePreset.bottomFloating.defaultBottomGap, 12.0)
        XCTAssertEqual(DockEdgePreset.bottomEdgeAnchored.defaultBottomGap, 0.0)
        XCTAssertEqual(DockEdgePreset.topNotchCompanion.defaultBottomGap, 0.0)
        XCTAssertEqual(DockEdgePreset.sideVerticalRail.defaultBottomGap, 12.0)

        XCTAssertTrue(DockEdgePreset.topNotchCompanion.isNotchCompanion)
        XCTAssertFalse(DockEdgePreset.bottomFloating.isNotchCompanion)
    }

    func testDockCompanionAutoHidingPolicy() {
        XCTAssertTrue(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: true))
        XCTAssertFalse(NotchDockCompanionPolicy.shouldHideDockCapsule(notchExpanded: false))
    }
}

