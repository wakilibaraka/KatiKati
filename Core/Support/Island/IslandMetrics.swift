import CoreGraphics
import Foundation

/// Physical and layout metrics for the Dynamic Island surface, ported from `opencoredev/islandcn`
/// with adaptations for macOS Notched Displays, MacBook Pro M5 OLED, and Non-Notch External Displays.
public struct IslandMetrics: Equatable, Sendable {
    public struct ScreenSpec: Equatable, Sendable {
        public var width: Double
        public var height: Double
    }

    public struct IdleSpec: Equatable, Sendable {
        public var width: Double
        public var height: Double
    }

    public struct CornerSpec: Equatable, Sendable {
        /// Continuous-corner smoothing factor (`0.72` fitted to simulator frames).
        public var smoothing: Double
    }

    public struct CompactInnerPadding: Equatable, Sendable {
        public var leading: Double
        public var trailing: Double
    }

    public struct CompactSpec: Equatable, Sendable {
        public var height: Double
        public var sensorWidth: Double
        public var edgePadding: Double
        public var innerPadding: CompactInnerPadding
        public var maxSlotWidth: Double
        public var maxWidth: Double
        public var balance: Double
    }

    public struct MinimalAttachedSpec: Equatable, Sendable {
        public var outerPadding: Double
        public var innerPadding: Double
    }

    public struct MinimalDetachedSpec: Equatable, Sendable {
        public var padding: Double
        public var minWidth: Double
    }

    public struct MinimalSpec: Equatable, Sendable {
        public var height: Double
        public var attached: MinimalAttachedSpec
        public var detached: MinimalDetachedSpec
        public var gap: Double
    }

    public struct SplitAttachedSpec: Equatable, Sendable {
        public var outerPadding: Double
        public var gap: Double
        public var innerPadding: Double
    }

    public struct SplitDetachedSpec: Equatable, Sendable {
        public var outerPadding: Double
        public var gap: Double
        public var trailingPadding: Double
        public var width: Double
        public var slotGap: Double
        public var slotEnd: Double
    }

    public struct SplitSpec: Equatable, Sendable {
        public var attached: SplitAttachedSpec
        public var detached: SplitDetachedSpec
        public var maxSpan: Double
    }

    public struct ExpandedPadding: Equatable, Sendable {
        public var top: Double
        public var side: Double
        public var trailing: Double
        public var bottom: Double
    }

    public struct ShadowPullSpec: Equatable, Sendable {
        public var side: Double
        public var top: Double
        public var bottom: Double
        public var opacity: Double
    }

    public struct ShadowSpec: Equatable, Sendable {
        public var offsetY: Double
        public var blur: Double
        public var aspect: Double
        public var opacity: Double
        public var tailOffsetY: Double
        public var tailBlur: Double
        public var tailAspect: Double
        public var tailStrength: Double
        public var pull: ShadowPullSpec
    }

    public struct ExpandedSpec: Equatable, Sendable {
        public var sideInset: Double
        public var top: Double
        public var minHeight: Double
        public var maxHeight: Double
        public var radius: Double
        public var padding: ExpandedPadding
        public var centerTop: Double
        public var rowGap: Double
        public var cornerAspect: Double
        public var cornerExponent: Double
        public var shadow: ShadowSpec
    }

    public struct ContentClipSpec: Equatable, Sendable {
        public var radius: Double
        public var chamfer: Double
    }

    public struct PressSpec: Equatable, Sendable {
        public var squish: Double
        public var swell: Double
        public var bubbleSwell: Double?
    }

    public struct BridgeSpec: Equatable, Sendable {
        public var handleSize: Double
        public var spread: Double
        public var maxGap: Double
    }

    public struct KeylineSpec: Equatable, Sendable {
        public var width: Double
        public var alpha: Double
        public var fullUntil: Double
        public var noneFrom: Double
        public var expandedDim: Double
        public var ramp: Double
    }

    public struct KeylineFadePoint: Equatable, Sendable {
        public let luma: Double
        public let share: Double
    }

    public var screen: ScreenSpec
    public var top: Double
    public var idle: IdleSpec
    public var corner: CornerSpec
    public var compact: CompactSpec
    public var minimal: MinimalSpec
    public var split: SplitSpec
    public var expanded: ExpandedSpec
    public var contentClip: ContentClipSpec
    public var press: PressSpec
    public var bridge: BridgeSpec
    public var keyline: KeylineSpec
    public var keylineFade: [KeylineFadePoint]

    /// Exact simulator-calibrated metrics from `opencoredev/islandcn` (`402 x 874` reference grid).
    public static let reference = IslandMetrics(
        screen: ScreenSpec(width: 402.0, height: 874.0),
        top: 13.91,
        idle: IdleSpec(width: 94.85, height: 36.84),
        corner: CornerSpec(smoothing: 0.72),
        compact: CompactSpec(
            height: 36.85,
            sensorWidth: 94.85,
            edgePadding: 7.18,
            innerPadding: CompactInnerPadding(leading: -0.18, trailing: 0.07),
            maxSlotWidth: 72.0,
            maxWidth: 260.0,
            balance: 0.7475
        ),
        minimal: MinimalSpec(
            height: 36.85,
            attached: MinimalAttachedSpec(outerPadding: 7.09, innerPadding: 8.4),
            detached: MinimalDetachedSpec(padding: 6.42, minWidth: 36.85),
            gap: 7.82
        ),
        split: SplitSpec(
            attached: SplitAttachedSpec(outerPadding: 6.59, gap: 6.15, innerPadding: 8.18),
            detached: SplitDetachedSpec(
                outerPadding: 6.42,
                gap: 12.0,
                trailingPadding: 13.09,
                width: 62.18,
                slotGap: 6.085,
                slotEnd: 7.175
            ),
            maxSpan: 290.0
        ),
        expanded: ExpandedSpec(
            sideInset: 13.83,
            top: 13.83,
            minHeight: 84.0,
            maxHeight: 180.0,
            radius: 47.9,
            padding: ExpandedPadding(top: 18.18, side: 18.5, trailing: 17.81, bottom: 18.35),
            centerTop: 1.33,
            rowGap: 8.0,
            cornerAspect: 1.0,
            cornerExponent: 2.0,
            shadow: ShadowSpec(
                offsetY: 10.7,
                blur: 30.76,
                aspect: 1.018,
                opacity: 0.3533,
                tailOffsetY: 23.43,
                tailBlur: 81.03,
                tailAspect: 1.084,
                tailStrength: 0.0922,
                pull: ShadowPullSpec(side: 0.14, top: 0.083, bottom: 0.276, opacity: 0.3533)
            )
        ),
        contentClip: ContentClipSpec(radius: 34.4, chamfer: 0.0),
        press: PressSpec(squish: 0.09, swell: 0.187, bubbleSwell: 0.0622),
        bridge: BridgeSpec(handleSize: 2.4, spread: 0.3, maxGap: 5.0),
        keyline: KeylineSpec(
            width: 1.5,
            alpha: 0.16,
            fullUntil: 0.04,
            noneFrom: 0.17,
            expandedDim: 0.07,
            ramp: 6.0
        ),
        keylineFade: [
            KeylineFadePoint(luma: 0.0706, share: 0.328),
            KeylineFadePoint(luma: 0.1104, share: 0.109),
        ]
    )

    /// Builds display-adapted metrics anchored to macOS hardware cutout geometry while keeping
    /// iOS 27 `islandcn` proportions, continuous corner smoothing, and asymmetric balance intact.
    public static func macAdapted(
        topOffset: Double,
        cutoutWidth: Double,
        capsuleHeight: Double,
        maxCompactWidth: Double = 360.0,
        expandedWidth: Double = 460.0,
        expandedMinHeight: Double = 104.0,
        expandedMaxHeight: Double = 190.0
    ) -> IslandMetrics {
        var copy = IslandMetrics.reference
        let safeHeight = max(24.0, capsuleHeight)
        let safeSensor = max(64.0, cutoutWidth)
        copy.top = topOffset
        copy.idle = IdleSpec(width: safeSensor, height: safeHeight)
        copy.compact.height = safeHeight
        copy.compact.sensorWidth = safeSensor
        copy.compact.maxWidth = max(safeSensor + 80.0, maxCompactWidth)
        copy.compact.maxSlotWidth = max(72.0, (copy.compact.maxWidth - safeSensor) * 0.44)
        copy.minimal.height = safeHeight
        copy.minimal.detached.minWidth = safeHeight
        copy.split.maxSpan = max(290.0, copy.compact.maxWidth + 86.0)
        copy.expanded.top = max(topOffset, 8.0)
        copy.expanded.sideInset = 14.0
        copy.screen.width = expandedWidth + 2.0 * copy.expanded.sideInset
        copy.expanded.minHeight = expandedMinHeight
        copy.expanded.maxHeight = expandedMaxHeight
        return copy
    }
}
