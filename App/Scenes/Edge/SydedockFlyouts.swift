import SwiftUI

// MARK: - 1. Hydration Flyout

struct HydrationFlyoutView: View {
    @ObservedObject private var hydro = HydrationController.shared

    static let size = CGSize(width: 340, height: 340)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Hydration")
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(hydro.todayGlasses) today")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            // Next reminder + Drink now CTA
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next reminder in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(verbatim: hydro.formattedRemainingTime)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(hydro.isOverdue ? .orange : .primary)
                }
                Spacer()
                Button {
                    hydro.drinkNow()
                } label: {
                    Label("Drink now", systemImage: "drop.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.blue))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.blue.opacity(0.3), lineWidth: 1))
            )

            // Reminder frequency stepper
            HStack {
                Text("Remind me every")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        hydro.setIntervalMinutes(hydro.intervalMinutes - 5)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(verbatim: "\(hydro.intervalMinutes) min")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .frame(minWidth: 52)

                    Button {
                        hydro.setIntervalMinutes(hydro.intervalMinutes + 5)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)

            Divider()

            // 14-day bar chart
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Last 14 days")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "Goal: \(hydro.dailyGoalGlasses) glasses")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let days = hydro.last14DaysData()
                let maxVal = max(hydro.dailyGoalGlasses, days.map(\.count).max() ?? 1)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 3) {
                            let hRatio = CGFloat(day.count) / CGFloat(max(1, maxVal))
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.isToday ? Color.cyan : Color.blue.opacity(day.count > 0 ? 0.7 : 0.18))
                                .frame(width: 14, height: max(4, 68 * hRatio))
                            Text(verbatim: day.dayLabel)
                                .font(.system(size: 8, weight: day.isToday ? .bold : .regular))
                                .foregroundColor(day.isToday ? .primary : .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(16)
    }
}

// MARK: - 2. Food, Fasting & Nutrition Flyout (3 Sections)

struct FoodFlyoutView: View {
    @ObservedObject private var nutri = NutritionController.shared

    static let size = CGSize(width: 340, height: 420)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Food & Fasting")
                    .font(.headline)
                Spacer()
                Text(verbatim: "\(nutri.todayMealsCount) meals today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Section 1: Intermittent Fasting
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Intermittent Fasting", systemImage: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                    Picker("Fasting Protocol", selection: $nutri.protocolType) {
                        ForEach([FastingProtocol.fast16_8, .fast18_6, .fast14_10, .none], id: \.self) { proto in
                            Text(verbatim: proto.title).tag(proto)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nutri.isFasting ? "Fasting elapsed" : "Eating window")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(verbatim: nutri.isFasting ? nutri.formattedFastTime : "Active")
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                    Button {
                        if nutri.isFasting { nutri.endFast() } else { nutri.startFast() }
                    } label: {
                        Text(nutri.isFasting ? "End Fast" : "Start Fast")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(nutri.isFasting ? Color.orange : Color.green))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }

                ProgressView(value: min(1.0, nutri.fastProgress))
                    .tint(.orange)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            // Section 2: Meal & Snack Cadence
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Meal Cadence", systemImage: "fork.knife")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    Text(verbatim: "Every \(String(format: "%.1f", nutri.mealIntervalHours))h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next meal in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(verbatim: nutri.formattedNextMealTime)
                            .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    }
                    Spacer()
                    Button {
                        nutri.logMeal()
                    } label: {
                        Label("Log Meal", systemImage: "plus.circle.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.blue))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            // Section 3: Daily Calories & Macros
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Calories & Macros", systemImage: "flame.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                    Spacer()
                    Text(verbatim: "\(nutri.todayCalories) / \(nutri.dailyCalorieGoal) kcal")
                        .font(.caption.monospacedDigit().weight(.medium))
                }

                ProgressView(value: nutri.calorieProgress)
                    .tint(.green)

                HStack(spacing: 12) {
                    macroBadge(title: "Protein", grams: nutri.proteinGrams, color: .blue)
                    macroBadge(title: "Carbs", grams: nutri.carbsGrams, color: .orange)
                    macroBadge(title: "Fat", grams: nutri.fatGrams, color: .purple)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
        .padding(16)
    }

    private func macroBadge(title: String, grams: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(grams)g")
                .font(.caption.bold().monospacedDigit())
            Text(verbatim: title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.12)))
    }
}

// MARK: - 3. Habits & 6-Week Matrix Flyout

struct HabitsFlyoutView: View {
    @ObservedObject private var store = HabitStreakStore.shared
    @State private var newHabitTitle = ""

    static let size = CGSize(width: 340, height: 360)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Habits")
                    .font(.headline)
                Spacer()
                Label(String(format: "%d day streak", store.streakCount), systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.orange)
            }

            // 6-week matrix
            let matrix = store.matrix42Days()
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 14)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<min(42, matrix.count), id: \.self) { idx in
                    let dot = matrix[idx]
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(dot.level == 0 ? Color.primary.opacity(0.1) : Color.blue.opacity(0.3 + Double(dot.level) * 0.23))
                        .frame(height: 14)
                        .overlay(dot.isToday ? RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1) : nil)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            // Checklist
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.habits) { habit in
                        Button {
                            store.toggleHabit(id: habit.id)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: habit.isDoneToday ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(habit.isDoneToday ? .blue : .secondary)
                                Text(verbatim: habit.title)
                                    .font(.subheadline)
                                    .strikethrough(habit.isDoneToday)
                                    .foregroundColor(habit.isDoneToday ? .secondary : .primary)
                                Spacer()
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Add habit field
            HStack {
                TextField("Add a habit...", text: $newHabitTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addHabit() }
                Button {
                    addHabit()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .disabled(newHabitTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
    }

    private func addHabit() {
        store.addHabit(title: newHabitTitle)
        newHabitTitle = ""
    }
}

// MARK: - 4. Clock Flyout

struct ClockFlyoutView: View {
    @State private var now = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    @State private var is24Hour = EdgeBarPrefs.load().clockIs24Hour
    @State private var showSeconds = EdgeBarPrefs.load().clockShowSeconds
    @State private var showDate = EdgeBarPrefs.load().clockShowDate

    static let size = CGSize(width: 300, height: 260)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Digital clock")
                    .font(.headline)
                Spacer()
                Text(verbatim: TimeZone.current.abbreviation() ?? "Local")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: formattedTime)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                Text(verbatim: formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.blue.opacity(0.12)))

            HStack {
                Text("Format")
                    .font(.subheadline)
                Spacer()
                Picker("Format", selection: $is24Hour) {
                    Text("12-hour").tag(false)
                    Text("24-hour").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .onChange(of: is24Hour) { _, newVal in
                    var prefs = EdgeBarPrefs.load()
                    prefs.clockIs24Hour = newVal
                    prefs.save()
                }
            }

            Toggle("Show Seconds", isOn: $showSeconds)
                .onChange(of: showSeconds) { _, newVal in
                    var prefs = EdgeBarPrefs.load()
                    prefs.clockShowSeconds = newVal
                    prefs.save()
                }

            Toggle("Show Date", isOn: $showDate)
                .onChange(of: showDate) { _, newVal in
                    var prefs = EdgeBarPrefs.load()
                    prefs.clockShowDate = newVal
                    prefs.save()
                }
        }
        .padding(16)
        .onReceive(timer) { now = $0 }
    }

    private var formattedTime: String {
        let df = DateFormatter()
        df.dateFormat = is24Hour ? (showSeconds ? "HH:mm:ss" : "HH:mm") : (showSeconds ? "h:mm:ss a" : "h:mm a")
        return df.string(from: now)
    }

    private var formattedDate: String {
        let df = DateFormatter()
        df.dateStyle = .full
        return df.string(from: now)
    }
}
