import SwiftUI

/// Phase 67D–E: performance profiles for desktop widgets.
struct DesktopPerformanceSettingsCard: View {
    @ObservedObject private var performance = DesktopPerformanceStore.shared

    private var settings: DesktopPerformanceSettings { performance.settings }

    private var modeBinding: Binding<String> {
        Binding(
            get: { settings.mode.rawValue },
            set: { raw in
                guard let mode = DesktopPerformanceMode(rawValue: raw) else { return }
                performance.selectMode(mode)
            }
        )
    }

    private var hiddenSurfaceBinding: Binding<Bool> {
        Binding(
            get: { settings.releasesHiddenSurfaces },
            set: { value in update { $0.releasesHiddenSurfaces = value } }
        )
    }

    private func animationBinding(_ animation: DesktopPerformanceAnimation) -> Binding<Bool> {
        Binding(
            get: { settings.allowsAnimation(animation) },
            set: { performance.setAnimation(animation, enabled: $0) }
        )
    }

    private func update(_ change: (inout DesktopPerformanceSettings) -> Void) {
        var next = settings
        next.mode = .custom
        change(&next)
        performance.apply(next)
    }

    var body: some View {
        SettingsCard(Text("Desktop Performance")) {
            SettingsPickerRow(Text("Performance Mode"), selection: modeBinding) {
                Text("Balanced").tag(DesktopPerformanceMode.balanced.rawValue)
                Text("Resource Saver").tag(DesktopPerformanceMode.resourceSaver.rawValue)
                Text("Custom").tag(DesktopPerformanceMode.custom.rawValue)
            }
            SettingsDivider()
            SettingsToggleRow(
                Text("Release Hidden Widget Views"),
                isOn: hiddenSurfaceBinding,
                note: Text("Frees each hidden widget's drawing surface until it is shown again.")
            )
            SettingsDivider()
            SettingsSliderRow(
                Text("Idle Cache Cleanup"),
                value: settings.visibleIdleCleanupSeconds,
                range: DesktopPerformanceConfig.idleCleanupRange,
                step: 10,
                valueText: settings.visibleIdleCleanupSeconds == 0
                    ? String(localized: "Off")
                    : String(format: String(localized: "%lld s"), Int(settings.visibleIdleCleanupSeconds))
            ) { seconds in
                update { $0.visibleIdleCleanupSeconds = seconds }
            }
            SettingsDivider()
            SettingsSliderRow(
                Text("Thumbnail Cache"),
                value: Double(settings.thumbnailCacheMegabytes),
                range: Double(DesktopPerformanceConfig.thumbnailCacheRange.lowerBound)...Double(DesktopPerformanceConfig.thumbnailCacheRange.upperBound),
                step: 8,
                valueText: "\(settings.thumbnailCacheMegabytes) MB"
            ) { value in
                update { $0.thumbnailCacheMegabytes = Int(value) }
            }
            SettingsDivider()
            SettingsSliderRow(
                Text("Image Cache"),
                value: Double(settings.imageCacheMegabytes),
                range: Double(DesktopPerformanceConfig.imageCacheRange.lowerBound)...Double(DesktopPerformanceConfig.imageCacheRange.upperBound),
                step: 16,
                valueText: "\(settings.imageCacheMegabytes) MB"
            ) { value in
                update { $0.imageCacheMegabytes = Int(value) }
            }
            SettingsDivider()
            SettingsToggleRow(Text("Vinyl Record Spin"), isOn: animationBinding(.vinylSpin))
            SettingsDivider()
            SettingsToggleRow(Text("Marquee Scrolling"), isOn: animationBinding(.marquee))
            SettingsDivider()
            SettingsToggleRow(Text("Glance Rotation"), isOn: animationBinding(.glanceRotation))
            SettingsDivider()
            SettingsToggleRow(Text("Capsule Effects"), isOn: animationBinding(.capsuleEffects))
        }
    }
}
