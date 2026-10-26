import XCTest
@testable import KatiKati

/// The Drives widget and the menu-bar item both read `DriveVolume`, so its arithmetic and the
/// reader's filtering are pinned here rather than assumed.
final class DriveInventoryTests: XCTestCase {
    private func volume(name: String, total: Int64, free: Int64, internal isInternal: Bool, removable: Bool = false) -> DriveVolume {
        DriveVolume(mountPath: "/Volumes/\(name)", name: name, totalBytes: total, freeBytes: free,
                    isRemovable: removable, isInternal: isInternal)
    }

    func testFractionIsClampedAndSurvivesNonsense() {
        // A volume that reports more free space than capacity (APFS purgeable accounting) must not
        // draw a negative bar.
        let odd = volume(name: "Odd", total: 100, free: 140, internal: true)
        XCTAssertEqual(odd.usedBytes, 0)
        XCTAssertEqual(odd.usedFraction, 0)

        // No capacity at all: empty, not a division by zero.
        XCTAssertEqual(volume(name: "Empty", total: 0, free: 0, internal: true).usedFraction, 0)

        let half = volume(name: "Half", total: 200, free: 100, internal: true)
        XCTAssertEqual(half.usedBytes, 100)
        XCTAssertEqual(half.usedFraction, 0.5, accuracy: 0.0001)
    }

    func testCapacityTextReadsLikeFinder() {
        // DiskView's own pair: 318.62 GB of 499.96 GB.
        let boot = volume(name: "Macintosh HD", total: 499_960_000_000, free: 181_340_000_000, internal: true)
        XCTAssertEqual(boot.capacityText, "318.62 GB / 499.96 GB")
    }

    func testInternalDrivesLeadThenName() {
        let sorted = DriveInventory.sorted([
            volume(name: "Samsung USB", total: 64_160_000_000, free: 13_000_000_000, internal: false, removable: true),
            volume(name: "Misc", total: 1_000_000_000_000, free: 163_000_000_000, internal: false),
            volume(name: "Macintosh HD", total: 499_960_000_000, free: 181_340_000_000, internal: true),
            volume(name: "LaCie", total: 1_000_000_000_000, free: 0, internal: false),
        ])
        XCTAssertEqual(sorted.map(\.name), ["Macintosh HD", "LaCie", "Misc", "Samsung USB"])
    }

    func testReaderFindsTheBootVolume() {
        // Any running machine has at least one mounted, browsable volume; anything with no capacity
        // (the preboot and VM volumes) must have been filtered out.
        let volumes = DriveInventory.volumes()
        XCTAssertFalse(volumes.isEmpty)
        XCTAssertTrue(volumes.allSatisfy { $0.totalBytes > 0 && $0.freeBytes >= 0 })
        XCTAssertEqual(Set(volumes.map(\.id)).count, volumes.count)
    }
}
