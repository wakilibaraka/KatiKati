import Foundation

/// SD-4b: the download engine's decisions, separated from `URLSession` so they can be driven by recorded
/// progress instead of a live transfer. The service owns tasks; this owns *what to do next*: which segment to
/// start, when a freed worker should steal the tail of the largest remaining chunk, when a quiet connection is
/// reconnected, how many connections the observed throughput justifies, and where a segment's bytes belong in
/// the one output file.
struct DownloadEngineState: Sendable {
    enum Action: Equatable, Sendable {
        /// Open a request for this segment.
        case start(index: Int)
        /// A worker freed up and the largest in-flight segment still has a tail worth splitting: shorten
        /// `victim` and start a new segment `tail`.
        case steal(victim: Int, tail: Int)
        /// Every byte is on disk.
        case assemble
        /// Nothing to do until a task reports back.
        case wait
    }

    let policy: DownloadEnginePolicy
    private(set) var plan: DownloadSegmentPlan
    private(set) var queued: [Int]
    private(set) var inFlight: Set<Int> = []
    private(set) var completed: [Int: Int64]
    private(set) var detector: DownloadStallDetector
    /// The ramp: how many connections the last throughput sample justified, never above the policy.
    private(set) var connections: Int

    init(plan: DownloadSegmentPlan, policy: DownloadEnginePolicy = .standard, completed: [Int: Int64] = [:]) {
        self.policy = policy
        self.plan = plan
        self.completed = completed
        self.detector = DownloadStallDetector(policy: policy)
        self.connections = max(1, min(policy.connections, plan.segments.count))
        // A segment already finished on disk (a resume record) is not queued again.
        self.queued = plan.segments
            .filter { (completed[$0.index] ?? 0) < $0.length }
            .map(\.index)
    }

    var isComplete: Bool {
        plan.segments.allSatisfy { (completed[$0.index] ?? 0) >= $0.length }
    }

    /// The flat write position for a segment: its own start plus what it has already written, so every worker
    /// seeks into one file instead of leaving a scatter of part files to concatenate later.
    func writeOffset(for index: Int) -> Int64 {
        guard let segment = plan.segments.first(where: { $0.index == index }) else { return 0 }
        return segment.start + (completed[index] ?? 0)
    }

    /// What the engine should do now. `freeSlot` is true when a worker just finished and its connection is
    /// idle again; the caller loops until `.wait` or `.assemble`.
    mutating func next(freeSlot: Bool = false) -> Action {
        if isComplete { return .assemble }
        if queued.isEmpty && inFlight.isEmpty { return .assemble }
        if inFlight.count < connections, !queued.isEmpty {
            let index = queued.removeFirst()
            inFlight.insert(index)
            return .start(index: index)
        }
        guard freeSlot, inFlight.count < min(connections, plan.segments.count) else { return .wait }
        guard let steal = stealCandidate() else { return .wait }
        var segments = plan.segments
        guard let victimIndex = segments.firstIndex(where: { $0.index == steal.victim }) else { return .wait }
        let victim = segments[victimIndex]
        // `DownloadSegment` is a value with let bounds, so the plan is rebuilt: the victim keeps its start and
        // the bytes it already wrote, and the tail keeps the victim's original end.
        segments[victimIndex] = DownloadSegment(index: victim.index, start: victim.start, end: steal.victimEnd,
                                                completedBytes: victim.completedBytes)
        segments.append(DownloadSegment(index: steal.tail, start: steal.tailStart, end: steal.oldEnd))
        plan = DownloadSegmentPlan(segments: segments, isMultiSegment: plan.isMultiSegment)
        inFlight.insert(steal.tail)
        // The shortened victim is re-queued behind the tail so its remaining range is fetched again.
        inFlight.remove(steal.victim)
        queued.insert(steal.victim, at: 0)
        return .steal(victim: steal.victim, tail: steal.tail)
    }

    /// The largest in-flight segment whose unwritten tail can pay for a whole new segment.
    private func stealCandidate() -> (victim: Int, victimEnd: Int64, tail: Int, tailStart: Int64, oldEnd: Int64)? {
        let minimum = DownloadSegmentPlanner.minimumSegmentBytes
        let candidates = inFlight.compactMap { index -> (Int, Int64)? in
            guard let segment = plan.segments.first(where: { $0.index == index }) else { return nil }
            let written = segment.start + (completed[index] ?? 0)
            let remaining = segment.end - written + 1
            // A tail is worth splitting only when both halves can carry the planner's minimum.
            return remaining >= minimum * 2 ? (index, remaining) : nil
        }
        guard let best = candidates.max(by: { $0.1 < $1.1 }),
              let victim = plan.segments.first(where: { $0.index == best.0 }) else { return nil }
        let tailStart = victim.start + (best.1 / 2)
        let tail = (plan.segments.map(\.index).max() ?? 0) + 1
        return (victim: best.0, victimEnd: tailStart - 1, tail: tail, tailStart: tailStart, oldEnd: victim.end)
    }

    /// A delegate callback: this segment has these bytes written at this moment.
    mutating func progress(index: Int, totalWritten: Int64, at now: Date = Date()) {
        completed[index] = totalWritten
        // The detector needs the transfer's whole progress: `plan.completedBytes` only tracks what was finalised
        // when a segment closed, so feeding it meant the rate never moved and no stall was ever visible.
        detector.record(bytes: completed.values.reduce(0, +), at: now)
    }

    /// A delegate callback: this segment is done.
    mutating func finish(index: Int) {
        inFlight.remove(index)
        if let segment = plan.segments.first(where: { $0.index == index }) {
            completed[index] = segment.length
        }
    }

    /// A cancelled in-flight segment has nothing on disk: the delegate only delivers completed ranges, so its
    /// offset goes back to the segment's own start.
    mutating func reset(index: Int) { completed[index] = 0 }

    /// One ticker beat: ramp the connection count from the samples the delegate fed us, then ask the reconnect
    /// path. The service calls exactly this from `onTick`.
    mutating func tick(now: Date = Date()) -> Action? {
        ramp(recent: detector.recentRate(now: now) ?? 0, peak: detector.peakRate() ?? 0)
        return stalledAction(now: now)
    }

    /// The ticker's reconnect path: a stalled transfer gets one reconnect per budget, for the segment that is
    /// furthest behind, then has to fail visibly.
    mutating func stalledAction(now: Date = Date()) -> Action? {
        guard !isComplete, detector.isStalled(now: now), let victim = mostBehind else { return nil }
        guard detector.noteReconnect() else { return nil }
        inFlight.remove(victim)
        if !queued.contains(victim) { queued.insert(victim, at: 0) }
        return .start(index: victim)
    }

    private var mostBehind: Int? {
        inFlight.min { left, right in
            let l = plan.segments.first { $0.index == left }
            let r = plan.segments.first { $0.index == right }
            let lRemaining = (l?.length ?? 0) - (completed[left] ?? 0)
            let rRemaining = (r?.length ?? 0) - (completed[right] ?? 0)
            return lRemaining > rRemaining
        }
    }

    /// Widening and narrowing from observed throughput: a line that keeps up earns more connections, one that
    /// falls behind gives them back. Both ends stay inside the policy.
    mutating func ramp(recent: Double, peak: Double) {
        guard peak > 0 else { return }
        if recent >= peak * 0.9 {
            connections = min(policy.connections, connections + 2)
        } else if recent < peak * 0.35 {
            connections = max(1, connections - 1)
        }
    }
}

/// SD-4b: flat positioned writes — a range's bytes go to its own offset in the one output file, so a segment
/// that was stolen, shortened or reconnected needs no concatenation pass and the file is whole the moment every
/// range has landed.
enum DownloadFlatWriter {
    static func write(_ data: Data, to url: URL, offset: Int64) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }
}
