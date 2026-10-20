import Foundation

/// Pure state of the Quick Add card (pill → kind menu → capture form → Save bubble), kept free of UI so it can be tested.
/// Lives in Core/Support (dual-compiled into the test target) — it sat in `GlassQuickAddView.swift`,
/// which the tests can't compile, so `QuickAddStateTests` could see the type but never link it.
struct QuickAddState: Equatable {
    enum Kind: String, CaseIterable, Sendable { case note, reminder, task }
    enum Stage: Equatable { case menu, capture(Kind) }
    enum Save: Equatable { case idle, saving, saved }
    enum Due: String, CaseIterable, Sendable { case none, today, tomorrow }

    var stage = Stage.menu
    var text = ""
    var save = Save.idle
    var due = Due.none
    var pinned = false
    var colorIndex = 0

    var kind: Kind? { if case let .capture(k) = stage { return k } else { return nil } }
    var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The Save bubble shows only once there is text to save.
    var canSave: Bool { kind != nil && !trimmed.isEmpty && save == .idle }

    mutating func choose(_ k: Kind) { stage = .capture(k); save = .idle }
    mutating func back() { stage = .menu; text = ""; save = .idle; due = .none; pinned = false }
    mutating func beginSave() -> Bool {
        guard canSave else { return false }
        save = .saving
        return true
    }
    mutating func finishSave(success: Bool) { save = success ? .saved : .idle }

    func dueDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch due {
        case .none: return nil
        case .today: return now
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: now)
        }
    }
}
