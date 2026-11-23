import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Today's total, the busiest apps and a seven-day strip (Phase 7B-W2). Used by the edge-deck flyout and, with fewer
/// rows, by the launcher's Screen Time tile. Shows an empty state when tracking is off.
struct ScreenTimeSummaryView: View {
    @ObservedObject private var controller = ProductivityServices.shared.screenTime
    let rows: Int

    var body: some View {
        let cal = Calendar.current
        let today = ScreenTimeLedger.dayKey(Date(), calendar: cal)
        let ledger = controller.ledger
        let top = ledger.top(day: today, limit: rows)
        let peak = max(1, top.first?.seconds ?? 1)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                Text(verbatim: ScreenTimeLedger.format(ledger.total(day: today)))
                    .font(.system(size: rows > 3 ? 28 : 20, weight: .light)).monospacedDigit()
            }
            if !controller.enabled {
                Text("Screen Time is Off").font(.system(size: 12)).foregroundColor(.secondary)
            } else if top.isEmpty {
                Text("No Activity Yet").font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                ForEach(top, id: \.bundleID) { app in
                    HStack(spacing: 6) {
                        Text(verbatim: app.name).font(.system(size: 11)).lineLimit(1).frame(width: 96, alignment: .leading)
                        GeometryReader { g in
                            Capsule().fill(Color.accentColor.opacity(0.75))
                                .frame(width: max(3, g.size.width * app.seconds / peak))
                        }
                        .frame(height: 6)
                        Text(verbatim: ScreenTimeLedger.format(app.seconds)).font(.system(size: 10)).monospacedDigit()
                            .foregroundColor(.secondary).frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }
}

private struct WeekStrip: View {
    let totals: [(day: String, seconds: Double)]

    var body: some View {
        let peak = max(1, totals.map(\.seconds).max() ?? 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(totals.enumerated()), id: \.offset) { _, t in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(t.seconds > 0 ? 0.8 : 0.2))
                        .frame(height: max(3, 44 * t.seconds / peak))
                    Text(verbatim: String(t.day.suffix(2))).font(.system(size: 9)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 60, alignment: .bottom)
    }
}

/// The edge-deck Screen Time flyout: summary, this week, the on/off switch and a wipe button.
struct ScreenTimeFlyoutView: View {
    @ObservedObject private var controller = ProductivityServices.shared.screenTime
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenTimeSummaryView(rows: 5)
            VStack(alignment: .leading, spacing: 4) {
                Text("This Week").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                WeekStrip(totals: controller.ledger.week(endingAt: Date(), calendar: .current))
            }
            limitsSection
            Spacer(minLength: 0)
            Toggle("Track Screen Time", isOn: Binding(get: { controller.enabled }, set: { controller.setEnabled($0) }))
                .toggleStyle(.switch)
            Text("Only the name of the front app and the time it was in front are kept, on this Mac.")
                .font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            Menu("Export") {
                Button { exportJSON() } label: { Text(verbatim: "JSON") }
                Button { exportCSV() } label: { Text(verbatim: "CSV") }
            }
            .menuStyle(.borderlessButton)
            Button("Delete Screen Time Data") { confirmDelete = true }
                .buttonStyle(.link).font(.system(size: 11))
                .alert(isPresented: $confirmDelete) {
                    Alert(title: Text("Delete Screen Time Data"), message: Text("This removes every recorded day. It cannot be undone."),
                          primaryButton: .destructive(Text("Delete")) { controller.deleteAllData() }, secondaryButton: .cancel())
                }
        }
        .padding(14)
    }

    private func exportJSON() {
        export(defaultName: "screen-time.json", contentType: .json) {
            try ScreenTimeExport.json(controller.ledger)
        }
    }

    private func exportCSV() {
        export(defaultName: "screen-time.csv", contentType: .commaSeparatedText) {
            ScreenTimeExport.csv(controller.ledger)
        }
    }

    private func export(defaultName: String, contentType: UTType, data: () throws -> Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType]
        panel.nameFieldStringValue = defaultName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data().write(to: url, options: .atomic)
        } catch {
            NSLog("ScreenTime export failed: \(error.localizedDescription)")
        }
    }

    @ViewBuilder private var limitsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Daily Limits").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                Spacer()
                let candidates = controller.ledger.names.filter { controller.limits[$0.key] == nil }.sorted { $0.value < $1.value }
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates, id: \.key) { id, name in
                            Button { controller.setLimit(id, minutes: 60) } label: { Text(verbatim: name) }
                        }
                    } label: { Text("Add Limit") }
                    .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                }
            }
            ForEach(controller.limits.keys.sorted(), id: \.self) { id in
                HStack {
                    Text(verbatim: controller.ledger.names[id] ?? id).font(.system(size: 11)).lineLimit(1)
                    Spacer()
                    Picker(selection: Binding(get: { controller.limits[id] ?? 60 }, set: { controller.setLimit(id, minutes: $0) })) {
                        ForEach(limitChoices(including: controller.limits[id]), id: \.self) { Text(verbatim: ScreenTimeLedger.format(Double($0) * 60)).tag($0) }
                    } label: { EmptyView() }
                    .labelsHidden().fixedSize().font(.system(size: 11))
                    Button { controller.setLimit(id, minutes: nil) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                }
            }
        }
    }

    private func limitChoices(including current: Int?) -> [Int] {
        var choices = ScreenTimeLimits.presets
        if let c = current, !choices.contains(c) { choices.append(c); choices.sort() }
        return choices
    }
}

// MARK: - Lumabar Signature Micro-Tiles (Slice 4.4)

struct DotMatrixProgressTileView: View {
    let model: DotMatrixProgressModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: model.label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach(0..<model.totalDots, id: \.self) { i in
                    Circle()
                        .fill(i < model.litDots ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: 4, height: 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct RetroFlipClockTileView: View {
    let digits: FlipClockDigits

    var body: some View {
        HStack(spacing: 3) {
            card(digits.hourString)
            Text(verbatim: ":").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            card(digits.minuteString)
            if !digits.amPm.isEmpty {
                Text(verbatim: digits.amPm)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 6).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }

    private func card(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
    }
}

struct InlineFocusTimerPill: View {
    let sessionText: String // e.g. "Focus 1/4"
    let timeRemainingText: String // e.g. "25:00"
    let isRunning: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                Image(systemName: "timer")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(verbatim: sessionText)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(verbatim: timeRemainingText)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.ultraThinMaterial))
            .overlay(Capsule().strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}

struct ScreenTimeHourlyBarTile: View {
    let totalText: String // e.g. "6h 5m"
    let hourlyFractions: [Double] // 0.0 ... 1.0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "hourglass")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.purple)
            Text(verbatim: totalText)
                .font(.system(size: 9.5, weight: .semibold))
            HStack(alignment: .bottom, spacing: 1.5) {
                ForEach(0..<min(12, hourlyFractions.count), id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.purple.opacity(0.7))
                        .frame(width: 2.5, height: max(2, 12 * CGFloat(hourlyFractions[i])))
                }
            }
            .frame(height: 12)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

struct AILimitDualBarTileView: View {
    let summary: AILimitBarTileSummary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: summary.providerName).font(.system(size: 9, weight: .bold))
                    Text(verbatim: summary.tokenFormatted).font(.system(size: 8)).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    bar(fraction: Double(summary.sessionPercent) / 100, label: "S: \(summary.sessionPercent)%", reset: summary.sessionResetCountdown)
                    bar(fraction: Double(summary.weeklyPercent) / 100, label: "W: \(summary.weeklyPercent)%", reset: summary.weeklyResetDay)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.cyan.opacity(0.2), lineWidth: 0.5))
    }

    private func bar(fraction: Double, label: String, reset: String) -> some View {
        HStack(spacing: 2) {
            Text(verbatim: label).font(.system(size: 8, weight: .medium))
            Capsule()
                .fill(fraction > 0.85 ? Color.red : Color.cyan)
                .frame(width: max(2, 24 * CGFloat(min(1.0, fraction))), height: 3)
            Text(verbatim: reset).font(.system(size: 7)).foregroundStyle(.secondary)
        }
    }
}
