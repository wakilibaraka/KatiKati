import Foundation

/// SD-1: everything the Side Deck's shell needs to know about itself, in one stored value.
///
/// The deck used to be hardcoded — 400 pt wide, left edge only, 18 pt corners, no activation preference of its
/// own — and its edge hover was a 7 Hz `NSEvent.mouseLocation` poll. This replaces that with clamped values
/// behind `com.katikati.sidedeck.prefs.v1`, plus a one-way migration from the old `drawer.edgeHover` opt-in.
struct SideDeckConfig: Equatable, Sendable {
    /// Which screen edge the deck docks to. The right Edge Bar owns the other one, so the two surfaces never
    /// fight over an edge (`Settings › Edge Bars` promises the left one stays free until the owner swaps).
    enum Side: String, CaseIterable, Sendable {
        case left, right

        var toggled: Side { self == .left ? .right : .left }
    }

    static let defaultsKey = "com.katikati.sidedeck.prefs.v1"
    static let migrationKey = "com.katikati.migration.sidedeck.v1"
    static let widthRange: ClosedRange<CGFloat> = 360...560
    static let dwellRange: ClosedRange<Double> = 0.08...0.6
    /// The panel floats this far below the menu bar and this far above the bottom, so the resting handle and
    /// the traffic lights never sit under glass.
    static let topInset: CGFloat = 20
    static let bottomInset: CGFloat = 16
    /// The plan's bento breakpoints: 3 columns at ≥900 pt of content, 2 at 620–900, 1 below.
    static let threeColumnMinimum: CGFloat = 900
    static let twoColumnMinimum: CGFloat = 620

    var side: Side
    var width: CGFloat
    /// Edge activation (a resting handle that opens on hover) is opt-in, exactly like the poll it replaces.
    var edgeActivation: Bool
    /// How long the pointer must rest on the handle before the deck opens.
    var dwell: Double
    /// Off by default: a second text surface costs localization and vertical room.
    var identityStrip: Bool
    /// Off by default: Weather stays a page, not a handle.
    var mergedWeatherHandle: Bool

    init(side: Side = .left, width: CGFloat = 400, edgeActivation: Bool = false, dwell: Double = 0.18,
         identityStrip: Bool = false, mergedWeatherHandle: Bool = false) {
        self.side = side
        self.width = min(max(width, Self.widthRange.lowerBound), Self.widthRange.upperBound)
        self.edgeActivation = edgeActivation
        self.dwell = min(max(dwell, Self.dwellRange.lowerBound), Self.dwellRange.upperBound)
        self.identityStrip = identityStrip
        self.mergedWeatherHandle = mergedWeatherHandle
    }

    static let standard = SideDeckConfig()

    // MARK: - Panel geometry

    /// Full height, inset below the menu bar and above the Dock, hugging the active edge.
    func panelFrame(in visible: CGRect, edgeGap: CGFloat = 8) -> CGRect {
        let width = min(max(self.width, Self.widthRange.lowerBound), max(Self.widthRange.lowerBound, visible.width - 2 * edgeGap))
        let top = min(Self.topInset, max(0, visible.height / 4))
        let bottom = min(Self.bottomInset, max(0, visible.height / 4))
        let height = max(0, visible.height - top - bottom)
        let x = side == .left ? visible.minX + edgeGap : visible.maxX - edgeGap - width
        return CGRect(x: x.rounded(), y: visible.minY + bottom, width: width.rounded(), height: height.rounded())
    }

    /// Bento columns from the content width, not the panel width: padding and the rail are already off it.
    static func columns(forContentWidth width: CGFloat) -> Int {
        if width >= threeColumnMinimum { return 3 }
        if width >= twoColumnMinimum { return 2 }
        return 1
    }

    // MARK: - Motion

    /// The plan's entry scale: 0.98 → 1. Reduce Motion keeps the fade and drops the scale.
    static func entryScale(reduceMotion: Bool) -> CGFloat { reduceMotion ? 1 : 0.98 }

    // MARK: - Storage

    static func stored(in defaults: UserDefaults = .standard) -> SideDeckConfig {
        let rawSide = defaults.string(forKey: defaultsKey + ".side").flatMap(Side.init(rawValue:))
        let width = defaults.object(forKey: defaultsKey + ".width") as? Double
        let dwell = defaults.object(forKey: defaultsKey + ".dwell") as? Double
        return SideDeckConfig(
            side: rawSide ?? standard.side,
            width: width.map { CGFloat($0) } ?? standard.width,
            edgeActivation: defaults.object(forKey: defaultsKey + ".edgeActivation") as? Bool ?? standard.edgeActivation,
            dwell: dwell ?? standard.dwell,
            identityStrip: defaults.object(forKey: defaultsKey + ".identityStrip") as? Bool ?? standard.identityStrip,
            mergedWeatherHandle: defaults.object(forKey: defaultsKey + ".mergedWeatherHandle") as? Bool
                ?? standard.mergedWeatherHandle
        )
    }

    func write(to defaults: UserDefaults = .standard) {
        defaults.set(side.rawValue, forKey: Self.defaultsKey + ".side")
        defaults.set(Double(width), forKey: Self.defaultsKey + ".width")
        defaults.set(edgeActivation, forKey: Self.defaultsKey + ".edgeActivation")
        defaults.set(dwell, forKey: Self.defaultsKey + ".dwell")
        defaults.set(identityStrip, forKey: Self.defaultsKey + ".identityStrip")
        defaults.set(mergedWeatherHandle, forKey: Self.defaultsKey + ".mergedWeatherHandle")
    }

    /// One-way, stamped, and only when v1 has nothing to say: the old opt-in edge hover becomes the deck's own
    /// activation preference. `drawer.pinned` is deliberately not copied — the deck still reads that same key,
    /// so moving it would be a no-op that could only lose the owner's choice.
    static func migrating(from defaults: UserDefaults = .standard) -> SideDeckConfig {
        var config = stored(in: defaults)
        guard !defaults.bool(forKey: migrationKey) else { return config }
        if defaults.object(forKey: "com.katikati.drawer.edgeHover") != nil {
            config.edgeActivation = defaults.bool(forKey: "com.katikati.drawer.edgeHover")
        }
        defaults.set(true, forKey: migrationKey)
        config.write(to: defaults)
        return config
    }
}

/// SD-8: the swap the Side Deck pane and the Edge Bars pane share. Each surface owns one edge, so the
/// control exchanges them in one write — a pane that moved only its own half could park both surfaces on
/// the same edge, which is the state `SideDeckConfig.Side` exists to prevent.
enum SideDeckEdgeSwap {
    struct Sides: Equatable, Sendable {
        var deck: SideDeckConfig.Side
        var edgeBar: EdgeSide
    }

    /// The deck takes the bar edge and the bar takes the deck edge. Applying it twice is the identity.
    static func exchange(_ sides: Sides) -> Sides {
        Sides(deck: sides.edgeBar == .left ? .left : .right,
              edgeBar: sides.deck == .left ? .left : .right)
    }
}
