import SwiftUI

public struct TrayChip: View {
    @StateObject private var status = SystemStatusProvider()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            // Wi-Fi
            Image(systemName: status.isWiFiConnected ? "wifi" : "wifi.slash")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(status.isWiFiConnected ? .blue : .gray)
            
            // Battery
            HStack(spacing: 4) {
                Text("\(status.batteryLevel)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                
                Image(systemName: "battery.100")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(status.isCharging ? .green : .primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.1))
        .clipShape(Capsule())
    }
}
