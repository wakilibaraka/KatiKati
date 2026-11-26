import Foundation

/// OB-1: the welcome guide is six acts, each capped to one decision — reveal, your bar, feel,
/// access, rhythm, all set. Every act except `reveal` writes straight to the store, live; the final
/// button only closes the window and applies the recommended system-Dock set.
///
/// `settings` is the pure act → settings map: it is what the tests pin, and it keeps a control from
/// drifting into an act that never writes it. `allCases` of `WelcomeGuideSetting` must appear in
/// exactly the act that owns it, and `reveal` owns none on purpose — it is the product statement,
/// so a control added there would be a control with no effect.
enum WelcomeGuideStep: Int, CaseIterable, Sendable {
    /// Act 1: the kinetic opener. Writes nothing.
    case reveal
    /// Act 2: dock style, the edge, the section set, the wings, the detached capsule, the Live
    /// Island and AI tracking — the bar's shape.
    case bar
    /// Act 3: the theme material and the app-icon preset, plus the recommended system Dock set.
    case feel
    /// Act 4: the one permission pass and the weather city (a fresh bar otherwise shows an empty
    /// "Add City" pill).
    case access
    /// Act 5: open at login, the launcher trigger and the clipboard toast.
    case rhythm
    /// Act 6: the kinetic close. Owns the system-Dock recommendation that "Apply" writes.
    case finale

    static let first: WelcomeGuideStep = .reveal

    /// The `DOCK_WELCOME_STEP` spelling of an act, so a live check can open the guide on one act.
    /// The DP-8 names stay valid: an existing live-check script that says `layout` or `permissions`
    /// must keep landing somewhere real rather than silently starting at act 1.
    static func named(_ name: String) -> WelcomeGuideStep? {
        switch name.lowercased() {
        case "reveal", "welcome": return .reveal
        case "bar", "layout": return .bar
        case "feel", "style", "theme": return .feel
        case "access", "permissions": return .access
        case "rhythm", "triggers": return .rhythm
        case "finale", "ready": return .finale
        default: return nil
        }
    }

    var next: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue + 1) }
    var previous: WelcomeGuideStep? { WelcomeGuideStep(rawValue: rawValue - 1) }

    /// Exactly the settings this act writes, live.
    var settings: Set<WelcomeGuideSetting> {
        switch self {
        case .reveal:
            return []
        case .bar:
            return [.dockStyle, .edgePlacement, .sections, .wings, .trailingCapsule, .notch, .aiTracking]
        case .feel:
            return [.theme, .appIconPreset]
        case .access:
            return [.permissions, .weatherCity]
        case .rhythm:
            return [.loginItem, .launcherTrigger, .clipboardToast]
        case .finale:
            return [.systemDock]
        }
    }
}

/// The store surfaces the guide can touch. Pure tag set so the mapping above is unit-testable.
///
/// `.theme` and `.loginItem` were written by the DP-8 guide (through `onPickTheme` and the
/// "Open at Login" row) without appearing here at all — a control with no owner, which is exactly
/// what the exact-once test exists to catch.
enum WelcomeGuideSetting: String, CaseIterable, Sendable {
    case dockStyle
    case edgePlacement
    case appIconPreset
    case sections
    case wings
    case trailingCapsule
    case notch
    case aiTracking
    case theme
    case permissions
    case weatherCity
    case loginItem
    case launcherTrigger
    case clipboardToast
    case systemDock
}

/// The seam between the reveal and the Accessibility window.
///
/// On a pristine install the reveal runs *before* the Accessibility gate (owner, OB-1): a fresh Mac
/// should meet the product, not a permission checklist. That means `AppDelegate` defers the
/// recovery window while the guide is up, and must hand over when it closes — otherwise pressing
/// Skip on a Mac with no Accessibility would leave the taskbar in limited mode with nothing telling
/// the user why, and no window to grant from.
///
/// Pure so the "Skip never strands you" invariant can be pinned in a unit test: the ordering logic
/// itself lives in `AppDelegate`, which no test target can drive.
enum WelcomeGuideHandover {
    /// - Parameters:
    ///   - isFirstRunDeferred: the reveal was presented ahead of the Accessibility gate on this launch
    ///   - isTrusted: `PermissionService.hasRequiredPermissions()` right now
    ///   - hasPresentation: the recovery machine currently wants a window
    static func shouldPresentRecoveryWindow(
        isFirstRunDeferred: Bool,
        isTrusted: Bool,
        hasPresentation: Bool
    ) -> Bool {
        // Not our launch to hand over: a Settings replay ("Show Setup Guide Again") runs long after
        // startup, and popping the Accessibility window when it closes would be a new, unrelated
        // interruption — the recovery machine raises it itself if the grant is ever lost.
        guard isFirstRunDeferred else { return false }
        // Granted during the guide (Act 4): there is nothing left to ask for.
        guard !isTrusted else { return false }
        return hasPresentation
    }
}
