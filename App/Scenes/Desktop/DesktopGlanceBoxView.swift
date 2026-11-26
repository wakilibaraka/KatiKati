import AVFoundation
import SwiftUI

/// Desktop Glance: big date, lunar date, solar term and festivals for today.
struct DesktopGlanceBoxView: View {
    @ObservedObject private var performance = DesktopPerformanceStore.shared

    var body: some View {
        if performance.settings.allowsAnimation(.glanceRotation) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                content(for: context.date)
            }
        } else {
            content(for: Date())
        }
    }

    private func content(for now: Date) -> some View {
        let calendar = Calendar.current
        let info = DesktopGlanceEngine.info(on: now, calendar: calendar)
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let script = Locale.current.language.script?.identifier
        var facts: [String] = []
        if let term = info.solarTerm { facts.append(DesktopGlanceNames.name(of: term, languageCode: language, script: script)) }
        facts += info.festivals.map { DesktopGlanceNames.name(of: $0, languageCode: language, script: script) }

        return VStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(verbatim: "\(calendar.component(.day, from: now))")
                .font(.system(size: 54, weight: .semibold, design: .rounded))
            Text(now.formatted(.dateTime.weekday(.wide).month(.wide).year()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if info.lunar != nil {
                Text(verbatim: Self.lunarString(for: now))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if !facts.isEmpty {
                Text(verbatim: facts.joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private static func lunarString(for date: Date) -> String {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = .current
        let formatter = DateFormatter()
        formatter.calendar = chinese
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMd")
        return formatter.string(from: date)
    }
}

/// WG-1: today's word on the desktop — the bundled catalogue's word, its parsed offline definition, a speaker
/// and a lookup field. `.task(id:)` re-reads only when the word or the query changes, so nothing polls.
struct DesktopWordOfTheDayBoxView: View {
    @StateObject private var lookup = DictionaryPanelModel()
    @State private var query = ""
    @State private var synthesizer: AVSpeechSynthesizer?

    private var today: WordOfTheDayWidget.Today { WordOfTheDayWidget.today() }
    private var isLooking: Bool {
        lookup.searched && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let today = today
        let entry = isLooking ? lookup.entry : today.entry
        let block = entry?.blocks.first
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(String(localized: "Word of the Day"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { speak(today.word) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(verbatim: today.word))
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: isLooking ? (entry?.headword.capitalized ?? query.capitalized) : today.word.capitalized)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .lineLimit(1)
                if let phonetic = entry?.phonetic, !phonetic.isEmpty {
                    Text(verbatim: phonetic)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let pos = block?.partOfSpeech, !pos.isEmpty {
                Text(verbatim: pos)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Text(verbatim: block?.senses.first?.text ?? String(localized: "No definition found"))
                .font(.system(size: 12))
                .foregroundStyle(entry == nil && lookup.searched ? .secondary : .primary)
                .lineLimit(isLooking ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
                TextField(String(localized: "Look up a word"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { look(query) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: query) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2, trimmed.caseInsensitiveCompare(today.word) != .orderedSame else { return }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            lookup.lookup(trimmed)
        }
    }

    private func look(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lookup.lookup(trimmed)
    }

    /// Allocated on the first tap only, so a card nobody speaks to never owns a synthesiser.
    private func speak(_ word: String) {
        if synthesizer == nil { synthesizer = AVSpeechSynthesizer() }
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.45
        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer?.speak(utterance)
    }
}

/// One dictionary read per day, shared by the Dock chip and the Desktop card so neither re-parses per draw.
@MainActor
enum WordOfTheDayWidget {
    typealias Today = (word: String, entry: DictionaryEntry?)

    private static var cachedKey: Int?
    private static var cachedWord = ""
    private static var cachedEntry: DictionaryEntry?

    static func today(_ date: Date = Date()) -> Today {
        let key = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        let word = WordOfTheDay.word(on: date)
        if cachedKey == key, cachedWord.caseInsensitiveCompare(word) == .orderedSame {
            return (word, cachedEntry)
        }
        cachedEntry = DictionaryEntry.parse(headword: word, payload: DictionaryService.define(word))
        cachedKey = key
        cachedWord = word
        return (word, cachedEntry)
    }
}

/// WG-2: how much of the year and the month are gone. Pure `YearProgress`; nothing polls.
struct DesktopYearProgressBoxView: View {
    var body: some View {
        let progress = YearProgress(date: Date())
        let calendar = Calendar.current
        let day = calendar.component(.day, from: Date())
        let daysInMonth = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
        VStack(alignment: .leading, spacing: 7) {
            Text(String(localized: "Year Progress"))
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(verbatim: "\(progress.percent)%")
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
            bar(progress.fraction, tint: .accentColor, height: 4)
            row(String(localized: "Month"), Double(day) / Double(max(daysInMonth, 1)))
            Spacer(minLength: 0)
            Text(String(format: String(localized: "%d days left"), progress.daysLeft))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func bar(_ fraction: Double, tint: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.09))
                Capsule().fill(tint).frame(width: max(2, geo.size.width * fraction))
            }
        }
        .frame(height: height)
    }

    private func row(_ label: String, _ fraction: Double) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            bar(fraction, tint: .secondary, height: 3).frame(width: 70)
            Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

/// WG-2: keep-awake as a one-tap tile. `KeepAwakeService` owns the assertion; this only calls `setManual`.
struct DesktopKeepAwakeBoxView: View {
    @ObservedObject private var keepAwake = KeepAwakeService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: keepAwake.manualOn ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 12))
                    .foregroundStyle(keepAwake.manualOn ? Color.accentColor : .secondary)
                Text(String(localized: "Keep Awake"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let end = keepAwake.manualEnd {
                    Text(end, style: .timer)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                pill("15m") { keepAwake.setManual(true, duration: 15 * 60) }
                pill("1h") { keepAwake.setManual(true, duration: 60 * 60) }
                pill(String(localized: "Off"), active: !keepAwake.manualOn) { keepAwake.setManual(false) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func pill(_ title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 11, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(active ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

/// WG-3: today's habits with one-click check-off. Event-driven: the store publishes, nothing polls.
struct DesktopHabitStreakBoxView: View {
    @ObservedObject private var store = HabitStreakStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(String(localized: "Habit Streak"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(verbatim: "\(store.streakCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            if store.habits.isEmpty {
                Text(String(localized: "No habits yet"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(store.habits.prefix(4)), id: \.id) { habit in
                    Button { store.toggleHabit(id: habit.id) } label: {
                        HStack(spacing: 7) {
                            Image(systemName: habit.isDoneToday ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(habit.isDoneToday ? Color.accentColor : .secondary)
                            Text(verbatim: habit.title)
                                .font(.system(size: 12))
                                .strikethrough(habit.isDoneToday, color: .secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// WG-4: storage and transfer glance — free space at rest, live aggregate speed while something downloads.
struct DesktopStorageGlanceBoxView: View {
    @ObservedObject private var downloads = DownloadManagerService.shared

    var body: some View {
        let free = Self.freeBytes
        let total = Self.totalBytes
        let used = total > 0 ? 1 - Double(free) / Double(total) : 0
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(String(localized: "Storage"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "internaldrive").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(verbatim: Self.bytes(free))
                .font(.system(size: 22, weight: .light, design: .rounded))
                .monospacedDigit()
            Text(String(localized: "Free space"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.09))
                    Capsule().fill(Color.accentColor).frame(width: max(2, geo.size.width * used))
                }
            }
            .frame(height: 4)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Image(systemName: downloads.aggregateDownloadBps > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(downloads.aggregateDownloadBps > 0 ? Color.accentColor : .secondary)
                Text(verbatim: downloads.aggregateDownloadBps > 0
                     ? "\(Self.bytes(downloads.aggregateDownloadBps))/s"
                     : String(localized: "Idle"))
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(verbatim: "\(Int((used * 100).rounded()))%")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    static var freeBytes: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    static var totalBytes: Int64 {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return Int64(values?.volumeTotalCapacity ?? 0)
    }

    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// WG-5: the notes pinned in the edge deck, kept in sight. Event-driven: `NotesController` publishes and
/// this card never touches the disk or the store itself.
struct DesktopPinnedNoteBoxView: View {
    var controller: NotesController?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(String(localized: "Pinned Note"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if let controller {
                PinnedNoteRows(controller: controller)
            } else {
                PinnedNoteEmptyState()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PinnedNoteRows: View {
    @ObservedObject var controller: NotesController

    var body: some View {
        let pinned = controller.notes.filter { $0.pinned && !$0.archived }
        if pinned.isEmpty {
            PinnedNoteEmptyState()
        } else {
            ForEach(Array(pinned.prefix(3))) { note in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: note.displayTitle.isEmpty ? String(localized: "Untitled") : note.displayTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    if !note.body.isEmpty {
                        Text(verbatim: ClipboardHistory.previewLine(note.body))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PinnedNoteEmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "No pinned notes"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(String(localized: "Pin a note in the edge deck to keep it here."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }
}

/// WG-5: the newest copies, one click back onto the pasteboard. Reads the one `ClipboardMonitor` the edge
/// flyout uses, so it neither starts a second poll nor turns recording on by itself.
struct DesktopClipboardBoxView: View {
    @ObservedObject private var monitor = ProductivityServices.shared.clipboard

    var body: some View {
        let entries = Array(monitor.history.displayOrder.prefix(5))
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(String(localized: "Quick-Paste Clipboard"))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Circle()
                    .fill(monitor.isRecording ? Color.accentColor : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
            }
            if entries.isEmpty {
                Text(monitor.isRecording
                     ? String(localized: "Clipboard is empty")
                     : String(localized: "Clipboard recording is off"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(entries) { entry in
                    Button { monitor.copy(entry) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: entry.pinned ? "pin.fill" : "doc.on.clipboard")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Text(verbatim: ClipboardHistory.previewLine(entry.text))
                                .font(.system(size: 11))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Copy"))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
