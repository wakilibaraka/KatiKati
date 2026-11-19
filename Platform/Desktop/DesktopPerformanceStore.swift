import Foundation

/// Live desktop performance profile. Views observe this store so switching profiles updates animations
/// immediately, and cache budgets are applied whenever the profile changes.
@MainActor
final class DesktopPerformanceStore: ObservableObject {
    static let shared = DesktopPerformanceStore()

    @Published private(set) var settings: DesktopPerformanceSettings
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = DesktopPerformanceConfig.settings(defaults: defaults)
        applyBudgets()
    }

    func apply(_ next: DesktopPerformanceSettings) {
        var clamped = next
        clamped.visibleIdleCleanupSeconds = DesktopPerformanceConfig.clampedIdleSeconds(next.visibleIdleCleanupSeconds)
        clamped.thumbnailCacheMegabytes = DesktopPerformanceConfig.clampedThumbnailMB(next.thumbnailCacheMegabytes)
        clamped.imageCacheMegabytes = DesktopPerformanceConfig.clampedImageMB(next.imageCacheMegabytes)
        settings = clamped
        DesktopPerformanceConfig.save(clamped, defaults: defaults)
        applyBudgets()
    }

    func selectMode(_ mode: DesktopPerformanceMode) {
        apply(DesktopPerformanceSettings.defaults(for: mode))
    }

    func setAnimation(_ animation: DesktopPerformanceAnimation, enabled: Bool) {
        var next = settings
        next.mode = .custom
        next.animations[animation] = enabled
        apply(next)
    }

    var mode: DesktopPerformanceMode { settings.mode }

    private func applyBudgets() {
        DesktopThumbnailCache.applyBudget(megabytes: settings.thumbnailCacheMegabytes)
        DesktopAssetStore.setCacheBudget(megabytes: settings.imageCacheMegabytes)
    }
}
