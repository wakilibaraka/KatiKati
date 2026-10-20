import Foundation

/// What a launch may open on its own (Pass 2). Pure decision — the delegate applies it.
enum StartupUIPolicy {
    /// General › "Launch hidden at login" / "Hide Dock icon". Unset reads false = the defaults.
    /// Never rename: both live in `UserDefaults` across releases.
    static let launchHiddenKey = "com.katikati.startup.launchHidden"
    static let hideDockIconKey = "com.katikati.dock.hideIcon"

    /// Quiet start ("Launch hidden at login"): an ordinary launch opens no discretionary
    /// windows. The first-run guide is exempt — a fresh install meets its setup exactly once,
    /// and a login launch is the likely moment to walk it. The permission guide never routes
    /// through here: without the grants the app cannot function at all.
    static func shouldPresentWelcomeGuide(isFirstRun: Bool, launchHidden: Bool) -> Bool {
        if isFirstRun { return true }
        return !launchHidden
    }
}
