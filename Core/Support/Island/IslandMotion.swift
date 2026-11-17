import Foundation

public enum IslandShapeTransition: String, CaseIterable, Hashable, Sendable {
    case appear
    case expand
    case pressExpand
    case appearExpand
    case swap
    case collapse
    case alertCollapse
    case collapseSplit
    case split
    case unsplit
    case dismiss
    case resize
}

public struct IslandDelayedSpring: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double
    public var delay: Double

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandCornerLeadTrailing: Equatable, Sendable {
    public var above: Double
    public var below: Double
}

public struct IslandCornerLead: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double
    public var delay: Double
    public var trailing: IslandCornerLeadTrailing?

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandTailLean: Equatable, Sendable {
    public var by: Double
    public var at: Double
    public var max: Double
    public var response: Double
    public var dampingFraction: Double

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }

    public static let off = IslandTailLean(by: 0, at: 0, max: 0, response: 0.3, dampingFraction: 1)
}

public struct IslandTailSettle: Equatable, Sendable {
    public var at: Double
    public var response: Double
    public var dampingFraction: Double

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }

    public static let off = IslandTailSettle(at: 0, response: 0.3, dampingFraction: 1)
}

public struct IslandTailLegs: Equatable, Sendable {
    public var lean: IslandTailLean
    public var settle: IslandTailSettle

    public static let off = IslandTailLegs(lean: .off, settle: .off)
}

public struct IslandShapeTail: Equatable, Sendable {
    public var width: IslandTailLegs
    public var height: IslandTailLegs
    public var top: IslandTailLegs

    public static let none = IslandShapeTail(width: .off, height: .off, top: .off)
}

public struct IslandAppearWide: Equatable, Sendable {
    public var from: Double
    public var to: Double
    public var spring: IslandSpringConfig
}

public struct IslandRetargetSprings: Equatable, Sendable {
    public var collapse: IslandSpringConfig
    public var alertCollapse: IslandSpringConfig
}

public struct IslandNeckTip: Equatable, Sendable {
    public var length: Double
    public var reach: Double
    public var until: Double
}

public struct IslandCollapseSplitVia: Equatable, Sendable {
    public var dip: Double
    public var at: Double
    public var response: Double
    public var dampingFraction: Double
    public var down: IslandSpringConfig

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandCollapseSplitRise: Equatable, Sendable {
    public var response: Double
    public var dampingFraction: Double
    public var delay: Double

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandCollapseSplitLift: Equatable, Sendable {
    public struct Back: Equatable, Sendable {
        public var at: Double
        public var response: Double
        public var dampingFraction: Double

        public var spring: IslandSpringConfig {
            IslandSpringConfig(response: response, dampingFraction: dampingFraction)
        }
    }

    public var by: Double
    public var response: Double
    public var dampingFraction: Double
    public var back: Back

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandCollapseSplitSpread: Equatable, Sendable {
    public struct RightPeel: Equatable, Sendable {
        public var at: Double
        public var to: Double
        public var response: Double
        public var dampingFraction: Double

        public var spring: IslandSpringConfig {
            IslandSpringConfig(response: response, dampingFraction: dampingFraction)
        }
    }

    public struct RightSettle: Equatable, Sendable {
        public var at: Double
        public var response: Double
        public var dampingFraction: Double

        public var spring: IslandSpringConfig {
            IslandSpringConfig(response: response, dampingFraction: dampingFraction)
        }
    }

    public struct RightBack: Equatable, Sendable {
        public var at: Double
        public var response: Double
        public var dampingFraction: Double

        public var spring: IslandSpringConfig {
            IslandSpringConfig(response: response, dampingFraction: dampingFraction)
        }
    }

    public var left: Double
    public var right: Double
    public var at: Double
    public var response: Double
    public var dampingFraction: Double
    public var rightPeel: RightPeel
    public var rightSettle: RightSettle
    public var rightBack: RightBack
    public var neckGap: Double
    public var neckPower: Double
    public var neckTip: IslandNeckTip?
    public var bubbleFrom: Double
    public var kick: Double?

    public var spring: IslandSpringConfig {
        IslandSpringConfig(response: response, dampingFraction: dampingFraction)
    }
}

public struct IslandBubbleMotion: Equatable, Sendable {
    public var split: IslandDelayedSpring
    public var collapseSplit: IslandDelayedSpring
    public var unsplit: IslandSpringConfig
    public var unsplitSlide: IslandSpringConfig
    public var unsplitAbsorb: Double
    public var absorbExpand: Double?
    public var absorbExpandCorner: IslandDelayedSpring?
    public var joinLead: Double?
    public var collapseSplitVia: IslandCollapseSplitVia
    public var collapseSplitRise: IslandCollapseSplitRise
    public var collapseSplitLift: IslandCollapseSplitLift
    public var collapseSplitSpread: IslandCollapseSplitSpread
}

public struct IslandIdleRelease: Equatable, Sendable {
    public var spring: IslandSpringConfig
    public var carry: Double
}

public struct IslandIdleWiden: Equatable, Sendable {
    public var by: Double
    public var rise: IslandSpringConfig
    public var hold: Double
    public var fall: IslandSpringConfig
}

public struct IslandPressMotion: Equatable, Sendable {
    public var down: IslandSpringConfig
    public var up: IslandSpringConfig
    public var swell: IslandSpringConfig
    public var bubbleSwell: IslandSpringConfig?
    public var swellTime: Double
    public var decide: Double
    public var release: IslandSpringConfig
    public var idleRelease: IslandIdleRelease?
    public var idleWiden: IslandIdleWiden?
    public var tapReturn: Double
    public var releaseReturn: Double?
    public var idleTapReturn: Double?
    public var holdReturn: Double
}

public struct IslandContentMotion: Equatable, Sendable {
    public var enter: IslandDelayedSpring
    public var exit: IslandDelayedSpring
    public var blur: Double
    public var enterBlur: Double
    public var exitBlur: Double
    public var scale: Double
    public var exitScale: Double
    public var fade: Double
    public var exitFade: Double
    public var bubbleDelay: Double
    public var trailingDelay: Double
    public var centerDelay: Double
    public var sharpen: Double
    public var bubbleScale: Double
    public var bubbleBlur: Double
    public var bubbleSharpen: Double
    public var leadingFade: Double
    public var skirt: Double

    public init(
        enter: IslandDelayedSpring,
        exit: IslandDelayedSpring,
        blur: Double,
        enterBlur: Double? = nil,
        exitBlur: Double? = nil,
        scale: Double,
        exitScale: Double = 0.85,
        fade: Double = 1.0,
        exitFade: Double = 1.0,
        bubbleDelay: Double = 0.0,
        trailingDelay: Double = 0.0,
        centerDelay: Double = 0.0,
        sharpen: Double = 1.0,
        bubbleScale: Double = 0.8,
        bubbleBlur: Double? = nil,
        bubbleSharpen: Double = 1.0,
        leadingFade: Double = 1.0,
        skirt: Double = 1.0
    ) {
        self.enter = enter
        self.exit = exit
        self.blur = blur
        self.enterBlur = enterBlur ?? blur
        self.exitBlur = exitBlur ?? blur
        self.scale = scale
        self.exitScale = exitScale
        self.fade = fade
        self.exitFade = exitFade
        self.bubbleDelay = bubbleDelay
        self.trailingDelay = trailingDelay
        self.centerDelay = centerDelay
        self.sharpen = sharpen
        self.bubbleScale = bubbleScale
        self.bubbleBlur = bubbleBlur ?? blur
        self.bubbleSharpen = bubbleSharpen
        self.leadingFade = leadingFade
        self.skirt = skirt
    }
}

public struct IslandGroupMotion: Equatable, Sendable {
    public var handoff: Double
    public var window: Double
}

public struct IslandKeylineMotion: Equatable, Sendable {
    public var dip: Double
    public var dipAt: Double
    public var backAt: Double
}

public struct IslandMotion: Equatable, Sendable {
    public var shape: [IslandShapeTransition: IslandSpringConfig]
    public var appearWide: IslandAppearWide?
    public var body: [IslandShapeTransition: IslandDelayedSpring]
    public var corner: [IslandShapeTransition: IslandDelayedSpring]
    public var cornerLead: [IslandShapeTransition: IslandCornerLead]
    public var viaIdle: [IslandShapeTransition: Double]
    public var collapseLift: Double
    public var tail: [IslandShapeTransition: IslandShapeTail]
    public var retarget: IslandRetargetSprings
    public var bubble: IslandBubbleMotion
    public var lag: [IslandShapeTransition: Double]
    public var contentTiming: [IslandShapeTransition: IslandContentMotion]
    public var press: IslandPressMotion
    public var longPress: Double
    public var longPressBubble: Double
    public var alertContentDelay: Double
    public var keyline: IslandKeylineMotion
    public var shadowRamp: IslandSpringConfig
    public var shadowRampPress: IslandSpringConfig
    public var group: IslandGroupMotion
    public var alertHold: Double
    public var alertHoldIdle: Double
    public var reducedDuration: Double

    public static let `default` = IslandMotion(
        shape: [
            .appear: IslandSpringConfig(response: 0.483, dampingFraction: 0.62),
            .expand: IslandSpringConfig(response: 0.517, dampingFraction: 0.824),
            .pressExpand: IslandSpringConfig(response: 0.387, dampingFraction: 0.792),
            .appearExpand: IslandSpringConfig(response: 0.54, dampingFraction: 0.811),
            .swap: IslandSpringConfig(response: 0.498, dampingFraction: 0.829),
            .collapse: IslandSpringConfig(response: 0.479, dampingFraction: 0.894),
            .alertCollapse: IslandSpringConfig(response: 0.535, dampingFraction: 0.84),
            .collapseSplit: IslandSpringConfig(response: 0.4, dampingFraction: 0.9),
            .split: IslandSpringConfig(response: 0.505, dampingFraction: 0.815),
            .unsplit: IslandSpringConfig(response: 0.487, dampingFraction: 0.794),
            .dismiss: IslandSpringConfig(response: 0.432, dampingFraction: 1.019),
            .resize: IslandSpringConfig(response: 0.5, dampingFraction: 0.82),
        ],
        appearWide: IslandAppearWide(
            from: 150.18,
            to: 178.25,
            spring: IslandSpringConfig(response: 0.47, dampingFraction: 0.74)
        ),
        body: [
            .appear: IslandDelayedSpring(response: 0.483, dampingFraction: 0.62, delay: 0),
            .expand: IslandDelayedSpring(response: 0.497, dampingFraction: 0.825, delay: 0),
            .pressExpand: IslandDelayedSpring(response: 0.388, dampingFraction: 0.791, delay: 0),
            .appearExpand: IslandDelayedSpring(response: 0.523, dampingFraction: 0.817, delay: 0),
            .swap: IslandDelayedSpring(response: 0.492, dampingFraction: 0.832, delay: 0.223),
            .collapse: IslandDelayedSpring(response: 0.453, dampingFraction: 0.928, delay: 0),
            .alertCollapse: IslandDelayedSpring(response: 0.481, dampingFraction: 0.908, delay: 0),
            .collapseSplit: IslandDelayedSpring(response: 0.481, dampingFraction: 0.884, delay: 0),
            .split: IslandDelayedSpring(response: 0.505, dampingFraction: 0.815, delay: 0),
            .unsplit: IslandDelayedSpring(response: 0.5, dampingFraction: 0.74, delay: 0),
            .dismiss: IslandDelayedSpring(response: 0.442, dampingFraction: 0.97, delay: 0),
            .resize: IslandDelayedSpring(response: 0.5, dampingFraction: 0.82, delay: 0),
        ],
        corner: [
            .appear: IslandDelayedSpring(response: 0.483, dampingFraction: 0.62, delay: 0),
            .expand: IslandDelayedSpring(response: 0.448, dampingFraction: 0.87, delay: 0.018),
            .pressExpand: IslandDelayedSpring(response: 0.32, dampingFraction: 0.831, delay: 0.019),
            .appearExpand: IslandDelayedSpring(response: 0.452, dampingFraction: 0.865, delay: 0.02),
            .swap: IslandDelayedSpring(response: 0.41, dampingFraction: 0.888, delay: 0.244),
            .collapse: IslandDelayedSpring(response: 0.449, dampingFraction: 0.94, delay: 0.01),
            .alertCollapse: IslandDelayedSpring(response: 0.47, dampingFraction: 0.86, delay: 0.009),
            .collapseSplit: IslandDelayedSpring(response: 0.36, dampingFraction: 0.865, delay: 0),
            .split: IslandDelayedSpring(response: 0.505, dampingFraction: 0.815, delay: 0),
            .unsplit: IslandDelayedSpring(response: 0.5, dampingFraction: 0.74, delay: 0),
            .dismiss: IslandDelayedSpring(response: 0.442, dampingFraction: 0.97, delay: 0),
            .resize: IslandDelayedSpring(response: 0.5, dampingFraction: 0.82, delay: 0),
        ],
        cornerLead: [
            .collapseSplit: IslandCornerLead(
                response: 0.481,
                dampingFraction: 0.884,
                delay: 0,
                trailing: IslandCornerLeadTrailing(above: 60.0, below: 50.0)
            )
        ],
        viaIdle: [
            .appear: 0,
            .expand: 0,
            .pressExpand: 0,
            .appearExpand: 0,
            .swap: 0.223,
            .collapse: 0.311,
            .alertCollapse: 0.29,
            .collapseSplit: 0,
            .split: 0.215,
            .unsplit: 0.203,
            .dismiss: 0,
            .resize: 0,
        ],
        collapseLift: 1.4,
        tail: [
            .appear: IslandShapeTail(
                width: IslandTailLegs(lean: .off, settle: IslandTailSettle(at: 0.28, response: 0.332, dampingFraction: 1)),
                height: .off,
                top: .off
            ),
            .expand: .none,
            .pressExpand: .none,
            .appearExpand: .none,
            .swap: .none,
            .collapse: IslandShapeTail(
                width: IslandTailLegs(
                    lean: IslandTailLean(by: 0.025, at: 0.396, max: 8, response: 0.3, dampingFraction: 0.866),
                    settle: IslandTailSettle(at: 0.608, response: 0.409, dampingFraction: 1)
                ),
                height: IslandTailLegs(
                    lean: IslandTailLean(by: 0.019, at: 0.242, max: 4, response: 0.287, dampingFraction: 0.724),
                    settle: IslandTailSettle(at: 0.56, response: 0.372, dampingFraction: 1)
                ),
                top: IslandTailLegs(lean: .off, settle: IslandTailSettle(at: 0.454, response: 0.28, dampingFraction: 1))
            ),
            .alertCollapse: IslandShapeTail(
                width: IslandTailLegs(
                    lean: IslandTailLean(by: 0.017, at: 0.366, max: 8, response: 0.357, dampingFraction: 0.704),
                    settle: IslandTailSettle(at: 0.652, response: 0.351, dampingFraction: 1)
                ),
                height: IslandTailLegs(
                    lean: IslandTailLean(by: 0.02, at: 0.248, max: 4, response: 0.318, dampingFraction: 0.718),
                    settle: IslandTailSettle(at: 0.548, response: 0.396, dampingFraction: 1)
                ),
                top: IslandTailLegs(lean: .off, settle: IslandTailSettle(at: 0.569, response: 0.15, dampingFraction: 1))
            ),
            .collapseSplit: IslandShapeTail(
                width: .off,
                height: IslandTailLegs(
                    lean: IslandTailLean(by: 0.026, at: 0.308, max: 4, response: 0.477, dampingFraction: 0.838),
                    settle: IslandTailSettle(at: 0.55, response: 0.383, dampingFraction: 1)
                ),
                top: IslandTailLegs(lean: .off, settle: IslandTailSettle(at: 0.489, response: 0.349, dampingFraction: 1))
            ),
            .split: .none,
            .unsplit: IslandShapeTail(
                width: IslandTailLegs(lean: .off, settle: IslandTailSettle(at: 0.646, response: 0.445, dampingFraction: 1)),
                height: .off,
                top: .off
            ),
            .dismiss: IslandShapeTail(
                width: IslandTailLegs(
                    lean: IslandTailLean(by: 0.042, at: 0.15, max: 4, response: 0.46, dampingFraction: 0.728),
                    settle: IslandTailSettle(at: 0.548, response: 0.4, dampingFraction: 1)
                ),
                height: .off,
                top: .off
            ),
            .resize: .none,
        ],
        retarget: IslandRetargetSprings(
            collapse: IslandSpringConfig(response: 0.447, dampingFraction: 1),
            alertCollapse: IslandSpringConfig(response: 0.527, dampingFraction: 0.837)
        ),
        bubble: IslandBubbleMotion(
            split: IslandDelayedSpring(response: 0.376, dampingFraction: 0.811, delay: 0.345),
            collapseSplit: IslandDelayedSpring(response: 0.3, dampingFraction: 0.8, delay: 0.24),
            unsplit: IslandSpringConfig(response: 0.25, dampingFraction: 1),
            unsplitSlide: IslandSpringConfig(response: 0.42, dampingFraction: 1),
            unsplitAbsorb: 0.205,
            absorbExpand: 0.222,
            absorbExpandCorner: IslandDelayedSpring(response: 0.49, dampingFraction: 0.826, delay: 0.001),
            joinLead: 0.012,
            collapseSplitVia: IslandCollapseSplitVia(
                dip: 24,
                at: 0.16,
                response: 0.22,
                dampingFraction: 1,
                down: IslandSpringConfig(response: 0.41, dampingFraction: 0.55)
            ),
            collapseSplitRise: IslandCollapseSplitRise(response: 0.12, dampingFraction: 1, delay: 0.1),
            collapseSplitLift: IslandCollapseSplitLift(
                by: 1.139,
                response: 0.475,
                dampingFraction: 0.581,
                back: IslandCollapseSplitLift.Back(at: 0.318, response: 0.485, dampingFraction: 0.878)
            ),
            collapseSplitSpread: IslandCollapseSplitSpread(
                left: 4.903,
                right: 5.467,
                at: 0.566,
                response: 0.457,
                dampingFraction: 0.816,
                rightPeel: IslandCollapseSplitSpread.RightPeel(at: 0.144, to: 3.431, response: 0.354, dampingFraction: 0.826),
                rightSettle: IslandCollapseSplitSpread.RightSettle(at: 0.41, response: 0.149, dampingFraction: 0.912),
                rightBack: IslandCollapseSplitSpread.RightBack(at: 0.464, response: 0.5, dampingFraction: 1),
                neckGap: 3.28,
                neckPower: 0.2,
                neckTip: IslandNeckTip(length: 1.4, reach: 2.4, until: 0.49),
                bubbleFrom: 12,
                kick: 3
            )
        ),
        lag: [
            .appear: 0,
            .expand: 0,
            .pressExpand: 0,
            .appearExpand: 0,
            .swap: 0,
            .collapse: 0,
            .alertCollapse: 0,
            .collapseSplit: 0.035,
            .split: 0,
            .unsplit: 0,
            .dismiss: 0,
            .resize: 0,
        ],
        contentTiming: [
            .appear: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.45, dampingFraction: 1, delay: 0.07),
                exit: IslandDelayedSpring(response: 0.12, dampingFraction: 1, delay: 0),
                blur: 5.5,
                enterBlur: 12,
                scale: 0.8,
                sharpen: 1.2,
                leadingFade: 2.8
            ),
            .expand: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.3, dampingFraction: 1, delay: 0.07),
                exit: IslandDelayedSpring(response: 0.24, dampingFraction: 1, delay: 0.01),
                blur: 9.5,
                enterBlur: 17,
                scale: 0.9,
                fade: 1.2,
                exitFade: 0.5,
                bubbleScale: 0.9,
                bubbleBlur: 14
            ),
            .pressExpand: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.36, dampingFraction: 1, delay: 0.056),
                exit: IslandDelayedSpring(response: 0.28, dampingFraction: 1, delay: 0.026),
                blur: 10.5,
                enterBlur: 12,
                exitBlur: 9,
                scale: 0.9,
                fade: 1.0,
                exitFade: 0.65,
                sharpen: 0.85,
                bubbleScale: 0.9,
                bubbleBlur: 16
            ),
            .appearExpand: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.36, dampingFraction: 1, delay: 0.02),
                exit: IslandDelayedSpring(response: 0.06, dampingFraction: 1, delay: 0),
                blur: 8,
                enterBlur: 12,
                scale: 0.6,
                fade: 1.8,
                sharpen: 0.85,
                bubbleScale: 0.6,
                bubbleBlur: 12,
                skirt: 0.5
            ),
            .swap: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.36, dampingFraction: 1, delay: 0.252),
                exit: IslandDelayedSpring(response: 0.33, dampingFraction: 1, delay: 0),
                blur: 8,
                enterBlur: 12,
                scale: 0.6,
                exitScale: 1.0,
                fade: 1.0,
                exitFade: 1.3,
                bubbleScale: 0.6,
                bubbleBlur: 10,
                skirt: 0.5
            ),
            .collapse: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.5, dampingFraction: 1, delay: 0.36),
                exit: IslandDelayedSpring(response: 0.22, dampingFraction: 1, delay: 0.017),
                blur: 7.75,
                enterBlur: 8.3,
                scale: 0.9,
                fade: 2.0,
                exitFade: 0.7,
                sharpen: 1.1,
                bubbleScale: 0.9,
                bubbleBlur: 8.3,
                bubbleSharpen: 1.6
            ),
            .alertCollapse: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.42, dampingFraction: 1, delay: 0.39),
                exit: IslandDelayedSpring(response: 0.3, dampingFraction: 0.8, delay: 0.03),
                blur: 10,
                enterBlur: 6.5,
                scale: 0.9,
                fade: 1.9,
                exitFade: 0.8,
                sharpen: 1.1,
                bubbleScale: 0.9,
                bubbleBlur: 8.3,
                bubbleSharpen: 1.6
            ),
            .collapseSplit: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.45, dampingFraction: 0.8, delay: 0.145),
                exit: IslandDelayedSpring(response: 0.03, dampingFraction: 1, delay: 0),
                blur: 7,
                enterBlur: 7,
                scale: 0.7,
                fade: 1.0,
                exitFade: 1.0,
                bubbleDelay: -0.065,
                trailingDelay: 0.02,
                sharpen: 2.0,
                bubbleScale: 1.5,
                bubbleBlur: 36,
                bubbleSharpen: 2.3,
                leadingFade: 0.6,
                skirt: 0.25
            ),
            .split: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.36, dampingFraction: 1, delay: 0.31),
                exit: IslandDelayedSpring(response: 0.3, dampingFraction: 1, delay: 0),
                blur: 5.5,
                enterBlur: 8,
                exitBlur: 7,
                scale: 0.8,
                exitScale: 0.5,
                fade: 0.8,
                exitFade: 0.8,
                bubbleDelay: -0.115,
                trailingDelay: 0.02,
                bubbleScale: 0.8,
                bubbleBlur: 15,
                bubbleSharpen: 0.85,
                leadingFade: 0.7,
                skirt: 0
            ),
            .unsplit: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.3, dampingFraction: 1, delay: 0.26),
                exit: IslandDelayedSpring(response: 0.26, dampingFraction: 1, delay: 0),
                blur: 6.5,
                enterBlur: 9,
                exitBlur: 4.5,
                scale: 0.8,
                exitFade: 0.8,
                trailingDelay: 0.03,
                sharpen: 0.75,
                bubbleBlur: 8,
                leadingFade: 1.3,
                skirt: 2
            ),
            .dismiss: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.2, dampingFraction: 1, delay: 0),
                exit: IslandDelayedSpring(response: 0.2, dampingFraction: 1, delay: 0),
                blur: 4.5,
                enterBlur: 6,
                exitBlur: 12,
                scale: 0.8,
                exitScale: 1.0,
                fade: 0.8,
                exitFade: 0.6,
                bubbleScale: 0.9,
                bubbleBlur: 6,
                skirt: 1
            ),
            .resize: IslandContentMotion(
                enter: IslandDelayedSpring(response: 0.3, dampingFraction: 1, delay: 0.08),
                exit: IslandDelayedSpring(response: 0.16, dampingFraction: 1, delay: 0),
                blur: 5.5,
                enterBlur: 8,
                scale: 0.85,
                bubbleScale: 0.85,
                bubbleBlur: 8
            ),
        ],
        press: IslandPressMotion(
            down: IslandSpringConfig(response: 0.45, dampingFraction: 1),
            up: IslandSpringConfig(response: 0.36, dampingFraction: 0.62),
            swell: IslandSpringConfig(response: 0.803, dampingFraction: 0.641),
            bubbleSwell: IslandSpringConfig(response: 0.509, dampingFraction: 0.05),
            swellTime: 0.22,
            decide: 0.1,
            release: IslandSpringConfig(response: 0.3, dampingFraction: 1.5),
            idleRelease: IslandIdleRelease(
                spring: IslandSpringConfig(response: 0.53, dampingFraction: 0.77),
                carry: 0.03
            ),
            idleWiden: IslandIdleWiden(
                by: 1.12,
                rise: IslandSpringConfig(response: 0.425, dampingFraction: 0.925),
                hold: 0.57,
                fall: IslandSpringConfig(response: 0.3, dampingFraction: 1.15)
            ),
            tapReturn: 0.22,
            releaseReturn: 0.17,
            idleTapReturn: 0.2,
            holdReturn: 0.236
        ),
        longPress: 0.216,
        longPressBubble: 0.224,
        alertContentDelay: 0.12,
        keyline: IslandKeylineMotion(dip: 0.15, dipAt: 0.5, backAt: 1.1),
        shadowRamp: IslandSpringConfig(response: 0.36, dampingFraction: 1),
        shadowRampPress: IslandSpringConfig(response: 0.507, dampingFraction: 0.839),
        group: IslandGroupMotion(handoff: 1.445, window: 6.014),
        alertHold: 5.975,
        alertHoldIdle: 5.969,
        reducedDuration: 0.2
    )
}
