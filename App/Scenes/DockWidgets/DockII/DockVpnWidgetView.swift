import SwiftUI

/// DeXign Studio Dock II Secure VPN Status & Traffic wing widget.
/// Powered by `DockVpnFeed` (`VPNServiceParser` + `SystemMonitorSampler.network()` + opt-in GeoIP).
struct DockVpnWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var feed = DockVpnFeed.shared
    @State private var showDetails = false

    var body: some View {
        let state = feed.state
        let secured = state.isConnected
        let statusTint = secured ? DockWidgetStyle.good : DockWidgetStyle.ink.opacity(0.45)
        let flag = GeoIPLocation(city: state.cityLabel, countryCode: state.countryCode, ip: nil).flagEmoji

        Group {
            if isVertical { verticalBody(state: state, secured: secured, statusTint: statusTint) }
            else { horizontalBody(state: state, secured: secured, statusTint: statusTint, flag: flag) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .popover(isPresented: $showDetails, arrowEdge: popoverEdge) { DockVpnPreviewCard() }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }

    private func verticalBody(state: DockVpnStatusState, secured: Bool, statusTint: Color) -> some View {
        VStack(spacing: 5) {
            toggleButton(secured: secured, statusTint: statusTint, ringSize: 30)
            if size != .small {
                Button { showDetails.toggle() } label: {
                    VStack(spacing: 1.5) {
                        Text(secured ? "SECURED" : "VPN")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(secured ? DockWidgetStyle.good : DockWidgetStyle.ink.opacity(0.72))
                            .lineLimit(1)
                        Text(verbatim: DockVpnRateFormat.formatted(state.downloadBytesPerSec))
                            .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(DockWidgetStyle.ink.opacity(0.72))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    private func horizontalBody(state: DockVpnStatusState, secured: Bool, statusTint: Color, flag: String?) -> some View {
        HStack(spacing: 8) {
            Button { showDetails.toggle() } label: {
                Group {
                    if size != .small {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(secured ? "SECURED" : "VPN")
                                    .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.6)
                                    .foregroundStyle(secured ? DockWidgetStyle.good : DockWidgetStyle.ink.opacity(0.65))
                                if let flag { Text(verbatim: flag).font(.system(size: 9.5)) }
                                Text(verbatim: state.displayLocation)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DockWidgetStyle.ink).lineLimit(1)
                            }
                            if size == .large {
                                HStack(spacing: 8) {
                                    Text(verbatim: "↑ \(DockVpnRateFormat.formatted(state.uploadBytesPerSec))")
                                    Text(verbatim: "↓ \(DockVpnRateFormat.formatted(state.downloadBytesPerSec))")
                                }
                                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(DockWidgetStyle.ink.opacity(0.72)).lineLimit(1)
                            } else {
                                Text(verbatim: "↓ \(DockVpnRateFormat.formatted(state.downloadBytesPerSec))")
                                    .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(DockWidgetStyle.ink.opacity(0.72)).lineLimit(1)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text(secured ? "SECURED" : "VPN")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(secured ? DockWidgetStyle.good : DockWidgetStyle.ink.opacity(0.78)).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            toggleButton(secured: secured, statusTint: statusTint, ringSize: 34)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
    }

    private func toggleButton(secured: Bool, statusTint: Color, ringSize: CGFloat) -> some View {
        Button { feed.toggleConnection() } label: {
            ZStack {
                if secured { Circle().stroke(DockWidgetStyle.good.opacity(0.22), lineWidth: 1).frame(width: ringSize, height: ringSize) }
                Circle().fill(statusTint).frame(width: 24, height: 24)
                if feed.isToggling { ProgressView().controlSize(.mini) }
                else {
                    Image(systemName: secured ? "checkmark" : "shield.slash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(secured ? Color.black.opacity(0.88) : DockWidgetStyle.ink)
                }
            }
            .scaleEffect(feed.isToggling ? 0.92 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.72), value: secured)
        }
        .buttonStyle(.plain)
        .disabled(feed.profiles.isEmpty || feed.isToggling)
        .accessibilityLabel(secured ? Text("Disconnect VPN") : Text("Connect VPN"))
    }
}

private struct DockVpnPreviewCard: View {
    @ObservedObject private var feed = DockVpnFeed.shared

    var body: some View {
        let state = feed.state
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: state.isConnected ? "checkmark.shield.fill" : "shield.slash")
                        .foregroundStyle(state.isConnected ? DockWidgetStyle.good : .secondary)
                    Text(state.isConnected ? "VPN Connected" : "VPN Disconnected")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button(state.isConnected ? "Disconnect" : "Connect") {
                        feed.toggleConnection()
                    }
                    .controlSize(.small)
                    .disabled(feed.profiles.isEmpty || feed.isToggling)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload").dockCaption()
                        Text(verbatim: DockVpnRateFormat.formatted(state.uploadBytesPerSec))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download").dockCaption()
                        Text(verbatim: DockVpnRateFormat.formatted(state.downloadBytesPerSec))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    }
                    if let city = state.cityLabel, !city.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location").dockCaption()
                            Text(verbatim: city)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                }

                Divider().opacity(0.25)

                if feed.profiles.isEmpty {
                    Text("No macOS VPN profiles configured in System Settings.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(feed.profiles, id: \.id) { profile in
                            HStack {
                                Circle()
                                    .fill(profile.connected ? DockWidgetStyle.good : Color.white.opacity(0.22))
                                    .frame(width: 7, height: 7)
                                Text(verbatim: profile.name)
                                    .font(.system(size: 11.5))
                                    .lineLimit(1)
                                Spacer()
                                Text(profile.connected ? "Connected" : "Idle")
                                    .dockCaption()
                            }
                        }
                    }
                }
            }
        }
        .onAppear { feed.retain() }
        .onDisappear { feed.release() }
    }
}
