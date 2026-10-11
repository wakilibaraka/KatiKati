import SwiftUI

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
            Button("Delete Screen Time Data") { confirmDelete = true }
                .buttonStyle(.link).font(.system(size: 11))
                .alert(isPresented: $confirmDelete) {
                    Alert(title: Text("Delete Screen Time Data"), message: Text("This removes every recorded day. It cannot be undone."),
                          primaryButton: .destructive(Text("Delete")) { controller.deleteAllData() }, secondaryButton: .cancel())
                }
        }
        .padding(14)
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
