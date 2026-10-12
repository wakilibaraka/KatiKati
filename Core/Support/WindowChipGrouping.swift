import Foundation

// Phase 9a — per-app window-chip grouping. Pure: no AppKit, no clock, no strings.
//
// Today every window gets its own chip ("separate"). A user can opt an app into "grouped": all of
// that app's windows collapse into ONE chip (reusing the multi-member chip the native-tab-group
// path already renders). The default stays `.separate`, so nothing moves unless the user asks —
// golden tests pin that.

enum WindowChipGroupPolicy: String, CaseIterable, Codable, Sendable {
    case separate
    case grouped
}

struct WindowChipGroupingPlan: Equatable, Sendable {
    var defaultPolicy: WindowChipGroupPolicy = .separate
    /// bundle ID → explicit policy. Absent = follow `defaultPolicy`.
    var overrides: [String: WindowChipGroupPolicy] = [:]

    static let ungrouped = WindowChipGroupingPlan()

    func policy(for bundleID: String?) -> WindowChipGroupPolicy {
        guard let bundleID else { return .separate }
        return overrides[bundleID] ?? defaultPolicy
    }

    /// True when no app can possibly be grouped (lets callers skip all work).
    var isInert: Bool {
        defaultPolicy == .separate && !overrides.values.contains(.grouped)
    }

    /// Stable chip identity for an app-level group. Never changes as windows come and go.
    static func groupToken(bundleID: String) -> String { "appgrp-\(bundleID)" }
    static func bundleID(fromToken token: String) -> String? {
        token.hasPrefix("appgrp-") ? String(token.dropFirst("appgrp-".count)) : nil
    }
}

enum WindowChipGrouping {
    /// Merges every app's slots into one slot when the plan groups that app and it has ≥ 2 real
    /// slots. The merged slot sits where the app's first slot was (first-appearance order, like the
    /// native tab-group collapse). Fallback (`app-*`) slots and ungrouped apps pass through untouched.
    static func merge<T>(
        slots: [[T]],
        bundleID: (T) -> String?,
        isFallback: (T) -> Bool,
        plan: WindowChipGroupingPlan
    ) -> [[T]] {
        guard !plan.isInert else { return slots }
        var result: [[T]] = []
        var indexByBundle: [String: Int] = [:]
        for slot in slots {
            guard let first = slot.first, !isFallback(first),
                  let bid = bundleID(first), plan.policy(for: bid) == .grouped else {
                result.append(slot)
                continue
            }
            if let idx = indexByBundle[bid] {
                result[idx].append(contentsOf: slot)
            } else {
                indexByBundle[bid] = result.count
                result.append(slot)
            }
        }
        return result
    }

    /// Which member a click on a grouped chip should raise: the window after the front one
    /// (wrapping), so repeated clicks cycle the app's windows. `frontIndex == nil` → the first.
    static func nextIndex(count: Int, frontIndex: Int?) -> Int {
        guard count > 0 else { return 0 }
        guard let frontIndex else { return 0 }
        return (frontIndex + 1) % count
    }
}
