import AppKit
import SwiftUI

// Phase 5h — the tiles that only the tall calendar stack has: the full-width clock + time zones,
// the countdown Timer (separate from Focus), the Stopwatch, event Countdowns and Quick Notes.

// MARK: - State

@MainActor
final class CountdownTimerController: ObservableObject {
    @Published private(set) var model = CountdownTimerModel()
    private var timer: Timer?

    func toggle() { model.toggle(); sync() }
    func reset() { model.reset(); sync() }
    func set(seconds: Int) { model.set(seconds: seconds); sync() }
    func adjust(by seconds: Int) { model.adjust(by: seconds); sync() }

    private func sync() {
        timer?.invalidate(); timer = nil
        guard model.isRunning else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.model.tick() { NSSound(named: "Glass")?.play(); self.sync() }
                self.objectWillChange.send()
            }
        }
    }

    deinit { timer?.invalidate() }
}

@MainActor
final class StopwatchController: ObservableObject {
    @Published private(set) var model = StopwatchModel()
    func toggle() { model.toggle(at: Date()); objectWillChange.send() }
    func lap() { model.lap(at: Date()); objectWillChange.send() }
    func reset() { model.reset(); objectWillChange.send() }
}

@MainActor
final class EventCountdownStore: ObservableObject {
    @Published private(set) var events: [EventCountdown]

    init() {
        events = UserDefaults.standard.data(forKey: EventCountdown.storageKey)
            .flatMap { try? JSONDecoder().decode([EventCountdown].self, from: $0) } ?? []
    }

    func add(label: String, date: Date) {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        events = EventCountdown.ordered(events + [EventCountdown(label: clean, date: date)], now: Date())
        persist()
    }

    func remove(_ id: UUID) { events.removeAll { $0.id == id }; persist() }

    private func persist() {
        if let data = try? JSONEncoder().encode(events) { UserDefaults.standard.set(data, forKey: EventCountdown.storageKey) }
    }
}

enum WidgetExtraPrefs {
    static let showNotesKey = "com.katikati.widgets.showNotes"
    static let showStopwatchKey = "com.katikati.widgets.showStopwatch"
    static let notesKey = "com.katikati.widgets.notes"
}

// MARK: - Clock + time zones (full width)

struct ClockWideTile: View {
    let env: TileEnv
    @ObservedObject var store: WorldClockStore
    let style: CalendarClockStyle
    let width: CGFloat
    let height: CGFloat
    @State private var picking = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
            HStack(spacing: 14) {
                face(at: ctx.date).frame(width: width * 0.5)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(verbatim: WorldClockModel.city(for: TimeZone.current.identifier).uppercased())
                            .font(.system(size: 12, weight: .bold)).foregroundColor(env.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if store.identifiers.count < WorldClockModel.maxClocks {
                            Button { picking.toggle() } label: { Image(systemName: "plus.circle.fill").font(.system(size: 15)) }
                                .buttonStyle(.plain).foregroundColor(env.accent(.clock))
                                .popover(isPresented: $picking) { TimeZonePicker(store: store, done: { picking = false }) }
                        }
                    }
                    Text(ctx.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Divider().opacity(0.4)
                    ForEach(store.identifiers.prefix(max(1, min(4, Int((height - 90) / 30)))), id: \.self) { id in
                        if let r = WorldClockModel.reading(for: id, at: ctx.date) {
                            HStack(spacing: 6) {
                                Image(systemName: r.isNight ? "moon.stars.fill" : "sun.max.fill")
                                    .font(.system(size: 11)).foregroundColor(r.isNight ? .indigo : .orange)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(verbatim: r.city).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    HStack(spacing: 3) {
                                        if r.dayDelta > 0 { Text("Tomorrow") } else if r.dayDelta < 0 { Text("Yesterday") }
                                        Text(verbatim: r.offsetLabel)
                                    }.font(.system(size: 9)).foregroundColor(env.secondary)
                                }
                                Spacer(minLength: 0)
                                Text(r.time).font(.system(size: 14, weight: .bold)).monospacedDigit()
                            }
                            .contextMenu { Button("Remove") { store.remove(id) } }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .foregroundColor(env.text)
        .padding(16)
        .frame(width: width, height: height)
        .tileSurface(env)
    }

    @ViewBuilder private func face(at date: Date) -> some View {
        let leftW = width * 0.5 - 16
        switch style {
        case .flip:
            let d = max(40, min((leftW - 20) / 2, (height - 32) / 1.12))
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            HStack(spacing: 6) {
                digit(String(format: "%02d", c.hour ?? 0), d)
                VStack(spacing: d * 0.16) { Circle().frame(width: 5, height: 5); Circle().frame(width: 5, height: 5) }.foregroundColor(env.secondary)
                digit(String(format: "%02d", c.minute ?? 0), d)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .analog:
            let d = min(leftW, height - 32)
            AnalogFace(env: env, date: date).frame(width: d, height: d).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func digit(_ text: String, _ size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(env.accent(.clock))
            Text(text).font(.system(size: size * 0.64, weight: .bold, design: .rounded)).monospacedDigit().foregroundColor(.white)
            Rectangle().fill(Color.black.opacity(0.35)).frame(height: 1)
        }
        .frame(width: size, height: size * 1.12)
    }
}

// MARK: - Timer

struct TimerTile: View {
    let env: TileEnv
    @ObservedObject var controller: CountdownTimerController
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let m = controller.model
        let ring = max(60, min(width - 40, height - 118))
        VStack(spacing: 6) {
            HStack { Text("Timer"); Spacer() }
                .font(.system(size: 11, weight: .bold)).textCase(.uppercase).foregroundColor(env.secondary)
            ZStack {
                Circle().stroke(env.accent(.timer).opacity(0.18), lineWidth: 8)
                Circle().trim(from: 0, to: m.isFinished ? 1 : max(0.001, m.progress))
                    .stroke(m.isFinished ? Color.red : env.accent(.timer), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(verbatim: CountdownTimerModel.label(m.remaining)).font(.system(size: ring * 0.26, weight: .bold)).monospacedDigit()
            }
            .frame(width: ring, height: ring)
            HStack(spacing: 12) {
                Button { controller.adjust(by: -60) } label: { Image(systemName: "minus.circle") }
                Button { controller.toggle() } label: {
                    Image(systemName: m.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 26)).foregroundColor(env.accent(.timer))
                }
                Button { controller.adjust(by: 60) } label: { Image(systemName: "plus.circle") }
                Button { controller.reset() } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(env.secondary)
            HStack(spacing: 4) {
                ForEach(CountdownTimerModel.presets, id: \.self) { s in
                    Button { controller.set(seconds: s) } label: {
                        Text(verbatim: "\(s / 60)m").font(.system(size: 10, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 3)
                            .background(Capsule().fill(m.total == s ? env.accent(.timer).opacity(0.25) : env.hairline))
                    }.buttonStyle(.plain)
                }
            }
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, height: height)
        .tileSurface(env)
    }
}

// MARK: - Stopwatch

struct StopwatchTile: View {
    let env: TileEnv
    @ObservedObject var controller: StopwatchController
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let m = controller.model
        VStack(spacing: 6) {
            HStack { Text("Stopwatch"); Spacer() }
                .font(.system(size: 11, weight: .bold)).textCase(.uppercase).foregroundColor(env.secondary)
            TimelineView(.animation(minimumInterval: 0.05, paused: !m.isRunning)) { ctx in
                Text(verbatim: StopwatchModel.label(m.elapsed(at: ctx.date)))
                    .font(.system(size: min(30, width / 6), weight: .bold, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: 14) {
                Button { controller.lap() } label: { Image(systemName: "flag.fill") }.disabled(!m.isRunning)
                Button { controller.toggle() } label: {
                    Image(systemName: m.isRunning ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 26)).foregroundColor(env.accent(.stopwatch))
                }
                Button { controller.reset() } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .buttonStyle(.plain).font(.system(size: 15, weight: .semibold)).foregroundColor(env.secondary)
            let rows = max(0, Int((height - 112) / 16))
            VStack(spacing: 1) {
                ForEach(Array(m.splits.prefix(rows).enumerated()), id: \.offset) { i, split in
                    HStack {
                        Text(verbatim: "#\(m.splits.count - i)").foregroundColor(env.secondary)
                        Spacer()
                        Text(verbatim: StopwatchModel.label(split)).monospacedDigit()
                    }.font(.system(size: 10, weight: .semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(env.text)
        .padding(12)
        .frame(width: width, height: height)
        .tileSurface(env)
    }
}

// MARK: - Event countdowns

struct CountdownTile: View {
    let env: TileEnv
    @ObservedObject var store: EventCountdownStore
    let width: CGFloat
    let height: CGFloat
    @State private var adding = false
    @State private var label = ""
    @State private var date = Date().addingTimeInterval(86_400 * 7)

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .full; f.dateTimeStyle = .named; return f
    }()

    var body: some View {
        let rows = max(1, Int((height - 30 - 10) / 34))
        BandTile(env: env, kind: .countdown, width: width, height: height, header: {
            HStack {
                Text("Countdown"); Spacer()
                Button { adding.toggle() } label: { Image(systemName: "plus") }.buttonStyle(.plain)
                    .popover(isPresented: $adding) {
                        VStack(spacing: 8) {
                            TextField("Event name", text: $label).textFieldStyle(.roundedBorder)
                            DatePicker(selection: $date, displayedComponents: .date) { Text("Date") }
                            Button("Add") { store.add(label: label, date: date); label = ""; adding = false }
                        }.padding(12).frame(width: 220)
                    }
            }
        }, content: {
            if store.events.isEmpty {
                Text("No events").font(.system(size: 12, weight: .semibold)).foregroundColor(env.secondary).padding(.top, 4)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.events.prefix(rows))) { e in
                        let days = e.daysRemaining(from: Date())
                        HStack {
                            Text(verbatim: e.label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(verbatim: Self.relative.localizedString(from: DateComponents(day: days)))
                                .font(.system(size: 11, weight: .bold)).foregroundColor(days < 0 ? env.secondary : env.accent(.countdown))
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(height: 34)
                        .contextMenu { Button("Remove") { store.remove(e.id) } }
                    }
                }
            }
        })
    }
}

// MARK: - Notes

struct NotesTile: View {
    let env: TileEnv
    let width: CGFloat
    let height: CGFloat
    @AppStorage(WidgetExtraPrefs.notesKey) private var notes = ""

    var body: some View {
        BandTile(env: env, kind: .notes, width: width, height: height, header: {
            HStack { Text("Notes"); Spacer(); Text(verbatim: "\(notes.count)").opacity(0.7).font(.system(size: 11, weight: .semibold)) }
        }, content: {
            TextEditor(text: $notes)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .cornerRadius(8)
        })
    }
}
