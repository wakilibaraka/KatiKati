import CoreGraphics

/// The owner's choice between the curved notch (flared top ears, rounded bottom) and a sharp one with
/// square corners everywhere. Pure so the rule is tested rather than eyeballed.
enum NotchEdgeStyle {
    static let sharpKey = "com.katikati.notch.sharpEdges"

    /// Mask parameters for the current state. Sharp zeroes every radius and drops the flares, so nothing
    /// is drawn beside the hardware notch.
    static func mask(sharp: Bool, expanded: Bool, hasHardwareNotch: Bool)
        -> (top: CGFloat, bottom: CGFloat, flares: Bool) {
        if sharp { return (0, 0, false) }
        let radii = expanded ? NotchDesignSpec.openCornerRadii : NotchDesignSpec.closedCornerRadii
        return (radii.topFlaring, radii.bottomSquircle, hasHardwareNotch)
    }
}
