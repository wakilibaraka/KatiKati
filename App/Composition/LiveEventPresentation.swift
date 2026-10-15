import Foundation

// Phase 8b-4B — the Live Island toast's copy: one event → SF Symbol + localized headline + data detail.
//
// This is the *only* place holding the toast's user-facing literals, which is what lets
// `LiveEventDetector` stay pure and string-free: the pure engine says *what* happened, this says how to
// word it.
//
// It is **dual-compiled** (app + test) — the same treatment `AppSettingsStore.swift` gets — because
// `LiveEventDetectorTests` pins the symbol/detail mapping. It deliberately depends on nothing but
// `LiveEvent` (Core) and `LiveIslandFormat` (Core), so it links into the test bundle without dragging
// AppKit or the app-only `LiveEventCenter` along.

/// The localized copy + SF Symbol for one event.
///
/// Headlines come from `String(localized:)` literals (so the localization gate sees every key) and are
/// rendered with `Text(verbatim:)` — they are already resolved, never re-looked-up as a key.
struct LiveEventPresentation {
    let symbol: String
    let headline: String
    let detail: String?

    init(_ event: LiveEvent) {
        switch event {
        case let .trackChanged(title, artist):
            symbol = "music.note"
            headline = String(localized: "Now Playing")
            detail = title ?? artist

        case let .focusPhaseChanged(phase):
            symbol = "brain.head.profile"
            switch phase {
            case .focus: headline = String(localized: "Back to focus")
            case .shortBreak: headline = String(localized: "Break time")
            case .longBreak: headline = String(localized: "Long break")
            }
            detail = nil

        case .focusCycleCompleted:
            symbol = "checkmark.circle.fill"
            headline = String(localized: "Focus session complete")
            detail = nil

        case let .timerFinished(total):
            symbol = "timer"
            headline = String(localized: "Time's up")
            detail = LiveIslandFormat.clock(total)

        case let .stopwatchStopped(elapsed):
            symbol = "stopwatch"
            headline = String(localized: "Stopwatch stopped")
            detail = LiveIslandFormat.stopwatch(elapsed)

        case let .countdownReachedToday(label):
            symbol = "calendar"
            headline = String(format: String(localized: "%@ is today"), label)
            detail = nil

        case let .clipboardCopied(preview):
            symbol = "doc.on.clipboard"
            headline = String(localized: "Clipboard")
            detail = preview

        case let .downloadFinished(name):
            symbol = "arrow.down.circle.fill"
            headline = String(localized: "Download finished")
            detail = name

        case let .notice(kind, extra):
            detail = extra
            switch kind {
            case .capsLockOn: symbol = "capslock.fill"; headline = String(localized: "Caps Lock On")
            case .capsLockOff: symbol = "capslock"; headline = String(localized: "Caps Lock Off")
            case .batteryHigh: symbol = "battery.75percent"; headline = String(localized: "Battery at 80%")
            case .batteryFull: symbol = "battery.100percent.bolt"; headline = String(localized: "Fully Charged")
            }
        }
    }
}