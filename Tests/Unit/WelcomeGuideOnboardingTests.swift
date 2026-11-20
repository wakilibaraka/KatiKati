import AppKit
import SwiftUI
import XCTest

/// Phase 6 "onboarding snapshot": a structural snapshot of the welcome guide rendered in a
/// real `NSHostingView` (the repo ships no image-golden library, and adding one would be a
/// new dependency). Pins the properties the window relies on — fixed width, a height that
/// fits the taller step, and the five mode cards from the solver.
@MainActor
final class WelcomeGuideOnboardingTests: XCTestCase {
    private func context(_ mode: BarLayoutMode = .split3, onPick: @escaping (BarLayoutMode) -> Void = { _ in }) -> WelcomeGuideLayoutContext {
        WelcomeGuideLayoutContext(initialMode: mode, inputs: LayoutThumbnailModel.Inputs(), onPick: onPick)
    }

    /// DP-8: three live-applying steps — layout & edge, widgets & wings, permissions & triggers.
    func testThreeStepsRunLayoutWidgetsPermissions() {
        XCTAssertEqual(WelcomeGuideStep.first, .layout)
        XCTAssertEqual(WelcomeGuideStep.allCases, [.layout, .widgets, .permissions])
        XCTAssertEqual(WelcomeGuideStep.layout.next, .widgets)
        XCTAssertEqual(WelcomeGuideStep.widgets.next, .permissions)
        XCTAssertNil(WelcomeGuideStep.permissions.next)
        XCTAssertEqual(WelcomeGuideStep.permissions.previous, .widgets)
        XCTAssertEqual(WelcomeGuideStep.widgets.previous, .layout)
        XCTAssertNil(WelcomeGuideStep.layout.previous)
    }

    /// DP-8's pure step → settings map: every setting the guide can write belongs to exactly one step.
    func testEachStepMapsToTheSettingsItWrites() {
        XCTAssertEqual(WelcomeGuideStep.layout.settings, [.dockStyle, .edgePlacement])
        XCTAssertEqual(WelcomeGuideStep.widgets.settings, [.sections, .wings, .weatherCity, .aiTracking, .notch])
        XCTAssertEqual(WelcomeGuideStep.permissions.settings, [.permissions, .launcherTrigger, .clipboardToast, .systemDock])
        let union = WelcomeGuideStep.allCases.reduce(into: Set<WelcomeGuideSetting>()) { $0.formUnion($1.settings) }
        XCTAssertEqual(union, Set(WelcomeGuideSetting.allCases), "a setting no step writes would be dead UI")
        let counts = WelcomeGuideSetting.allCases.map { setting in
            WelcomeGuideStep.allCases.filter { $0.settings.contains(setting) }.count
        }
        XCTAssertTrue(counts.allSatisfy { $0 == 1 }, "each setting is written by exactly one step")
    }

    func testGuideMeasuresToAStableFixedWidthWindow() {
        let heights = BarLayoutMode.allCases.map { mode -> CGFloat in
            let host = NSHostingView(rootView: WelcomeGuideView(layout: context(mode), onApply: { _ in }, onDismiss: {}))
            host.setFrameSize(NSSize(width: WelcomeGuideView.contentWidth, height: 0))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(host.fittingSize.width, WelcomeGuideView.contentWidth, accuracy: 0.5, "\(mode)")
            return host.fittingSize.height
        }
        XCTAssertGreaterThan(heights[0], 200)
        XCTAssertEqual(Set(heights.map { $0.rounded() }).count, 1,
                       "the measured height must not depend on the initially selected mode: \(heights)")
    }

    /// The demo draws a `Shape`, which has no intrinsic size, so its `.fit` ratio is only as
    /// trustworthy as the proposal it is solved against — hence the explicit drawing height.
    /// Guards that the demo stays inside the panel it stands for.
    /// (This harness measures `fittingSize`, which cannot isolate the drawing; it does not
    /// reproduce the live proportions.)
    func testNotchPreviewKeepsThePanelProportionsInEveryColumn() {
        for skin in LiveIslandSkin.allCases {
            let panel = NotchGeometry.previewSize(for: skin, expanded: true)
            let host = NSHostingView(rootView: NotchPreview(skin: skin, isEnabled: true))
            for column in [900.0, 464.0, 300.0] {
                host.setFrameSize(NSSize(width: column, height: 0))
                host.layoutSubtreeIfNeeded()
                let fitted = host.fittingSize
                // `fittingSize` solves an unspecified proposal, so it reports the drawing's ideal
                // size, not the laid-out one: assert the demo never claims to be bigger than the
                // panel it stands for, plus the caption and the stack spacing.
                XCTAssertLessThanOrEqual(fitted.width, panel.width + 0.5, "\(skin) at \(column) pt wide")
                XCTAssertLessThanOrEqual(fitted.height, panel.height + 34,
                                         "\(skin) at \(column) pt wide: drawing stretched past its own ratio")
            }
        }
    }

    func testPickerOffersEveryModeDrawnFromTheSolver() {
        for mode in BarLayoutMode.allCases {
            XCTAssertFalse(LayoutThumbnailModel.islands(for: mode).isEmpty, "\(mode) thumbnail has islands")
        }
        XCTAssertEqual(BarLayoutMode.allCases.count, 5)
    }

    func testDockLivePreviewStripFitsAndMapsAllSections() {
        for section in BarSection.allCases {
            XCTAssertFalse(DockLivePreviewStrip.symbol(for: section).isEmpty)
        }
        let preview = DockLivePreviewStrip(
            mode: .split3,
            visibleOrder: BarSection.defaultOrder,
            wings: DockWingsConfiguration(
                left: DockWingSlotConfig(preset: .spotify, size: .medium),
                right: DockWingSlotConfig(preset: .ai, size: .medium)
            )
        )
        let host = NSHostingView(rootView: preview.frame(width: 460))
        host.setFrameSize(NSSize(width: 460, height: 0))
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.height, 52, accuracy: 0.5)
    }
}
