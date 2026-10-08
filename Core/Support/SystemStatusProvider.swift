import Foundation
import Combine

public final class SystemStatusProvider: ObservableObject {
    @Published public private(set) var batteryLevel: Int
    @Published public private(set) var isCharging: Bool
    @Published public private(set) var isWiFiConnected: Bool
    
    // In the future, this will hook into IOKit / CoreWLAN to provide real metrics.
    // For Slice 4f, we establish the reactive pipeline and data shape.
    public init(batteryLevel: Int = 100, isCharging: Bool = false, isWiFiConnected: Bool = true) {
        self.batteryLevel = batteryLevel
        self.isCharging = isCharging
        self.isWiFiConnected = isWiFiConnected
    }
}
