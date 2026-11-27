import AppKit
import SwiftUI

/// SN-2: snApp — a small glass grid of window layouts. The panel never activates, so the app the user
/// was working in stays frontmost and `WindowSnapService.apply` lands on *its* focused window, not on
/// KatiKati. Keys: ←/→ move, ↑/↓ jump a row, 1–5 pick a card, Return applies, Esc closes.
@MainActor
final class SnapPickerModel: ObservableObject {
    let presets = SnapLayoutCatalog.presets
    @Published private(set) var selected: Int?
    @Published private(set) var selectedZone: SnapPosition?
    /// AT-7: the zone under the pointer, so the picker can show where the window will land.
    @Published private(set) var hoveredZone: SnapPosition?
    private var selectedAreaIndex: Int?

    /// Flattened list of every individual shape across all five cards so keyboard arrows reach all 12 zones.
    private var allAreas: [(presetIndex: Int, zone: SnapPosition)] {
        presets.enumerated().flatMap { presetIndex, preset in
            preset.areas.map { (presetIndex, $0.zone) }
        }
    }

    var onPick: ((SnapPosition) -> Void)?
    var onDismiss: (() -> Void)?
    var onHover: ((SnapPosition?) -> Void)?

    func hover(_ zone: SnapPosition?) {
        guard zone != hoveredZone else { return }
        hoveredZone = zone
        onHover?(zone)
    }

    /// Digit key codes, 1…8, in order (AT-7 added the vertical pair and the named sizes).
    private static let digitCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28]

    /// A fresh open starts with nothing picked, so Return cannot fire a stale card.
    func reset() {
        selected = nil
        selectedZone = nil
        selectedAreaIndex = nil
        hover(nil)
    }

    func move(by step: Int) {
        let zones = allAreas
        guard !zones.isEmpty else { return }
        let next = (selectedAreaIndex ?? (step > 0 ? -1 : 0)) + step
        let clamped = min(max(next, 0), zones.count - 1)
        selectedAreaIndex = clamped
        selected = zones[clamped].presetIndex
        selectedZone = zones[clamped].zone
    }

    func commit() {
        if let zone = selectedZone {
            pick(zone: zone)
            return
        }
        guard let selected, presets.indices.contains(selected) else { return }
        pick(selected)
    }

    func pick(_ index: Int) {
        guard presets.indices.contains(index), let zone = presets[index].areas.first?.zone else { return }
        selected = index
        selectedZone = zone
        selectedAreaIndex = allAreas.firstIndex(where: { $0.presetIndex == index && $0.zone == zone })
        onDismiss?()
        onPick?(zone)
    }

    func pick(zone: SnapPosition) {
        if let areaIdx = allAreas.firstIndex(where: { $0.zone == zone }) {
            selectedAreaIndex = areaIdx
            selected = allAreas[areaIdx].presetIndex
        }
        selectedZone = zone
        onDismiss?()
        onPick?(zone)
    }

    /// Returns `true` when the key was ours; the panel swallows only those.
    func handle(keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: onDismiss?(); return true                 // esc
        case 123: move(by: -1); return true                // ←
        case 124: move(by: 1); return true                 // →
        case 126: move(by: -1); return true                // ↑
        case 125: move(by: 1); return true                 // ↓
        case 36, 76: commit(); return true                 // return / enter
        default:
            guard let digit = Self.digitCodes.firstIndex(of: keyCode), digit < presets.count else { return false }
            pick(digit)
            return true
        }
    }
}

/// A borderless panel that can take keys without activating the app — the picker has to answer Esc and
/// the arrows while the user's editor still owns the keyboard *focus ring*, not the app activation.
final class SnapPickerPanel: NSPanel {
    var onKeyCode: ((UInt16) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        guard onKeyCode?(event.keyCode) == true else {
            super.keyDown(with: event)
            return
        }
    }
}

@MainActor
final class SnapPickerController: NSObject, NSWindowDelegate {
    static let shared = SnapPickerController()

    private let model = SnapPickerModel()
    private var panel: SnapPickerPanel?
    private var hosting: NSHostingView<SnapPickerView>?
    /// AT-7: a click-through ghost of the target frame, so a card is a picture of the result rather
    /// than a guess. Removed whenever the picker closes.
    private var ghostPanel: NSPanel?

    private override init() {
        super.init()
        model.onDismiss = { [weak self] in self?.dismiss() }
        // The picker applies through the same service the dock and the hot keys use, so a zone means the
        // same frame however it was chosen.
        model.onPick = { zone in WindowSnapService.apply(zone) }
        model.onHover = { [weak self] zone in self?.showGhost(zone) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the grid at the configured placement (AT-7), clamped to the screen under the pointer or
    /// the anchor. Density and placement are read on every open, so a Settings change applies live.
    func present(anchor: CGRect? = nil) {
        let panel = ensurePanel()
        model.reset()

        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor?.origin ?? pointer) })
                ?? NSScreen.main else { return }
        let placement = SnapPanelPlacement.current()
        let density = SnapGridDensity.current()
        hosting?.rootView = SnapPickerView(model: model, density: density,
                                           isFullScreen: placement == .fullScreen)
        var size = hosting?.fittingSize ?? panel.frame.size
        if placement == .fullScreen {
            let visible = screen.visibleFrame
            size = CGSize(width: max(size.width, visible.width - 48),
                          height: max(size.height, visible.height - 48))
        }
        let frame = SnapPanelGeometry.frame(
            placement: placement,
            panelSize: size,
            pointer: pointer,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            anchor: anchor,
            notchInset: screen.safeAreaInsets.top,
            menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY
        )
        panel.setFrame(frame, display: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
        ghostPanel?.orderOut(nil)
    }

    /// AT-7: draws the target zone on the display under the pointer while a card is hovered.
    private func showGhost(_ zone: SnapPosition?) {
        guard let zone, isVisible,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            ghostPanel?.orderOut(nil)
            return
        }
        let panel = ensureGhostPanel()
        let frame = zone.frame(in: WindowSnapService.workArea(of: screen), gaps: SnapGaps.current())
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func ensureGhostPanel() -> NSPanel {
        if let ghostPanel { return ghostPanel }
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = NSView()
        view.wantsLayer = true
        view.layer?.borderColor = NSColor.controlAccentColor.cgColor
        view.layer?.borderWidth = 2
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        panel.contentView = view
        ghostPanel = panel
        return panel
    }

    private func ensurePanel() -> SnapPickerPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: SnapPickerView(model: model, density: SnapGridDensity.current()))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = SnapPickerPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        // The picker is the one elevated panel that must take clicks: its cards are the UI.
        // INPUT-HYGIENE: INTERACTIVE
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.onKeyCode = { [weak self] code in self?.model.handle(keyCode: code) ?? false }
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    /// A click anywhere else is a dismissal, not a stray pick.
    func windowDidResignKey(_ notification: Notification) {
        dismiss()
    }
}

struct SnapPickerView: View {
    @ObservedObject var model: SnapPickerModel
    /// AT-7: cards resize with the density setting; the keyboard model does not change.
    var density: SnapGridDensity = .regular
    var isFullScreen = false
    @Environment(\.colorScheme) private var scheme

    private var ink: Color { scheme == .dark ? .white : .black }
    private var fill: Color { ink.opacity(scheme == .dark ? 0.10 : 0.06) }
    private var stroke: Color { ink.opacity(scheme == .dark ? 0.16 : 0.10) }
    private var accent: Color { .accentColor }

    var body: some View {
        VStack(spacing: density.spacing) {
            HStack(spacing: 8) {
                Text(verbatim: "snApp")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.7))
                Spacer(minLength: 12)
                Text(verbatim: "1–8")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(ink.opacity(0.45))
            }
            .padding(.horizontal, 2)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: density.spacing), count: density.columns),
                spacing: density.spacing
            ) {
                ForEach(Array(model.presets.enumerated()), id: \.offset) { index, preset in
                    card(index, preset)
                }
            }
            .frame(maxWidth: density.cardSize.width * CGFloat(density.columns)
                + density.spacing * CGFloat(density.columns - 1))
        }
        .padding(density.padding)
        .frame(maxWidth: isFullScreen ? .infinity : nil, maxHeight: isFullScreen ? .infinity : nil)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ink.opacity(scheme == .dark ? 0.04 : 0.02)))
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(stroke, lineWidth: 1))
    }

    private func card(_ index: Int, _ preset: SnapLayoutPreset) -> some View {
        let cardHighlighted = model.selected == index || preset.zones.contains(where: { $0 == model.hoveredZone })
        return VStack(spacing: 3) {
            GeometryReader { geo in shapes(of: preset, in: geo.size) }
                .frame(height: density.cardSize.height - 15)
            HStack(spacing: 3) {
                Text(SnapLayoutCatalog.titleKey(for: preset))
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: "\(index + 1)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(ink.opacity(0.45))
            }
        }
        .padding(6)
        .frame(width: density.cardSize.width, height: density.cardSize.height)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(cardHighlighted ? accent.opacity(0.14) : fill))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(cardHighlighted ? accent.opacity(0.75) : stroke, lineWidth: cardHighlighted ? 1.5 : 1))
    }

    /// Draws each selectable area inside the card as its own button so every half, quarter, third,
    /// ⅔ split, and maximize zone is individually clickable and keyboard-selectable.
    private func shapes(of preset: SnapLayoutPreset, in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(preset.areas.enumerated()), id: \.offset) { _, area in
                let w = area.unit.width * size.width
                let h = area.unit.height * size.height
                let x = area.unit.minX * size.width
                let y = (1 - area.unit.maxY) * size.height
                let active = model.selectedZone == area.zone || model.hoveredZone == area.zone
                Button { model.pick(zone: area.zone) } label: {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active ? accent.opacity(0.55) : ink.opacity(0.24))
                        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(active ? accent : Color.clear, lineWidth: 1))
                        .overlay(alignment: .center) {
                            if let label = area.label {
                                Text(verbatim: label)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(active ? Color.white : ink.opacity(0.75))
                            }
                        }
                        .frame(width: max(3, w - 3), height: max(3, h - 3))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { model.hover(area.zone) }
                    else if model.hoveredZone == area.zone { model.hover(nil) }
                }
                .accessibilityLabel(Self.accessibilityTitle(for: area.zone))
                .offset(x: x + 1.5, y: y + 1.5)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private static func accessibilityTitle(for zone: SnapPosition) -> Text {
        switch zone {
        case .leftHalf: return Text("Left Half")
        case .rightHalf: return Text("Right Half")
        case .topHalf: return Text("Top Half")
        case .bottomHalf: return Text("Bottom Half")
        case .topLeft: return Text("Top Left")
        case .topRight: return Text("Top Right")
        case .bottomLeft: return Text("Bottom Left")
        case .bottomRight: return Text("Bottom Right")
        case .leftThird: return Text("Left Third")
        case .centerThird: return Text("Center Third")
        case .rightThird: return Text("Right Third")
        case .leftTwoThirds: return Text("Left Two Thirds")
        case .rightTwoThirds: return Text("Right Two Thirds")
        case .center: return Text("Center")
        case .focus: return Text("Focus")
        case .maximize: return Text("Maximize")
        }
    }
}
