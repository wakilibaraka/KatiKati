import AppKit
import SwiftUI


// MARK: - Art tokens (Phase 4U decision 8d)

/// The combined clock chip's own palette: a weather-pill twin, not a colour twin — same
/// rounded gradient-card construction at the bar's right end, its own hues so the pair
/// (weather left / clock right) reads as matched siblings rather duplicates.
///
/// Hues picked at build time (2026-10-09), to be signed off on the render:
/// - **Day (warm):** amber → coral, echoing the sun spot on the weather card.
/// - **Night (indigo):** deeper indigo → violet, deliberately one step darker than the
///   weather night family so the two night pills stay distinguishable.
public enum ClockArt {
    /// (leading, trailing) gradient stops for the clock card.
    public static func stops(isNight: Bool) -> (Color, Color) {
        if isNight {
            return (Color(red: 62/255, green: 72/255, blue: 198/255),
                    Color(red: 124/255, green: 98/255, blue: 220/255))
        }
        return (Color(red: 247/255, green: 148/255, blue: 62/255),
                Color(red: 238/255, green: 97/255, blue: 84/255))
    }

    public static func gradient(isNight: Bool) -> LinearGradient {
        let (a, b) = stops(isNight: isNight)
        return LinearGradient(colors: [a, b], startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Bar widget (combined clock chip)

public struct ClockChip: View {
    @AppStorage("com.katikati.clock.preset") private var preset: ClockPreset = .modernMac
    private let provider: ClockDataProvider

    public init(provider: ClockDataProvider = StandardClockProvider()) {
        self.provider = provider
    }

    public var body: some View {
        // Flip tiles are their own form (owner's hand-built variant kept as a
        // third preset): they bypass the 8d gradient card entirely.
        if preset == .flipTiles {
            FlipClockChip()
        } else {
            // 4e: minute-aligned. The timeline starts on the next whole-minute boundary and ticks
            // every 60s from there, so the main thread wakes once a minute and the chip can never
            // show a reading that is up to 59s stale. A per-second `Timer.publish` used to run here
            // even though the provider's content is minute-resolution.
            TimelineView(.periodic(from: ClockTick.nextMinute(after: Date()), by: 60)) { context in
                card(for: context.date)
            }
            .onTapGesture {
                CalendarPanelController.shared.toggle()
            }
        }
    }

    /// 8d locked spec: the weather-pill twin. Identical construction to `WeatherChip`
    /// (8/4 padding, radius-10 continuous gradient card, white 0.18 rim, tap → popup),
    /// own hue from `ClockArt` split by `ClockChipDaylight`, content = large time + a
    /// smaller weekday/date line. Both presets live here — they change the typography,
    /// never the form.
    private func card(for date: Date) -> some View {
        let content = provider.currentContent(for: date)
        let art = ClockArt.gradient(isNight: ClockChipDaylight.isNight(date))

        // ViewThatFits is macOS 13+; the floor is 12, so the fallback there is the full
        // layout truncating (same rule as the weather pill).
        return Group {
            if #available(macOS 13.0, *) {
                ViewThatFits(in: .horizontal) {
                    fullCard(content: content)
                    compactCard(content: content)
                }
            } else {
                fullCard(content: content)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(art))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }

    /// Large time leading, the smaller weekday/date line trailing — horizontal so the card
    /// clears the slot's fixed 36pt height (a stacked pair cannot: 19pt time + 10pt date +
    /// padding overshoots and would clip).
    private func fullCard(content: ClockContent) -> some View {
        HStack(spacing: 8) {
            Text(content.primaryText)
                .font(timeFont)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let secondary = content.secondaryText {
                Text(secondary)
                    .font(dateFont)
                    .opacity(preset == .modernMac ? 0.85 : 0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .foregroundStyle(.white)
    }

    /// Narrow widget widths (the Settings slider goes down to 60pt): keep the load-bearing
    /// element instead of crushing the pair.
    private func compactCard(content: ClockContent) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text(content.primaryText)
                .font(preset == .modernMac
                      ? .system(size: 15, weight: .semibold, design: .rounded)
                      : .system(size: 15, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }

    /// Preset identity survives the restyle as typography: `modern` stays SF Rounded,
    /// `pixel` stays monospaced and shouts its date line — both inside the one new form.
    /// `flipTiles` never reaches here (it bypasses the card in `body`).
    private var timeFont: Font {
        switch preset {
        case .modernMac:
            return .system(size: 19, weight: .semibold, design: .rounded)
        case .pixelRetro:
            return .system(size: 18, weight: .bold, design: .monospaced)
        case .flipTiles:
            return .system(size: 19, weight: .semibold, design: .rounded)
        }
    }

    private var dateFont: Font {
        switch preset {
        case .modernMac:
            return .system(size: 10, weight: .regular, design: .rounded)
        case .pixelRetro:
            return .system(size: 10, weight: .medium, design: .monospaced)
        case .flipTiles:
            return .system(size: 10, weight: .regular, design: .rounded)
        }
    }
}

// MARK: - Floating calendar panel (Phase 5e-A)

/// Panel subclass that can take key focus without activating the app, so Esc (`cancelOperation`)
/// dismisses it.
final class CalendarFloatingPanel: NonConstrainingPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Owns the single floating widget-tile window opened by tapping the clock chip. The window is
/// transparent and **content-sized**: the tiles report their height and the pure
/// `PanelGeometry.calendarPanelFrame` places it top-right. Dismissal = clock tap again, Esc, or a
/// click outside the app.
@MainActor
final class CalendarPanelController {
    static let shared = CalendarPanelController()

    private var panel: CalendarFloatingPanel?
    private var outsideClickMonitor: Any?
    private var layoutShown: CalendarPanelLayout?
    private var geometry: PanelScreenGeometry?

    var isVisible: Bool { panel?.isVisible ?? false }

    func toggle() {
        isVisible ? close() : show()
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        outsideClickMonitor = nil
    }

    /// Reads the layout, carrying the pre-rework size preset over once (`compact420`→mac, `halfScreen`→ipad).
    static func currentLayout(defaults: UserDefaults = .standard) -> CalendarPanelLayout {
        if let raw = defaults.string(forKey: CalendarPanelLayout.storageKey), let layout = CalendarPanelLayout(rawValue: raw) {
            return layout
        }
        let migrated = CalendarPanelSettingsMigration.layout(fromLegacy: defaults.string(forKey: "com.katikati.calendar.panelPreset")) ?? .mac
        defaults.set(migrated.rawValue, forKey: CalendarPanelLayout.storageKey)
        return migrated
    }

    private func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let layout = Self.currentLayout()
        let geometry = PanelScreenGeometry(
            frame: screen.frame, visibleFrame: screen.visibleFrame, safeAreaTop: screen.safeAreaInsets.top
        )
        self.geometry = geometry
        if layoutShown != layout { self.panel?.orderOut(nil); self.panel = nil }
        layoutShown = layout

        let panel = self.panel ?? makePanel(layout: layout, geometry: geometry)
        // Start at the tallest allowed frame so the tiles never clip while they measure themselves;
        // the first height report shrinks the window to fit.
        panel.setFrame(PanelGeometry.calendarPanelFrame(on: geometry, layout: layout, contentHeight: .greatestFiniteMagnitude), display: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
    }

    private func resize(toContentHeight height: CGFloat, layout: CalendarPanelLayout) {
        guard let panel, let geometry, height > 0 else { return }
        let frame = PanelGeometry.calendarPanelFrame(on: geometry, layout: layout, contentHeight: height)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func makePanel(layout: CalendarPanelLayout, geometry: PanelScreenGeometry) -> CalendarFloatingPanel {
        let panel = CalendarFloatingPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isFloatingPanel = true
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        let width = layout.width(forScreenWidth: geometry.frame.width)
        let view = CalendarPanelView(
            layout: layout, width: width,
            maxHeight: PanelGeometry.calendarPanelMaxHeight(on: geometry),
            onHeight: { [weak self] h in DispatchQueue.main.async { self?.resize(toContentHeight: h, layout: layout) } }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hosting
        self.panel = panel
        return panel
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Global monitors only see events destined for *other* apps, so a tap on the bar (the clock
        // chip toggling itself) never races this dismissal.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }
}
private struct DayCell: View {
    let date: Date
    let isToday: Bool

    var body: some View {
        // 4d: a bare day-of-month is a number, not translatable copy — verbatim so the
        // localization gate stops treating the interpolation as a missing key.
        Text(verbatim: "\(Calendar.current.component(.day, from: date))")
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(isToday ? Color.blue : Color.clear)
            .foregroundColor(isToday ? .white : .primary)
            .clipShape(Circle())
    }
}


public struct FlipClockChip: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        HStack(spacing: 6) {
            let components = Calendar.current.dateComponents([.hour, .minute], from: currentTime)
            let hourStr = String(format: "%02d", components.hour ?? 0)
            let minuteStr = String(format: "%02d", components.minute ?? 0)

            flipTile(text: hourStr)
            
            VStack(spacing: 8) {
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4)
                Circle().fill(Color.white.opacity(0.8)).frame(width: 4, height: 4)
            }
            
            flipTile(text: minuteStr)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onReceive(timer) { input in
            currentTime = input
        }
    }

    private func flipTile(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(white: 0.18))
                .frame(width: 32, height: 32)
            
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            // Horizontal split line
            Rectangle()
                .fill(Color.black.opacity(0.4))
                .frame(height: 1)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.black.opacity(0.2), lineWidth: 1)
        )
    }
}
