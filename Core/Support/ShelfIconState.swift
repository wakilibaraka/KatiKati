import Foundation

// What the dock shelf icon shows for how much is on the shelf, and when the first-use guide in the shelf
// window applies. Pure so the thresholds are unit-tested. Dual-compiled.

enum ShelfIconState: Equatable, Sendable {
    /// Nothing parked: just the back plate and the glass pocket.
    case empty
    /// One item: a single blank paper.
    case onePaper
    /// Two or more: three papers with writing on them.
    case stack

    static func from(count: Int) -> ShelfIconState {
        switch count {
        case ..<1: return .empty
        case 1: return .onePaper
        default: return .stack
        }
    }
}

enum ShelfIntro {
    /// The explanatory notes show only while the shelf has never held anything: once an item has been
    /// parked (`introSeen`) or the shelf has items, they never come back.
    static func shouldShow(introSeen: Bool, itemCount: Int) -> Bool {
        !introSeen && itemCount == 0
    }
}
