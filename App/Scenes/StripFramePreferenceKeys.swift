import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

/// 悬停命中帧（`StripEntry.id` → "strip" 空间帧）。**四个区的卡全收进这一本**——它回答的是
/// 「指针压在谁身上」，那本来就不分区。同样独立于其余三本：那三本各自喂重排 / 弹窗锚点 /
/// 释放判定，语义不同，合并会互相污染（评审 P1 的老教训）。
struct StripHoverFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// **The one frame registry.** Every strip chip that draws a frame publishes it here with the zone it
/// belongs to, and the per-zone tables the reorder and popup code reads are derived from this value.
/// It replaces seven separate keys (window / kept-app / messaging / folder / section / shelf / trash /
/// pop) whose union in `allStripChipFrames()` had to be hand-extended for every new chip kind — the
/// omission that made the drawer-pop chip hit-test-dead for a whole session.
struct StripChipFramesPreferenceKey: PreferenceKey {
    static var defaultValue = StripChipFrames()
    static func reduce(value: inout StripChipFrames, nextValue: () -> StripChipFrames) {
        value.merge(nextValue())
    }
}

// MARK: - Where the reported geometry lives

/// Every frame the strip reports about itself — the four per-zone chip-frame tables, the shelf and
/// trash frames and the content area's screen rect — lives here, in one reference box held by
/// `DockStripView` as `@State var frames`, **never as `@State` values of its own**.
///
/// The reason is the write frequency: during a make-way spring, a slot collapse / reopen or the
/// panel re-centering, every one of these changes on **every animation frame**, and a `@State`
/// write re-evaluates the whole strip (`makeProjection`, order reconcile, twenty chips). Writing a
/// property of a class held in `@State` invalidates nothing, so the geometry can update at frame
/// rate while the body only re-runs for model changes. Everything that reads geometry does so at
/// event time (reorder hit-tests, landing anchors, hover resolution, drop routing, popup anchors)
/// and reads the box directly — always the latest value, never a copy captured by an earlier body.
/// The one rendering input derived from geometry, the hover bubble's anchor, is written separately
/// as `DockStripView.hoveredAnchor` only when the hovered card's screen frame actually moves.
@MainActor
final class StripFrameBox {
    /// Every chip's frame, by zone — written once from `StripChipFramesPreferenceKey`.
    var chipRegistry = StripChipFrames()
    /// Hover hit frames for every zone's cards (`StripEntry.id` → frame): "who is under the pointer".
    var stripHoverFrames: [String: CGRect] = [:]
    /// Live window / kept-app chip frames — the drag-reorder hit-test and landing input.
    var chipFrames: [String: CGRect] { chipRegistry.frames(in: .window) }
    /// Pinned-folder chip frames — popup anchors, external pin routing, in-zone reorder.
    var folderChipFrames: [String: CGRect] { chipRegistry.frames(in: .folder) }
    /// Messaging chip frames by bundle id — in-zone reorder and the drawer→messaging release range.
    var messagingChipFrames: [String: CGRect] { chipRegistry.frames(in: .messaging) }
    /// Widget-section placeholder frames — excluded from the taskbar-menu claim zone.
    var sectionFrames: [String: CGRect] { chipRegistry.frames(in: .section) }
    var shelfFrame: CGRect { chipRegistry.first(in: .shelf) ?? .zero }
    var trashFrame: CGRect { chipRegistry.first(in: .trash) ?? .zero }
    var popFrame: CGRect { chipRegistry.first(in: .pop) ?? .zero }
    /// The content area's frame in screen coordinates (bottom-left); `.zero` until first reported.
    var stripRootScreenRect: CGRect = .zero
    /// The `stripSlotCollapsed` value the last committed body rendered. Written from
    /// `.onChange(of: stripSlotCollapsed)` — the same moment the old `@State` copy was written, so the
    /// body that first sees the flip still picks the collapse curve — but as a box field the write
    /// itself no longer re-evaluates the strip (that echo body rendered nothing new).
    var renderedCollapsed = false
}

// MARK: - Drag-reorder preference (任务条拖动重排 路线 A 自绘拖动)

