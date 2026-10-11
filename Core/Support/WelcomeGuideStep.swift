import Foundation

/// Steps of the first-run welcome guide (Phase 6): pick a layout, then the recommended
/// Dock settings. Pure so the flow is unit-tested without a window.
enum WelcomeGuideStep: Int, CaseIterable, Sendable {
    case pickLayout
    case dockSettings

    static let first: WelcomeGuideStep = .pickLayout

    var next: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue + 1) }
    var previous: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue - 1) }
}
