import SwiftUI

// Keep Awake notch page: Brewing card, duration chips, Lid closed + AI agents rows, battery floor.
// Reads and drives `KeepAwakeService`; the old media-card timer and the hotkey go through the same service.

enum StayAwakePreset: Int, CaseIterable {
    case m15 = 15, m30 = 30, h1 = 60, h2 = 120, h5 = 300, indefinite = 0

    var label: String {
        switch self {
        case .m15: return "15m"
        case .m30: return "30m"
        case .h1: return "1h"
        case .h2: return "2h"
        case .h5: return "5h"
        case .indefinite: return "∞"
        }
    }

    var seconds: Int? { rawValue == 0 ? nil : rawValue * 60 }
    var duration: TimeInterval? { seconds.map(TimeInterval.init) }
}

struct NotchKeepAwakePageView: View {
    @ObservedObject private var service = KeepAwakeService.shared
    @AppStorage("com.katikati.stayawake.preset") private var presetRaw: Int = 30
    @State private var lidNeedsAdmin = false

    private var preset: StayAwakePreset { StayAwakePreset(rawValue: presetRaw) ?? .m30 }

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            hero.frame(width: 190)
            VStack(spacing: 8) {
                chips
                lidRow
                agentsRow
                floorRow
            }
        }
    }

    // MARK: Hero

    private var title: String {
        if service.decision.reason == .batteryLow { return String(localized: "Sleepy") }
        return service.decision.hold ? String(localized: "Brewing") : String(localized: "Idle")
    }

    private var reasonLine: String {
        switch service.decision.reason {
        case .manual:
            if let end = service.manualEnd { return String(format: String(localized: "Until %@"), end.formatted(date: .omitted, time: .shortened)) }
            return String(localized: "Until you turn it off")
        case .agents: return String(localized: "AI agents are working")
        case .grace: return String(localized: "Agents just finished")
        case .batteryLow: return String(format: String(localized: "Battery under %lld%%"), service.floorPercent)
        case .timerEnded: return String(localized: "Timer ended")
        case .off: return String(localized: "Your Mac can sleep")
        }
    }

    private var hero: some View {
        let brewing = service.decision.hold
        return Button {
            service.setManual(!service.manualOn, duration: preset.duration)
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(brewing ? Color.orange : .white.opacity(0.35))
                        .padding(.top, 14)
                    if brewing { Steam() }
                }
                .frame(height: 64)
                Text(verbatim: title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(verbatim: reasonLine)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: NotchDesignSpec.cardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(brewing ? 0.12 : 0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Keep Awake"))
        .accessibilityValue(Text(verbatim: title))
    }

    // MARK: Rows

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(StayAwakePreset.allCases, id: \.self) { p in
                Button {
                    presetRaw = p.rawValue
                    service.setManual(true, duration: p.duration)
                } label: {
                    Text(verbatim: p.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(Capsule().fill(selected(p) ? Color.orange.opacity(0.85) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selected(_ p: StayAwakePreset) -> Bool { service.manualOn && p == preset }

    private var lidRow: some View {
        row(icon: "laptopcomputer", title: String(localized: "Lid closed"),
            detail: lidNeedsAdmin ? String(localized: "Admin approval was not given")
                : String(localized: "Keep running with the lid shut"),
            isOn: Binding(get: { service.lidClosedEnabled }, set: { on in
                Task { lidNeedsAdmin = !(await service.setLidClosed(on)) }
            }))
    }

    private var agentsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(icon: "sparkles", title: String(localized: "AI agents"),
                detail: String(localized: "Stay awake while they work"),
                isOn: $service.agentsEnabled)
            if service.agentsEnabled, !service.agents.isEmpty {
                ForEach(service.agents.prefix(3)) { a in
                    HStack(spacing: 6) {
                        Circle().fill(a.working ? Color.green : Color.white.opacity(0.25)).frame(width: 5, height: 5)
                        Text(verbatim: a.count > 1 ? "\(a.name) ×\(a.count)" : a.name)
                        Spacer()
                        if a.background { Text("Background run") }
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 10)
                }
            }
        }
    }

    private var floorRow: some View {
        HStack {
            Image(systemName: "battery.25percent").foregroundStyle(.white.opacity(0.6))
            Text("Sleep under battery")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Spacer()
            Stepper(value: $service.floorPercent, in: 5...80, step: 5) {
                Text(verbatim: "\(service.floorPercent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .labelsHidden()
            Text(verbatim: "\(service.floorPercent)%")
                .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func row(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.white.opacity(0.7)).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Text(verbatim: detail).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Toggle(isOn: isOn) { Text(verbatim: title) }.labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

/// Three rising wisps above the glass; static under Reduce Motion.
private struct Steam: View {
    @State private var up = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(Color.white.opacity(up ? 0.0 : 0.5))
                    .frame(width: 3, height: 12)
                    .offset(y: up ? -6 : 4)
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.4).repeatForever(autoreverses: false).delay(Double(i) * 0.3), value: up)
            }
        }
        .onAppear { up = true }
    }
}
