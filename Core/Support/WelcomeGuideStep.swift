import Foundation

/// Steps of the first-run welcome guide (Phase 6): pick a layout, choose the notch Live
/// Island, grant permissions, then the recommended Dock settings. Pure so the flow is unit-tested without a window.
enum WelcomeGuideStep: Int, CaseIterable, Sendable {
    case pickLayout
    case liveIsland
    /// Accessibility / Screen Recording / Input Monitoring, each with why it helps.
    case permissions
    case dockSettings

    static let first: WelcomeGuideStep = .pickLayout

    var next: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue + 1) }
    var previous: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue - 1) }
}
