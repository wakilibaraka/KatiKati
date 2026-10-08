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
    
    public var body: some View {
        HStack {
            if preset == .modernMac {
                modernMacView
            } else {
                pixelRetroView
            }
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
