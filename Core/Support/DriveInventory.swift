import Foundation

/// One mounted volume, the way DiskView lists them: a name, the capacity, and what is free.
struct DriveVolume: Identifiable, Equatable, Sendable {
    let mountPath: String
    let name: String
    let totalBytes: Int64
    let freeBytes: Int64
    let isRemovable: Bool
    let isInternal: Bool

    var id: String { mountPath }

    /// Never negative: APFS reports reserves that can make free space read larger than the capacity
    /// on a nearly empty volume, and a negative bar is worse than a full one.
    var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    /// 0…1. A volume that reports no capacity reads empty instead of dividing by zero.
    var usedFraction: Double {
        totalBytes > 0 ? min(1, Double(usedBytes) / Double(totalBytes)) : 0
    }

    /// `318.62 GB / 499.96 GB` — the pair DiskView prints above each bar.
    var capacityText: String {
        "\(SystemMonitorFormat.bytes(Double(usedBytes))) / \(SystemMonitorFormat.bytes(Double(totalBytes)))"
    }
}

/// The Drives widget's and the menu-bar item's reader: mounted, browsable, local volumes with the
/// free space Finder shows (`volumeAvailableCapacityForImportantUsage` counts purgeable space, which
/// is why it reads higher than the raw figure and why Finder and this agree).
enum DriveInventory {
    private static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
        .volumeIsRemovableKey, .volumeIsInternalKey, .volumeIsBrowsableKey, .volumeIsLocalKey,
    ]

    static func volumes(fileManager: FileManager = .default) -> [DriveVolume] {
        guard let urls = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) else { return [] }
        return sorted(urls.compactMap(volume(for:)))
    }

    /// `nil` for anything that is not a browsable local volume — the preboot and VM volumes ride
    /// along in the mount table and are not drives anyone wants a bar for.
    static func volume(for url: URL) -> DriveVolume? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)),
              values.volumeIsBrowsable ?? true,
              values.volumeIsLocal ?? true,
              let total = values.volumeTotalCapacity, total > 0
        else { return nil }
        return DriveVolume(
            mountPath: url.path,
            name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
            totalBytes: Int64(total),
            freeBytes: max(0, values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)),
            isRemovable: values.volumeIsRemovable ?? false,
            isInternal: values.volumeIsInternal ?? false
        )
    }

    /// Internal first, then by name: the boot drive leads, as it does in DiskView.
    static func sorted(_ volumes: [DriveVolume]) -> [DriveVolume] {
        volumes.sorted {
            if $0.isInternal != $1.isInternal { return $0.isInternal }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
