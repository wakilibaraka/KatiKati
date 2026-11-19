import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Per-widget appearance customization popover triggered from the folder box overflow menu.
struct DesktopBoxAppearancePopover: View {
    let item: DesktopWidgetItem
    let canvasTheme: DesktopCanvasThemeState
    let onUpdate: (DesktopWidgetItem) -> Void
    let onReset: () -> Void

    @State private var emojiDraft = ""

    private enum IconMode: Hashable { case systemDefault, emoji, sfSymbol, customImage }
    private enum BackgroundMode: Hashable { case materialOnly, tint, image, panorama }

    private static let emojiPresets = ["📁", "📌", "⭐️", "🚀", "📦", "🎨"]
    private static let symbolPresets = [
        "folder.fill", "tray.fill", "star.fill", "bookmark.fill",
        "sparkles", "photo.fill", "doc.text.fill", "music.note",
    ]
    private static let accentPresets = [
        "#3B82F6", "#8B5CF6", "#EC4899", "#F97316", "#10B981", "#EAB308",
    ]

    private var iconMode: IconMode {
        switch item.appearance.iconBadge {
        case .systemDefault: return .systemDefault
        case .emoji: return .emoji
        case .sfSymbol: return .sfSymbol
        case .customImage: return .customImage
        }
    }

    private var backgroundMode: BackgroundMode {
        switch item.appearance.background {
        case .materialOnly: return .materialOnly
        case .tint: return .tint
        case .image: return .image
        case .panorama: return .panorama
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                iconSection
                Divider()
                materialSection
                Divider()
                backgroundSection
                Divider()
                borderAndCornersSection
                Divider()
                textTreatmentSection
                Divider()
                HStack {
                    Spacer()
                    Button("Reset Appearance", action: onReset).buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(12)
        }
        .frame(width: 280)
        .frame(maxHeight: 460)
        .onAppear { syncEmojiDraft() }
        .onChange(of: item.appearance.iconBadge) { _, _ in syncEmojiDraft() }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Icon Badge").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(selection: Binding(get: { iconMode }, set: { applyIconMode($0) })) {
                Text("Default").tag(IconMode.systemDefault)
                Text("Emoji").tag(IconMode.emoji)
                Text("Symbol").tag(IconMode.sfSymbol)
                Text("Image").tag(IconMode.customImage)
            } label: { EmptyView() }
            .pickerStyle(.segmented).controlSize(.small)

            switch item.appearance.iconBadge {
            case .systemDefault:
                EmptyView()
            case .emoji(let current):
                HStack(spacing: 6) {
                    ForEach(Self.emojiPresets, id: \.self) { emoji in
                        Button { updateAppearance { $0.iconBadge = .emoji(emoji) } } label: {
                            Text(verbatim: emoji)
                                .padding(4)
                                .background(current == emoji ? Color.accentColor.opacity(0.22) : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    TextField(text: $emojiDraft) { EmptyView() }
                        .textFieldStyle(.roundedBorder).frame(width: 38)
                        .accessibilityLabel(Text("Custom Emoji"))
                        .onChange(of: emojiDraft) { _, next in
                            if let ch = next.trimmingCharacters(in: .whitespacesAndNewlines).first {
                                let single = String(ch)
                                if emojiDraft != single { emojiDraft = single }
                                updateAppearance { $0.iconBadge = .emoji(single) }
                            }
                        }
                }
            case .sfSymbol(let current):
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(Self.symbolPresets, id: \.self) { sym in
                        Button { updateAppearance { $0.iconBadge = .sfSymbol(sym) } } label: {
                            Image(systemName: sym).frame(maxWidth: .infinity, minHeight: 24)
                                .background(current == sym ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .customImage(let path):
                imageRow(path: path) { pickAndImportImage(kind: .widgetIcon) }
            }
        }
    }

    private var materialSection: some View {
        HStack {
            Text("Material").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Picker(selection: Binding(get: { item.appearance.materialOverride }, set: { next in updateAppearance { $0.materialOverride = next } })) {
                Text("Default").tag(Optional<DesktopBoxMaterialStyle>.none)
                Text("Inherit Dock").tag(Optional(DesktopBoxMaterialStyle.inheritDock))
                Text("Frosted Glass").tag(Optional(DesktopBoxMaterialStyle.frostedGlass))
                Text("Tinted Glass").tag(Optional(DesktopBoxMaterialStyle.tintedGlass))
                Text("Solid Card").tag(Optional(DesktopBoxMaterialStyle.solidCard))
                Text("Clear").tag(Optional(DesktopBoxMaterialStyle.clearMinimal))
            } label: { EmptyView() }
            .labelsHidden().controlSize(.small)
        }
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Background").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Picker(selection: Binding(get: { backgroundMode }, set: { applyBackgroundMode($0) })) {
                Text("Material Only").tag(BackgroundMode.materialOnly)
                Text("Color Tint").tag(BackgroundMode.tint)
                Text("Image").tag(BackgroundMode.image)
                Text("Panorama").tag(BackgroundMode.panorama)
            } label: { EmptyView() }
            .pickerStyle(.segmented).controlSize(.small)

            switch item.appearance.background {
            case .materialOnly, .panorama:
                EmptyView()
            case .tint(let hex, let opacity):
                swatchRow(selectedHex: hex, allowDefault: false) { chosen in
                    if let chosen { updateAppearance { $0.background = .tint(hex: chosen, opacity: opacity) } }
                }
                sliderRow(Text("Opacity"), value: opacity, range: 0.05...1.0, valueText: "\(Int((opacity * 100).rounded()))%") { next in
                    updateAppearance { $0.background = .tint(hex: hex, opacity: next) }
                }
            case .image(let path, let opacity, let blur):
                imageRow(path: path) { pickAndImportImage(kind: .widgetBackground) }
                sliderRow(Text("Opacity"), value: opacity, range: 0.05...1.0, valueText: "\(Int((opacity * 100).rounded()))%") { next in
                    updateAppearance { $0.background = .image(path: path, opacity: next, blurRadius: blur) }
                }
                sliderRow(Text("Blur"), value: blur, range: 0...24, valueText: "\(Int(blur.rounded())) pt") { next in
                    updateAppearance { $0.background = .image(path: path, opacity: opacity, blurRadius: next) }
                }
            }
        }
    }

    private var borderAndCornersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Border").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Picker(selection: Binding(get: { item.appearance.borderStyle }, set: { next in updateAppearance { $0.borderStyle = next } })) {
                    Text("Standard").tag(DesktopBoxBorderStyle.standard)
                    Text("Glow").tag(DesktopBoxBorderStyle.glow)
                    Text("Hairline").tag(DesktopBoxBorderStyle.hairline)
                    Text("None").tag(DesktopBoxBorderStyle.none)
                } label: { EmptyView() }
                .labelsHidden().controlSize(.small)
            }

            Text("Accent Color").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            swatchRow(selectedHex: item.appearance.accentHex, allowDefault: true) { chosen in
                updateAppearance { $0.accentHex = chosen }
            }

            let radius = Double(item.appearance.cornerRadiusOverride ?? DockShape.panelCornerRadius)
            let range = Double(DesktopCanvasConfig.cornerRadiusRange.lowerBound)...Double(DesktopCanvasConfig.cornerRadiusRange.upperBound)
            sliderRow(Text("Corner Radius"), value: radius, range: range, valueText: "\(Int(radius.rounded())) pt") { next in
                updateAppearance { $0.cornerRadiusOverride = CGFloat(next) }
            }
        }
    }

    private var textTreatmentSection: some View {
        HStack {
            Text("Text Style").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Picker(selection: Binding(get: { item.appearance.textTreatment }, set: { next in updateAppearance { $0.textTreatment = next } })) {
                Text("Auto").tag(DesktopBoxTextTreatment.auto)
                Text("Shadowed").tag(DesktopBoxTextTreatment.shadowed)
                Text("High Contrast").tag(DesktopBoxTextTreatment.highContrast)
                Text("Monospaced").tag(DesktopBoxTextTreatment.monospaced)
            } label: { EmptyView() }
            .labelsHidden().controlSize(.small)
        }
    }

    private func imageRow(path: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: path.isEmpty ? "—" : URL(fileURLWithPath: path).lastPathComponent)
                .font(.caption).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer()
            Button("Choose Image…", action: action).controlSize(.small)
        }
    }

    private func swatchRow(selectedHex: String?, allowDefault: Bool, onSelect: @escaping (String?) -> Void) -> some View {
        HStack(spacing: 8) {
            if allowDefault {
                Button { onSelect(nil) } label: {
                    Image(systemName: "circle.slash").font(.system(size: 13)).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(selectedHex == nil ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: selectedHex == nil ? 2 : 1))
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Default"))
            }
            ForEach(Self.accentPresets, id: \.self) { hex in
                let rgb = DesktopHexColor.parse(hex)
                let color = rgb.map { Color(red: $0.r, green: $0.g, blue: $0.b) } ?? .accentColor
                let selected = DesktopHexColor.normalized(selectedHex ?? "") == hex
                Button { onSelect(hex) } label: {
                    Circle().fill(color).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 2))
                }
                .buttonStyle(.plain).accessibilityLabel(Text(verbatim: hex))
            }
        }
    }

    private func sliderRow(_ title: Text, value: Double, range: ClosedRange<Double>, valueText: String, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                title.font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(verbatim: valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { value }, set: onChange), in: range).controlSize(.small)
        }
    }

    private func updateAppearance(_ mutate: (inout DesktopWidgetAppearance) -> Void) {
        var copy = item
        mutate(&copy.appearance)
        let a = copy.appearance
        copy.appearance = DesktopWidgetAppearance(
            materialOverride: a.materialOverride,
            borderStyle: a.borderStyle,
            accentHex: a.accentHex,
            textTreatment: a.textTreatment,
            iconBadge: a.iconBadge,
            background: a.background,
            cornerRadiusOverride: a.cornerRadiusOverride
        )
        onUpdate(copy)
    }

    private func syncEmojiDraft() {
        if case .emoji(let value) = item.appearance.iconBadge { emojiDraft = value } else { emojiDraft = "" }
    }

    private func applyIconMode(_ mode: IconMode) {
        switch mode {
        case .systemDefault: updateAppearance { $0.iconBadge = .systemDefault }
        case .emoji: updateAppearance { $0.iconBadge = .emoji(emojiDraft.first.map(String.init) ?? "📁") }
        case .sfSymbol: updateAppearance { $0.iconBadge = .sfSymbol("folder.fill") }
        case .customImage: pickAndImportImage(kind: .widgetIcon)
        }
    }

    private func applyBackgroundMode(_ mode: BackgroundMode) {
        switch mode {
        case .materialOnly: updateAppearance { $0.background = .materialOnly }
        case .tint: updateAppearance { $0.background = .tint(hex: "#3B82F6", opacity: 0.28) }
        case .image: pickAndImportImage(kind: .widgetBackground)
        case .panorama:
            let _ = canvasTheme
            updateAppearance { $0.background = .panorama }
        }
    }

    private func pickAndImportImage(kind: DesktopAssetKind) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let imported = try? DesktopAssetStore.importImage(from: url, kind: kind)
        else { return }
        if kind == .widgetIcon {
            updateAppearance { $0.iconBadge = .customImage(imported.path) }
        } else if kind == .widgetBackground {
            updateAppearance { $0.background = .image(path: imported.path, opacity: 0.72, blurRadius: 0) }
        }
    }
}
