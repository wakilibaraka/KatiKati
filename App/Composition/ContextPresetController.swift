import AppKit
import Combine

/// Phase 10a-7 — applies a widget preset by schedule. Off by default; while off there is no timer and no
/// subscription work. While on, one minute-aligned one-shot timer re-evaluates `ContextPresetRules` and applies
/// a preset only when the matched one changes (a manual tweak inside a window sticks until the next change).
@MainActor
final class ContextPresetController {
    static let shared = ContextPresetController()

    private var settings: AppSettingsStore?
    private var cancellables = Set<AnyCancellable>()
    private var timer: Timer?
    private var lastApplied: String?

    private init() {}

    func configure(settings: AppSettingsStore) {
        guard self.settings == nil else { return }
        self.settings = settings
        Publishers.CombineLatest3(settings.$contextPresetsEnabled, settings.$contextWorkPresetID, settings.$contextEveningPresetID)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled, _, _ in
                guard let self else { return }
                if enabled { self.lastApplied = nil; self.evaluate() } else { self.stop() }
            }
            .store(in: &cancellables)
    }

    private func stop() {
        timer?.invalidate(); timer = nil
        lastApplied = nil
    }

    private func rules(_ settings: AppSettingsStore) -> [ContextPresetRule] {
        var result: [ContextPresetRule] = []
        if !settings.contextWorkPresetID.isEmpty { result.append(ContextPresetRules.workRule(presetID: settings.contextWorkPresetID)) }
        if !settings.contextEveningPresetID.isEmpty { result.append(ContextPresetRules.eveningRule(presetID: settings.contextEveningPresetID)) }
        return result
    }

    private func evaluate() {
        guard let settings, settings.contextPresetsEnabled else { return }
        let now = Date()
        let matched = ContextPresetRules.matchingPresetID(rules: rules(settings), at: now)
        if let id = ContextPresetRules.presetToApply(matched: matched, lastApplied: lastApplied),
           let preset = (WidgetPresets.builtIns + settings.userWidgetPresets).first(where: { $0.id == id }) {
            settings.applyWidgetPreset(preset)
        }
        lastApplied = matched
        timer?.invalidate()
        let next = Timer(timeInterval: ContextPresetRules.secondsToNextMinute(from: now) + 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }
}
