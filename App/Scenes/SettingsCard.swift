import SwiftUI

// Phase 12 (2026-10-15) — the Settings window's one card and one row type (`Docs/SETTINGS.md`,
// rules 2 and 3). Before this file the pages rendered sections through three different boxes
// (`SettingsLayoutPane.section`, `settingsGroup`, the system grouped `Form`) and five different row
// idioms (groupRow, edgePrefRow, segmentedRow, sliderRow, hand-rolled HStacks), so the same content
// landed at a different inset and a different rhythm on every page.
//
// Every user-facing literal is passed in as a `Text`, so `Scripts/check_localization.py` keeps
// finding the keys — never pass a bare string.
//
// Dual-compiled with the test target: `SettingsLayoutPane` compiles into both, so anything it uses
// must too (the app-only/dual-compiled trap that broke the test gate before).

private struct SettingsLiveWindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = SettingsMetrics.windowWidth
}

extension EnvironmentValues {
    var settingsLiveWindowWidth: CGFloat {
        get { self[SettingsLiveWindowWidthKey.self] }
        set { self[SettingsLiveWindowWidthKey.self] = newValue }
    }
}

/// Dynamic iridescent palette derived from the active `DockThemeStyle` and `ColorScheme`.
/// Powers the Neo-Glassmorphic cards, gel buttons, iridescent borders, and floating navigation bar.
struct SettingsIridescentPalette {
    let primaryAccent: Color
    let secondaryAccent: Color
    let tertiaryAccent: Color
    let sheenColor: Color
    let rimTopColor: Color
    let rimBottomColor: Color
    let cardTintTop: Color
    let cardTintBottom: Color
    let glowColor: Color

    static func resolve(style: DockThemeStyle, colorScheme: ColorScheme) -> SettingsIridescentPalette {
        let isDark = colorScheme == .dark
        let appearance: AppearanceMode = isDark ? .dark : .light
        let resolvedStyle = style.resolved(for: appearance)

        switch resolvedStyle {
        case .auroraGlow:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.22, green: 0.86, blue: 0.68),
                secondaryAccent: Color(red: 0.30, green: 0.66, blue: 0.96),
                tertiaryAccent: Color(red: 0.56, green: 0.45, blue: 0.96),
                sheenColor: Color(red: 0.55, green: 0.96, blue: 0.82),
                rimTopColor: Color(red: 0.45, green: 0.95, blue: 0.78).opacity(isDark ? 0.42 : 0.55),
                rimBottomColor: Color(red: 0.25, green: 0.62, blue: 0.92).opacity(isDark ? 0.16 : 0.24),
                cardTintTop: Color(red: 0.16, green: 0.75, blue: 0.62).opacity(isDark ? 0.10 : 0.12),
                cardTintBottom: Color(red: 0.25, green: 0.55, blue: 0.92).opacity(isDark ? 0.05 : 0.07),
                glowColor: Color(red: 0.24, green: 0.88, blue: 0.70).opacity(isDark ? 0.28 : 0.22)
            )
        case .deepOcean:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.24, green: 0.62, blue: 0.98),
                secondaryAccent: Color(red: 0.42, green: 0.48, blue: 0.96),
                tertiaryAccent: Color(red: 0.18, green: 0.82, blue: 0.92),
                sheenColor: Color(red: 0.55, green: 0.82, blue: 1.0),
                rimTopColor: Color(red: 0.45, green: 0.76, blue: 1.0).opacity(isDark ? 0.42 : 0.55),
                rimBottomColor: Color(red: 0.36, green: 0.42, blue: 0.94).opacity(isDark ? 0.16 : 0.24),
                cardTintTop: Color(red: 0.18, green: 0.52, blue: 0.94).opacity(isDark ? 0.11 : 0.12),
                cardTintBottom: Color(red: 0.38, green: 0.36, blue: 0.90).opacity(isDark ? 0.05 : 0.07),
                glowColor: Color(red: 0.25, green: 0.64, blue: 0.98).opacity(isDark ? 0.28 : 0.22)
            )
        case .forestMoss:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.34, green: 0.82, blue: 0.52),
                secondaryAccent: Color(red: 0.20, green: 0.72, blue: 0.68),
                tertiaryAccent: Color(red: 0.58, green: 0.86, blue: 0.38),
                sheenColor: Color(red: 0.66, green: 0.94, blue: 0.72),
                rimTopColor: Color(red: 0.50, green: 0.88, blue: 0.60).opacity(isDark ? 0.40 : 0.52),
                rimBottomColor: Color(red: 0.22, green: 0.66, blue: 0.58).opacity(isDark ? 0.16 : 0.24),
                cardTintTop: Color(red: 0.26, green: 0.70, blue: 0.44).opacity(isDark ? 0.10 : 0.11),
                cardTintBottom: Color(red: 0.18, green: 0.58, blue: 0.54).opacity(isDark ? 0.05 : 0.07),
                glowColor: Color(red: 0.34, green: 0.82, blue: 0.52).opacity(isDark ? 0.26 : 0.20)
            )
        case .cyberpunkGlass:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.88, green: 0.32, blue: 0.92),
                secondaryAccent: Color(red: 0.36, green: 0.52, blue: 0.98),
                tertiaryAccent: Color(red: 0.98, green: 0.38, blue: 0.66),
                sheenColor: Color(red: 0.96, green: 0.62, blue: 0.98),
                rimTopColor: Color(red: 0.94, green: 0.46, blue: 0.94).opacity(isDark ? 0.46 : 0.58),
                rimBottomColor: Color(red: 0.38, green: 0.50, blue: 0.98).opacity(isDark ? 0.20 : 0.28),
                cardTintTop: Color(red: 0.82, green: 0.28, blue: 0.88).opacity(isDark ? 0.12 : 0.13),
                cardTintBottom: Color(red: 0.34, green: 0.46, blue: 0.96).opacity(isDark ? 0.06 : 0.08),
                glowColor: Color(red: 0.88, green: 0.34, blue: 0.92).opacity(isDark ? 0.32 : 0.24)
            )
        case .emberSunset:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.98, green: 0.48, blue: 0.32),
                secondaryAccent: Color(red: 0.94, green: 0.34, blue: 0.62),
                tertiaryAccent: Color(red: 0.98, green: 0.68, blue: 0.28),
                sheenColor: Color(red: 1.0, green: 0.74, blue: 0.56),
                rimTopColor: Color(red: 0.98, green: 0.58, blue: 0.40).opacity(isDark ? 0.44 : 0.56),
                rimBottomColor: Color(red: 0.90, green: 0.34, blue: 0.58).opacity(isDark ? 0.18 : 0.26),
                cardTintTop: Color(red: 0.94, green: 0.44, blue: 0.30).opacity(isDark ? 0.11 : 0.12),
                cardTintBottom: Color(red: 0.88, green: 0.30, blue: 0.54).opacity(isDark ? 0.05 : 0.08),
                glowColor: Color(red: 0.98, green: 0.48, blue: 0.32).opacity(isDark ? 0.30 : 0.22)
            )
        case .roseQuartz:
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.94, green: 0.46, blue: 0.68),
                secondaryAccent: Color(red: 0.62, green: 0.48, blue: 0.96),
                tertiaryAccent: Color(red: 0.36, green: 0.68, blue: 0.98),
                sheenColor: Color(red: 0.98, green: 0.76, blue: 0.88),
                rimTopColor: Color(red: 0.96, green: 0.60, blue: 0.78).opacity(isDark ? 0.42 : 0.56),
                rimBottomColor: Color(red: 0.58, green: 0.48, blue: 0.94).opacity(isDark ? 0.18 : 0.25),
                cardTintTop: Color(red: 0.92, green: 0.46, blue: 0.68).opacity(isDark ? 0.10 : 0.13),
                cardTintBottom: Color(red: 0.54, green: 0.50, blue: 0.94).opacity(isDark ? 0.05 : 0.08),
                glowColor: Color(red: 0.94, green: 0.46, blue: 0.68).opacity(isDark ? 0.28 : 0.22)
            )
        case let .customRGBA(r, g, b, _):
            let base = Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b))
            let comp = Color(.sRGB, red: Double(min(1, b * 0.85 + 0.15)), green: Double(min(1, r * 0.7 + 0.2)), blue: Double(min(1, g * 0.85 + 0.15)))
            return SettingsIridescentPalette(
                primaryAccent: base,
                secondaryAccent: comp,
                tertiaryAccent: Color(red: 0.58, green: 0.46, blue: 0.96),
                sheenColor: base.opacity(0.85),
                rimTopColor: base.opacity(isDark ? 0.44 : 0.55),
                rimBottomColor: comp.opacity(isDark ? 0.18 : 0.25),
                cardTintTop: base.opacity(isDark ? 0.11 : 0.12),
                cardTintBottom: comp.opacity(isDark ? 0.05 : 0.07),
                glowColor: base.opacity(isDark ? 0.28 : 0.22)
            )
        default:
            // Default Vision Pro blue-pink-purple iridescent spectrum
            return SettingsIridescentPalette(
                primaryAccent: Color(red: 0.34, green: 0.56, blue: 0.98),
                secondaryAccent: Color(red: 0.68, green: 0.42, blue: 0.96),
                tertiaryAccent: Color(red: 0.94, green: 0.46, blue: 0.74),
                sheenColor: Color(red: 0.78, green: 0.68, blue: 1.0),
                rimTopColor: Color(red: 0.56, green: 0.68, blue: 1.0).opacity(isDark ? 0.38 : 0.52),
                rimBottomColor: Color(red: 0.86, green: 0.48, blue: 0.84).opacity(isDark ? 0.16 : 0.24),
                cardTintTop: Color(red: 0.36, green: 0.54, blue: 0.98).opacity(isDark ? 0.09 : 0.11),
                cardTintBottom: Color(red: 0.78, green: 0.42, blue: 0.90).opacity(isDark ? 0.05 : 0.07),
                glowColor: Color(red: 0.52, green: 0.48, blue: 0.98).opacity(isDark ? 0.26 : 0.20)
            )
        }
    }

    var pillGradient: LinearGradient {
        LinearGradient(
            colors: [primaryAccent, secondaryAccent, tertiaryAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var subtleSurfaceGradient: LinearGradient {
        LinearGradient(
            colors: [cardTintTop, cardTintBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var rimGradient: LinearGradient {
        LinearGradient(
            colors: [rimTopColor, rimBottomColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Gel-like button style with specular top highlight, iridescent gradient fill on hover/press,
/// soft shadow, and spring scale feedback.
struct SettingsGelButtonStyle: ButtonStyle {
    @Environment(\.dockThemeStyle) private var themeStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    var prominent: Bool = false
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let palette = SettingsIridescentPalette.resolve(style: themeStyle, colorScheme: colorScheme)
        let isDark = colorScheme == .dark
        let active = prominent || isHovered || configuration.isPressed

        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(
                !isEnabled
                    ? Color.secondary.opacity(0.55)
                    : (prominent ? Color.white : Color.primary.opacity(active ? 1.0 : 0.92))
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    Capsule(style: .continuous)
                        .fill(
                            prominent
                                ? AnyShapeStyle(palette.pillGradient)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            active
                                                ? palette.primaryAccent.opacity(isDark ? 0.28 : 0.20)
                                                : Color.primary.opacity(isDark ? 0.10 : 0.06),
                                            active
                                                ? palette.secondaryAccent.opacity(isDark ? 0.20 : 0.14)
                                                : Color.primary.opacity(isDark ? 0.06 : 0.03)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                    // Top specular gel highlight
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isDark ? (active ? 0.26 : 0.14) : (active ? 0.55 : 0.38)),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                active ? palette.rimTopColor : Color.white.opacity(isDark ? 0.22 : 0.45),
                                active ? palette.rimBottomColor : Color.primary.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: active ? palette.glowColor : Color.black.opacity(isDark ? 0.22 : 0.08),
                radius: active ? 6 : 2,
                x: 0,
                y: active ? 2 : 1
            )
            .scaleEffect(configuration.isPressed ? 0.96 : (isHovered && isEnabled ? 1.02 : 1.0))
            .animation(.spring(response: 0.24, dampingFraction: 0.74), value: isHovered)
            .animation(.spring(response: 0.18, dampingFraction: 0.72), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}

/// Two-column adaptive Bento row for side-by-side cards when the window is wide enough,
/// collapsing cleanly into a vertical stack on narrower windows.
struct SettingsBentoSplit<Leading: View, Trailing: View>: View {
    @Environment(\.settingsLiveWindowWidth) private var windowWidth
    private let leading: Leading
    private let trailing: Trailing

    init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        if windowWidth >= 820 {
            HStack(alignment: .top, spacing: SettingsMetrics.sectionSpacing) {
                leading.frame(maxWidth: .infinity, alignment: .topLeading)
                trailing.frame(maxWidth: .infinity, alignment: .topLeading)
            }
        } else {
            VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
                leading
                trailing
            }
        }
    }
}

/// A page's stack of cards: one gap between sections, the page margin on both sides (rule 1).
struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, SettingsMetrics.paneMargin)
    }
}

/// One section: optional header, its rows, an optional one-line note (rule 4 — anything longer
/// belongs behind an info button on the row it explains).
/// Styled with Neo-Glassmorphism: translucent material, dynamic Dock-theme iridescence, soft
/// inner specular highlight, gradient border rim, and subtle hover elevation.
struct SettingsCard<Content: View>: View {
    @Environment(\.dockThemeStyle) private var themeStyle
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private let header: Text?
    private let note: Text?
    private let content: Content

    init(_ header: Text? = nil, note: Text? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.note = note
        self.content = content()
    }

    var body: some View {
        let palette = SettingsIridescentPalette.resolve(style: themeStyle, colorScheme: colorScheme)
        let isDark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius + 4, style: .continuous)

        VStack(alignment: .leading, spacing: SettingsMetrics.cardHeaderSpacing) {
            if let header {
                HStack(spacing: 8) {
                    Capsule(style: .continuous)
                        .fill(palette.pillGradient)
                        .frame(width: 4, height: 15)
                        .shadow(color: palette.glowColor, radius: 3, x: 0, y: 0)
                        .accessibilityHidden(true)
                    header
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color.primary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            if let note {
                SettingsNote(note)
            }
        }
        .padding(SettingsMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(Color.primary.opacity(SettingsMetrics.cardFillOpacity))
                shape.fill(palette.subtleSurfaceGradient)
                // Top specular gel reflection
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? (isHovered ? 0.10 : 0.06) : (isHovered ? 0.42 : 0.28)),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        )
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        isHovered ? palette.rimTopColor : palette.rimTopColor.opacity(0.68),
                        isHovered ? palette.rimBottomColor : Color.primary.opacity(isDark ? 0.12 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isHovered ? 1.25 : 1.0
            )
        )
        .shadow(
            color: isHovered ? palette.glowColor.opacity(0.45) : Color.black.opacity(isDark ? 0.24 : 0.07),
            radius: isHovered ? 12 : 7,
            x: 0,
            y: isHovered ? 4 : 2
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

/// A row whose control sits at the trailing edge: menus, buttons, custom controls.
struct SettingsRow<Control: View>: View {
    private let label: Text
    private let note: Text?
    private let info: String?
    private let control: Control

    init(_ label: Text, note: Text? = nil, info: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label
        self.note = note
        self.info = info
        self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                HStack(spacing: 6) {
                    label
                    if let info {
                        SettingsInfoButton(text: info)
                    }
                }
                Spacer(minLength: SettingsMetrics.rowMinimumLabelGap)
                control
            }
            if let note {
                SettingsNote(note)
            }
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A switch row. The switch is `labelsHidden` and takes its VoiceOver label from the row, so the
/// row reads as one control and the switch is never unlabelled (rule 9).
struct SettingsToggleRow: View {
    private let label: Text
    private let note: Text?
    private let info: String?
    private let isOn: Binding<Bool>

    init(_ label: Text, isOn: Binding<Bool>, note: Text? = nil, info: String? = nil) {
        self.label = label
        self.isOn = isOn
        self.note = note
        self.info = info
    }

    var body: some View {
        SettingsRow(label, note: note, info: info) {
            Toggle(isOn: isOn) { label }
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}

/// A checklist cell: a checkbox with its name beside it, laid out by `SettingsGrid`. This is the
/// control the window's checklists have always used (what tiles exist, which quick settings show,
/// which apps the launcher hides), and it stays deliberately shorter than a settings row
/// (`SettingsMetrics.gridRowVerticalPadding`) — eighteen of these are a list to scan, not eighteen
/// preferences. The checkbox takes its name from the cell for VoiceOver (rule 9).
struct SettingsCheckboxRow: View {
    private let label: Text
    private let isOn: Binding<Bool>

    init(_ label: Text, isOn: Binding<Bool>) {
        self.label = label
        self.isOn = isOn
    }

    var body: some View {
        Toggle(isOn: isOn) { label }
            .toggleStyle(.checkbox)
            .accessibilityLabel(label)
            .padding(.vertical, SettingsMetrics.gridRowVerticalPadding)
    }
}

/// The ⓘ that carries a row's long explanation (`Docs/SETTINGS.md` rule 4): the note under a row
/// stays one line, and anything longer opens on demand on the row it explains.
struct SettingsInfoButton: View {
    /// A plain `String` rather than a `Text`: the call site passes the same already-localized string
    /// to VoiceOver and to the popover, so the disclosure is never read twice from two keys.
    let text: String

    @State private var shows = false

    var body: some View {
        Button { shows = true } label: {
            // A text-sized symbol, not the system help bezel: that one is as tall as the row.
            Image(systemName: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        // A bare symbol reads as an unnamed button; say the disclosure itself.
        .accessibilityLabel(Text(text))
        .popover(isPresented: $shows, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(14)
        }
    }
}

/// A card's rows in two columns (`Docs/SETTINGS.md` rule 5): a checklist long enough to run past the
/// screen uses the window's width instead of leaving the right half of the card empty while the
/// reader scrolls. Reading order is left, right, next line, and every cell is an ordinary row, so
/// its control keeps the row's accessibility label (rule 9).
struct SettingsGrid<Item, ID: Hashable, Row: View>: View {
    private let items: [Item]
    private let id: KeyPath<Item, ID>
    private let row: (Item) -> Row

    init(_ items: [Item], id: KeyPath<Item, ID>, @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.id = id
        self.row = row
    }

    var body: some View {
        LazyVGrid(
            // No gutter between the columns: the second one then starts at exactly half the card,
            // which is where `SettingsRowPair`'s right half starts too (rule 1).
            columns: [GridItem(.flexible(), spacing: 0, alignment: .leading),
                      GridItem(.flexible(), spacing: 0, alignment: .leading)],
            alignment: .leading,
            spacing: 0
        ) {
            ForEach(items, id: id) { item in
                row(item)
            }
        }
    }
}

/// Two rows side by side in a card (`Docs/SETTINGS.md` rule 5): a card whose rows are mostly narrow
/// controls — a switch, a menu, a segmented picker — uses the window's width instead of running one
/// row per line, which is what pulls the long pages back inside the window. Reading order is left,
/// right, like `SettingsGrid`, and each half is an ordinary row, so its control keeps the row's
/// accessibility label (rule 9). A slider never pairs: its track needs the card's width.
struct SettingsRowPair<Left: View, Right: View>: View {
    @Environment(\.settingsLiveWindowWidth) private var windowWidth
    private let left: Left
    private let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        if windowWidth < SettingsMetrics.pairStackThreshold {
            VStack(alignment: .leading, spacing: 0) {
                left.frame(maxWidth: .infinity, alignment: .leading)
                SettingsDivider()
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // 两半是**弹性的**，不写死 `halfRowWidth`：同一个 pair 现在也出现在 `SettingsBentoSplit`
            // 的**列**里，而按整窗算出来的那半 = 整张卡宽，列里放不下就会把另一列挤成一条。
            HStack(alignment: .top, spacing: 0) {
                left.frame(maxWidth: .infinity, alignment: .leading)
                right.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A menu row: label leading, value trailing — the shape macOS preferences uses.
struct SettingsPickerRow<Value: Hashable, Options: View>: View {
    private let label: Text
    private let note: Text?
    private let selection: Binding<Value>
    private let options: Options

    init(_ label: Text, selection: Binding<Value>, note: Text? = nil, @ViewBuilder options: () -> Options) {
        self.label = label
        self.selection = selection
        self.note = note
        self.options = options()
    }

    var body: some View {
        SettingsRow(label, note: note) {
            Picker(selection: selection) { options } label: { label }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
        }
    }
}

/// A segmented row: label leading, pills trailing and sized to their own content, so the same
/// control sits at the same edge on every page (rule 3).
struct SettingsSegmentedRow<Value: Hashable, Options: View>: View {
    private let label: Text
    private let note: Text?
    private let selection: Binding<Value>
    private let options: Options

    init(_ label: Text, selection: Binding<Value>, note: Text? = nil, @ViewBuilder options: () -> Options) {
        self.label = label
        self.selection = selection
        self.note = note
        self.options = options()
    }

    var body: some View {
        SettingsRow(label, note: note) {
            Picker(selection: selection) { options } label: { label }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel(label)
                .fixedSize()
        }
    }
}

/// A slider row: its label takes the shared column so every track starts on the same x, the track
/// fills the rest, the value trails. (`valueText` is optional; the default prints points.)
struct SettingsSliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    private let label: Text
    private let note: Text?
    private let valueText: String?
    private let value: Value
    private let range: ClosedRange<Value>
    private let step: Value.Stride
    private let set: (Value) -> Void

    init(
        _ label: Text,
        value: Value,
        range: ClosedRange<Value>,
        step: Value.Stride,
        valueText: String? = nil,
        note: Text? = nil,
        set: @escaping (Value) -> Void
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.note = note
        self.set = set
    }

    private var resolvedValueText: String {
        if let valueText { return valueText }
        return value.rounded() == value ? "\(Int(value)) pt" : String(format: "%.1f pt", Double(value))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                label.frame(width: SettingsMetrics.labelColumnWidth, alignment: .leading)
                Slider(value: Binding(get: { value }, set: set), in: range, step: step)
                    .accessibilityLabel(label)
                Text(verbatim: resolvedValueText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsMetrics.valueColumnWidth, alignment: .trailing)
            }
            if let note {
                SettingsNote(note)
            }
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A stepper row: label leading, the stepper trailing, with the value shown beside it. The stepper's
/// own label is hidden and taken from the row, so the row reads as one control (rules 3 and 9).
struct SettingsStepperRow: View {
    private let label: Text
    private let note: Text?
    private let value: Binding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private let readout: String

    init(
        _ label: Text,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        readout: String,
        note: Text? = nil
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.step = step
        self.readout = readout
        self.note = note
    }

    var body: some View {
        SettingsRow(label, note: note) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                Text(verbatim: readout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(value: value, in: range, step: step) { label }
                    .labelsHidden()
                    .accessibilityLabel(label)
            }
        }
    }
}

/// A lone action inside a card. The button is the row, so an action never gets labelled twice
/// (rule 6) — used for Restore/Clear/Reset-style buttons. A button that can be `.disabled` passes
/// its reason as the note (rule 7: the state is visible on the row, not only in a tooltip).
struct SettingsButtonRow: View {
    private let title: Text
    private let note: Text?
    private let info: String?
    private let action: () -> Void

    /// `info` is the row's long explanation (`Docs/SETTINGS.md` rule 4). It sits beside the button
    /// rather than on it: several one-line steps under a button is what this row had before, which is
    /// the shape rule 4 replaces.
    init(_ title: Text, note: Text? = nil, info: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.note = note
        self.info = info
        self.action = action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            HStack(spacing: SettingsMetrics.controlSpacing) {
                Button(action: action) { title }
                    .buttonStyle(SettingsGelButtonStyle())
                if let info {
                    SettingsInfoButton(text: info)
                }
                Spacer(minLength: 0)
            }
            if let note {
                SettingsNote(note)
            }
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// An editor row (`Docs/SETTINGS.md` rule 8): the text area shows its placeholder while it is empty,
/// so a first-run page is never a blank box, and the field takes its VoiceOver name from the row
/// (rule 9). The placeholder is a whole localized literal, never assembled from fragments.
struct SettingsEditorRow: View {
    private let label: Text
    private let placeholder: Text
    private let text: Binding<String>
    private let height: CGFloat

    init(_ label: Text, text: Binding<String>, placeholder: Text, height: CGFloat = 60) {
        self.label = label
        self.text = text
        self.placeholder = placeholder
        self.height = height
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.rowNoteSpacing) {
            label
            TextEditor(text: text)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: height)
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        placeholder
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                .accessibilityLabel(label)
        }
        .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The one-line note under a row or under a card.
struct SettingsNote: View {
    private let text: Text

    init(_ text: Text) {
        self.text = text
    }

    var body: some View {
        text
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row divider, so every card's rows separate the same way.
struct SettingsDivider: View {
    @Environment(\.dockThemeStyle) private var themeStyle
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = SettingsIridescentPalette.resolve(style: themeStyle, colorScheme: colorScheme)
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        palette.primaryAccent.opacity(0.18),
                        Color.primary.opacity(SettingsMetrics.dividerOpacity * 0.28),
                        palette.secondaryAccent.opacity(0.14)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
