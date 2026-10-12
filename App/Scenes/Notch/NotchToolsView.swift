import SwiftUI

/// The notch's second tab: three matched cards — Focus & Timers, Clipboard + Quick note, System. (The file
/// shelf lives on the dock now.) Everything reuses existing controllers; no new data sources.
struct NotchToolsView: View {
    private let services = ProductivityServices.shared

    var body: some View {
        HStack(alignment: .top, spacing: NotchLayoutSpec.homeSpacing) {
            card { NotchFocusCard(focus: services.focus, timer: services.timer) }
            card { NotchClipboardCard(clipboard: services.clipboard, tasks: services.tasks) }
            card { NotchSystemCard(monitor: services.systemMonitor) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(NotchLayoutSpec.cardPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: NotchLayoutSpec.cardRadius, style: .continuous)
                .fill(Color.white.opacity(NotchLayoutSpec.cardFillOpacity)))
    }
}

private func cardTitle(_ symbol: String, _ title: Text) -> some View {
    HStack(spacing: 5) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        title.font(.system(size: 11, weight: .semibold))
        Spacer(minLength: 0)
    }
    .foregroundStyle(.white.opacity(0.6))
}

private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.white.opacity(0.14)))
    }
    .buttonStyle(.plain)
}

private func chip(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(verbatim: title).font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.14)))
    }
    .buttonStyle(.plain)
}

// MARK: Focus & timers

struct NotchFocusCard: View {
    @ObservedObject var focus: FocusTimerController
    @ObservedObject var timer: CountdownTimerController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle("brain.head.profile", Text("Focus"))
            Text(verbatim: NotchLayoutSpec.clockText(Double(focus.model.remaining)))
                .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
            HStack(spacing: 8) {
                smallButton(focus.model.isRunning ? "pause.fill" : "play.fill") { focus.toggle() }
                smallButton("forward.end.fill") { focus.skip() }
                smallButton("arrow.counterclockwise") { focus.reset() }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                ForEach([5, 15, 25], id: \.self) { minutes in
                    chip("\(minutes)m") { timer.set(seconds: minutes * 60); timer.toggle() }
                }
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: Clipboard + quick note

struct NotchClipboardCard: View {
    @ObservedObject var clipboard: ClipboardMonitor
    @ObservedObject var tasks: TasksController
    @State private var note = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardTitle("doc.on.clipboard", Text("Clipboard"))
            if !clipboard.isRecording {
                chip(String(localized: "Turn On Clipboard History")) { clipboard.setRecording(true) }
            } else if clipboard.history.entries.isEmpty {
                Text("Nothing copied yet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(Array(clipboard.history.entries.prefix(3))) { entry in
                    Button { clipboard.copy(entry) } label: {
                        Text(verbatim: entry.text.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11)).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            TextField(String(localized: "Quick note"), text: $note, onCommit: {
                let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                tasks.add(text)
                note = ""
            })
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.1)))
        }
        .foregroundStyle(.white)
    }
}

// MARK: System

struct NotchSystemCard: View {
    @ObservedObject var monitor: SystemMonitorController

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 8) {
            cardTitle("gauge.medium", Text("System"))
            meter("cpu", Text("CPU"), snap.cpu)
            meter("memorychip", Text("Memory"), snap.memory.fraction)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .onAppear { monitor.acquire() }
        .onDisappear { monitor.release() }
    }

    private func meter(_ symbol: String, _ title: Text, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Image(systemName: symbol).font(.system(size: 10))
                title.font(.system(size: 11))
                Spacer()
                Text(verbatim: SystemMonitorFormat.percent(fraction)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(fraction > 0.85 ? Color.orange : Color.white).frame(width: geo.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 4)
        }
    }
}
