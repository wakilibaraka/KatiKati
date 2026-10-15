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
struct SettingsCard<Content: View>: View {
    private let header: Text?
    private let note: Text?
    private let content: Content

    init(_ header: Text? = nil, note: Text? = nil, @ViewBuilder content: () -> Content) {
        self.header = header
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.cardHeaderSpacing) {
            if let header {
                header.font(.headline)
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
            RoundedRectangle(cornerRadius: SettingsMetrics.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(SettingsMetrics.cardFillOpacity))
        )
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
    private let left: Left
    private let right: Right

    init(@ViewBuilder left: () -> Left, @ViewBuilder right: () -> Right) {
        self.left = left()
        self.right = right()
    }

    var body: some View {
        // Two `maxWidth: .infinity` children are not two equal children: both an `HStack` and a
        // two-column grid size them by their own content, so the half with the wider control took
        // the width from the other one (measured live 2026-10-15: the right half's Record button
        // rendered as “…” at 20 pt while the left half's said “Record”). The window is a fixed 900
        // pt (rule 10), so a half is `SettingsMetrics.halfRowWidth` and both halves are equal.
        HStack(alignment: .top, spacing: 0) {
            left.frame(width: SettingsMetrics.halfRowWidth, alignment: .leading)
            right.frame(width: SettingsMetrics.halfRowWidth, alignment: .leading)
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
    var body: some View {
        Divider().opacity(SettingsMetrics.dividerOpacity)
    }
}
