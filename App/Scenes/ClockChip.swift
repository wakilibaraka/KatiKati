import Combine

import SwiftUI

public struct ClockChip: View {
    @AppStorage("com.katikati.clock.preset") private var preset: ClockPreset = .modernMac
    @State private var content: ClockContent
    private let provider: ClockDataProvider
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    public init(provider: ClockDataProvider = StandardClockProvider()) {
        self.provider = provider
        _content = State(initialValue: provider.currentContent(for: Date()))
    }
    
    @State private var showingCalendar = false

    public var body: some View {
        HStack {
            if preset == .modernMac {
                modernMacView
            } else {
                pixelRetroView
            }
        }
        .onTapGesture {
            showingCalendar.toggle()
        }
        .popover(isPresented: $showingCalendar, arrowEdge: .top) {
            CalendarPopupView()
        }
        .onReceive(timer) { date in
            let newContent = provider.currentContent(for: date)
            if newContent != content {
                content = newContent
            }
        }
    }
    
    private var modernMacView: some View {
        HStack(spacing: 6) {
            Text(content.primaryText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            if let secondary = content.secondaryText {
                Text(secondary)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var pixelRetroView: some View {
        HStack(spacing: 6) {
            Text(content.primaryText)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.green)
            
            if let secondary = content.secondaryText {
                Text(secondary)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.green.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.5), lineWidth: 1)
        )
    }
}
import SwiftUI

struct CalendarPopupView: View {
    @State private var currentDate = Date()
    private let calendar = Calendar.current
    
    var body: some View {
        VStack(spacing: 12) {
        }
        .padding(16)
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 8)
    }
    
    private var header: some View {
        HStack {
            Text(currentDate.formatted(.dateTime.month(.wide).year()))
                .font(.headline)
            Spacer()
            HStack(spacing: 8) {
                Button(action: {
                    if let newDate = calendar.date(byAdding: .month, value: -1, to: currentDate) {
                        currentDate = newDate
                    }
                }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                
                Button(action: {
                    if let newDate = calendar.date(byAdding: .month, value: 1, to: currentDate) {
                        currentDate = newDate
                    }
                }) {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var daysOfWeek: some View {
        let symbols = calendar.veryShortWeekdaySymbols
        return HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var monthGrid: some View {
        let days = extractDays(for: currentDate)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    DayCell(date: date, isToday: calendar.isDateInToday(date))
                } else {
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
    
    private func extractDays(for month: Date) -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let monthFirstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start),
              let monthLastWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.end - 1)
        else {
            return []
        }
        
        let startDate = monthFirstWeek.start
        let endDate = monthLastWeek.end
        
        var days: [Date?] = []
        var currentDate = startDate
        
        while currentDate < endDate {
            if calendar.isDate(currentDate, equalTo: month, toGranularity: .month) {
                days.append(currentDate)
            } else {
                days.append(nil)
            }
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }
        
        return days
    }
}

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    
    var body: some View {
        Text("\(Calendar.current.component(.day, from: date))")
            .font(.system(size: 14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(isToday ? Color.blue : Color.clear)
            .foregroundColor(isToday ? .white : .primary)
            .clipShape(Circle())
    }
}
