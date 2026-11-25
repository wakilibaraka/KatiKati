import Foundation

/// The welcome guide's Permissions step is the one place this app raises TCC prompts. Once that pass
/// has run, feature code must never prompt on its own: a panel that appears, a camera page that
/// opens or a hover that wants thumbnails reports the current grant instead, and the Settings rows
/// carry the Grant button for anything the owner wants to change.
///
/// Before the pass completes the flag is false, so a first-run feature can still ask — which is what
/// keeps the app usable for someone who skipped onboarding and went straight to a panel.
enum PermissionBootstrap {
    static let completedKey = "com.katikati.permissions.initialRequestCompleted"

    /// True once `WelcomeGuideView.requestEveryPermissionOnce()` has raised every prompt it can.
    static var hasCompletedInitialRequest: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Whether a feature may raise a system prompt right now.
    static var mayPromptFromFeature: Bool { !hasCompletedInitialRequest }
}
