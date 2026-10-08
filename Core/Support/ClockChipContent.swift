import Foundation
import Combine

public enum ClockPreset: String, CaseIterable, Equatable {
    case modernMac = "modern"
    case pixelRetro = "pixel"
}

public struct ClockContent: Equatable {
    public let primaryText: String
    public let secondaryText: String?
    
    public init(primaryText: String, secondaryText: String? = nil) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
    }
}

public protocol ClockDataProvider {
    func currentContent(for date: Date) -> ClockContent
}

public final class StandardClockProvider: ClockDataProvider {
    private let timeFormatter: DateFormatter
    private let dateFormatter: DateFormatter
    
    public init() {
        timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none
        
        dateFormatter = DateFormatter()
        // Example: "Wed, Jun 17"
        dateFormatter.dateFormat = "E, MMM d"
    }
    
    public func currentContent(for date: Date) -> ClockContent {
        return ClockContent(
            primaryText: timeFormatter.string(from: date),
            secondaryText: dateFormatter.string(from: date)
        )
    }
}
