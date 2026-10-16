import SwiftUI

// Phase 32b — the SwiftUI half of the dock's motion language. `Core/Support/WidgetMotionSpec.swift`
// stays free of SwiftUI so it can be tested (and dual-compiled) as data; this file is the one place
// that turns its springs into `Animation`, so no widget writes its own curve and `Instant` — or
// Reduce Motion — cuts the change in exactly one way.

extension SpringParameters {
    /// The house conversion: the same literal the notch writes inline for its own springs
    /// (`NotchIslandView`, `NotchPanelController`), now named once.
    var animation: Animation { .spring(response: response, dampingFraction: dampingRatio) }
}

extension WidgetMotion {
    /// The content morph's animation. `nil` = the change cuts (Instant, or Reduce Motion winning).
    var contentAnimation: Animation? { contentSpring?.animation }
}

extension View {
    /// A dock widget's reading morphs in place: the number slides to its new value with the preset's
    /// content spring, and cuts when the preset has none. `value` is the reading itself, so only a
    /// real change animates — hovering, resizing or a re-render never does.
    func dockReadingMorph(_ motion: WidgetMotion, value: some Equatable) -> some View {
        contentTransition(.numericText()).animation(motion.contentAnimation, value: value)
    }
}
