import CoreGraphics
import SwiftUI

/// Phase 12c — live status for the three grants, reachable after onboarding. Reuses the welcome
/// guide's `PermissionRow` (same copy, same keys); re-reads once a second while Settings is open.
struct PermissionsSettingsBlock: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Text("Permissions").font(.headline)
        PermissionRow(title: Text("Accessibility"),
                      note: Text("Shows your open windows as chips and lets you switch to them."),
                      isGranted: accessibilityGranted,
                      grant: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) })
        PermissionRow(title: Text("Screen Recording"),
                      note: Text("Shows live window thumbnails in hover previews. Without it, previews show titles only."),
                      isGranted: screenRecordingGranted,
                      grant: { _ = CGRequestScreenCaptureAccess() })
        PermissionRow(title: Text("Input Monitoring"),
                      note: Text("Only for the optional Hyper key. Skip it if you won’t use that."),
                      isGranted: inputMonitoringGranted,
                      grant: { _ = CGRequestListenEventAccess() })
            .onReceive(timer) { _ in
                accessibilityGranted = AXIsProcessTrusted()
                screenRecordingGranted = CGPreflightScreenCaptureAccess()
                inputMonitoringGranted = CGPreflightListenEventAccess()
            }
    }
}
