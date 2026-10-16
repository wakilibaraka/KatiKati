import Foundation

// Phase 45 — the player-permission probe behind the music surfaces.
//
// The surfaces can read a player two ways: MediaRemote (answers only a trustworthily signed process,
// Phase 43) and AppleScript (Spotify / Music). macOS gates every Apple event behind a per-pair Automation
// grant, so a rebuilt or freshly copied KatiKati can simply be told no — `NSAppleScript` then fails with
// -1743 (`errAEEventNotPermitted`) or -1742 (`errAEEventWouldRequireUserConsent`). The reading threw that
// error away, so the widget said "Not Playing" while the player was playing: nothing was wrong with the
// player, nobody could see the refusal. This verdict is what the UI shows instead, with the door to fix it.
//
// `Foundation`-only and dual-compiled, so the classification and the message are unit-tested.

enum PlayerAccess: Equatable {
    /// Nothing readable is running, or nothing has been read yet: no permission story to tell.
    case unknown
    /// The player answered — MediaRemote handed over a track, or AppleScript returned a reading.
    case readable
    /// A running player was asked and macOS refused the Apple event.
    case refused(player: String)

    /// The AppleScript error numbers that mean "KatiKati may not ask this app":
    /// `errAEEventNotPermitted` (-1743) and `errAEEventWouldRequireUserConsent` (-1742). Every other
    /// failure (-600 no such app, -2741 our own script) is not a permission verdict.
    static let refusalErrorNumbers: Set<Int> = [-1743, -1742]

    /// Classifies one reading script's raw output: a refusal marker it reported, else `.unknown`.
    static func probe(scriptOutput raw: String) -> PlayerAccess {
        guard let refusal = AppleScriptNowPlaying.refusal(in: raw),
              refusalErrorNumbers.contains(refusal.errorNumber) else { return .unknown }
        return .refused(player: refusal.player)
    }

    /// The line a surface shows in place of "Not Playing"; `nil` when there is nothing to explain.
    var unreadableMessage: String? {
        guard case .refused(let player) = self else { return nil }
        return String(format: String(localized: "KatiKati can't read %@"), player)
    }

    /// System Settings › Privacy & Security › Automation, where the missing grant lives (same
    /// `x-apple.systempreferences` route the Settings page uses for Input Monitoring).
    static let automationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
}
