import Foundation

/// Balanced / Resource Saver / Custom desktop performance profiles (Phase 67D–E).
enum DesktopPerformanceMode: String, Codable, CaseIterable, Sendable {
    case balanced
    case resourceSaver
    case custom
}

enum DesktopPerformanceAnimation: String, CaseIterable, Codable, Sendable {
    case vinylSpin
    case marquee
    case glanceRotation
    case capsuleEffects
}

struct DesktopPerformanceSettings: Codable, Equatable, Sendable {
    var mode: DesktopPerformanceMode
    /// Release each hidden widget's SwiftUI hosting surface until it is shown again.
    var releasesHiddenSurfaces: Bool
    /// Seconds with no desktop interaction before caches are purged.
    var visibleIdleCleanupSeconds: Double
    var thumbnailCacheMegabytes: Int
    var imageCacheMegabytes: Int
    var animations: [DesktopPerformanceAnimation: Bool]

    static func defaults(for mode: DesktopPerformanceMode) -> DesktopPerformanceSettings {
        switch mode {
        case .balanced:
            return DesktopPerformanceSettings(
                mode: .balanced,
                releasesHiddenSurfaces: true,
                visibleIdleCleanupSeconds: 120,
                thumbnailCacheMegabytes: 64,
                imageCacheMegabytes: 128,
                animations: Dictionary(uniqueKeysWithValues: DesktopPerformanceAnimation.allCases.map { ($0, true) })
            )
        case .resourceSaver:
            return DesktopPerformanceSettings(
                mode: .resourceSaver,
                releasesHiddenSurfaces: true,
                visibleIdleCleanupSeconds: 20,
                thumbnailCacheMegabytes: 16,
                imageCacheMegabytes: 32,
                animations: Dictionary(uniqueKeysWithValues: DesktopPerformanceAnimation.allCases.map { ($0, false) })
            )
        case .custom:
            return defaults(for: .balanced).withMode(.custom)
        }
    }

    func withMode(_ mode: DesktopPerformanceMode) -> DesktopPerformanceSettings {
        var copy = self
        copy.mode = mode
        return copy
    }

    func allowsAnimation(_ animation: DesktopPerformanceAnimation) -> Bool {
        animations[animation] ?? (mode != .resourceSaver)
    }
}

enum DesktopPerformanceConfig {
    static let modeKey = "com.katikati.desktop.performance.mode"
    static let hiddenSurfaceReleaseKey = "com.katikati.desktop.performance.hiddenSurfaceRelease"
    static let idleCleanupSecondsKey = "com.katikati.desktop.performance.idleCleanupSeconds"
    static let thumbnailCacheMBKey = "com.katikati.desktop.performance.thumbnailCacheMB"
    static let imageCacheMBKey = "com.katikati.desktop.performance.imageCacheMB"
    static let animationPrefix = "com.katikati.desktop.performance.animation."

    static let idleCleanupRange: ClosedRange<Double> = 0...600
    static let thumbnailCacheRange: ClosedRange<Int> = 8...512
    static let imageCacheRange: ClosedRange<Int> = 16...1024

    static func animationKey(_ animation: DesktopPerformanceAnimation) -> String {
        animationPrefix + animation.rawValue
    }

    static func clampedIdleSeconds(_ value: Double) -> Double {
        min(max(value, idleCleanupRange.lowerBound), idleCleanupRange.upperBound)
    }

    static func clampedThumbnailMB(_ value: Int) -> Int {
        min(max(value, thumbnailCacheRange.lowerBound), thumbnailCacheRange.upperBound)
    }

    static func clampedImageMB(_ value: Int) -> Int {
        min(max(value, imageCacheRange.lowerBound), imageCacheRange.upperBound)
    }

    static func settings(defaults: UserDefaults = .standard) -> DesktopPerformanceSettings {
        let mode = defaults.string(forKey: modeKey).flatMap(DesktopPerformanceMode.init(rawValue:)) ?? .balanced
        let base = DesktopPerformanceSettings.defaults(for: mode)
        let hidden = defaults.object(forKey: hiddenSurfaceReleaseKey) as? Bool ?? base.releasesHiddenSurfaces
        let idle = defaults.object(forKey: idleCleanupSecondsKey) as? Double ?? base.visibleIdleCleanupSeconds
        let thumb = defaults.object(forKey: thumbnailCacheMBKey) as? Int ?? base.thumbnailCacheMegabytes
        let image = defaults.object(forKey: imageCacheMBKey) as? Int ?? base.imageCacheMegabytes
        var animations = base.animations
        for animation in DesktopPerformanceAnimation.allCases {
            if let value = defaults.object(forKey: animationKey(animation)) as? Bool {
                animations[animation] = value
            }
        }
        return DesktopPerformanceSettings(
            mode: mode,
            releasesHiddenSurfaces: hidden,
            visibleIdleCleanupSeconds: clampedIdleSeconds(idle),
            thumbnailCacheMegabytes: clampedThumbnailMB(thumb),
            imageCacheMegabytes: clampedImageMB(image),
            animations: animations
        )
    }

    static func save(_ settings: DesktopPerformanceSettings, defaults: UserDefaults = .standard) {
        defaults.set(settings.mode.rawValue, forKey: modeKey)
        defaults.set(settings.releasesHiddenSurfaces, forKey: hiddenSurfaceReleaseKey)
        defaults.set(settings.visibleIdleCleanupSeconds, forKey: idleCleanupSecondsKey)
        defaults.set(settings.thumbnailCacheMegabytes, forKey: thumbnailCacheMBKey)
        defaults.set(settings.imageCacheMegabytes, forKey: imageCacheMBKey)
        for animation in DesktopPerformanceAnimation.allCases {
            defaults.set(settings.allowsAnimation(animation), forKey: animationKey(animation))
        }
    }
}
