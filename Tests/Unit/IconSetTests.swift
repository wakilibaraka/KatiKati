import Metal
import XCTest

final class IconSetTests: XCTestCase {
    func testMissingOrUnknownValueFallsBackToSystem() {
        XCTAssertEqual(IconSet(storedValue: nil), .system)
        XCTAssertEqual(IconSet(storedValue: "neon"), .system)
        XCTAssertEqual(IconSet(storedValue: "modern"), .modern)
        XCTAssertEqual(IconSet(storedValue: "classic"), .classic)
    }

    func testClassicTrashSymbolFollowsFullness() {
        XCTAssertEqual(IconSet.classicTrashSymbol(isFull: false), "trash")
        XCTAssertEqual(IconSet.classicTrashSymbol(isFull: true), "trash.fill")
    }

    @MainActor
    func testStorePersistsIconSetIndependentlyOfTheme() {
        let defaults = TestDefaults.make("IconSetTests", for: self)
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.iconSet, .system)
        store.setThemeMaterial(.deepOcean)
        store.setIconSet(.classic)
        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.iconSet, .classic)
        XCTAssertEqual(reloaded.themeMaterial, .deepOcean)
        XCTAssertEqual(defaults.string(forKey: "com.katikati.iconSet"), "classic")
    }

    // MARK: - IS-1.2 Icon Studio Core & Persistence Tests

    func testIconStudioStateCodableAndPersistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IconStudioTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("nested/icon-studio.json")

        XCTAssertEqual(IconStudioPersistence.load(from: fileURL), IconStudioState())
        XCTAssertEqual(IconStudioPersistence.decode(Data("not-json".utf8)), IconStudioState())
        XCTAssertEqual(IconStudioPersistence.decode(Data("{\"schemaVersion\":999}".utf8)), IconStudioState())

        var state = IconStudioState()
        let look = IconLook(
            artwork: .localFile(relativePath: "custom/slack.png"),
            recolor: IconRecolorSpec(mode: .duotone, primaryHex: "#FFAA00", secondaryHex: "#112233", intensity: 1.5),
            shader: IconShaderSpec(preset: .gold, strength: 0.8, trigger: .hover),
            decorations: [IconDecoration(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, kind: .stringLights, anchorX: 0.2, anchorY: 1.4, spacing: -0.3, scale: 2.5)],
            badgeEffect: IconBadgeEffectSpec(kind: .fire, minUnreadCount: 0),
            live: .default(for: .claude)
        )
        XCTAssertEqual(look.recolor.intensity, 1.0)
        XCTAssertEqual(look.decorations[0].anchorY, 1.0)
        XCTAssertEqual(look.decorations[0].spacing, 0.0)
        XCTAssertEqual(look.decorations[0].scale, 1.8)
        XCTAssertEqual(look.badgeEffect.minUnreadCount, 1)

        state.setLook(look, for: "com.tinyspeck.slackmacgap")
        let fixedDate = Date(timeIntervalSince1970: 1_764_000_000)
        state.savePreset(name: "  Warm Gold  ", from: look, id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, now: fixedDate)

        try IconStudioPersistence.save(state, to: fileURL)
        let loaded = IconStudioPersistence.load(from: fileURL)
        XCTAssertEqual(loaded, state)
        XCTAssertNil(loaded.savedPresets.first?.look.live)
        XCTAssertEqual(loaded.savedPresets.first?.name, "Warm Gold")
    }

    func testUnreadBadgeParserAndBadgeEffectThresholds() {
        XCTAssertEqual(IconUnreadBadgeParser.parseCount(nil), 0)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("   "), 0)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("0"), 0)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("3"), 3)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("99+"), 99)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("1,234"), 1234)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("•"), 1)
        XCTAssertEqual(IconUnreadBadgeParser.parseCount("!"), 1)

        let fireAtFive = IconBadgeEffectSpec(kind: .fire, minUnreadCount: 5)
        XCTAssertFalse(fireAtFive.isTriggered(byBadgeText: "4"))
        XCTAssertFalse(fireAtFive.isTriggered(byBadgeText: "•"))
        XCTAssertTrue(fireAtFive.isTriggered(byBadgeText: "5"))
        XCTAssertTrue(fireAtFive.isTriggered(byBadgeText: "99+"))

        let disabled = IconBadgeEffectSpec(kind: .none, minUnreadCount: 1)
        XCTAssertFalse(disabled.isTriggered(byBadgeText: "10"))
    }

    func testShaderZeroIdleCPUAndReduceMotionPolicy() {
        let foilHover = IconShaderSpec(preset: .holographicFoil, strength: 0.7, trigger: .hover)
        XCTAssertFalse(foilHover.shouldAnimate(isHovered: false, isLiveActive: true, reduceMotion: false))
        XCTAssertTrue(foilHover.shouldAnimate(isHovered: true, isLiveActive: false, reduceMotion: false))
        XCTAssertFalse(foilHover.shouldAnimate(isHovered: true, isLiveActive: true, reduceMotion: true))

        let crtActive = IconShaderSpec(preset: .crt, strength: 0.6, trigger: .active)
        XCTAssertFalse(crtActive.shouldAnimate(isHovered: true, isLiveActive: false, reduceMotion: false))
        XCTAssertTrue(crtActive.shouldAnimate(isHovered: false, isLiveActive: true, reduceMotion: false))

        let offShader = IconShaderSpec(preset: .vhs, strength: 1.0, trigger: .off)
        XCTAssertFalse(offShader.shouldAnimate(isHovered: true, isLiveActive: true, reduceMotion: false))

        let staticGold = IconShaderSpec(preset: .gold, strength: 1.0, trigger: .hover)
        XCTAssertTrue(staticGold.preset.requiresStaticBake)
        XCTAssertFalse(staticGold.shouldAnimate(isHovered: true, isLiveActive: true, reduceMotion: false))
    }

    func testIconLookCanonicalLayerOrderAndOriginalDetection() {
        let original = IconLook()
        XCTAssertTrue(original.isOriginal)
        XCTAssertEqual(original.activeLayers, [.baseArtwork])

        let full = IconLook(
            artwork: .macOSIcons(id: "abc", cachedRelativePath: "mi/abc.png"),
            recolor: IconRecolorSpec(mode: .tint, primaryHex: "#00FFAA", intensity: 0.5),
            shader: IconShaderSpec(preset: .liquidGlass, strength: 0.9, trigger: .hover),
            decorations: [IconDecoration(kind: .pine)],
            badgeEffect: IconBadgeEffectSpec(kind: .glint, minUnreadCount: 2),
            live: .default(for: .spotify)
        )
        XCTAssertFalse(full.isOriginal)
        XCTAssertEqual(full.activeLayers, [.baseArtwork, .recolor, .shader, .liveData, .decorations, .badgeEffect])
    }

    func testStaticBakeFingerprintDeterminismAndIsolation() {
        let base = IconLook(
            artwork: .localFile(relativePath: "a.png"),
            recolor: IconRecolorSpec(mode: .tint, primaryHex: "#123456", intensity: 0.4),
            shader: IconShaderSpec(preset: .woodInlay, strength: 0.6, trigger: .hover)
        )
        let fp1 = base.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128)
        let fp2 = base.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128)
        XCTAssertEqual(fp1.count, 16)
        XCTAssertEqual(fp1, fp2)

        var dynamicChangesOnly = base
        dynamicChangesOnly.decorations = [IconDecoration(kind: .snowGlobe)]
        dynamicChangesOnly.badgeEffect = IconBadgeEffectSpec(kind: .waxSeal, minUnreadCount: 3)
        dynamicChangesOnly.live = .default(for: .safari)
        XCTAssertEqual(dynamicChangesOnly.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128), fp1)

        var animatedOnly = IconLook(artwork: base.artwork, recolor: base.recolor, shader: IconShaderSpec(preset: .holographicFoil, strength: 0.9, trigger: .hover))
        XCTAssertEqual(animatedOnly.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128),
                       IconLook(artwork: base.artwork, recolor: base.recolor).staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128))

        animatedOnly.recolor.intensity = 0.8
        XCTAssertNotEqual(animatedOnly.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 128), fp1)
        XCTAssertNotEqual(base.staticBakeFingerprint(bundleID: "com.apple.Safari", pixelSize: 256), fp1)
    }

    func testSaveAndApplyLookPresetPreservesTargetLiveConfigAndRestorePrunes() {
        var state = IconStudioState()
        let spotifyLive = LiveIconConfig.default(for: .spotify)
        let existingSpotify = IconLook(artwork: .localFile(relativePath: "sp.png"), live: spotifyLive)
        state.setLook(existingSpotify, for: "com.spotify.client")

        let sourceLook = IconLook(
            recolor: IconRecolorSpec(mode: .monochrome, primaryHex: "#FFFFFF", intensity: 0.5),
            shader: IconShaderSpec(preset: .brushedMetal, strength: 0.7, trigger: .hover),
            live: .default(for: .claude)
        )
        let preset = state.savePreset(name: "Brushed", from: sourceLook)
        state.applyPreset(preset, to: "com.spotify.client")

        let updated = state.looksByBundleID["com.spotify.client"]
        XCTAssertEqual(updated?.live, spotifyLive)
        XCTAssertEqual(updated?.artwork, .localFile(relativePath: "sp.png"))
        XCTAssertEqual(updated?.shader.preset, .brushedMetal)

        state.restoreOriginal(for: "com.spotify.client")
        XCTAssertNil(state.looksByBundleID["com.spotify.client"])

        state.setLook(IconLook(), for: "com.apple.finder")
        XCTAssertNil(state.looksByBundleID["com.apple.finder"])
        state.deletePreset(id: preset.id)
        XCTAssertTrue(state.savedPresets.isEmpty)
    }

    func testBadgeEligibleBundleIDsAndDefaultOptInProbesOff() {
        for kind in LiveIconKind.allCases {
            let cfg = LiveIconConfig.default(for: kind)
            XCTAssertFalse(cfg.optInActivityProbe, "\(kind.rawValue) must default optInActivityProbe to false")
        }
        var state = IconStudioState()
        state.setLook(IconLook(shader: IconShaderSpec(preset: .gloss)), for: "com.apple.Safari")
        state.setLook(IconLook(badgeEffect: IconBadgeEffectSpec(kind: .sunlight, minUnreadCount: 2)), for: "com.tinyspeck.slackmacgap")
        state.setLook(IconLook(live: .default(for: .mail)), for: "com.apple.mail")
        state.setLook(IconLook(live: .default(for: .claude)), for: "com.anthropic.claudefordesktop")

        XCTAssertEqual(state.badgeEligibleBundleIDs, ["com.tinyspeck.slackmacgap", "com.apple.mail"])
    }

    func testIconBakeActorProducesAndCachesDeterministicPNG() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("IconBakeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let baker = IconBakeActor(cacheDir: dir)
        let img = NSImage(size: NSSize(width: 32, height: 32))
        img.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        img.unlockFocus()
        guard let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff),
              let srcPNG = bmp.representation(using: .png, properties: [:]) else {
            XCTFail("Failed to create test PNG"); return
        }
        let fp = "testfp0123456789"
        let out = await baker.bakeIfNeeded(
            fingerprint: fp,
            sourceImageData: srcPNG,
            recolor: IconRecolorSpec(mode: .tint, primaryHex: "#FF5500", intensity: 0.6),
            shader: IconShaderSpec(preset: .gold, strength: 0.8),
            pixelSize: 64
        )
        XCTAssertNotNil(out)
        XCTAssertTrue(FileManager.default.fileExists(atPath: baker.cacheFileURL(fingerprint: fp).path))
        let hit = await baker.bakeIfNeeded(fingerprint: fp, sourceImageData: nil, recolor: .init(), shader: .init(), pixelSize: 64)
        XCTAssertEqual(out, hit)
    }

    @MainActor
    func testIconShaderEngineCompilesRuntimeMSLLibrary() {
        XCTAssertEqual(IconShaderEngine.presetIndex(for: .holographicFoil), 0)
        XCTAssertEqual(IconShaderEngine.presetIndex(for: .vhs), 1)
        XCTAssertEqual(IconShaderEngine.presetIndex(for: .crt), 2)
        XCTAssertEqual(IconShaderEngine.presetIndex(for: .lavaLamp), 3)
        XCTAssertEqual(IconShaderEngine.presetIndex(for: .neonSign), 4)
        XCTAssertNil(IconShaderEngine.presetIndex(for: .gold))
        if MTLCreateSystemDefaultDevice() != nil {
            XCTAssertNotNil(IconShaderEngine.shared)
        }
    }

    func testLiveIconMetricsVinylAccumulatorAndCodexRateLimits() {
        XCTAssertNil(LiveIconMetrics.usageFillFraction(usedPercent: 40, mode: .none))
        XCTAssertEqual(LiveIconMetrics.usageFillFraction(usedPercent: 52, mode: .used) ?? -1, 0.52, accuracy: 0.001)
        XCTAssertEqual(LiveIconMetrics.usageFillFraction(usedPercent: 52, mode: .remaining) ?? -1, 0.48, accuracy: 0.001)
        XCTAssertEqual(LiveIconMetrics.formattedPercentage(0.654), "65%")

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LiveIconMetrics.weeklyResetFraction(now: now, resetsAt: now.addingTimeInterval(3.5 * 86_400)) ?? -1, 0.5, accuracy: 0.01)

        var vinyl = VinylAngleAccumulator()
        _ = vinyl.advance(to: now, isPlaying: true, degreesPerSecond: 90)
        let rotated = vinyl.advance(to: now.addingTimeInterval(1.0), isPlaying: true, degreesPerSecond: 90)
        XCTAssertEqual(rotated, 90.0, accuracy: 0.01)
        let paused = vinyl.advance(to: now.addingTimeInterval(2.0), isPlaying: false, degreesPerSecond: 90)
        XCTAssertEqual(paused, 90.0, accuracy: 0.01)
        let stillPaused = vinyl.advance(to: now.addingTimeInterval(3.0), isPlaying: false, degreesPerSecond: 90)
        XCTAssertEqual(stillPaused, 90.0, accuracy: 0.01)

        XCTAssertEqual(CursorBudgetEstimator.estimatedUsedPercent(todayCostUSD: 2.5, dailyBudgetUSD: 5.0), 50.0, accuracy: 0.01)

        let rl1 = AgentCodexParser.parseRateLimit(from: #"{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary_used_percent":12,"secondary_used_percent":38}}}"#)
        XCTAssertEqual(rl1?.sessionPercent, 12)
        XCTAssertEqual(rl1?.weeklyPercent, 38)
        let rl2 = AgentCodexParser.parseRateLimit(from: #"{"rate_limits":{"primary":{"used_percent":61}}}"#)
        XCTAssertEqual(rl2?.sessionPercent, 61)
    }
}
