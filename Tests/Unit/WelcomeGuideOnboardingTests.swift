import AppKit
import SwiftUI
import XCTest

/// Phase 6 "onboarding snapshot", re-cut for OB-1's six acts.
///
/// The repo ships no image-golden library (adding one would be a new dependency), so this pins the
/// structural properties the window actually relies on: a fixed size, one owner per setting, and a
/// reveal act that writes nothing at all.
@MainActor
final class WelcomeGuideOnboardingTests: XCTestCase {
    private func context(_ mode: BarLayoutMode = .split3) -> WelcomeGuideLayoutContext {
        WelcomeGuideLayoutContext(initialMode: mode, inputs: LayoutThumbnailModel.Inputs())
    }

    /// VoiceOver reads the theme's *name*, not its storage token. The bug this pins: the four Feel
    /// swatches were labelled `Text(verbatim: style.token)`, so every locale heard "obsidianDark".
    /// The names are the catalogue's existing theme keys, via `DockThemeStyle.menuTitle`.
    func testThemeSwatchesAnnounceTheLocalizedNameNotTheToken() {
        let choices = WelcomeGuideView.themeChoices
        XCTAssertEqual(choices.count, 4, "one row of swatches")
        let names = choices.map(\.menuTitle)
        for (style, name) in zip(choices, names) {
            XCTAssertFalse(name.isEmpty, "\(style.token) has no VoiceOver name")
            XCTAssertNotEqual(name, style.token, "VoiceOver would read the internal token '\(style.token)'")
        }
        XCTAssertEqual(Set(names).count, choices.count, "four swatches, four distinct names")
    }

    /// OB-1: six acts, strictly linear. `reveal` first, `finale` last, nothing after it.
    func testSixActsRunRevealToFinale() {
        XCTAssertEqual(WelcomeGuideStep.first, .reveal)
        XCTAssertEqual(WelcomeGuideStep.allCases, [.reveal, .bar, .feel, .access, .rhythm, .finale])
        XCTAssertNil(WelcomeGuideStep.reveal.previous)
        XCTAssertNil(WelcomeGuideStep.finale.next)
        for step in WelcomeGuideStep.allCases where step != .finale {
            XCTAssertEqual(step.next, WelcomeGuideStep(rawValue: step.rawValue + 1), "\(step)")
        }
        for step in WelcomeGuideStep.allCases where step != .reveal {
            XCTAssertEqual(step.previous, WelcomeGuideStep(rawValue: step.rawValue - 1), "\(step)")
        }
    }

    /// The DP-8 debug spellings stay valid, so an existing live-check script keeps working — while a
    /// synonym that was never shipped is not silently accepted in its place.
    func testDebugSwitchNamesKeepTheOldSpellings() {
        XCTAssertEqual(WelcomeGuideStep.named("layout"), .bar)
        XCTAssertEqual(WelcomeGuideStep.named("widgets"), .bar)
        XCTAssertEqual(WelcomeGuideStep.named("permissions"), .access)
        for step in WelcomeGuideStep.allCases {
            XCTAssertEqual(WelcomeGuideStep.named("\(step)"), step, "the act's own name")
        }
        XCTAssertNil(WelcomeGuideStep.named("theme"))
        XCTAssertNil(WelcomeGuideStep.named("ready"))
        XCTAssertNil(WelcomeGuideStep.named("nope"))
    }

    /// OB-1's pure act → settings map: every setting the guide can write belongs to exactly one act.
    func testEachActMapsToTheSettingsItWrites() {
        XCTAssertEqual(WelcomeGuideStep.bar.settings,
                       [.dockStyle, .edgePlacement, .sections, .wings, .trailingCapsule, .notch, .aiTracking])
        XCTAssertEqual(WelcomeGuideStep.feel.settings, [.theme, .appIconPreset])
        XCTAssertEqual(WelcomeGuideStep.access.settings, [.permissions, .weatherCity])
        XCTAssertEqual(WelcomeGuideStep.rhythm.settings, [.loginItem, .launcherTrigger, .clipboardToast])
        XCTAssertEqual(WelcomeGuideStep.finale.settings, [.systemDock])

        let union = WelcomeGuideStep.allCases.reduce(into: Set<WelcomeGuideSetting>()) { $0.formUnion($1.settings) }
        XCTAssertEqual(union, Set(WelcomeGuideSetting.allCases), "a setting no act writes would be dead UI")
        let counts = WelcomeGuideSetting.allCases.map { setting in
            WelcomeGuideStep.allCases.filter { $0.settings.contains(setting) }.count
        }
        XCTAssertTrue(counts.allSatisfy { $0 == 1 }, "each setting is written by exactly one act")
    }

    /// The reveal is the product statement: it must not write anything, or it stops being a reveal
    /// and becomes a seventh settings page the user can't skip out of.
    func testRevealWritesNothing() {
        XCTAssertTrue(WelcomeGuideStep.reveal.settings.isEmpty)
    }

    /// OB-2: the window is a fixed size, which is what let the measurement probe and the
    /// all-acts-same-height constraint go away.
    ///
    /// Measured through `WelcomeGuideWindowContent`, because that wrapper is what carries the
    /// explicit frame — `WelcomeGuideView` on its own solves to whatever its content's *ideal* width
    /// is, and ideal width (unwrapped text) is not what the window gets.
    func testWindowContentClaimsTheFixedSizeForEveryAct() {
        // Near-square on purpose: the window is a panel in the middle of the screen, not a strip.
        XCTAssertEqual(WelcomeGuideView.contentSize, CGSize(width: 720, height: 640))
        let aspect = WelcomeGuideView.contentSize.width / WelcomeGuideView.contentSize.height
        XCTAssertGreaterThan(aspect, 0.9, "a narrow/tall window is the bug this replaced")
        XCTAssertLessThan(aspect, 1.5, "and so is a wide/short strip")
        for startAt in WelcomeGuideStep.allCases {
            let host = NSHostingView(rootView: WelcomeGuideWindowContent(
                layout: context(), onApply: { _ in }, onDismiss: {}, startAt: startAt))
            XCTAssertEqual(host.fittingSize.width, WelcomeGuideView.contentSize.width, accuracy: 0.5,
                           "\(startAt) must not resize the window")
            XCTAssertEqual(host.fittingSize.height, WelcomeGuideView.contentSize.height, accuracy: 0.5,
                           "\(startAt) must not resize the window")
        }
    }

    /// Centred in the **usable** area, not the physical display: a panel centred in `screen.frame`
    /// sits half a menu bar too high, which looks like a bug and screenshots badly.
    func testPanelIsCentredInTheUsableArea() {
        // A 1512x982 display with a 60 pt Dock at the bottom and a 43 pt menu bar: the usable area
        // is 1512x879 starting at y=60.
        let usable = CGRect(x: 0, y: 60, width: 1512, height: 879)
        let frame = WelcomeGuideView.centeredFrame(in: usable, frameSize: CGSize(width: 720, height: 640))
        XCTAssertEqual(frame.width, 720, accuracy: 0.5)
        XCTAssertEqual(frame.height, 640, accuracy: 0.5)
        XCTAssertEqual(frame.midX, usable.midX, accuracy: 0.5, "horizontally centred")
        XCTAssertEqual(frame.midY, usable.midY, accuracy: 0.5, "vertically centred")
        XCTAssertTrue(usable.contains(frame), "the whole panel stays inside the usable area")
    }

    /// A short screen must not push the panel's traffic lights off the top edge: the height clamps to
    /// the usable height and the panel sits at its bottom, while the width still fits and so still
    /// centres. (An earlier version of this test expected `minX == usable.minX`, which would have
    /// pinned the panel to the left edge on every short-but-wide display.)
    func testPanelClampsOntoAShortScreen() {
        let usable = CGRect(x: 0, y: 25, width: 1280, height: 500)
        let frame = WelcomeGuideView.centeredFrame(in: usable, frameSize: CGSize(width: 720, height: 640))
        XCTAssertEqual(frame.height, 500, accuracy: 0.5, "clamped to the usable height")
        XCTAssertEqual(frame.minY, usable.minY, accuracy: 0.5, "pinned to the bottom of the usable area")
        XCTAssertEqual(frame.width, 720, accuracy: 0.5, "width fits, so it is untouched")
        XCTAssertEqual(frame.midX, usable.midX, accuracy: 0.5, "and still horizontally centred")
        XCTAssertLessThanOrEqual(frame.maxY, usable.maxY + 0.5)
    }

    /// Degenerate geometry (no screen yet) must not produce NaN, which would crash `setFrame`.
    func testPanelSurvivesAnEmptyUsableArea() {
        let frame = WelcomeGuideView.centeredFrame(in: .zero, frameSize: CGSize(width: 720, height: 640))
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 720, height: 640))
    }

    /// The defect this pins: a panel that **stretches** to its content (the original "tall strip"), or
    /// one that clips the content instead of scrolling it. Both fail here — the document must be
    /// taller than its viewport *and* the hosting view must still measure 720x640.
    func testAccessActOverflowsAndScrollsWithoutStretchingTheWindow() {
        let (window, host) = hostedGuide(startAt: .access, offersNativeDock: false)
        XCTAssertEqual(window.minSize, WelcomeGuideView.contentSize)
        XCTAssertEqual(window.maxSize, WelcomeGuideView.contentSize)
        // The live 720x672 bug: content-based pinning let AppKit stack the 32 pt titlebar on top, so
        // the panel grew after launch. Frame-based pinning must not allow that.
        XCTAssertEqual(window.frame.size, WelcomeGuideView.contentSize,
                       "the window frame must stay at the panel size, titlebar included")
        defer { window.contentView = nil }

        guard let scroll = Self.firstScrollView(in: host) else {
            XCTFail("no NSScrollView in the guide — the Access act would clip instead of scroll")
            return
        }
        let viewport = scroll.contentView.bounds.height
        let document = scroll.documentView?.bounds.height ?? 0
        print("ACCESS_ACT_LAYOUT viewport=\(Int(viewport.rounded()))"
              + " document=\(Int(document.rounded()))"
              + " maxOffset=\(Int(max(0, document - viewport).rounded()))"
              + " hosting=\(NSStringFromRect(host.frame))")
        XCTAssertGreaterThan(document, viewport + 100,
                             "Access act must overflow its viewport (document \(document) vs viewport \(viewport))")
        XCTAssertEqual(scroll.frame.size.width, WelcomeGuideView.contentSize.width, accuracy: 0.5,
                       "the scroll view spans the panel, it does not widen to its content")
        XCTAssertEqual(host.frame.size, WelcomeGuideView.contentSize,
                       "the hosting view must stay at the panel size")
        // (0,0) is the pin: with `sizingOptions = []` the hosting view advertises no intrinsic size, so
        // it cannot resize a window. Drop that line and this becomes 720x672 — the stretch defect.
        XCTAssertEqual(host.fittingSize, .zero,
                       "the hosting view must advertise no size a window could adopt")
    }

    /// OB-3: a **short** act must claim the whole viewport.
    ///
    /// The reveal holds ~250 pt of content. Before this it was top-aligned in a 528 pt viewport, so the
    /// entire leftover pooled between the copy and the footer's `Continue` button — the top-heavy frame
    /// the live screenshots caught. `minHeight` on the scroll content is what lets the act's own spacers
    /// split that leftover, so the structural property to pin is "document == viewport, and no scroll".
    /// The Access act stays the counter-case above: taller than the viewport, and still scrolling.
    func testShortActsClaimTheViewportInsteadOfPoolingSpaceBelow() {
        // `.feel` is in the list on purpose: naming its four swatches added ~19 pt, and this is the
        // test that fails if that pushes a settings act into a scroll.
        for step in [WelcomeGuideStep.reveal, .feel, .rhythm, .finale] {
            let (window, host) = hostedGuide(startAt: step, offersNativeDock: true)
            defer { window.contentView = nil }
            guard let scroll = Self.firstScrollView(in: host) else {
                XCTFail("no NSScrollView in the guide — \(step) would clip instead of scroll")
                return
            }
            let viewport = scroll.contentView.bounds.height
            let document = scroll.documentView?.bounds.height ?? 0
            print("SHORT_ACT_LAYOUT step=\(step) viewport=\(Int(viewport.rounded()))"
                  + " document=\(Int(document.rounded()))")
            XCTAssertGreaterThan(viewport, 400, "\(step): the panel must leave a real viewport")
            XCTAssertEqual(document, viewport, accuracy: 1,
                           "\(step) must fill the viewport (document \(document) vs viewport \(viewport))")
        }
    }

    /// A window is required for SwiftUI to lay out the scroll *content* (without one the document view
    /// reports height 0). It is never ordered front, and `isReleasedWhenClosed = false` plus no
    /// `close()` — tearing a window down inside the test host is what crashed the runner earlier.
    private func hostedGuide(startAt: WelcomeGuideStep, offersNativeDock: Bool)
        -> (NSWindow, NSHostingView<WelcomeGuideWindowContent>) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: WelcomeGuideView.contentSize),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        // The production factory, not a hand-rolled copy: a missing `sizingOptions`/`safeAreaRegions`
        // line there is the defect the Access test exists to catch.
        let host = WelcomeGuideView.pinnedHostingView(WelcomeGuideWindowContent(
            layout: context(), onApply: { _ in }, onDismiss: {},
            offersNativeDock: offersNativeDock, startAt: startAt))
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: WelcomeGuideView.contentSize)
        WelcomeGuideView.pinPanelWindow(window)
        window.setFrame(NSRect(origin: .zero, size: WelcomeGuideView.contentSize), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        host.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        return (window, host)
    }

    private static func firstScrollView(in view: NSView?) -> NSScrollView? {
        guard let view else { return nil }
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews {
            if let found = firstScrollView(in: sub) { return found }
        }
        return nil
    }

    /// The sandboxed copy gets the reveal too, minus the act-3 system-Dock controls. This is the
    /// rendering half of `testSandboxedPresentsWithoutTheNativeDockOptions`.
    func testSandboxedWindowStillRendersAtTheFixedSize() {
        let host = NSHostingView(rootView: WelcomeGuideWindowContent(
            layout: context(), onApply: { _ in }, onDismiss: {}, offersNativeDock: false))
        XCTAssertEqual(host.fittingSize, WelcomeGuideView.contentSize)
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

    /// The bar act and the bar must answer the same question with the same state.
    ///
    /// The strip draws `dockSlotLayout` and splices the sections that have no slot (`calendar`,
    /// `system`, `devices`, `widgets`) back from `WidgetLayout`. The act used to read only the widget
    /// model and write only six slot-backed sections, so half the grid showed the wrong state while
    /// four switches did nothing; Now Playing read unchecked with its slot on the bar.
    func testEverySectionSwitchInTheActReachesTheBar() {
        let store = AppSettingsStore(defaults: TestDefaults.make("com.katikati.tests.guide.sections", for: self))
        /// Exactly what the strip renders: the slot layout plus the legacy sections it has no slot for.
        func barSections() -> Set<BarSection> {
            Set(DockModularityValidator.renderOrder(for: store.dockSlotLayout,
                                                    mode: store.barLayoutMode,
                                                    legacyOrder: store.widgetLayout.visibleOrder))
        }

        XCTAssertEqual(Set(WelcomeGuideView.configurableSections),
                       Set(BarSection.canonicalOrder.filter { $0 != .apps }),
                       "the act offers every section the bar can draw, once")

        for section in WelcomeGuideView.configurableSections {
            store.setBarSection(section, visible: false)
            XCTAssertFalse(barSections().contains(section),
                           "\(section) still draws after the act switched it off")
            store.setBarSection(section, visible: true)
            XCTAssertTrue(barSections().contains(section),
                          "\(section) never reaches the bar, so its switch does nothing")
        }
    }

    func testNotchPreviewKeepsThePanelProportionsInEveryColumn() {
        for skin in LiveIslandSkin.allCases {
            let panel = NotchGeometry.previewSize(for: skin, expanded: true)
            let host = NSHostingView(rootView: NotchPreview(skin: skin, isEnabled: true))
            for column in [900.0, 464.0, 300.0] {
                host.setFrameSize(NSSize(width: column, height: 0))
                host.layoutSubtreeIfNeeded()
                let fitted = host.fittingSize
                XCTAssertLessThanOrEqual(fitted.width, panel.width + 0.5, "\(skin) at \(column) pt wide")
                XCTAssertLessThanOrEqual(fitted.height, panel.height + 34,
                                         "\(skin) at \(column) pt wide: drawing stretched past its own ratio")
            }
        }
    }
}
