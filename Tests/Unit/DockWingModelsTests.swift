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

    func testWingLadderStepsDownPerSideWithoutPooling() {
        let config = DockWingsConfiguration(
            left: DockWingSlotConfig(preset: .spotify, size: .large),     // 248
            right: DockWingSlotConfig(preset: .telemetry, size: .large),  // 240
            gap: 10
        )
        // A starved right side degrades on its own; the roomy left side keeps `.large` (never pooled).
        let perSide = DockWingLadder.resolve(config: config, availableLeft: 450, availableRight: 200)
        XCTAssertEqual(perSide.left, .size(.large))
        XCTAssertEqual(perSide.right, .size(.medium))

        // Under `.small` there is still a rung: the icon pillar, not an instant vanish.
        let pillow = DockWingLadder.resolve(config: config, availableLeft: 100, availableRight: 100)
        XCTAssertEqual(pillow.left, .iconPillar)
        XCTAssertEqual(pillow.right, .iconPillar)
        XCTAssertEqual(DockWingLadder.width(of: .iconPillar, preset: .spotify, scale: 1), 52, accuracy: 0.01)

        // Only below the pillar width does a wing go hidden.
        let gone = DockWingLadder.resolve(config: config, availableLeft: 40, availableRight: 10)
        XCTAssertEqual(gone.left, .hidden)
        XCTAssertEqual(gone.right, .hidden)
        XCTAssertFalse(gone.left.isVisible)

        // An empty slot owns no rung at all.
        let empty = DockWingLadder.resolve(
            config: DockWingsConfiguration(left: .init(preset: .none, size: .large),
                                           right: .init(preset: .none, size: .large), gap: 10),
            availableLeft: 900, availableRight: 900)
        XCTAssertEqual(empty.left, .hidden)
        XCTAssertEqual(empty.right, .hidden)
    }

    func testWingPanelFramesTakeTheIconPillarStepBeforeHidingOnLaptopWidths() throws {
        let metrics = PanelLayoutMetrics.tungstenEdge
        let pad = metrics.shadowPadding
        let scale = max(0.5, metrics.panelHeight / IslandChrome.nativeBarHeight)
        // 12 window chips: the bar itself is wide, so the flanks are what run out of room.
        let chipSpan: CGFloat = 12 * 38 + 16

        for screenWidth: CGFloat in [1440, 1512] {
            let screen = PanelScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: screenWidth, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: screenWidth, height: 875),
                safeAreaTop: 0)
            // Dock sits near the left edge: 58 pt of left flank (pillar, not full wing), roomy right flank.
            let plate = CGRect(x: 80, y: 2, width: chipSpan, height: metrics.panelHeight)
            let dockFrame = plate.insetBy(dx: -pad, dy: -pad)
            let config = DockWingsConfiguration(
                left: DockWingSlotConfig(preset: .spotify, size: .large),
                right: DockWingSlotConfig(preset: .telemetry, size: .large),
                gap: 10)

            let layout = PanelGeometry.wingPanelFrames(
                dockFrame: dockFrame, capsuleFrame: .zero, config: config,
                stripPlacement: .bottom, drawerPlacement: .right, controlCentreTrailing: false,
                on: screen, metrics: metrics)

            XCTAssertEqual(layout.leftStep, .iconPillar, "width \(screenWidth)")
            XCTAssertEqual(layout.rightStep, .size(.large), "width \(screenWidth): right keeps its own budget")
            let leftPlate = try XCTUnwrap(layout.leftFrame).insetBy(dx: pad, dy: pad)
            XCTAssertEqual(leftPlate.width,
                           DockWingLadder.nativeIconPillarWidth * scale, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(leftPlate.minX, screen.frame.minX + 12)
            XCTAssertLessThanOrEqual(leftPlate.maxX, plate.minX - 10 + 0.01)
        }
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
        XCTAssertEqual(store.dockWings, .recommendedDefault)
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

    func testLivecheckWingsAcrossAllLayoutModesAndPlacements() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1710, height: 1112),
            visibleFrame: CGRect(x: 0, y: 0, width: 1710, height: 1075),
            safeAreaTop: 37
        )
        let metrics = PanelLayoutMetrics.tungstenEdge
        let pad = metrics.shadowPadding
        let config = DockWingsConfiguration.recommendedDefault

        for placement in StripPlacement.allCases {
            for mode in BarLayoutMode.allCases {
                let islands = BarSection.islands(for: mode, order: BarSection.defaultOrder)
                let appsSlot = islands.firstIndex { $0.contains(.apps) } ?? 0
                let frames: [CGRect] = (0..<mode.slotCount).map { slot in
                    let len: CGFloat = (slot == appsSlot) ? 260 : 140
                    return PanelGeometry.stripTargetFrame(
                        slot: slot,
                        contentLength: len,
                        mode: mode,
                        stripPlacement: placement,
                        on: screen,
                        metrics: metrics,
                        gap: 10,
                        margin: 12,
                        widgetLayout: .default,
                        wingConfig: config
                    )
                }
                let appsFrame = frames[appsSlot]
                let splitUnion = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
                let anchor = mode.isSplit ? splitUnion : appsFrame
                let capsule = PanelGeometry.stripCapsuleTargetFrame(
                    forDock: appsFrame,
                    stripPlacement: placement,
                    on: screen,
                    drawerPlacement: .right,
                    metrics: metrics
                )
                let wingLayout = PanelGeometry.wingPanelFrames(
                    dockFrame: anchor,
                    capsuleFrame: capsule,
                    config: config,
                    stripPlacement: placement,
                    drawerPlacement: .right,
                    controlCentreTrailing: false,
                    on: screen,
                    metrics: metrics,
                    margin: 12,
                    isSplit: mode.isSplit
                )
                let lp = wingLayout.leftFrame?.insetBy(dx: pad, dy: pad)
                let rp = wingLayout.rightFrame?.insetBy(dx: pad, dy: pad)
                let anchorPlate = anchor.insetBy(dx: pad, dy: pad)
                let capPlate = capsule.insetBy(dx: pad, dy: pad)
                let lOverlapsMenuBar = lp.map { $0.maxY > screen.visibleFrame.maxY } ?? false
                let lOverlapsAnchor = lp?.intersects(anchorPlate) ?? false
                let rOverlapsAnchor = rp?.intersects(anchorPlate) ?? false
                let rOverlapsCap = rp?.intersects(capPlate) ?? false
                let lRailOverhang = lp.map { placement.isVertical ? abs($0.width - anchorPlate.width) : 0 } ?? 0
                let rRailOverhang = rp.map { placement.isVertical ? abs($0.width - anchorPlate.width) : 0 } ?? 0
                XCTAssertFalse(lOverlapsMenuBar)
                XCTAssertFalse(lOverlapsAnchor)
                XCTAssertFalse(rOverlapsAnchor)
                XCTAssertFalse(rOverlapsCap)
                if placement.isVertical {
                    XCTAssertNotNil(lp, "\(mode) should host top vertical wing cap on \(placement)")
                    XCTAssertNotNil(rp, "\(mode) should host bottom vertical wing cap on \(placement)")
                    XCTAssertEqual(lRailOverhang, 0, accuracy: 0.01, "Top wing width must match rail thickness")
                    XCTAssertEqual(rRailOverhang, 0, accuracy: 0.01, "Bottom wing width must match rail thickness")
                    if let lp { XCTAssertEqual(lp.minX, anchorPlate.minX, accuracy: 0.01) }
                    if let rp { XCTAssertEqual(rp.minX, anchorPlate.minX, accuracy: 0.01) }
                } else if mode == .centered {
                    XCTAssertNotNil(lp, "Centered mode should host left wing on \(placement)")
                    XCTAssertNotNil(rp, "Centered mode should host right wing on \(placement)")
                }
            }
        }
    }
}
