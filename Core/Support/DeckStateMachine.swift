import Foundation

/// The deck's three states (Phase 7A-D1), after noty's `DeckState` (MIT, NOTICE §5): `rest` (a pill at the
/// screen edge), `fan` (tabs slid out), `expanded(id)` (one note's sheet is open).
enum DeckState: Equatable, Sendable {
    case rest
    case fan
    case expanded(String)

    var expandedID: String? {
        if case let .expanded(id) = self { return id }
        return nil
    }

    /// Ordering used to decide whether the panel grows (enter) or shrinks (exit) on a transition.
    var rank: Int {
        switch self {
        case .rest: return 0
        case .fan: return 1
        case .expanded: return 2
        }
    }
}

enum DeckEvent: Equatable, Sendable {
    case pointerEntered
    /// Fired only after the 0.15 s "really left the hot zone" confirmation.
    case pointerExitConfirmed
    case tabClicked(String)
    /// The pointer rested on a tab for `DeckTiming.hoverOpenDelay`.
    case hoverRested(String)
    /// Seconds since the last user activity (from the idle watch tick).
    case idle(TimeInterval)
    case escape
    case outsideClick
    /// The open note was deleted or archived.
    case noteRemoved(String)
    /// "Keep the deck open" was switched; `state` is re-pointed at the new resting state.
    case keepOpenChanged
}

struct DeckContext: Equatable, Sendable {
    var keepOpen = false
    /// A tab or the pill is being dragged: the deck must not tidy itself away mid-drag.
    var isDragging = false
    /// The open note is pinned: it never idles shut.
    var openNoteIsPinned = false
    var openOnHover = false

    var restingState: DeckState { keepOpen ? .fan : .rest }
}

enum DeckTiming {
    /// Seconds with no activity before a fan folds back to the pill.
    static let fanIdleTimeout: TimeInterval = 4
    /// Seconds before an open (unpinned) note closes.
    static let noteIdleTimeout: TimeInterval = 60
    static let exitConfirmDelay: TimeInterval = 0.15
    static let hoverOpenDelay: TimeInterval = 0.4
    static let previewDelay: TimeInterval = 0.18
}

/// Pure transition table; the controller owns timers, panels and animation.
enum DeckStateMachine {
    static func reduce(_ state: DeckState, _ event: DeckEvent, _ ctx: DeckContext) -> DeckState {
        switch event {
        case .pointerEntered:
            return state == .rest ? .fan : state

        case .pointerExitConfirmed:
            // An open note stays open until Esc / outside click / idle; a kept-open fan never folds.
            guard state == .fan, !ctx.keepOpen, !ctx.isDragging else { return state }
            return .rest

        case let .tabClicked(id):
            return state == .expanded(id) ? .fan : .expanded(id)

        case let .hoverRested(id):
            guard ctx.openOnHover, !ctx.isDragging, state != .expanded(id) else { return state }
            return .expanded(id)

        case let .idle(seconds):
            switch state {
            case .fan where !ctx.keepOpen && !ctx.isDragging && seconds > DeckTiming.fanIdleTimeout:
                return .rest
            case .expanded where !ctx.openNoteIsPinned && !ctx.isDragging && seconds > DeckTiming.noteIdleTimeout:
                return ctx.restingState
            default:
                return state
            }

        case .escape:
            switch state {
            case .expanded: return .fan
            case .fan: return ctx.restingState
            case .rest: return .rest
            }

        case .outsideClick:
            return state.expandedID == nil ? state : ctx.restingState

        case let .noteRemoved(id):
            return state == .expanded(id) ? .fan : state

        case .keepOpenChanged:
            // Follow the new resting state only when the deck is idling in the old one.
            switch state {
            case .rest where ctx.keepOpen: return .fan
            case .fan where !ctx.keepOpen: return .rest
            default: return state
            }
        }
    }
}

/// Validation shared by the deck settings (store) and the views.
enum DeckSettingsRules {
    static let scaleRange: ClosedRange<Double> = 0.8...1.4
    static let defaultScale = 1.0

    static func clampedScale(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return defaultScale }
        return min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func clampedRatio(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }
}

/// How non-note tiles (status trio, widgets) are drawn in the deck.
enum EdgeTileStyle: String, CaseIterable, Sendable {
    case glass
    case coloured
}
