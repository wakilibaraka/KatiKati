import AppKit
import Combine
import CoreGraphics
import QuartzCore
import SwiftUI

/// Drives closed-form `IslandShapeAnimation` in sync with `NSScreen` / `NSView` ProMotion display
/// refresh (`120 Hz` on M1–M5 MacBook Pros), and stops the display link completely at rest (`0%` idle CPU).
@MainActor
final class IslandSurfaceDriver: ObservableObject {
    let store: IslandStore
    let clock: IslandClock

    @Published private(set) var snapshot: IslandSnapshot
    @Published private(set) var scene: IslandScene
    @Published private(set) var frame: IslandFrameGeometry
    @Published private(set) var currentTransition: IslandShapeTransition = .resize
    @Published private(set) var keylineDimMultiplier: Double = 1.0
    @Published var isShowingBentoSuite: Bool = false

    /// 1:1 vertical pull-down drag offset during touch/trackpad interaction (`0` when released).
    @Published var dragPullOffset: Double = 0
    @Published var touchMode: Bool = false
    @Published var nonNotchIdleBehavior: IslandNonNotchIdleBehavior = .compactPill
    @Published var keylineSetting: IslandKeylineSetting = .auto
    @Published var topology: IslandDisplayTopology

    var metrics: IslandMetrics {
        didSet {
            if metrics != oldValue {
                retargetCurrent(instant: true)
            }
        }
    }
    var motion: IslandMotion = .default
    var stageWidth: Double {
        didSet {
            if abs(stageWidth - oldValue) > 0.5 {
                refreshFrame(at: currentTimeSeconds())
            }
        }
    }
    var reduceMotion: Bool = false
    var measure: IslandContentMeasure = .empty {
        didSet {
            if measure != oldValue {
                retargetCurrent(instant: false)
            }
        }
    }

    private var shapeAnimation: IslandShapeAnimation
    private var previousKind: IslandPresentationKind = .idle
    private var previousPrimaryId: String?
    private var lastCollapseStartedAt: Double?
    private var lastChangeId: Int = -1
    private var unsubscribeStore: (() -> Void)?

    private final class DisplayLinkProxy: NSObject {
        weak var owner: IslandSurfaceDriver?
        init(owner: IslandSurfaceDriver) { self.owner = owner }
        @objc func step(_ sender: CADisplayLink) {
            Task { @MainActor [weak owner = self.owner] in
                owner?.tickDisplayLink()
            }
        }
    }

    private var displayLink: CADisplayLink?
    private var linkProxy: DisplayLinkProxy?
    private weak var anchorView: NSView?

    init(
        store: IslandStore? = nil,
        clock: IslandClock = WallIslandClock(),
        topology: IslandDisplayTopology? = nil,
        stageWidth: Double = 520.0
    ) {
        let resolvedClock = clock
        let resolvedStore = store ?? IslandStore(clock: resolvedClock)
        let defaultTopology = topology ?? IslandDisplayTopology.resolve(
            screenWidth: 1728,
            screenHeight: 1117,
            safeAreaTop: 38,
            auxLeftWidth: 760,
            auxRightWidth: 760,
            menuBarHeight: 38,
            isBuiltinDisplay: true,
            isOLED: false,
            supportsMultiTouch: false
        )
        let initialMetrics = defaultTopology.islandMetrics(nonNotchBehavior: .compactPill, touchEnabled: false)
        let initialSnapshot = resolvedStore.snapshot
        let initialScene = deriveIslandScene(initialSnapshot)
        let initialTarget = IslandChoreography.shapeTarget(
            kind: initialScene.presentation,
            measure: .empty,
            screenWidth: IslandChoreography.screenWidth(containerWidth: stageWidth, metrics: initialMetrics),
            metrics: initialMetrics
        )
        let initialAnim = IslandShapeAnimation(target: initialTarget, metrics: initialMetrics)

        self.clock = resolvedClock
        self.store = resolvedStore
        self.topology = defaultTopology
        self.metrics = initialMetrics
        self.stageWidth = stageWidth
        self.snapshot = initialSnapshot
        self.scene = initialScene
        self.shapeAnimation = initialAnim
        self.previousKind = initialScene.presentation
        self.previousPrimaryId = initialScene.primary?.id
        self.lastChangeId = initialSnapshot.changeId
        self.frame = IslandChoreography.frameAt(
            initialAnim,
            at: resolvedClock.nowMs() / 1000.0,
            stageWidth: stageWidth,
            metrics: initialMetrics
        )

        self.unsubscribeStore = resolvedStore.subscribe { [weak self] newSnapshot in
            Task { @MainActor [weak self] in
                self?.handleStoreSnapshot(newSnapshot)
            }
        }
    }

    deinit {
        displayLink?.invalidate()
        unsubscribeStore?()
    }

    /// Binds this driver to a backing AppKit `NSView` so its `CADisplayLink` tracks the active display's ProMotion rate.
    func attach(to view: NSView) {
        guard anchorView !== view else { return }
        anchorView = view
        if displayLink != nil {
            stopDisplayLink()
            ensureDisplayLinkRunning()
        }
    }

    func updateDisplayTopology(_ nextTopology: IslandDisplayTopology, touchEnabled: Bool, nonNotchBehavior: IslandNonNotchIdleBehavior) {
        topology = nextTopology
        touchMode = touchEnabled
        nonNotchIdleBehavior = nonNotchBehavior
        metrics = nextTopology.islandMetrics(nonNotchBehavior: nonNotchBehavior, touchEnabled: touchEnabled)
    }

    func updateContentMeasure(_ nextMeasure: IslandContentMeasure) {
        measure = nextMeasure
    }

    private func currentTimeSeconds() -> Double {
        clock.nowMs() / 1000.0
    }

    private func effectiveMotionMode(instantOverride: Bool = false) -> IslandMotionMode {
        if instantOverride || snapshot.instant { return .instant }
        return reduceMotion ? .reduced : .spring
    }

    private func handleStoreSnapshot(_ nextSnapshot: IslandSnapshot) {
        let prevSnapshot = snapshot
        snapshot = nextSnapshot
        let nextScene = deriveIslandScene(nextSnapshot)
        scene = nextScene
        let t = nextSnapshot.changedAtMs / 1000.0

        if nextSnapshot.expanded?.id == nil && isShowingBentoSuite {
            isShowingBentoSuite = false
        }

        // Handle bubble merge lead time ahead of long-press collapse into expanded card.
        if prevSnapshot.joiningAtMs != nextSnapshot.joiningAtMs {
            let idle = IslandChoreography.shapeTarget(
                kind: .idle,
                measure: measure,
                screenWidth: stageWidth,
                metrics: metrics
            )
            let restTarget = IslandChoreography.shapeTarget(
                kind: nextScene.presentation,
                measure: measure,
                screenWidth: IslandChoreography.screenWidth(containerWidth: stageWidth, metrics: metrics),
                metrics: metrics
            )
            IslandChoreography.leadJoin(
                shapeAnimation,
                joinAt: nextSnapshot.joiningAtMs.map { $0 / 1000.0 },
                at: clock.nowMs() / 1000.0,
                idleRight: idle.right,
                restLeft: restTarget.bubbleLeft,
                motion: motion,
                mode: effectiveMotionMode()
            )
        }

        if prevSnapshot.pressed != nextSnapshot.pressed {
            IslandChoreography.retargetPress(
                shapeAnimation,
                pressed: nextSnapshot.pressed,
                style: .swell,
                at: clock.nowMs() / 1000.0,
                motion: motion,
                metrics: metrics,
                mode: effectiveMotionMode(),
                idle: nextScene.presentation == .idle
            )
        }

        if nextSnapshot.changeId != lastChangeId {
            lastChangeId = nextSnapshot.changeId
            let toKind = nextScene.presentation
            let primaryChanged = nextScene.primary?.id != previousPrimaryId
            let transition = IslandChoreography.shapeTransition(
                from: previousKind,
                to: toKind,
                swap: primaryChanged && previousPrimaryId != nil && nextScene.primary != nil,
                swelling: prevSnapshot.pressed != nil,
                alert: prevSnapshot.expanded?.reason == .alert
            )
            currentTransition = transition
            let lag = motion.lag[transition] ?? 0
            let t0 = t + lag
            if transition == .collapse || transition == .alertCollapse || transition == .collapseSplit {
                lastCollapseStartedAt = t0
            }

            let screenW = IslandChoreography.screenWidth(containerWidth: stageWidth, metrics: metrics)
            let idleTarget = IslandChoreography.shapeTarget(kind: .idle, measure: measure, screenWidth: screenW, metrics: metrics)
            let target = IslandChoreography.shapeTarget(kind: toKind, measure: measure, screenWidth: screenW, metrics: metrics)

            IslandChoreography.retargetShape(
                shapeAnimation,
                transition: transition,
                target: target,
                idle: idleTarget,
                at: t0,
                motion: motion,
                mode: effectiveMotionMode()
            )
            previousKind = toKind
            previousPrimaryId = nextScene.primary?.id
        }

        refreshFrame(at: clock.nowMs() / 1000.0)
        ensureDisplayLinkRunning()
    }

    private func retargetCurrent(instant: Bool) {
        let t = currentTimeSeconds()
        let screenW = IslandChoreography.screenWidth(containerWidth: stageWidth, metrics: metrics)
        let idleTarget = IslandChoreography.shapeTarget(kind: .idle, measure: measure, screenWidth: screenW, metrics: metrics)
        let target = IslandChoreography.shapeTarget(kind: scene.presentation, measure: measure, screenWidth: screenW, metrics: metrics)
        IslandChoreography.retargetShape(
            shapeAnimation,
            transition: .resize,
            target: target,
            idle: idleTarget,
            at: t,
            motion: motion,
            mode: effectiveMotionMode(instantOverride: instant)
        )
        refreshFrame(at: t)
        if !instant {
            ensureDisplayLinkRunning()
        }
    }

    func finishInteractivePull(translationY: Double, velocityY: Double) {
        let expanded = scene.presentation == .expanded
        let shouldCommit = IslandTouchHitPolicy.shouldCommitPull(
            translationY: translationY,
            velocityY: velocityY,
            isExpanded: expanded,
            touchEnabled: touchMode
        )
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            dragPullOffset = 0
        }
        if shouldCommit {
            if expanded {
                store.collapse()
            } else {
                store.expand()
            }
        }
    }

    private func ensureDisplayLinkRunning() {
        let nowSec = currentTimeSeconds()
        let dimSettled = lastCollapseStartedAt.map { (nowSec - $0) >= motion.keyline.backAt } ?? true
        if shapeAnimation.isAtRest(at: nowSec) && dimSettled && abs(dragPullOffset) < 0.1 {
            stopDisplayLink()
            return
        }
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy(owner: self)
        linkProxy = proxy
        let link: CADisplayLink?
        if let anchorView {
            link = anchorView.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        } else if let mainScreen = NSScreen.main {
            link = mainScreen.displayLink(target: proxy, selector: #selector(DisplayLinkProxy.step(_:)))
        } else {
            link = nil
        }
        if let link {
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        linkProxy = nil
    }

    private func tickDisplayLink() {
        let nowSec = currentTimeSeconds()
        refreshFrame(at: nowSec)
        let dimSettled = lastCollapseStartedAt.map { (nowSec - $0) >= motion.keyline.backAt } ?? true
        if shapeAnimation.isAtRest(at: nowSec) && dimSettled && abs(dragPullOffset) < 0.1 {
            lastCollapseStartedAt = nil
            stopDisplayLink()
        }
    }

    private func refreshFrame(at t: Double) {
        frame = IslandChoreography.frameAt(
            shapeAnimation,
            at: t,
            stageWidth: stageWidth,
            metrics: metrics
        )
        if let collapseStart = lastCollapseStartedAt {
            let elapsed = t - collapseStart
            keylineDimMultiplier = islandKeylineDimMultiplier(elapsedSeconds: elapsed, motion: motion.keyline)
        } else {
            keylineDimMultiplier = 1.0
        }
    }
}
