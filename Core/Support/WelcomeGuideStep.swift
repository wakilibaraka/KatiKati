import Foundation

/// DP-8: the welcome guide is three live-applying steps instead of five pages — layout & edge,
/// widgets & wings, permissions & triggers. Every step writes straight to the store; the final
/// button only closes the window and applies the recommended system-Dock set.
///
/// `settings` is the pure step → settings map: it is what the tests pin, and it keeps a control from
/// drifting into a step that never writes it. `allCases` of `WelcomeGuideSetting` must appear in
/// exactly the step that owns it.
enum WelcomeGuideStep: Int, CaseIterable, Sendable {
    /// Step 1: the four look cards (Wide preselected) and the Bottom / Left / Right edge.
    case layout
    /// Step 2: widgets, wings, the weather city, the AI opt-in and the Dynamic Notch row.
    case widgets
    /// Step 3: permission grants, the launcher trigger, the clipboard toast, and the recommended
    /// system-Dock set the guide closes with.
    case permissions

    static let first: WelcomeGuideStep = .layout

    var next: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue + 1) }
    var previous: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue - 1) }

    /// Exactly the settings this step writes, live.
    var settings: Set<WelcomeGuideSetting> {
        switch self {
        case .layout: return [.dockStyle, .edgePlacement]
        case .widgets: return [.sections, .wings, .weatherCity, .aiTracking, .notch]
        case .permissions: return [.permissions, .launcherTrigger, .clipboardToast, .systemDock]
        }
    }
}

/// The store surfaces the guide can touch. Pure tag set so the mapping above is unit-testable.
enum WelcomeGuideSetting: String, CaseIterable, Sendable {
    case dockStyle
    case edgePlacement
    case sections
    case wings
    case weatherCity
    case aiTracking
    case notch
    case permissions
    case launcherTrigger
    case clipboardToast
    case systemDock
}
