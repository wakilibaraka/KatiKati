import Foundation

/// Abstract clock used by `IslandStore` so wall-clock Dispatch/RunLoop scheduling and deterministic
/// simulated unit-test clocks share the exact same queue semantics.
public protocol IslandClock: AnyObject {
    func nowMs() -> Double
    @discardableResult
    func schedule(atMs: Double, _ callback: @escaping (_ dueMs: Double) -> Void) -> () -> Void
}

public final class ManualIslandClock: IslandClock {
    private struct ScheduledTimer {
        let id: Int
        let atMs: Double
        let callback: (Double) -> Void
        var cancelled = false
    }

    private var currentMs: Double
    private var nextId = 0
    private var timers: [ScheduledTimer] = []

    public init(initialMs: Double = 0) {
        self.currentMs = initialMs
    }

    public func nowMs() -> Double {
        currentMs
    }

    @discardableResult
    public func schedule(atMs: Double, _ callback: @escaping (Double) -> Void) -> () -> Void {
        let id = nextId
        nextId += 1
        let item = ScheduledTimer(id: id, atMs: atMs, callback: callback)
        timers.append(item)
        return { [weak self] in
            guard let self else { return }
            if let index = self.timers.firstIndex(where: { $0.id == id }) {
                self.timers[index].cancelled = true
            }
        }
    }

    /// Advances simulated clock time by `deltaMs`, firing due callbacks in exact scheduled order.
    public func advance(byMs deltaMs: Double) {
        let targetMs = currentMs + max(0, deltaMs)
        while true {
            let nextIndex = timers.enumerated()
                .filter { !$0.element.cancelled && $0.element.atMs <= targetMs }
                .min { a, b in
                    if a.element.atMs != b.element.atMs {
                        return a.element.atMs < b.element.atMs
                    }
                    return a.element.id < b.element.id
                }?.offset
            guard let index = nextIndex else { break }
            let timer = timers.remove(at: index)
            if timer.atMs > currentMs {
                currentMs = timer.atMs
            }
            timer.callback(timer.atMs)
        }
        currentMs = targetMs
    }
}

public final class WallIslandClock: IslandClock {
    public init() {}

    public func nowMs() -> Double {
        ProcessInfo.processInfo.systemUptime * 1000.0
    }

    @discardableResult
    public func schedule(atMs: Double, _ callback: @escaping (Double) -> Void) -> () -> Void {
        let delayMs = max(0.0, atMs - nowMs())
        let work = DispatchWorkItem {
            callback(atMs)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delayMs / 1000.0, execute: work)
        return { work.cancel() }
    }
}

public enum IslandExpandReason: String, Equatable, Hashable, Sendable {
    case user
    case alert
}

public enum IslandUpdateTransition: String, Equatable, Hashable, Sendable {
    case morph
    case crossfade
}

public struct IslandActivityContentDescriptor: Equatable, Sendable {
    public var compactLeadingKey: String?
    public var compactTrailingKey: String?
    public var minimalKey: String?
    public var expandedKey: String?

    public init(
        compactLeadingKey: String? = nil,
        compactTrailingKey: String? = nil,
        minimalKey: String? = nil,
        expandedKey: String? = nil
    ) {
        self.compactLeadingKey = compactLeadingKey
        self.compactTrailingKey = compactTrailingKey
        self.minimalKey = minimalKey
        self.expandedKey = expandedKey
    }
}

public struct IslandActivitySpec {
    public let id: String
    public var label: String
    public var priority: Int
    public var group: String?
    public var content: IslandActivityContentDescriptor
    public var alert: Bool
    public var onPress: (() -> Void)?

    public init(
        id: String,
        label: String? = nil,
        priority: Int = 0,
        group: String? = nil,
        content: IslandActivityContentDescriptor = .init(),
        alert: Bool = false,
        onPress: (() -> Void)? = nil
    ) {
        self.id = id
        self.label = label ?? id
        self.priority = priority
        self.group = group
        self.content = content
        self.alert = alert
        self.onPress = onPress
    }
}

public struct IslandActivityUpdate {
    public var label: String?
    public var priority: Int?
    public var content: IslandActivityContentDescriptor?
    public var hasCompactUpdate: Bool
    public var hasMinimalUpdate: Bool
    public var hasExpandedUpdate: Bool
    public var transition: IslandUpdateTransition
    public var alert: Bool
    public var onPress: (() -> Void)??

    public init(
        label: String? = nil,
        priority: Int? = nil,
        content: IslandActivityContentDescriptor? = nil,
        hasCompactUpdate: Bool = false,
        hasMinimalUpdate: Bool = false,
        hasExpandedUpdate: Bool = false,
        transition: IslandUpdateTransition = .morph,
        alert: Bool = false,
        onPress: (() -> Void)?? = nil
    ) {
        self.label = label
        self.priority = priority
        self.content = content
        self.hasCompactUpdate = hasCompactUpdate
        self.hasMinimalUpdate = hasMinimalUpdate
        self.hasExpandedUpdate = hasExpandedUpdate
        self.transition = transition
        self.alert = alert
        self.onPress = onPress
    }
}

public struct IslandActivityRecord {
    public let id: String
    public var label: String
    public var priority: Int
    public let order: Int
    public var content: IslandActivityContentDescriptor
    public var revision: Int
    public let group: String?
    public var onPress: (() -> Void)?

    public var contentIdentity: String {
        revision > 0 ? "\(id)#\(revision)" : id
    }
}

public struct IslandExpandedState: Equatable, Sendable {
    public let id: String
    public let reason: IslandExpandReason
}

public struct IslandSnapshot {
    public var activities: [IslandActivityRecord]
    public var expanded: IslandExpandedState?
    public var changeId: Int
    public var changedAtMs: Double
    public var instant: Bool
    public var pressed: IslandPressTarget?
    public var joiningAtMs: Double?
    public var front: [String: String]
    public var handoff: String?
}

public struct IslandScene {
    public let presentation: IslandPresentationKind
    public let contentKey: String
    public let label: String
    public let primary: IslandActivityRecord?
    public let detached: IslandActivityRecord?
}

public func isActivityShown(_ snapshot: IslandSnapshot, activity: IslandActivityRecord) -> Bool {
    guard let group = activity.group else { return true }
    if snapshot.handoff == group { return false }
    let members = snapshot.activities.filter { $0.group == group }
    if let forward = snapshot.front[group], members.contains(where: { $0.id == forward }) {
        return activity.id == forward
    }
    let firstOrder = members.min(by: { $0.order < $1.order })?.id
    return activity.id == firstOrder
}

public func deriveIslandScene(_ snapshot: IslandSnapshot) -> IslandScene {
    let visible = snapshot.activities.filter { isActivityShown(snapshot, activity: $0) }
    if let expandedState = snapshot.expanded,
       let expanded = snapshot.activities.first(where: { $0.id == expandedState.id }) {
        return IslandScene(
            presentation: .expanded,
            contentKey: "expanded:\(expanded.contentIdentity)",
            label: expanded.label,
            primary: expanded,
            detached: nil
        )
    }
    guard let first = visible.first else {
        return IslandScene(presentation: .idle, contentKey: "idle", label: "", primary: nil, detached: nil)
    }
    guard visible.count > 1 else {
        return IslandScene(
            presentation: .compact,
            contentKey: "compact:\(first.contentIdentity)",
            label: first.label,
            primary: first,
            detached: nil
        )
    }
    let second = visible[1]
    return IslandScene(
        presentation: .minimal,
        contentKey: "minimal:\(first.contentIdentity):\(second.contentIdentity)",
        label: "\(first.label), \(second.label)",
        primary: first,
        detached: second
    )
}

/// Multi-activity priority, split turn-taking, alert timer, and long-press state store,
/// faithful to `opencoredev/islandcn`'s `createIslandStore`.
public final class IslandStore {
    private let clock: IslandClock
    private let motionProvider: () -> IslandMotion
    public private(set) var snapshot: IslandSnapshot

    private var pressTimers: [() -> Void] = []
    private var alertTimers: [() -> Void] = []
    private var pendingContent: [String: () -> Void] = [:]
    private var holding: (target: IslandPressTarget, atMs: Double, isLong: Bool, activityId: String?)?
    private var nextOrder = 0
    private var isInstant = false
    private var listeners: [UUID: (IslandSnapshot) -> Void] = [:]

    public init(clock: IslandClock = WallIslandClock(), motion: @escaping () -> IslandMotion = { .default }) {
        self.clock = clock
        self.motionProvider = motion
        self.snapshot = IslandSnapshot(
            activities: [],
            expanded: nil,
            changeId: 0,
            changedAtMs: clock.nowMs(),
            instant: false,
            pressed: nil,
            joiningAtMs: nil,
            front: [:],
            handoff: nil
        )
    }

    public var scene: IslandScene {
        deriveIslandScene(snapshot)
    }

    public var presentation: IslandPresentationKind {
        scene.presentation
    }

    @discardableResult
    public func subscribe(_ listener: @escaping (IslandSnapshot) -> Void) -> () -> Void {
        let token = UUID()
        listeners[token] = listener
        return { [weak self] in
            self?.listeners.removeValue(forKey: token)
        }
    }

    private func sortActivities(_ list: [IslandActivityRecord]) -> [IslandActivityRecord] {
        list.sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return a.order < b.order
        }
    }

    private func commit(_ draft: IslandSnapshot, atMs: Double? = nil) {
        let before = deriveIslandScene(snapshot)
        let after = deriveIslandScene(draft)
        let shownChanged = before.contentKey != after.contentKey
        var next = draft
        if shownChanged || isInstant {
            next.changeId = snapshot.changeId + 1
            next.changedAtMs = atMs ?? clock.nowMs()
            next.instant = isInstant
        } else {
            next.changeId = snapshot.changeId
            next.changedAtMs = snapshot.changedAtMs
            next.instant = snapshot.instant
        }
        snapshot = next
        for listener in listeners.values {
            listener(snapshot)
        }
    }

    private func clearAlertTimers() {
        for cancel in alertTimers { cancel() }
        alertTimers.removeAll()
    }

    private func cancelHoldTimers() {
        for cancel in pressTimers { cancel() }
        pressTimers.removeAll()
    }

    private func returnAt(id: String, atMs: Double) {
        alertTimers.append(
            clock.schedule(atMs: atMs) { [weak self] dueMs in
                guard let self else { return }
                if self.snapshot.expanded?.id == id && self.snapshot.expanded?.reason == .alert {
                    var draft = self.snapshot
                    draft.expanded = nil
                    self.commit(draft, atMs: dueMs)
                }
            }
        )
    }

    @discardableResult
    private func triggerAlert(id: String, fromIdle: Bool = false) -> Double {
        clearAlertTimers()
        let m = motionProvider()
        let nowMs = clock.nowMs()
        let activity = snapshot.activities.first { $0.id == id }
        let group = activity?.group
        if activity == nil || group == nil || activity.map({ isActivityShown(snapshot, activity: $0) }) == true {
            var draft = snapshot
            draft.expanded = IslandExpandedState(id: id, reason: .alert)
            draft.handoff = nil
            commit(draft)
            let hold = fromIdle ? m.alertHoldIdle : m.alertHold
            returnAt(id: id, atMs: nowMs + hold * 1000.0)
            return nowMs
        }
        guard let group else { return nowMs }
        var draft = snapshot
        draft.expanded = nil
        draft.handoff = group
        draft.front[group] = id
        commit(draft)
        let expandAtMs = nowMs + m.group.handoff * 1000.0
        alertTimers.append(
            clock.schedule(atMs: expandAtMs) { [weak self] dueMs in
                guard let self else { return }
                guard self.snapshot.handoff == group, self.snapshot.activities.contains(where: { $0.id == id }) else { return }
                var next = self.snapshot
                next.handoff = nil
                next.expanded = IslandExpandedState(id: id, reason: .alert)
                self.commit(next, atMs: dueMs)
            }
        )
        returnAt(id: id, atMs: nowMs + m.group.window * 1000.0)
        return expandAtMs
    }

    public func start(_ spec: IslandActivitySpec) {
        if snapshot.activities.contains(where: { $0.id == spec.id }) {
            update(
                spec.id,
                IslandActivityUpdate(
                    label: spec.label,
                    priority: spec.priority,
                    content: spec.content,
                    hasCompactUpdate: true,
                    hasMinimalUpdate: true,
                    hasExpandedUpdate: true,
                    alert: spec.alert,
                    onPress: spec.onPress.map { Optional($0) }
                )
            )
            return
        }

        let order = nextOrder
        nextOrder += 1
        let record = IslandActivityRecord(
            id: spec.id,
            label: spec.label,
            priority: spec.priority,
            order: order,
            content: spec.content,
            revision: 0,
            group: spec.group,
            onPress: spec.onPress
        )
        let wasIdle = snapshot.activities.isEmpty
        var draft = snapshot
        draft.activities = sortActivities(snapshot.activities + [record])
        commit(draft)
        if spec.alert {
            triggerAlert(id: spec.id, fromIdle: wasIdle)
        }
    }

    public func update(_ id: String, _ update: IslandActivityUpdate) {
        if let flush = pendingContent.removeValue(forKey: id) {
            flush()
        }
        guard let existingIndex = snapshot.activities.firstIndex(where: { $0.id == id }) else { return }
        let found = snapshot.activities[existingIndex]

        var mergedContent = found.content
        if let incoming = update.content {
            if update.hasCompactUpdate {
                mergedContent.compactLeadingKey = incoming.compactLeadingKey ?? mergedContent.compactLeadingKey
                mergedContent.compactTrailingKey = incoming.compactTrailingKey ?? mergedContent.compactTrailingKey
            }
            if update.hasMinimalUpdate {
                mergedContent.minimalKey = incoming.minimalKey
            }
            if update.hasExpandedUpdate {
                mergedContent.expandedKey = incoming.expandedKey ?? mergedContent.expandedKey
            }
        }

        var next = found
        next.label = update.label ?? found.label
        next.priority = update.priority ?? found.priority
        if let onPressOverride = update.onPress {
            next.onPress = onPressOverride
        }
        next.content = mergedContent
        next.revision = update.transition == .crossfade ? found.revision + 1 : found.revision

        func replace(_ replacement: IslandActivityRecord, atMs: Double? = nil) {
            var draft = snapshot
            draft.activities = sortActivities(snapshot.activities.map { $0.id == id ? replacement : $0 })
            commit(draft, atMs: atMs)
        }

        let changesContent = update.hasCompactUpdate || update.hasExpandedUpdate || update.hasMinimalUpdate
        let delay = motionProvider().alertContentDelay
        if update.alert && changesContent && delay > 0 && snapshot.expanded?.id != id && isActivityShown(snapshot, activity: found) {
            var delayedRecord = next
            delayedRecord.content = found.content
            delayedRecord.revision = found.revision
            replace(delayedRecord)
            let expandAtMs = triggerAlert(id: id)
            let cancel = clock.schedule(atMs: expandAtMs + delay * 1000.0) { [weak self] dueMs in
                guard let self else { return }
                self.pendingContent.removeValue(forKey: id)
                guard let current = self.snapshot.activities.first(where: { $0.id == id }) else { return }
                var updated = current
                updated.content = mergedContent
                updated.revision = next.revision
                var draft = self.snapshot
                draft.activities = draft.activities.map { $0.id == id ? updated : $0 }
                self.commit(draft, atMs: dueMs)
            }
            pendingContent[id] = { [weak self] in
                cancel()
                guard let self else { return }
                if let current = self.snapshot.activities.first(where: { $0.id == id }) {
                    var updated = current
                    updated.content = mergedContent
                    updated.revision = next.revision
                    var draft = self.snapshot
                    draft.activities = draft.activities.map { $0.id == id ? updated : $0 }
                    self.commit(draft)
                }
            }
            return
        }

        replace(next)
        if update.alert {
            triggerAlert(id: id)
        }
    }

    public func end(_ id: String) {
        if let flush = pendingContent.removeValue(forKey: id) {
            flush()
        }
        guard let ending = snapshot.activities.first(where: { $0.id == id }) else { return }
        let nextExpanded = snapshot.expanded?.id == id ? nil : snapshot.expanded
        let handingTo = ending.group != nil && snapshot.handoff == ending.group && snapshot.front[ending.group!] == id
        if nextExpanded == nil || handingTo {
            clearAlertTimers()
        }
        var draft = snapshot
        draft.activities = snapshot.activities.filter { $0.id != id }
        draft.expanded = nextExpanded
        draft.front = snapshot.front.filter { $0.value != id }
        if handingTo {
            draft.handoff = nil
        }
        commit(draft)
    }

    public func expand(_ id: String? = nil) {
        let targetId = id ?? snapshot.activities.first(where: { isActivityShown(snapshot, activity: $0) })?.id
        guard let targetId, let activity = snapshot.activities.first(where: { $0.id == targetId }) else { return }
        clearAlertTimers()
        var draft = snapshot
        draft.expanded = IslandExpandedState(id: targetId, reason: .user)
        if let group = activity.group {
            draft.front[group] = activity.id
        }
        draft.handoff = nil
        commit(draft)
    }

    public func collapse() {
        guard snapshot.expanded != nil else { return }
        clearAlertTimers()
        var draft = snapshot
        draft.expanded = nil
        commit(draft)
    }

    public func instantly(_ body: () -> Void) {
        isInstant = true
        defer { isInstant = false }
        body()
    }

    public func press(_ target: IslandPressTarget) {
        let currentScene = deriveIslandScene(snapshot)
        let activity = target == .bubble ? currentScene.detached : currentScene.primary
        if target == .bubble && activity == nil { return }
        cancelHoldTimers()
        let m = motionProvider()
        let atMs = clock.nowMs()
        let isExpanded = currentScene.presentation == .expanded
        holding = (target: target, atMs: atMs, isLong: false, activityId: activity?.id)
        if isExpanded { return }

        var draft = snapshot
        draft.pressed = target
        draft.joiningAtMs = nil
        commit(draft)

        let springBack: (Double) -> Void = { [weak self] dueMs in
            guard let self, self.snapshot.pressed != nil else { return }
            var next = self.snapshot
            next.pressed = nil
            self.commit(next, atMs: dueMs)
        }

        guard let activity else {
            pressTimers.append(clock.schedule(atMs: atMs + m.press.holdReturn * 1000.0, springBack))
            return
        }

        let longPressDuration = target == .bubble ? m.longPressBubble : m.longPress
        pressTimers.append(
            clock.schedule(atMs: atMs + m.press.decide * 1000.0) { [weak self] _ in
                guard let self, var currentHold = self.holding, currentHold.target == target, currentHold.atMs == atMs else { return }
                currentHold.isLong = true
                self.holding = currentHold
                if target == .bubble {
                    var next = self.snapshot
                    next.joiningAtMs = atMs + longPressDuration * 1000.0
                    self.commit(next)
                }
            }
        )
        pressTimers.append(
            clock.schedule(atMs: atMs + longPressDuration * 1000.0) { [weak self] dueMs in
                guard let self, let currentHold = self.holding, currentHold.atMs == atMs, currentHold.isLong else { return }
                self.holding = nil
                self.pressTimers.removeAll()
                self.clearAlertTimers()
                var next = self.snapshot
                next.pressed = nil
                next.joiningAtMs = nil
                next.expanded = IslandExpandedState(id: activity.id, reason: .user)
                self.commit(next, atMs: dueMs)
            }
        )
    }

    public func release(cancel: Bool = false) {
        guard let press = holding else { return }
        let m = motionProvider()
        let nowMs = clock.nowMs()
        if press.isLong && !cancel { return }
        holding = nil
        cancelHoldTimers()

        if snapshot.joiningAtMs != nil {
            var draft = snapshot
            draft.joiningAtMs = nil
            commit(draft)
        }

        if snapshot.pressed != nil {
            let backMs: Double
            if press.activityId != nil {
                backMs = max(
                    press.atMs + m.press.tapReturn * 1000.0,
                    nowMs + (m.press.releaseReturn ?? 0) * 1000.0
                )
            } else {
                backMs = press.atMs + (m.press.idleTapReturn ?? m.press.tapReturn) * 1000.0
            }
            if backMs > nowMs {
                pressTimers.append(
                    clock.schedule(atMs: backMs) { [weak self] dueMs in
                        guard let self, self.snapshot.pressed != nil, self.holding == nil else { return }
                        var next = self.snapshot
                        next.pressed = nil
                        self.commit(next, atMs: dueMs)
                    }
                )
            } else {
                var draft = snapshot
                draft.pressed = nil
                commit(draft)
            }
        }

        if cancel { return }
        guard let activityId = press.activityId,
              let activity = snapshot.activities.first(where: { $0.id == activityId }) else { return }
        activity.onPress?()
    }

    public func reset() {
        clearAlertTimers()
        isInstant = true
        defer { isInstant = false }
        cancelHoldTimers()
        holding = nil
        for (_, flush) in pendingContent {
            flush()
        }
        pendingContent.removeAll()
        commit(
            IslandSnapshot(
                activities: [],
                expanded: nil,
                changeId: snapshot.changeId,
                changedAtMs: snapshot.changedAtMs,
                instant: true,
                pressed: nil,
                joiningAtMs: nil,
                front: [:],
                handoff: nil
            )
        )
    }
}
