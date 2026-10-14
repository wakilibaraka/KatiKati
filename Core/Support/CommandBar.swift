import Foundation

/// Phase 27a: the pure command-bar core. `CommandBarResults.build` is the whole "what rows does the
/// palette show for this query" decision — answer rows, running-app quit rows, then app matches. The
/// platform layer (`NSWorkspace`/`NSRunningApplication`) only maps its objects into these value types.
/// No AppKit here.

/// A running application, mapped from `NSRunningApplication` so the ordering stays pure and testable.
struct RunningAppRef: Equatable, Sendable {
    var bundleID: String
    var name: String
    var pid: Int32
    var path: String
}

/// One row in the command bar.
enum CommandBarResult: Equatable, Sendable {
    /// A math or web answer (Phase 21's `LauncherAnswer`).
    case answer(LauncherAnswer)
    /// Launch (or focus) an installed app.
    case app(LauncherApp)
    /// Quit a running app (graceful `terminate()`; the UI confirms first).
    case quit(RunningAppRef)
}

enum CommandBarResults {
    /// The rows for `query`, in display order: answers → running-app quit rows → app matches. A
    /// non-app route (math/web) yields only its answer rows. Empty input yields nothing.
    static func build(query: String,
                      apps: [LauncherApp],
                      usage: [String: LauncherUsage],
                      running: [RunningAppRef]) -> [CommandBarResult] {
        let routed = LauncherCommandParser.parse(query)
        guard case .apps(let term) = routed else {
            return LauncherAnswers.answers(for: routed).map(CommandBarResult.answer)
        }
        guard !term.isEmpty else { return [] }

        let quits = running
            .filter { LauncherSearch.score(query: term, name: $0.name) != nil }
            .sorted { a, b in
                let sa = LauncherSearch.score(query: term, name: a.name) ?? 0
                let sb = LauncherSearch.score(query: term, name: b.name) ?? 0
                return sa != sb ? sa > sb : a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
            .map(CommandBarResult.quit)

        return quits + LauncherSearch.search(term, in: apps, usage: usage).map(CommandBarResult.app)
    }
}

/// Phase 27a: the Spotlight hand-off. macOS has no API to take ⌘Space, so the bar guides the user to
/// free it. The steps are cases (the UI owns the localized copy, so this stays string-free); the URL
/// deep-links System Settings › Keyboard.
enum SpotlightHandoff {
    enum Step: Int, CaseIterable, Equatable, Sendable {
        case openKeyboard
        case openShortcuts
        case selectSpotlight
        case uncheckShowSearch
        case testHere
    }

    static let settingsURL = "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"

    static func steps() -> [Step] { Step.allCases }
}
