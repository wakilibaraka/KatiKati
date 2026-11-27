import AppKit
import SwiftUI

/// Date Calculator popover/card shared inside the Calendar & Time panel (supports both day/time deltas and date offsets).
struct DateCalculatorView: View {
    enum Mode: Int, CaseIterable {
        case between
        case offset
    }

    @State private var mode: Mode = .between
    @State private var startDate = Calendar.current.startOfDay(for: Date())
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 30, to: Calendar.current.startOfDay(for: Date())) ?? Date()
    @State private var baseDate = Date()
    @State private var offsetAmount = 14
    @State private var offsetUnit: DateCalculator.OffsetUnit = .days
    @State private var countdownTitle = ""
    @State private var savedConfirmation = false

    @ObservedObject private var countdowns = ProductivityServices.shared.countdowns

    private var diff: DateCalculator.DateDifference {
        DateCalculator.difference(from: startDate, to: endDate)
    }

    private var calculatedDate: Date {
        DateCalculator.offset(from: baseDate, amount: offsetAmount, unit: offsetUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Date Calculator", systemImage: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Picker("Mode", selection: $mode) {
                    Text("Between").tag(Mode.between)
                    Text("Offset").tag(Mode.offset)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            if mode == .between {
                betweenBody
            } else {
                offsetBody
            }
        }
        .padding(14)
        .frame(width: 310)
    }

    private var betweenBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    DatePicker("From", selection: $startDate, displayedComponents: [.date])
                        .labelsHidden()
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("To").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    DatePicker("To", selection: $endDate, displayedComponents: [.date])
                        .labelsHidden()
                }
            }

            HStack(spacing: 6) {
                quickPresetButton(title: "+7d") { setEndOffset(days: 7) }
                quickPresetButton(title: "+30d") { setEndOffset(days: 30) }
                quickPresetButton(title: "+90d") { setEndOffset(days: 90) }
                quickPresetButton(title: "End of Year") { setEndOfYear() }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: "\(diff.totalDays)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("days")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if diff.isPast {
                        Text("ago")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Text(verbatim: "\(diff.years)y · \(diff.months)m · \(diff.days)d")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Divider().opacity(0.25)

                HStack {
                    metricPill(label: String(localized: "Weekdays"), value: "\(diff.businessDays)")
                    metricPill(label: String(localized: "Hours"), value: "\(diff.totalHours)")
                    metricPill(label: String(localized: "Minutes"), value: "\(diff.totalMinutes)")
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

            HStack(spacing: 8) {
                TextField("Countdown label", text: $countdownTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                Button("Add") {
                    let clean = countdownTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    let name = clean.isEmpty ? endDate.formatted(date: .abbreviated, time: .omitted) : clean
                    countdowns.add(label: name, date: endDate)
                    countdownTitle = ""
                    savedConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { savedConfirmation = false }
                }
                .controlSize(.small)
            }

            if savedConfirmation {
                Text("Saved to Countdowns")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.green)
            }
        }
    }

    private var offsetBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Start").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                DatePicker("Start", selection: $baseDate, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }

            HStack(spacing: 8) {
                Stepper(value: $offsetAmount, in: -9999...9999) {
                    Text(verbatim: offsetAmount >= 0 ? "+\(offsetAmount)" : "\(offsetAmount)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .leading)
                }
                Picker("Unit", selection: $offsetUnit) {
                    ForEach(DateCalculator.OffsetUnit.allCases) { unit in
                        Text(unitTitle(unit)).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(calculatedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year()))
                    .font(.system(size: 14, weight: .semibold))
                Text(calculatedDate.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.06)))

            HStack {
                Spacer()
                Button("Copy Date") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        calculatedDate.formatted(date: .long, time: .shortened),
                        forType: .string
                    )
                }
                .controlSize(.small)
            }
        }
    }

    private func metricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: label).font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            Text(verbatim: value).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickPresetButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func setEndOffset(days: Int) {
        endDate = DateCalculator.offset(from: startDate, amount: days, unit: .days)
    }

    private func setEndOfYear() {
        let cal = Calendar.current
        let year = cal.component(.year, from: startDate)
        endDate = cal.date(from: DateComponents(year: year, month: 12, day: 31)) ?? endDate
    }

    private func unitTitle(_ unit: DateCalculator.OffsetUnit) -> String {
        switch unit {
        case .days: return String(localized: "Days")
        case .weeks: return String(localized: "Weeks")
        case .months: return String(localized: "Months")
        case .years: return String(localized: "Years")
        case .hours: return String(localized: "Hours")
        case .minutes: return String(localized: "Minutes")
        }
    }
}
