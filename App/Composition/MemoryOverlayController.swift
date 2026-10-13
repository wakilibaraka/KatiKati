import AppKit
import Combine

/// Phase 20b — hold Control over the dock to see each app's memory. Costs nothing at rest: the 0.1 s modifier
/// check and the 2 s sampler exist **only while the pointer is inside a dock panel** (and only the sampler
/// while Control is down). No global event monitor, no permission.
@MainActor
final class MemoryOverlayController: ObservableObject {
    static let shared = MemoryOverlayController()
    static let enabledKey = "com.katikati.memoryOverlay.enabled"

    @Published private(set) var controlHeld = false
    @Published private(set) var memory: [String: UInt64] = [:]

    private var insideCount = 0
    private var modifierTimer: Timer?
    private var sampleTimer: Timer?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }

    /// Called from each dock panel's hover; panels can overlap (strip + drawer), so it counts.
    func pointer(inside: Bool) {
        insideCount = max(0, insideCount + (inside ? 1 : -1))
        if insideCount > 0, isEnabled { startWatching() } else { stopWatching() }
    }

    private func startWatching() {
        guard modifierTimer == nil else { return }
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        modifierTimer = t
        tick()
    }

    private func stopWatching() {
        modifierTimer?.invalidate(); modifierTimer = nil
        stopSampling()
        if controlHeld { controlHeld = false }
    }

    private func tick() {
        let held = NSEvent.modifierFlags.contains(.control)
        guard held != controlHeld else { return }
        controlHeld = held
        held ? startSampling() : stopSampling()
    }

    private func startSampling() {
        sample()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        RunLoop.main.add(t, forMode: .common)
        sampleTimer = t
    }

    private func stopSampling() {
        sampleTimer?.invalidate(); sampleTimer = nil
    }

    private func sample() {
        var roots: [String: Int32] = [:]
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, !app.isTerminated { roots[id] = app.processIdentifier }
        }
        Task.detached(priority: .utility) {
            let aggregated = ProcessMemory.aggregate(procs: ProcessMemoryReader.snapshot(), roots: roots)
            await MainActor.run { MemoryOverlayController.shared.memory = aggregated }
        }
    }
}

import SwiftUI

/// The small pill drawn over a chip while Control is held.
struct MemoryPill: View {
    let bytes: UInt64

    var body: some View {
        let tier = ProcessMemory.tier(bytes: bytes)
        Text(verbatim: ProcessMemory.format(bytes: bytes))
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(Capsule().fill(color(tier)))
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
            .allowsHitTesting(false)
            .transition(.opacity)
    }

    private func color(_ tier: ProcessMemory.Tier) -> Color {
        switch tier {
        case .low: return Color(red: 0.16, green: 0.62, blue: 0.34)
        case .medium: return Color(red: 0.85, green: 0.58, blue: 0.08)
        case .high: return Color(red: 0.82, green: 0.2, blue: 0.2)
        }
    }
}
