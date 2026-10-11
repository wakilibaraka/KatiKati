import SwiftUI

/// The one set of reminder / alarm / timer stores, shared by the edge-deck flyouts and the weather-side widget
/// stack so a timer started in one is the same timer in the other (Phase 7A-P2). Created on first use.
@MainActor
final class ProductivityServices {
    static let shared = ProductivityServices()
    let calendar = CalendarService()
    let focus = FocusTimerController()
    let alarms = AlarmStore()
    let timer = CountdownTimerController()
    let stopwatch = StopwatchController()
    let countdowns = EventCountdownStore()
    lazy var tasks = TasksController()
    lazy var clipboard = ClipboardMonitor()
    lazy var capture = CaptureController()
    lazy var systemMonitor = SystemMonitorController()
    lazy var screenTime = ScreenTimeController()
    private init() {}
}

/// Flyout sizes (outer panel), per item.
enum ProductivityFlyout {
    static func size(_ item: ProductivityItem) -> CGSize {
        switch item {
        case .time: return CGSize(width: 340, height: 340)
        case .tasks: return CGSize(width: 320, height: 360)
        case .windows: return CGSize(width: 300, height: 290)
        case .capture: return CGSize(width: 320, height: 300)
        case .screenTime: return CGSize(width: 340, height: 500)
        default: return CGSize(width: 300, height: 290)
        }
    }

    @MainActor
    static func view(_ item: ProductivityItem) -> AnyView? {
        switch item {
        case .reminders: return AnyView(RemindersFlyoutView())
        case .alarms: return AnyView(AlarmsFlyoutView())
        case .time: return AnyView(TimeFlyoutView())
        case .tasks: return AnyView(TasksFlyoutView())
        case .windows: return AnyView(WindowsFlyoutView())
        case .clipboard: return AnyView(ClipboardFlyoutView())
        case .capture: return AnyView(CaptureResultView())
        case .screenTime: return AnyView(ScreenTimeFlyoutView())
        default: return nil
        }
    }

    /// Flyouts with a text field need the panel to take key focus.
    static func takesKey(_ item: ProductivityItem) -> Bool { item == .time || item == .tasks }
}

struct RemindersFlyoutView: View {
    @ObservedObject private var service = ProductivityServices.shared.calendar
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = ProductivityFlyout.size(.reminders)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        RemindersTile(env: env, service: service, width: size.width - 16, height: size.height - 16,
                      rows: max(1, Int((size.height - 16 - 40) / 34)), rowHeight: 34)
            .padding(8)
            .onAppear { service.start(); service.refreshReminders() }
    }
}

struct AlarmsFlyoutView: View {
    @ObservedObject private var store = ProductivityServices.shared.alarms
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let size = ProductivityFlyout.size(.alarms)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        AlarmsTile(env: env, store: store, width: size.width - 16, height: size.height - 16,
                   rows: max(1, Int((size.height - 16 - 40) / 34)), rowHeight: 34, band: 30)
            .padding(8)
    }
}

/// Timer / Stopwatch / Countdown / Focus in one flyout. "Pomodoro" is the Focus tab (the existing focus/break cycle).
struct TimeFlyoutView: View {
    enum Tab: String, CaseIterable { case timer, stopwatch, countdown, focus }

    @ObservedObject private var timer = ProductivityServices.shared.timer
    @ObservedObject private var stopwatch = ProductivityServices.shared.stopwatch
    @ObservedObject private var countdowns = ProductivityServices.shared.countdowns
    @ObservedObject private var focus = ProductivityServices.shared.focus
    @AppStorage("com.katikati.edge.timeTab") private var tabRaw = Tab.timer.rawValue
    @AppStorage(TilePalette.storageKey) private var palette: TilePalette = .classic
    @Environment(\.colorScheme) private var colorScheme

    private var tab: Binding<Tab> {
        Binding(get: { Tab(rawValue: tabRaw) ?? .timer }, set: { tabRaw = $0.rawValue })
    }

    var body: some View {
        let size = ProductivityFlyout.size(.time)
        let env = TileEnv(palette: palette, isDark: colorScheme == .dark)
        let w = size.width - 16
        let h = size.height - 16 - 34
        VStack(spacing: 8) {
            Picker("Time", selection: tab) {
                Text("Timer").tag(Tab.timer)
                Text("Stopwatch").tag(Tab.stopwatch)
                Text("Countdown").tag(Tab.countdown)
                Text("Focus").tag(Tab.focus)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: w)
            switch tab.wrappedValue {
            case .timer: TimerTile(env: env, controller: timer, width: w, height: h)
            case .stopwatch: StopwatchTile(env: env, controller: stopwatch, width: w, height: h)
            case .countdown: CountdownTile(env: env, store: countdowns, width: w, height: h)
            case .focus: FocusTile(env: env, controller: focus, width: w, height: h)
            }
        }
        .padding(8)
    }
}
