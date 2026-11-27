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
    private var selectedAreaIndex: Int?

    /// Flattened list of every individual shape across all five cards so keyboard arrows reach all 12 zones.
    private var allAreas: [(presetIndex: Int, zone: SnapPosition)] {
        presets.enumerated().flatMap { presetIndex, preset in
            preset.areas.map { (presetIndex, $0.zone) }
        }
    }

    var onPick: ((SnapPosition) -> Void)?
    var onDismiss: (() -> Void)?

    /// Digit key codes, 1…5, in order.
    private static let digitCodes: [UInt16] = [18, 19, 20, 21, 23]

    /// A fresh open starts with nothing picked, so Return cannot fire a stale card.
    func reset() {
        selected = nil
        selectedZone = nil
        selectedAreaIndex = nil
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

    private override init() {
        super.init()
        model.onDismiss = { [weak self] in self?.dismiss() }
        // The picker applies through the same service the dock and the hot keys use, so a zone means the
        // same frame however it was chosen.
        model.onPick = { zone in WindowSnapService.apply(zone) }
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Shows the grid under `anchor` (screen coordinates) or at the pointer, clamped to the screen.
    func present(anchor: CGRect? = nil) {
        let panel = ensurePanel()
        model.reset()

        let size = panel.frame.size
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchor?.origin ?? pointer) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var origin: CGPoint
        if let anchor, !anchor.isEmpty {
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - size.height - 10)
            if origin.y < visible.minY + 8 { origin.y = anchor.maxY + 10 }
        } else {
            origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 14)
            if origin.y < visible.minY + 8 { origin.y = pointer.y + 14 }
        }
        origin.x = min(max(origin.x, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        origin.y = min(max(origin.y, visible.minY + 8), max(visible.minY + 8, visible.maxY - size.height - 8))

        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        panel?.orderOut(nil)
    }

    private func ensurePanel() -> SnapPickerPanel {
        if let panel { return panel }

        let hosting = NSHostingView(rootView: SnapPickerView(model: model))
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
    @Environment(\.colorScheme) private var scheme
    @State private var hoveredZone: SnapPosition?

    private var ink: Color { scheme == .dark ? .white : .black }
    private var fill: Color { ink.opacity(scheme == .dark ? 0.10 : 0.06) }
    private var stroke: Color { ink.opacity(scheme == .dark ? 0.16 : 0.10) }
    private var accent: Color { .accentColor }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { ForEach(0..<min(3, model.presets.count), id: \.self) { card($0) } }
            if model.presets.count > 3 {
                HStack(spacing: 10) { ForEach(3..<model.presets.count, id: \.self) { card($0) } }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(ink.opacity(scheme == .dark ? 0.04 : 0.02)))
        }
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(stroke, lineWidth: 1))
    }

    private func card(_ index: Int) -> some View {
        let preset = model.presets[index]
        let cardHighlighted = model.selected == index || preset.zones.contains(where: { $0 == hoveredZone })
        return GeometryReader { geo in shapes(of: preset, in: geo.size) }
            .frame(width: 92, height: 62)
            .padding(7)
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
                let active = model.selectedZone == area.zone || hoveredZone == area.zone
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
                    if inside { hoveredZone = area.zone } else if hoveredZone == area.zone { hoveredZone = nil }
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
        case .maximize: return Text("Maximize")
        }
    }
}
