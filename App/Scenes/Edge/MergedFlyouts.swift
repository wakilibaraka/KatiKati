import SwiftUI

// MARK: - 1. Bluetooth & Wi-Fi Unified Flyout

struct BluetoothWifiFlyoutView: View {
    let service: SystemStatusService
    static let size = CGSize(width: 340, height: 480)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Wi-Fi & Connectivity", systemImage: "wifi")
                        .font(.headline)
                    Spacer()
                    Button("Control Center") {
                        AppDelegate.shared?.toggleControlCenter()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                StatusPopupView(kind: .wifi, service: service)
                    .frame(height: 140)

                Divider()
                    .padding(.horizontal, 14)

                HStack {
                    Label("Bluetooth Devices", systemImage: "wave.3.right.circle.fill")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 14)

                BluetoothFlyoutView()
                    .frame(height: 240)
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - 2. Reminders & Tasks Unified Flyout

struct RemindersTasksFlyoutView: View {
    static let size = CGSize(width: 340, height: 520)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RemindersFlyoutView()
                    .frame(height: 210)

                Divider()
                    .padding(.horizontal, 14)

                TasksFlyoutView()
                    .frame(height: 290)
            }
        }
    }
}

// MARK: - 3. System & Battery Unified Flyout

struct SystemBatteryFlyoutView: View {
    let service: SystemStatusService
    static let size = CGSize(width: 340, height: 500)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                StatusPopupView(kind: .battery, service: service)
                    .frame(height: 210)

                Divider()
                    .padding(.horizontal, 14)

                SystemMonitorFlyoutView()
                    .frame(height: 260)
            }
        }
    }
}

// MARK: - 4. Time & Alarms Unified Flyout

struct TimeAlarmsFlyoutView: View {
    static let size = CGSize(width: 340, height: 520)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TimeFlyoutView()
                    .frame(height: 280)

                Divider()
                    .padding(.horizontal, 14)

                AlarmsFlyoutView()
                    .frame(height: 220)
            }
        }
    }
}

// MARK: - 5. Capture & Screenshot Unified Flyout

struct CaptureScreenshotFlyoutView: View {
    let onCapture: () -> Void
    let onScreenshot: () -> Void

    static let size = CGSize(width: 340, height: 380)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    onCapture()
                } label: {
                    Label("Capture Text", systemImage: "text.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onScreenshot()
                } label: {
                    Label("Copy Screenshot", systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            Divider()
                .padding(.horizontal, 14)

            CaptureResultView()
        }
    }
}
