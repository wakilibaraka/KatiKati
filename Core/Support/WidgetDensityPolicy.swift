import CoreGraphics
import Foundation

enum WidgetDensityTier: Int, Equatable, Comparable, Sendable {
    case compact = 0
    case regular = 1
    case spacious = 2

    static func < (lhs: WidgetDensityTier, rhs: WidgetDensityTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct WidgetDensitySpec: Equatable, Sendable {
    let tier: WidgetDensityTier
    let showsSparkline: Bool
    let showsSecondaryCaption: Bool
    let showsDeviceName: Bool
}

/// D2: Docktor-style responsive density policy that sheds sparklines and secondary captions
/// before numeric readouts ever clip or truncate at small dock heights.
enum WidgetDensityPolicy {
    static func resolve(dockHeight: CGFloat, widgetSize: WidgetSize) -> WidgetDensitySpec {
        if dockHeight < 44 || widgetSize == .small {
            return WidgetDensitySpec(
                tier: .compact,
                showsSparkline: false,
                showsSecondaryCaption: false,
                showsDeviceName: false
            )
        }
        if dockHeight < 58 || widgetSize == .medium {
            return WidgetDensitySpec(
                tier: .regular,
                showsSparkline: dockHeight >= 48,
                showsSecondaryCaption: true,
                showsDeviceName: false
            )
        }
        return WidgetDensitySpec(
            tier: .spacious,
            showsSparkline: true,
            showsSecondaryCaption: true,
            showsDeviceName: true
        )
    }
}
