import SwiftUI

// Keep Awake notch page: Brewing card, duration chips, Lid closed + AI agents rows, battery floor.
// Reads and drives `KeepAwakeService`; the old media-card timer and the hotkey go through the same service.

struct NotchKeepAwakePageView: View {
    @ObservedObject private var service = KeepAwakeService.shared
    @AppStorage("com.katikati.stayawake.preset") private var presetRaw: Int = 30
    @State private var lidNeedsAdmin = false

    private var preset: StayAwakePreset { StayAwakePreset(rawValue: presetRaw) ?? .m30 }

    var body: some View {
        HStack(spacing: NotchDesignSpec.cardSpacing) {
            hero.frame(width: 190)
            VStack(spacing: 4) {
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
            .notchCard()
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
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(Capsule().fill(selected(p) ? Color.orange.opacity(0.75) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { val in
                    let currentMinutes = preset.rawValue == 0 ? 30 : preset.rawValue
                    let targetMinutes = PomodoroScrubberMath.minutes(start: currentMinutes, dragDelta: Double(val.translation.width))
                    let closest = StayAwakePreset.allCases.min(by: { abs($0.rawValue - targetMinutes) < abs($1.rawValue - targetMinutes) })
                    if let c = closest, c.rawValue != presetRaw {
                        presetRaw = c.rawValue
                        if service.manualOn { service.setManual(true, duration: c.duration) }
                    }
                }
        )
    }

    private func selected(_ p: StayAwakePreset) -> Bool { service.manualOn && p == preset }

    private var lidDetail: String {
        lidNeedsAdmin ? String(localized: "Admin approval was not given")
            : String(localized: "Keep running with the lid shut")
    }

    private var lidRow: some View {
        toggleRow(icon: "laptopcomputer", title: String(localized: "Lid closed"), detail: lidDetail,
                  isOn: Binding(get: { service.lidClosedEnabled }, set: { on in
                      Task { lidNeedsAdmin = !(await service.setLidClosed(on)) }
                  }))
    }

    private var agentsRow: some View {
        toggleRow(icon: "sparkles", title: String(localized: "AI agents"),
                  detail: String(localized: "Stay awake while they work"),
                  isOn: $service.agentsEnabled)
    }

    private var floorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "battery.25percent").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            Text("Sleep under battery")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            Stepper(value: $service.floorPercent, in: 5...80, step: 5) { Text(verbatim: "Battery floor") }
                .labelsHidden()
                .controlSize(.mini)
            Text(verbatim: "\(service.floorPercent)%")
                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    /// NP-4: one 28 pt line per switch. The old rows stacked a title and a detail line — four rows asked
    /// for more than the 132 pt page body and the floor row was cut off by the panel — so the detail is a
    /// tooltip and the running-agent list (three more rows) is gone.
    private func toggleRow(icon: String, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7)).frame(width: 16)
            Text(verbatim: title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            Spacer(minLength: 4)
            Toggle(isOn: isOn) { Text(verbatim: title) }.labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
        .help(Text(verbatim: detail))
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
