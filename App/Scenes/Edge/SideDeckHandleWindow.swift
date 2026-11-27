import AppKit
import Combine
import SwiftUI

/// SD-1 (render 1): the resting handle — a 4 × 44 pt capsule on the active edge, below the menu bar and above
/// the Dock, that opens the deck on hover (or a compact weather pill when `mergedWeatherHandle` is on).
///
/// A hidden floating panel receives no mouse events, and the plan forbids a global pointer monitor while
/// retiring the old 7 Hz `NSEvent.mouseLocation` poll. So the handle is its own always-present borderless
/// window with a tracking area: 4 pt of ink, padded to a 14 pt hit target (≤6 pt on either side), nothing
/// else on screen. Recorded as the choice the plan leaves open.
@MainActor
final class SideDeckHandleWindow {
    private var panel: NSPanel?
    private var host: NSView?
    private var dwellWork: DispatchWorkItem?
    private var weatherSink: AnyCancellable?
    private var currentScreen: NSScreen?
    private var currentSide: SideDeckConfig.Side = .left
    private var currentMergedWeatherHandle = false
    private let onOpen: () -> Void

    static let inkWidth: CGFloat = 4
    static let inkHeight: CGFloat = 44
    static let weatherWidth: CGFloat = 28
    static let weatherHeight: CGFloat = 64
    static let hitPadding: CGFloat = 5

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
    }

    /// Places the handle on `screen`'s active edge, vertically centred between the menu bar and the Dock.
    func show(on screen: NSScreen, side: SideDeckConfig.Side, mergedWeatherHandle: Bool = false) {
        currentScreen = screen
        currentSide = side
        currentMergedWeatherHandle = mergedWeatherHandle

        let showsWeather = mergedWeatherHandle && WeatherService.shared.currentState.hasData
        let inkW = showsWeather ? Self.weatherWidth : Self.inkWidth
        let inkH = showsWeather ? Self.weatherHeight : Self.inkHeight
        let visible = screen.visibleFrame
        let width = inkW + 2 * Self.hitPadding
        let height = inkH + 2 * Self.hitPadding
        let x = side == .left ? visible.minX : visible.maxX - width
        let frame = NSRect(x: x, y: visible.midY - height / 2, width: width, height: height)

        let panel = panel ?? makePanel(frame: frame)
        panel.setFrame(frame, display: false)
        self.panel = panel

        let content = HandleTrackingView(frame: NSRect(origin: .zero, size: frame.size))
        content.onEnter = { [weak self] in self?.scheduleOpen() }
        content.onExit = { [weak self] in self?.cancelOpen() }
        let hosting = NSHostingView(rootView: SideDeckHandleCapsule(mergedWeatherHandle: mergedWeatherHandle))
        hosting.frame = content.bounds
        hosting.autoresizingMask = [.width, .height]
        content.addSubview(hosting)
        panel.contentView = content
        host = content
        panel.orderFrontRegardless()

        if mergedWeatherHandle && weatherSink == nil {
            weatherSink = WeatherService.shared.$currentState
                .map(\.hasData)
                .removeDuplicates()
                .sink { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.panel != nil, self.currentMergedWeatherHandle,
                              let s = self.currentScreen else { return }
                        self.show(on: s, side: self.currentSide, mergedWeatherHandle: true)
                    }
                }
        } else if !mergedWeatherHandle {
            weatherSink = nil
        }
    }

    func hide() {
        cancelOpen()
        weatherSink = nil
        currentScreen = nil
        panel?.orderOut(nil)
        panel = nil
        host = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isMovable = false
        // The handle lives on its tracking area, not on clicks: it must receive mouseEntered/Exited, so
        // this window is deliberately not click-through (4 pt of ink inside a 14 pt hit target).
        // INPUT-HYGIENE: INTERACTIVE
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = PanelCollectionBehavior.standard
        panel.isReleasedWhenClosed = false
        return panel
    }

    /// 180 ms by default: enough that crossing the edge on the way somewhere else never opens the deck.
    private func scheduleOpen() {
        cancelOpen()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onOpen()
            }
        }
        dwellWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SideDeckConfig.migrating(from: .standard).dwell,
                                      execute: work)
    }

    private func cancelOpen() {
        dwellWork?.cancel()
        dwellWork = nil
    }
}

private struct SideDeckHandleCapsule: View {
    let mergedWeatherHandle: Bool
    @ObservedObject private var weather = WeatherService.shared
    @AppStorage(WeatherUnits.temperatureKey) private var tempUnit: TemperatureUnit = .celsius

    var body: some View {
        let state = weather.currentState
        if mergedWeatherHandle, state.hasData {
            VStack(spacing: 3) {
                Image(systemName: state.glyphName)
                    .font(.system(size: 11, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(verbatim: WeatherUnits.degrees(state.temperatureCelsius, tempUnit))
                    .font(.system(size: 9.5, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)
            .frame(width: SideDeckHandleWindow.weatherWidth, height: SideDeckHandleWindow.weatherHeight)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text("Open Side Deck"))
        } else {
            Capsule(style: .continuous)
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: SideDeckHandleWindow.inkWidth, height: SideDeckHandleWindow.inkHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(Text("Open Side Deck"))
        }
    }
}

/// The hit target: a plain view whose tracking area covers the padded frame, so a 4 pt capsule is grabbable
/// without widening the ink.
private final class HandleTrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        self.area = area
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}
