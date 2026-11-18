import SwiftUI

/// DeXign Studio Dock II Friends / Contacts HUD wing widget.
/// Powered by `DockFriendsStore` and `BadgeStore` (with opt-in `CNContactStore` import in Settings).
struct DockFriendsWidgetView: View {
    @Environment(\.widgetSize) private var size
    @Environment(\.dockWingVertical) private var isVertical
    @Environment(\.dockPopoverEdge) private var popoverEdge
    @Environment(\.dockBadgesByBundleID) private var badgesByBundleID
    @ObservedObject private var friendsStore = DockFriendsStore.shared
    @State private var selectedFriend: DockFriendContact?

    var onOpenSettings: () -> Void = {}

    private var maxAvatars: Int {
        switch size {
        case .small: return 2
        case .medium: return 3
        case .large: return 4
        }
    }

    var body: some View {
        let visibleFriends = Array(friendsStore.friends.prefix(maxAvatars))

        Group {
            if visibleFriends.isEmpty {
                Button(action: onOpenSettings) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                        if !isVertical && size != .small {
                            Text("Add Friends")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(DockWidgetStyle.ink.opacity(0.82))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Configure contacts in Wing Settings"))
            } else if isVertical {
                VStack(spacing: size == .small ? 4 : 6) {
                    ForEach(visibleFriends) { friendAvatarButton($0) }
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: size == .small ? 6 : 9) {
                    ForEach(visibleFriends) { friend in
                        friendAvatarButton(friend)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .popover(item: $selectedFriend, arrowEdge: popoverEdge) { friend in
            DockFriendActionCard(
                friend: friend,
                badgeText: friendsStore.badgeText(for: friend, badgesByBundleID: badgesByBundleID),
                avatarImage: friendsStore.avatarImage(for: friend),
                onOpenApp: { friendsStore.openFriend(friend) },
                onFaceTimeAudio: { friendsStore.openFaceTimeAudio(for: friend) },
                onFaceTimeVideo: { friendsStore.openFaceTimeVideo(for: friend) },
                onToggleSpeaking: {
                    var updated = friend
                    updated.isSpeaking.toggle()
                    friendsStore.updateFriend(updated)
                    selectedFriend = updated
                }
            )
        }
    }

    private func friendAvatarButton(_ friend: DockFriendContact) -> some View {
        let badge = friendsStore.badgeText(for: friend, badgesByBundleID: badgesByBundleID)
        let avatarNSImage = friendsStore.avatarImage(for: friend)
        let avatarDiameter: CGFloat = size == .small ? 28 : 30

        return Button {
            selectedFriend = friend
        } label: {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if friend.isSpeaking {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [Color(red: 0.42, green: 0.45, blue: 1.0), Color(red: 0.65, green: 0.42, blue: 0.98)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: avatarDiameter + 4, height: avatarDiameter + 4)
                    }

                    Circle()
                        .fill(Self.pastelTint(for: friend.accentIndex))
                        .frame(width: avatarDiameter, height: avatarDiameter)
                        .overlay {
                            if let avatarNSImage {
                                Image(nsImage: avatarNSImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipShape(Circle())
                            } else {
                                Text(verbatim: Self.initials(from: friend.displayName))
                                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.black.opacity(0.82))
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.22), lineWidth: 0.75)
                        )
                }

                if friend.isSpeaking {
                    Circle()
                        .fill(Color(red: 0.36, green: 0.34, blue: 0.94))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundStyle(.white)
                        )
                        .offset(x: 3, y: -2)
                } else if let badge {
                    Text(verbatim: badge)
                        .font(.system(size: 8, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule(style: .continuous).fill(Color(red: 0.92, green: 0.24, blue: 0.22)))
                        .offset(x: 4, y: -3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(verbatim: friend.displayName))
        .accessibilityLabel(Text(verbatim: friend.displayName))
    }

    static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap(\.first)
        if chars.isEmpty { return "?" }
        return String(chars).uppercased()
    }

    static func pastelTint(for index: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.99, green: 0.89, blue: 0.78),
            Color(red: 0.85, green: 0.87, blue: 0.96),
            Color(red: 0.98, green: 0.82, blue: 0.88),
            Color(red: 0.80, green: 0.93, blue: 0.86)
        ]
        return palette[abs(index) % palette.count]
    }
}

private struct DockFriendActionCard: View {
    let friend: DockFriendContact
    let badgeText: String?
    let avatarImage: NSImage?
    let onOpenApp: () -> Void
    let onFaceTimeAudio: () -> Void
    let onFaceTimeVideo: () -> Void
    let onToggleSpeaking: () -> Void

    var body: some View {
        DockPreviewCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(DockFriendsWidgetView.pastelTint(for: friend.accentIndex))
                        .frame(width: 40, height: 40)
                        .overlay {
                            if let avatarImage {
                                Image(nsImage: avatarImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .clipShape(Circle())
                            } else {
                                Text(verbatim: DockFriendsWidgetView.initials(from: friend.displayName))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black.opacity(0.8))
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: friend.displayName)
                            .font(.system(size: 14, weight: .semibold))
                        Text(verbatim: friend.handle.isEmpty ? friend.preferredApp.localizedTitle : friend.handle)
                            .dockCaption()
                    }
                    Spacer()
                    if let badgeText {
                        Text(verbatim: badgeText)
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                    }
                }

                HStack(spacing: 8) {
                    Button(action: onOpenApp) {
                        Label(friend.preferredApp.localizedTitle, systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.small)

                    Button(action: onFaceTimeAudio) {
                        Image(systemName: "phone.fill")
                    }
                    .controlSize(.small)
                    .help(Text("FaceTime Audio"))

                    Button(action: onFaceTimeVideo) {
                        Image(systemName: "video.fill")
                    }
                    .controlSize(.small)
                    .help(Text("FaceTime Video"))

                    Button(action: onToggleSpeaking) {
                        Image(systemName: friend.isSpeaking ? "waveform.circle.fill" : "waveform.circle")
                            .foregroundStyle(friend.isSpeaking ? Color.accentColor : Color.primary)
                    }
                    .controlSize(.small)
                    .help(Text("Speaking Indicator"))
                }
            }
        }
    }
}
