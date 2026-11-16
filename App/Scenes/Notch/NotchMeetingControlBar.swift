import AppKit
import SwiftUI

/// Compact Live Activity meeting indicator and 1-click meeting controls for Notch (Slice 2.3).
struct NotchMeetingControlBar: View {
    let call: MeetingCallState
    var onToggleMute: (() -> Void)? = nil
    var onToggleCamera: (() -> Void)? = nil
    var onEndCall: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: call.platform.sfSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                Text(verbatim: call.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Mute / Unmute
            let muteShortcut = NotchMeetingControlRouter.shortcut(for: .toggleMute, on: call.platform)
            Button {
                onToggleMute?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: call.isMicMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundColor(call.isMicMuted ? .red : .primary)
                    Text(verbatim: muteShortcut.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            // Camera Toggle
            let camShortcut = NotchMeetingControlRouter.shortcut(for: .toggleCamera, on: call.platform)
            Button {
                onToggleCamera?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: call.isCameraOff ? "video.slash.fill" : "video.fill")
                        .foregroundColor(call.isCameraOff ? .orange : .primary)
                    Text(verbatim: camShortcut.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)

            // End Call
            let endShortcut = NotchMeetingControlRouter.shortcut(for: .endCall, on: call.platform)
            Button {
                onEndCall?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "phone.down.fill")
                        .foregroundColor(.white)
                    Text(verbatim: endShortcut.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
    }
}
