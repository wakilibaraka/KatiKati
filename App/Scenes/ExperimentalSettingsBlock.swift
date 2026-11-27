import SwiftUI

/// Experimental settings consolidated into one dedicated tab: undocumented / private macOS surfaces
/// (`Mission Control` overview overlay, `Lock Screen Card`, and `Album Art Wallpaper`) plus safety controls.
struct ExperimentalSettingsBlock: View {
    @ObservedObject var tabState: SettingsTabState

    @AppStorage(MusicSurfaceConfig.wallpaperEnabledKey) private var wallpaperEnabled = false
    @AppStorage(MusicSurfaceConfig.wallpaperClassicKey) private var wallpaperClassic = false
    @AppStorage(MusicSurfaceConfig.wallpaperAnimatedKey) private var wallpaperAnimated = false
    @AppStorage(MusicSurfaceConfig.lockScreenCardKey) private var lockScreenCard = false

    var body: some View {
        SettingsCard(
            Text("Experimental Surface Controls"),
            note: Text("Features below use undocumented WindowServer APIs, private Spaces, or full-screen layers that can break or need adjustment after macOS updates.")
        ) {
            SettingsToggleRow(
                Text("Album Art Wallpaper"),
                isOn: Binding(
                    get: { wallpaperEnabled },
                    set: { on in
                        wallpaperEnabled = on
                        if on {
                            MusicWallpaperController.shared.start(service: DesktopWidgetServices.nowPlaying)
                        } else {
                            MusicWallpaperController.shared.stop()
                        }
                        MusicSurfaceConfig.notifyChange()
                    }
                ),
                note: Text("Draws full-screen album art on the desktop wallpaper layer.")
            )
            if wallpaperEnabled {
                SettingsDivider()
                SettingsToggleRow(
                    Text("Classic Static Backdrop"),
                    isOn: Binding(
                        get: { wallpaperClassic },
                        set: { on in
                            wallpaperClassic = on
                            UserDefaults.standard.set(on, forKey: MusicSurfaceConfig.wallpaperClassicKey)
                        }
                    ),
                    note: Text("One cached frame per track, no timers — no idle CPU.")
                )
                SettingsDivider()
                SettingsToggleRow(
                    Text("Animated Album Art"),
                    isOn: Binding(
                        get: { wallpaperAnimated },
                        set: { on in
                            wallpaperAnimated = on
                            UserDefaults.standard.set(on, forKey: MusicSurfaceConfig.wallpaperAnimatedKey)
                            MusicSurfaceConfig.notifyChange()
                        }
                    ),
                    note: Text("Slides and zooms the art on a slow loop while playing.")
                )
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Lock Screen Card"),
                isOn: Binding(
                    get: { lockScreenCard },
                    set: { on in
                        lockScreenCard = on
                        if on { LockScreenMusicCardController.shared.start() } else { LockScreenMusicCardController.shared.stop() }
                    }
                ),
                note: Text("Uses a private macOS space; hidden automatically when the system does not allow it.")
            )
            SettingsDivider()
            SettingsRow(Text("Desktop & Music Styles")) {
                Button("Open Music") { tabState.selected = .music }
                    .buttonStyle(SettingsGelButtonStyle())
            }
        }

        SettingsLockScreenMusicCard()
    }
}
