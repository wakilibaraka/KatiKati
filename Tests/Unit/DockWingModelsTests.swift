import XCTest
@testable import KatiKati

final class DockWingModelsTests: XCTestCase {
    func testDefaultConfigurationHasNoActiveWings() {
        let config = DockWingsConfiguration.default
        XCTAssertFalse(config.hasAnyActiveWing)
        XCTAssertEqual(config.left.preset, .none)
        XCTAssertEqual(config.right.preset, .none)
        XCTAssertEqual(config.gap, DockWingsConfiguration.defaultGap)
    }

    func testConfigurationCodableRoundTripAndGapClamp() {
        let config = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .spotify, size: .large),
            right: DockWingSlotConfig(preset: .telemetry, size: .medium),
            gap: 99
        )
        XCTAssertEqual(config.gap, DockWingsConfiguration.maxGap)
        let data = config.encoded()
        XCTAssertNotNil(data)
        let decoded = DockWingsConfiguration.decode(data)
        XCTAssertEqual(decoded, config)
    }

    func testDecodeRejectsGarbageAndClampsHandEditedGap() throws {
        XCTAssertNil(DockWingsConfiguration.decode(Data("not-json".utf8)))
        let raw = """
        {"left":{"preset":"vpn","size":"small"},"right":{"preset":"friends","size":"large"},"gap":-12}
        """.data(using: .utf8)!
        let decoded = try XCTUnwrap(DockWingsConfiguration.decode(raw))
        XCTAssertEqual(decoded.left.preset, .vpn)
        XCTAssertEqual(decoded.right.preset, .friends)
        XCTAssertEqual(decoded.gap, DockWingsConfiguration.minGap)
    }

    func testSlotAssignmentPreservesOppositeWing() {
        let step1 = DockWingsConfiguration.default
            .assigning(.spotify, size: .medium, to: .leftWing)
        let step2 = step1
            .assigning(.controlCenter, size: .large, to: .rightWing)
        XCTAssertEqual(step2.left, DockWingSlotConfig(preset: .spotify, size: .medium))
        XCTAssertEqual(step2.right, DockWingSlotConfig(preset: .controlCenter, size: .large))
        XCTAssertTrue(step2.hasAnyActiveWing)

        let cleared = step2.assigning(.none, to: .leftWing)
        XCTAssertEqual(cleared.left.preset, .none)
        XCTAssertEqual(cleared.right.preset, .controlCenter)
        XCTAssertTrue(cleared.hasAnyActiveWing)
    }

    func testAutoDegradeStepsDownWidestWingFirst() {
        let config = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .spotify, size: .large),     // 248
            right: DockWingSlotConfig(preset: .telemetry, size: .large),  // 240
            gap: 10
        )
        // Budget 450 < 248 + 240: steps down left (248 -> 188), total = 188 + 240 = 428 <= 450
        let fit450 = DockWingLayoutPlanner.resolveSizes(config: config, availableWingBudget: 450)
        XCTAssertEqual(fit450.left, .medium)
        XCTAssertEqual(fit450.right, .large)

        // Tight budget 240 forces both down to .small
        let fit240 = DockWingLayoutPlanner.resolveSizes(config: config, availableWingBudget: 240)
        XCTAssertEqual(fit240.left, .small)
        XCTAssertEqual(fit240.right, .small)
    }

    func testVpnRateFormatting() {
        XCTAssertEqual(DockVpnRateFormat.formatted(-5), "0 B/s")
        XCTAssertEqual(DockVpnRateFormat.formatted(512), "512 B/s")
        XCTAssertEqual(DockVpnRateFormat.formatted(19_000), "19.0 KB/s")
        XCTAssertEqual(DockVpnRateFormat.formatted(193_000), "193.0 KB/s")
        XCTAssertEqual(DockVpnRateFormat.formatted(2_500_000), "2.5 MB/s")
    }

    func testFriendLaunchURLs() {
        XCTAssertEqual(DockFriendAppKind.messages.launchURL(handle: "+15551234")?.scheme, "sms")
        XCTAssertEqual(DockFriendAppKind.facetime.launchURL(handle: "alex@example.com")?.scheme, "facetime")
        XCTAssertNil(DockFriendAppKind.messages.launchURL(handle: "   "))
    }

    func testWingPanelFramesClearDockAndCapsuleAndStayInScreenBounds() throws {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaTop: 0
        )
        let metrics = PanelLayoutMetrics.tungstenEdge
        let pad = metrics.shadowPadding
        let dockFrame = CGRect(x: 500 - pad, y: 2 - pad, width: 440 + 2 * pad, height: metrics.windowHeight)
        let capsuleFrame = PanelGeometry.capsuleTargetFrame(
            forDock: dockFrame, on: screen, placement: .right, metrics: metrics, controlCentreTrailing: false
        )
        let config = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .spotify, size: .medium),
            right: DockWingSlotConfig(preset: .vpn, size: .medium),
            gap: 10
        )

        let layout = PanelGeometry.wingPanelFrames(
            dockFrame: dockFrame,
            capsuleFrame: capsuleFrame,
            config: config,
            stripPlacement: .bottom,
            drawerPlacement: .right,
            controlCentreTrailing: false,
            on: screen,
            metrics: metrics
        )

        let leftPlate = try XCTUnwrap(layout.leftFrame).insetBy(dx: pad, dy: pad)
        let rightPlate = try XCTUnwrap(layout.rightFrame).insetBy(dx: pad, dy: pad)
        let dockPlate = dockFrame.insetBy(dx: pad, dy: pad)
        let capsulePlate = capsuleFrame.insetBy(dx: pad, dy: pad)

        XCTAssertEqual(leftPlate.maxX, dockPlate.minX - 10, accuracy: 0.01)
        XCTAssertEqual(rightPlate.minX, capsulePlate.maxX + 10, accuracy: 0.01)
        XCTAssertFalse(leftPlate.intersects(dockPlate))
        XCTAssertFalse(rightPlate.intersects(capsulePlate))
        XCTAssertGreaterThanOrEqual(leftPlate.minX, screen.frame.minX + 12)
        XCTAssertLessThanOrEqual(rightPlate.maxX, screen.frame.maxX - 12)
    }

    func testWingPanelFramesStillClearTrailingCapsuleWhenControlCentreTrailingIsTrue() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1087),
            safeAreaTop: 0
        )
        let dock = CGRect(x: 246, y: 0, width: 1163, height: 86)
        let capsule = CGRect(x: 1377, y: 0, width: 86, height: 86)
        let config = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .spotify, size: .medium),
            right: DockWingSlotConfig(preset: .friends, size: .medium),
            gap: 10
        )

        let layout = PanelGeometry.wingPanelFrames(
            dockFrame: dock,
            capsuleFrame: capsule,
            config: config,
            stripPlacement: .bottom,
            drawerPlacement: .right,
            controlCentreTrailing: true,
            on: screen
        )

        let pad = PanelLayoutMetrics.tungstenEdge.shadowPadding
        let rightPlate = tryUnwrap(layout.rightFrame).insetBy(dx: pad, dy: pad)
        let capsulePlate = capsule.insetBy(dx: pad, dy: pad)
        XCTAssertGreaterThanOrEqual(rightPlate.minX, capsulePlate.maxX + 9)
        XCTAssertFalse(rightPlate.intersects(capsulePlate))
    }

    func testFloatingWidgetStackAnchorsRightFlankAndDodgesOpenPopup() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1087),
            safeAreaTop: 0
        )
        let dock = CGRect(x: 246, y: 0, width: 1163, height: 86)
        let rightWing = CGRect(x: 1431, y: 0, width: 190, height: 86)
        let size = CGSize(width: 280, height: 140)
        let pad = PanelLayoutMetrics.tungstenEdge.shadowPadding

        let defaultFrame = PanelGeometry.floatingWidgetStackFrame(
            size: size,
            dockFrame: dock,
            customOrigin: nil,
            on: screen,
            rightFlankFrame: rightWing,
            avoidRect: nil
        )
        let defaultPlate = defaultFrame.insetBy(dx: pad, dy: pad)
        let rightWingPlate = rightWing.insetBy(dx: pad, dy: pad)
        XCTAssertEqual(defaultPlate.maxX, rightWingPlate.maxX, accuracy: 0.5)

        let centerPopup = CGRect(x: 560, y: 80, width: 520, height: 220)
        let customCollision = PanelGeometry.floatingWidgetStackFrame(
            size: size,
            dockFrame: dock,
            customOrigin: CGPoint(x: 680, y: 90),
            on: screen,
            rightFlankFrame: rightWing,
            avoidRect: centerPopup
        )
        let dodgedPlate = customCollision.insetBy(dx: pad, dy: pad)
        let popupPlate = centerPopup.insetBy(dx: pad, dy: pad)
        XCTAssertFalse(dodgedPlate.intersects(popupPlate))
    }

    private func tryUnwrap(_ rect: CGRect?) -> CGRect {
        rect ?? .zero
    }

    @MainActor
    func testAppSettingsStorePersistsDockWingsAndOptInFlags() {
        let suiteName = "com.katikati.tests.dockWings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertFalse(store.dockWings.hasAnyActiveWing)
        XCTAssertFalse(store.dockWingGeoIPEnabled)
        XCTAssertFalse(store.dockWingSpotifyOAuthEnabled)
        XCTAssertFalse(store.dockWingTelemetryIOHIDEnabled)
        XCTAssertFalse(store.dockWingFriendsContactsEnabled)

        store.setDockWing(.spotify, size: .large, placement: .leftWing)
        store.setDockWing(.friends, size: .small, placement: .rightWing)
        store.setDockWingGeoIPEnabled(true)

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.dockWings.left, DockWingSlotConfig(preset: .spotify, size: .large))
        XCTAssertEqual(reloaded.dockWings.right, DockWingSlotConfig(preset: .friends, size: .small))
        XCTAssertTrue(reloaded.dockWingGeoIPEnabled)
    }

    func testAIPresetDimensionsAndPerDisplayUUIDResolution() throws {
        XCTAssertEqual(DockWingDimensions.nativeWidth(for: .ai, size: .small), 112)
        XCTAssertEqual(DockWingDimensions.nativeWidth(for: .ai, size: .medium), 184)
        XCTAssertEqual(DockWingDimensions.nativeWidth(for: .ai, size: .large), 244)
        XCTAssertEqual(DockWidgetPresetType.ai.symbolName, "sparkles")

        let base = DockWingsConfiguration.default
            .assigning(.spotify, size: .medium, to: .leftWing)
            .assigning(.ai, size: .large, to: .rightWing, forDisplay: "UUID-STUDIO-DISPLAY")
            .assigning(.vpn, size: .small, to: .leftWing, forDisplay: "42")

        let byUUID = base.resolved(displayUUID: "UUID-STUDIO-DISPLAY", displayID: "42")
        XCTAssertEqual(byUUID.right, DockWingSlotConfig(preset: .ai, size: .large))
        XCTAssertEqual(byUUID.left, DockWingSlotConfig(preset: .spotify, size: .medium))

        let byLegacyID = base.resolved(displayUUID: "UUID-UNKNOWN", displayID: "42")
        XCTAssertEqual(byLegacyID.left, DockWingSlotConfig(preset: .vpn, size: .small))

        let fallbackGlobal = base.resolved(displayUUID: "UUID-OTHER", displayID: "99")
        XCTAssertEqual(fallbackGlobal.left, DockWingSlotConfig(preset: .spotify, size: .medium))

        let roundTrip = try XCTUnwrap(DockWingsConfiguration.decode(base.encoded()))
        XCTAssertEqual(roundTrip, base)
    }

    func testRecommendedDefaultAndTelemetryWingMetrics() {
        let rec = DockWingsConfiguration.recommendedDefault
        XCTAssertEqual(rec.left.preset, .telemetry)
        XCTAssertEqual(rec.right.preset, .ram)

        XCTAssertEqual(DockWidgetPresetType.ram.symbolName, "memorychip")
        XCTAssertEqual(DockWidgetPresetType.network.symbolName, "network")
        XCTAssertEqual(DockWidgetPresetType.disk.symbolName, "internaldrive")
        XCTAssertEqual(DockWidgetPresetType.battery.symbolName, "battery.75percent")

        let low = MemoryUsage(used: 8 * 1_073_741_824, total: 16 * 1_073_741_824)
        XCTAssertEqual(low.pressureLevel, .normal)
        XCTAssertEqual(low.pressureLabel, "Normal")
        XCTAssertEqual(low.formattedGigabytesPair, "8.0 / 16 GB")

        let high = MemoryUsage(used: 15 * 1_073_741_824, total: 16 * 1_073_741_824)
        XCTAssertEqual(high.pressureLevel, .critical)
        XCTAssertEqual(high.pressureLabel, "Crit")
    }
}
