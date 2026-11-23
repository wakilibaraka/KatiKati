import CoreGraphics
import Foundation

/// 任务条横向滚动的纯决策：把一个滚动事件折算成条内的横向位移。
///
/// 为什么需要它：任务条装不下时靠横向 `ScrollView` 滚，而横向 ScrollView **对垂直滑动本来就
/// 不响应**。原来只接管离散滚轮（`hasPreciseScrollingDeltas == false`），于是触控板、妙控鼠标、
/// 开了平滑滚动的鼠标（Logitech Options 等）——它们发的都是连续事件，见
/// `Docs/27-product-decisions.md`「鼠标滚轮反转」——垂直滑一律石沉大海（issue #14）。
///
/// 副作用（读 `NSEvent`、写 `NSScrollView`）留在 `DockStripView` 的拦截视图里。
enum StripWheelScroll {
    /// 离散滚轮一格换算成多少 pt。已定稿的手感，改动前后必须一致。
    static let wheelSpeed: CGFloat = 56
    /// 离散滚轮单次步长上限。快速甩轮时的 delta 可以很大，不封顶会一下飞到头。
    static let maxStep: CGFloat = 120

    /// 从 `NSEvent` 提炼出来的纯输入。
    struct Input: Equatable {
        var deltaX: CGFloat
        var deltaY: CGFloat
        /// `NSEvent.hasPreciseScrollingDeltas`：true = 连续事件（触控板 / 妙控 / 平滑滚轮）。
        var hasPreciseDeltas: Bool
        /// `NSEvent.isDirectionInvertedFromDevice`：即系统「自然滚动」对该设备是否生效。
        /// **取自事件本身而不是读 `com.apple.swipescrolldirection`**：逐设备正确，
        /// 而且事件热路径上不再有 UserDefaults 读取。
        var isDirectionInverted: Bool
        /// True when only the Option modifier is held (`⌥+Scroll` time travel scrub).
        var isOptionPressed: Bool

        init(deltaX: CGFloat, deltaY: CGFloat, hasPreciseDeltas: Bool, isDirectionInverted: Bool,
             isOptionPressed: Bool = false) {
            self.deltaX = deltaX
            self.deltaY = deltaY
            self.hasPreciseDeltas = hasPreciseDeltas
            self.isDirectionInverted = isDirectionInverted
            self.isOptionPressed = isOptionPressed
        }
    }

    /// 条内要走的横向位移（pt，正 = 往后翻）；`nil` = 本事件不接管，原样交给底下的 `NSScrollView`。
    static func horizontalStep(for input: Input) -> CGFloat? {
        guard input.deltaY != 0 else { return nil }
        // **横向为主的手势必须放行**：触控板左右滑、妙控鼠标左右滑现在就由 NSScrollView
        // 原生处理，带惯性和橡皮筋；接管过来只会更差。
        guard abs(input.deltaY) > abs(input.deltaX) else { return nil }

        let sign: CGFloat = input.isDirectionInverted ? -1 : 1
        if input.hasPreciseDeltas {
            // 连续事件的 delta 本来就是点数，1:1 即可；再乘 wheelSpeed 会飞出去。
            // 也不封顶——惯性阶段的大 delta 正是它该有的手感。
            let step = sign * input.deltaY
            return step == 0 ? nil : step
        }
        let raw = sign * input.deltaY * wheelSpeed
        let step = min(max(raw, -maxStep), maxStep)
        return step == 0 ? nil : step
    }
}

/// Slice E, ported as behaviour from OpenTaskbar (MIT, NOTICE): a vertical wheel over an app card cycles that
/// app's windows, over empty bar it turns the volume, and the strip's own horizontal overflow scroll keeps
/// priority exactly as before.
enum WheelTarget: Equatable, Sendable {
    case emptyBar
    /// A window card, or the card that stands for an app's grouped windows.
    case appCard(bundleID: String)
    /// Folder chips, the drawer, the trash, separators — not the bar's own surface.
    case otherSurface
}

enum WheelDirection: Equatable, Sendable {
    case previous
    case next
}

enum WheelAction: Equatable, Sendable {
    case ignore
    /// Pan the strip. The interceptor owns the `NSScrollView`, so this one never leaves the view.
    case scrollStrip(by: CGFloat)
    case cycleWindows(bundleID: String, direction: WheelDirection)
    case volume(delta: Float)
    /// Option+Scroll scrubs the shared 25-event Time Travel ring buffer.
    case timeTravel(delta: Int)
}

enum WheelActionMap {
    /// One notch on a discrete wheel. The strip asks for small steps so a fast spin cannot slam the volume.
    static let volumeStepPerNotch: Float = 0.05
    /// Trackpads and smooth-scrolling mice send many events per gesture; each one moves less.
    static let preciseVolumeStep: Float = 0.02

    /// The decision table. Option+Scroll triggers Time Travel; otherwise horizontal overflow panning keeps
    /// priority and only events the strip cannot pan reach card/volume rules.
    static func action(for input: StripWheelScroll.Input,
                       target: WheelTarget,
                       stripOverflows: Bool) -> WheelAction {
        if input.isOptionPressed, input.deltaY != 0, abs(input.deltaY) >= abs(input.deltaX) {
            return .timeTravel(delta: input.deltaY > 0 ? -1 : 1)
        }
        if stripOverflows, let step = StripWheelScroll.horizontalStep(for: input) {
            return .scrollStrip(by: step)
        }
        guard input.deltaY != 0, abs(input.deltaY) > abs(input.deltaX) else { return .ignore }
        let sign: CGFloat = input.isDirectionInverted ? -1 : 1
        let travel = sign * input.deltaY
        guard travel != 0 else { return .ignore }

        switch target {
        case .appCard(let bundleID):
            return .cycleWindows(bundleID: bundleID, direction: travel > 0 ? .next : .previous)
        case .emptyBar:
            let step = input.hasPreciseDeltas ? preciseVolumeStep : volumeStepPerNotch
            return .volume(delta: travel > 0 ? step : -step)
        case .otherSurface:
            return .ignore
        }
    }
}

/// Slice E: which window a wheel step lands on. Wraps in both directions and keeps `ids` order, so the strip's
/// own left-to-right order is the cycle order.
enum WheelWindowCycle {
    static func next(ids: [String], front: String?, direction: WheelDirection) -> String? {
        guard !ids.isEmpty else { return nil }
        guard ids.count > 1 else { return ids[0] }
        let index = front.flatMap { ids.firstIndex(of: $0) }
        switch direction {
        case .next:
            let base = index ?? -1
            return ids[(base + 1 + ids.count) % ids.count]
        case .previous:
            let base = index ?? 0
            return ids[(base - 1 + ids.count) % ids.count]
        }
    }
}

/// Accumulates continuous precise-scroll volume deltas and rate-limits volume steps to once per 60 ms,
/// matching `ControlCenterScroll` so a single trackpad swipe never slams the system volume.
enum WheelVolumeThrottle {
    static let stepInterval: TimeInterval = 0.06
    static let preciseThreshold: Float = 0.05

    struct State: Equatable, Sendable {
        var accumulatedDelta: Float = 0
        var lastStepAt: Date = .distantPast
    }

    static func consume(delta: Float, state: inout State, now: Date = Date()) -> Float? {
        guard delta != 0 else { return nil }
        let isPrecise = abs(delta) < WheelActionMap.volumeStepPerNotch
        if !isPrecise {
            guard now.timeIntervalSince(state.lastStepAt) >= stepInterval else { return nil }
            state.lastStepAt = now
            state.accumulatedDelta = 0
            return delta
        }
        state.accumulatedDelta += delta
        guard abs(state.accumulatedDelta) >= preciseThreshold,
              now.timeIntervalSince(state.lastStepAt) >= stepInterval else {
            return nil
        }
        let step: Float = state.accumulatedDelta > 0 ? WheelActionMap.preciseVolumeStep : -WheelActionMap.preciseVolumeStep
        state.accumulatedDelta = 0
        state.lastStepAt = now
        return step
    }
}

// MARK: - Multi-Page Widget Cycling & Trackpad Detent (Slice DO-7)

/// Pure page-index cycling and persisted-index clamping for multi-page in-dock widgets.
enum WidgetPageCycle {
    static func clamped(_ page: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(page, 0), count - 1)
    }

    static func next(current: Int, count: Int, delta: Int = 1) -> Int {
        guard count > 1 else { return 0 }
        let safe = clamped(current, count: count)
        return ((safe + delta) % count + count) % count
    }
}

enum WidgetPageScrollPhase: Equatable, Sendable {
    case began, changed, ended, cancelled, discrete
}

struct WidgetPageScrollInput: Equatable, Sendable {
    var deltaX: CGFloat
    var deltaY: CGFloat
    var hasPreciseDeltas: Bool
    var isMomentum: Bool
    var phase: WidgetPageScrollPhase
    var timestamp: TimeInterval
}

/// Phase-aware scroll detent for multi-page widgets: ignores trackpad momentum and locks at 1 page per swipe.
enum WidgetPageScrollEngine {
    static let preciseDetentThreshold: CGFloat = 28
    static let discreteCooldown: TimeInterval = 0.22

    struct State: Equatable, Sendable {
        var accumulated: CGFloat = 0
        var lockedForGesture: Bool = false
        var lastDiscreteStepAt: TimeInterval = -10
    }

    static func consume(_ input: WidgetPageScrollInput, state: inout State) -> Int? {
        guard !input.isMomentum else { return nil }
        switch input.phase {
        case .began:
            state.accumulated = 0
            state.lockedForGesture = false
        case .ended, .cancelled:
            state.accumulated = 0
            state.lockedForGesture = false
            return nil
        case .changed, .discrete:
            break
        }
        let delta = abs(input.deltaY) >= abs(input.deltaX) ? input.deltaY : input.deltaX
        guard delta != 0 else { return nil }

        if !input.hasPreciseDeltas || input.phase == .discrete {
            guard input.timestamp - state.lastDiscreteStepAt >= discreteCooldown else { return nil }
            state.lastDiscreteStepAt = input.timestamp
            return delta < 0 ? 1 : -1
        }
        guard !state.lockedForGesture else { return nil }
        state.accumulated += delta
        guard abs(state.accumulated) >= preciseDetentThreshold else { return nil }
        let step = state.accumulated < 0 ? 1 : -1
        state.lockedForGesture = true
        state.accumulated = 0
        return step
    }
}
