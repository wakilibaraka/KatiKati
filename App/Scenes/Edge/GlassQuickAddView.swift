import SwiftUI

/// Liquid Glass Quick Add (Notes, Reminders, Tasks): own SwiftUI take on the morphing capture card — 26pt continuous corners,
/// ~0.4s spring between stages, tinted 36pt discs, chips ≥34pt, Save bubble only with text. Reduce Motion cross-fades.
struct GlassQuickAddView: View {
    let notes: () -> NotesController?
    let onDone: () -> Void

    @State private var state = QuickAddState()
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 320, height: 300)

    private var morph: Animation { reduceMotion ? .easeInOut(duration: 0.15) : EdgeStyleTokens.morphSpring }

    var body: some View {
        ZStack {
            switch state.stage {
            case .menu: menu.transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.96)))
            case let .capture(kind): capture(kind).transition(.opacity.combined(with: reduceMotion ? .identity : .scale(scale: 0.96)))
            }
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(EdgeGlassSurface(shape: RoundedRectangle(cornerRadius: EdgeStyleTokens.glassRadius, style: .continuous)))
        .animation(morph, value: state.stage)
        .onExitCommand(perform: onDone)
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Add").font(.headline).foregroundStyle(.primary).padding(.bottom, 4)
            ForEach(QuickAddState.Kind.allCases, id: \.self) { kind in
                Button { state.choose(kind); focused = true } label: {
                    HStack(spacing: 12) {
                        disc(kind)
                        Text(Self.title(kind)).font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func capture(_ kind: QuickAddState.Kind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button { state.back() } label: { Image(systemName: "chevron.left").frame(width: 34, height: 34) }
                    .buttonStyle(.plain).accessibilityLabel(Text("Back"))
                disc(kind)
                Text(Self.title(kind)).font(.headline)
                Spacer()
            }
            TextField(Self.prompt(kind), text: $state.text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...8)
                .focused($focused)
                .onSubmit(save)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                chips(kind)
                Spacer(minLength: 0)
                if state.canSave || state.save != .idle { saveBubble.transition(.scale.combined(with: .opacity)) }
            }
        }
        .onAppear { focused = true }
    }

    @ViewBuilder private func chips(_ kind: QuickAddState.Kind) -> some View {
        switch kind {
        case .note:
            chip(state.pinned ? "pin.fill" : "pin", "Pin", on: state.pinned) { state.pinned.toggle() }
            chip("paintpalette", "Colour", on: false) { state.colorIndex = (state.colorIndex + 1) % NotePalette.all.count }
                .tint(NotePalette.entry(at: state.colorIndex).dashColor)
        case .reminder:
            chip("sun.max", "Today", on: state.due == .today) { state.due = state.due == .today ? .none : .today }
            chip("sunrise", "Tomorrow", on: state.due == .tomorrow) { state.due = state.due == .tomorrow ? .none : .tomorrow }
        case .task:
            EmptyView()
        }
    }

    private func chip(_ symbol: String, _ title: LocalizedStringKey, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.callout)
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var saveBubble: some View {
        Button(action: save) {
            ZStack {
                switch state.save {
                case .idle: Image(systemName: "arrow.up")
                case .saving: ProgressView().controlSize(.small)
                case .saved: Image(systemName: "checkmark")
                }
            }
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
        }
        .buttonStyle(.plain)
        .disabled(!state.canSave)
        .accessibilityLabel(Text("Save"))
    }

    private func disc(_ kind: QuickAddState.Kind) -> some View {
        Image(systemName: Self.symbol(kind))
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Self.tint(kind))
            .frame(width: 36, height: 36)
            .background(Circle().fill(Self.tint(kind).opacity(scheme == .dark ? 0.28 : 0.18)))
    }

    private func save() {
        guard let kind = state.kind, state.beginSave() else { return }
        let text = state.trimmed
        var ok = false
        switch kind {
        case .note:
            if let controller = notes() {
                let note = controller.create(body: text)
                controller.setColor(id: note.id, state.colorIndex)
                if state.pinned { controller.togglePin(id: note.id) }
                ok = true
            }
        case .reminder: ok = ProductivityServices.shared.calendar.addReminder(title: text, due: state.dueDate())
        case .task: ProductivityServices.shared.tasks.add(text); ok = true
        }
        state.finishSave(success: ok)
        if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: onDone) }
    }

    static func title(_ k: QuickAddState.Kind) -> LocalizedStringKey {
        switch k { case .note: return "Note"; case .reminder: return "Reminder"; case .task: return "Task" }
    }
    static func prompt(_ k: QuickAddState.Kind) -> LocalizedStringKey {
        switch k { case .note: return "Write a note…"; case .reminder: return "Remind me to…"; case .task: return "Add a task…" }
    }
    static func symbol(_ k: QuickAddState.Kind) -> String {
        switch k { case .note: return "note.text"; case .reminder: return "bell"; case .task: return "checkmark.circle" }
    }
    static func tint(_ k: QuickAddState.Kind) -> Color {
        switch k { case .note: return .orange; case .reminder: return .red; case .task: return .blue }
    }
}
