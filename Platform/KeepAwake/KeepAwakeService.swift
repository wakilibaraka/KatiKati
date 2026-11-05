import AppKit
import IOKit.ps
import IOKit.pwr_mgt

struct KeepAwakeAgentRow: Identifiable, Equatable {
    var name: String
    var count: Int
    var working: Bool
    var background: Bool
    var id: String { name }
}

/// Hybrid keep-awake: the owner's manual switch plus AI-agent activity, with a battery floor. Agent activity is
/// the union of a process scan (any agent CLI, one-shot runs, tool-call CPU) and `AgentUsageService`'s
/// hook/log signal, so Claude keeps its precise "turn started/stopped" hook and other agents are still seen.
@MainActor
final class KeepAwakeService: ObservableObject {
    static let shared = KeepAwakeService()

    private enum Key {
        static let agents = "com.katikati.keepawake.agents"
        static let lid = "com.katikati.keepawake.lid"
        static let floor = "com.katikati.keepawake.floor"
        static let grace = "com.katikati.keepawake.grace"
        static let custom = "com.katikati.keepawake.customAgents"
    }

    @Published private(set) var manualOn = false
    @Published private(set) var manualEnd: Date?
    @Published private(set) var decision = KeepAwakeDecision(hold: false, reason: .off, lidGuard: false)
    @Published private(set) var agents: [KeepAwakeAgentRow] = []
    @Published private(set) var batteryPercent: Int?
    @Published private(set) var onBattery = false
    @Published var agentsEnabled: Bool { didSet { UserDefaults.standard.set(agentsEnabled, forKey: Key.agents); evaluate() } }
    @Published var lidClosedEnabled: Bool { didSet { UserDefaults.standard.set(lidClosedEnabled, forKey: Key.lid); evaluate() } }
    @Published var floorPercent: Int { didSet { UserDefaults.standard.set(floorPercent, forKey: Key.floor); evaluate() } }

    var graceSeconds: TimeInterval { TimeInterval(UserDefaults.standard.object(forKey: Key.grace) as? Int ?? 180) }
    /// Comma-separated command names the owner added (matched like the built-in agents).
    var customAgentNames: [String] {
        (UserDefaults.standard.string(forKey: Key.custom) ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var policy = KeepAwakePolicy()
    private var assertion: IOPMAssertionID = 0
    private var assertionType: String?
    private var processWorking = false
    private var previousCPU: [Int: Double] = [:]
    private var timer: Timer?
    private var scanning = false

    private init() {
        let d = UserDefaults.standard
        agentsEnabled = d.object(forKey: Key.agents) as? Bool ?? true
        lidClosedEnabled = d.bool(forKey: Key.lid)
        floorPercent = d.object(forKey: Key.floor) as? Int ?? 20
    }

    /// Starts the 10-second poll. Safe to call twice.
    func start() {
        guard timer == nil else { return }
        AgentUsageService.shared.startMonitoring()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
    }

    /// Manual switch. `duration` nil = until switched off.
    func setManual(_ on: Bool, duration: TimeInterval? = nil) {
        manualOn = on
        manualEnd = on ? duration.map { Date().addingTimeInterval($0) } : nil
        evaluate()
    }

    /// Releases everything (quit): the assertion dies with the process anyway, this keeps the state honest.
    func shutdown() {
        timer?.invalidate(); timer = nil
        apply(nil)
    }

    private func tick() {
        guard !scanning else { return }
        scanning = true
        let extra = customAgentNames
        let before = previousCPU
        Task.detached(priority: .utility) {
            let rows = AgentProcessScan.parse(Self.runPS())
            let found = AgentProcessScan.agents(rows, extraNames: extra)
            let working = Set(found.filter { AgentProcessScan.isWorking($0, previousCPU: before) }.map(\.pid))
            let cpu = Dictionary(found.map { ($0.pid, $0.cpuSeconds) }, uniquingKeysWith: { a, _ in a })
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                self.previousCPU = cpu
                self.processWorking = !working.isEmpty
                self.agents = Self.rows(found, working: working)
                self.evaluate()
            }
        }
    }

    private func evaluate() {
        let battery = PowerFactsReader.iopsBattery()
        batteryPercent = battery?[kIOPSCurrentCapacityKey] as? Int
        onBattery = (battery?[kIOPSPowerSourceStateKey] as? String) == kIOPSBatteryPowerValue

        // shortcut: a Claude hook that says "working" while its log is >90s stale is not counted; the process scan covers long tool calls.
        let logWorking = AgentUsageService.shared.snapshot.recentTurns.contains {
            $0.isActive && -$0.lastActivity.timeIntervalSinceNow < 90
        }
        var inputs = KeepAwakeInputs()
        inputs.manualOn = manualOn
        inputs.manualEnd = manualEnd
        inputs.agentsEnabled = agentsEnabled
        inputs.lidClosedEnabled = lidClosedEnabled
        inputs.agentsWorking = processWorking || logWorking
        inputs.batteryPercent = batteryPercent
        inputs.onBattery = onBattery
        inputs.externalDisplay = Self.hasExternalDisplay()
        inputs.graceSeconds = graceSeconds
        inputs.floorPercent = floorPercent

        let next = policy.decide(inputs, now: Date())
        if next.reason == .timerEnded { manualOn = false; manualEnd = nil }
        if next != decision { decision = next }
        apply(next.hold ? (next.reason == .manual ? "PreventUserIdleDisplaySleep" : "PreventUserIdleSystemSleep") : nil)
    }

    /// Holds exactly one power assertion of the wanted type, or none.
    private func apply(_ type: String?) {
        guard type != assertionType else { return }
        if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }
        assertionType = nil
        guard let type else { return }
        let ok = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                             "KatiKati Keep Awake" as CFString, &assertion)
        if ok == kIOReturnSuccess { assertionType = type } else { assertion = 0 }
    }

    nonisolated private static func runPS() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axo", "pid=,ppid=,time=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile() // read before wait: ps output can exceed the pipe buffer
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func hasExternalDisplay() -> Bool {
        NSScreen.screens.contains { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                .map { CGDisplayIsBuiltin($0) == 0 } ?? false
        }
    }

    private static let displayNames = ["claude": "Claude Code", "codex": "Codex", "gemini": "Gemini CLI",
                                       "opencode": "OpenCode", "copilot": "Copilot"]

    private static func rows(_ found: [AgentProcess], working: Set<Int>) -> [KeepAwakeAgentRow] {
        Dictionary(grouping: found, by: \.name).map { name, list in
            KeepAwakeAgentRow(name: displayNames[name] ?? name, count: list.count,
                              working: list.contains { working.contains($0.pid) },
                              background: list.contains { $0.background })
        }.sorted { $0.name < $1.name }
    }
}
