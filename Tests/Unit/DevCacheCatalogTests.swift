import XCTest
@testable import KatiKati

final class DevCacheCatalogTests: XCTestCase {
    private let home = "/Users/tester"

    func testEveryTargetIsUniqueAndCarriesItsOwnMetadata() {
        XCTAssertEqual(Set(DevCacheCatalog.targets.map(\.id)).count, DevCacheCatalog.targets.count)
        XCTAssertEqual(Set(DevCacheCatalog.targets.map(\.kind)), Set(DevCacheTarget.Kind.allCases),
                       "every catalogue kind is offered exactly once")
        for target in DevCacheCatalog.targets {
            XCTAssertFalse(target.title.isEmpty)
            XCTAssertFalse(target.symbol.isEmpty)
        }
        XCTAssertEqual(DevCacheCatalog.targets.filter { $0.relativePaths.isEmpty }.map(\.kind), [.nodeModules],
                       "only node_modules is discovered rather than read from a fixed root")
    }

    func testResolvedPathsStayUnderTheHomeDirectory() {
        for target in DevCacheCatalog.targets {
            for path in target.resolvedPaths(home: home) {
                XCTAssertTrue(path.hasPrefix(home + "/"), "\(path) escaped the home directory")
                XCTAssertFalse(path.contains(".."))
            }
        }
    }

    func testSnapshotReportsOnlyRootsThatExistAndWeighSomething() {
        let existing: Set<String> = [home + "/Library/Developer/Xcode/DerivedData",
                                     home + "/Library/Caches/pip"]
        let readings = DevCacheCatalog.snapshot(
            home: home,
            isDirectory: { existing.contains($0) },
            size: { $0.hasSuffix("DerivedData") ? 900 : 40 },
            children: { _ in [] }
        )
        XCTAssertEqual(readings.map(\.target.kind), [.derivedData, .pip])
        XCTAssertEqual(readings.first?.paths, [home + "/Library/Developer/Xcode/DerivedData"])
        XCTAssertEqual(readings.reduce(0) { $0 + $1.bytes }, 940)
    }

    func testSnapshotFindsNodeModulesOneLevelUnderASourceRoot() {
        let root = home + "/Developer/Shop"
        let modules = root + "/node_modules"
        let readings = DevCacheCatalog.snapshot(
            home: home,
            isDirectory: { $0 == home + "/Developer" || $0 == modules },
            size: { $0 == modules ? 1_200 : 0 },
            children: { $0 == home + "/Developer" ? [root] : [] }
        )
        XCTAssertEqual(readings.map(\.target.kind), [.nodeModules])
        XCTAssertEqual(readings.first?.paths, [modules])
    }

    func testOneClickReclaimLeavesHighRiskRootsAlone() {
        let low = DevCacheReading(target: target(.derivedData), paths: ["/a"], bytes: 100)
        let medium = DevCacheReading(target: target(.nodeModules), paths: ["/b"], bytes: 200)
        let high = DevCacheReading(target: target(.archives), paths: ["/c"], bytes: 400)
        XCTAssertEqual(DevCacheCatalog.reclaimableBytes([low, medium, high]), 300)
        XCTAssertEqual(DevCacheCatalog.reclaimableBytes([high]), 0)
    }

    func testOrderingPutsRiskFirstThenSize() {
        let readings = [
            DevCacheReading(target: target(.derivedData), paths: ["/a"], bytes: 900),
            DevCacheReading(target: target(.archives), paths: ["/b"], bytes: 10),
            DevCacheReading(target: target(.pip), paths: ["/c"], bytes: 50),
        ]
        XCTAssertEqual(DevCacheCatalog.ordered(readings).map(\.target.kind), [.archives, .derivedData, .pip])
    }

    func testRiskTitlesAreTheAlreadyLocalizedLevels() {
        XCTAssertEqual(DevCacheTarget.Risk.allCases.map(\.rawValue), [0, 1, 2])
        XCTAssertTrue(DevCacheTarget.Risk.low.isReclaimableInOneClick)
        XCTAssertTrue(DevCacheTarget.Risk.medium.isReclaimableInOneClick)
        XCTAssertFalse(DevCacheTarget.Risk.high.isReclaimableInOneClick)
    }

    private func target(_ kind: DevCacheTarget.Kind) -> DevCacheTarget {
        DevCacheCatalog.targets.first { $0.kind == kind }!
    }
}

/// The storage page's last measurement, kept for surfaces that must not scan (the dashboard).
final class DevCacheSnapshotTests: XCTestCase {
    private let suiteName = "com.katikati.tests.devcache.snapshot"

    func testSaveKeepsTheOneClickTotalAndTheMeasurementDate() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        XCTAssertNil(DevCacheSnapshotStore.load(defaults: defaults), "a machine that never opened Storage has no total")

        let low = DevCacheReading(target: DevCacheCatalog.targets.first { $0.kind == .derivedData }!,
                                  paths: ["/a"], bytes: 100)
        let high = DevCacheReading(target: DevCacheCatalog.targets.first { $0.kind == .archives }!,
                                   paths: ["/b"], bytes: 400)
        let measured = Date(timeIntervalSince1970: 1_700_000_000)
        DevCacheSnapshotStore.save([low, high], at: measured, defaults: defaults)

        XCTAssertEqual(DevCacheSnapshotStore.load(defaults: defaults),
                       DevCacheSnapshot(measuredAt: measured, reclaimableBytes: 100),
                       "archives are never part of the one-click figure")
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDecodeRejectsMalformedOrNegativeSnapshots() {
        XCTAssertNil(DevCacheSnapshotStore.decode(nil))
        XCTAssertNil(DevCacheSnapshotStore.decode("v2|1|2"))
        XCTAssertNil(DevCacheSnapshotStore.decode("v1|nope|2"))
        XCTAssertNil(DevCacheSnapshotStore.decode("v1|1|-2"), "a negative total would draw as a credit")
        XCTAssertNil(DevCacheSnapshotStore.decode("v1|1"))
        XCTAssertEqual(DevCacheSnapshotStore.decode("v1|0|0"),
                       DevCacheSnapshot(measuredAt: Date(timeIntervalSince1970: 0), reclaimableBytes: 0))
    }

    func testRoundTripIsStableForTheStoredFormat() {
        let snapshot = DevCacheSnapshot(measuredAt: Date(timeIntervalSince1970: 1_800_000_000),
                                        reclaimableBytes: 5_200_000_000)
        XCTAssertEqual(DevCacheSnapshotStore.encode(snapshot), "v1|1800000000|5200000000")
        XCTAssertEqual(DevCacheSnapshotStore.decode(DevCacheSnapshotStore.encode(snapshot)), snapshot)
    }
}
