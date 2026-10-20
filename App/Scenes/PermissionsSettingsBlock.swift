import AppKit
import AVFAudio
import CoreGraphics
import SwiftUI

/// Phase 12c — live status for the grants, reachable after onboarding. Reuses the welcome
/// guide's `PermissionRow` (same copy, same keys); re-reads once a second while Settings is open.
/// `PermissionRow` already shows `Grant` → `Granted ✓` (rule 7), so the state is never implied.
struct PermissionsSettingsBlock: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @State private var inputMonitoringGranted = CGPreflightListenEventAccess()
    @State private var microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SettingsCard(Text("Permissions")) {
            // `PermissionRow` is the welcome guide's own row (same copy, same keys) and carries no
            // rhythm of its own — the card supplies the shared row padding and divider (rule 3), the
            // way the guide's container does for it.
            PermissionRow(title: Text("Accessibility"),
                          note: Text("Shows your open windows as chips and lets you switch to them."),
                          isGranted: accessibilityGranted,
                          grant: { _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) })
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            SettingsDivider()
            PermissionRow(title: Text("Screen Recording"),
                          note: Text("Shows live window thumbnails in hover previews. Without it, previews show titles only."),
                          isGranted: screenRecordingGranted,
                          grant: { _ = CGRequestScreenCaptureAccess(); PermissionRow.openPrivacy("Privacy_ScreenCapture") })
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            SettingsDivider()
            PermissionRow(title: Text("Input Monitoring"),
                          note: Text("Only for the optional Hyper key. Skip it if you won’t use that."),
                          isGranted: inputMonitoringGranted,
                          grant: { _ = CGRequestListenEventAccess(); PermissionRow.openPrivacy("Privacy_ListenEvent") })
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
            SettingsDivider()
            PermissionRow(title: Text("Microphone"),
                          note: Text("Records audio in the widget pane recorder."),
                          isGranted: microphoneGranted,
                          grant: {
                              // A denied mic can't re-prompt: send the grant path where it can be flipped.
                              if AVAudioApplication.shared.recordPermission == .denied {
                                  NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
                              } else {
                                  AVAudioApplication.requestRecordPermission { _ in }
                              }
                          })
                .padding(.vertical, SettingsMetrics.rowVerticalPadding)
        }
        .onReceive(timer) { _ in
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
            inputMonitoringGranted = CGPreflightListenEventAccess()
            microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
        }
    }
}
