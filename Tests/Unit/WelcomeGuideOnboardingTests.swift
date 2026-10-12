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

    func testStepsRunPickLayoutThenDockSettings() {
        XCTAssertEqual(WelcomeGuideStep.first, .pickLayout)
        XCTAssertEqual(WelcomeGuideStep.pickLayout.next, .liveIsland)
        XCTAssertEqual(WelcomeGuideStep.liveIsland.next, .dockSettings)
        XCTAssertNil(WelcomeGuideStep.dockSettings.next)
        XCTAssertEqual(WelcomeGuideStep.dockSettings.previous, .liveIsland)
        XCTAssertEqual(WelcomeGuideStep.liveIsland.previous, .pickLayout)
        XCTAssertNil(WelcomeGuideStep.pickLayout.previous)
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

    func testPickerOffersEveryModeDrawnFromTheSolver() {
        for mode in BarLayoutMode.allCases {
            XCTAssertFalse(LayoutThumbnailModel.islands(for: mode).isEmpty, "\(mode) thumbnail has islands")
        }
        XCTAssertEqual(BarLayoutMode.allCases.count, 5)
    }
}
