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
