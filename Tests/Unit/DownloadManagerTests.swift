import Foundation
import XCTest
@testable import KatiKati

final class DownloadManagerTests: XCTestCase {

    func testMagnetURIParserValid() {
        let uri = "magnet:?xt=urn:btih:c12fe1c06bba254a9dc9f519b335380dc1f74c38&dn=Ubuntu+24.04+LTS&tr=https%3A%2F%2Ftorrent.ubuntu.com%2Fannounce&xl=5400000000"
        let parsed = MagnetURIParser.parse(uri)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.displayName, "Ubuntu 24.04 LTS")
        XCTAssertEqual(parsed?.infoHash, "C12FE1C06BBA254A9DC9F519B335380DC1F74C38")
        XCTAssertEqual(parsed?.exactLength, 5400000000)
        XCTAssertEqual(parsed?.trackers.count, 1)
        XCTAssertEqual(parsed?.trackers.first, "https://torrent.ubuntu.com/announce")
    }

    func testMagnetURIParserInvalid() {
        let invalid = "https://example.com/file.iso"
        XCTAssertNil(MagnetURIParser.parse(invalid))

        let noHash = "magnet:?dn=Something"
        XCTAssertNil(MagnetURIParser.parse(noHash))
    }

    func testDownloadItemCalculations() {
        var item = DownloadItem(
            name: "test.zip",
            type: .directUrl,
            state: .active,
            bytesDownloaded: 500_000_000,
            totalBytes: 1_000_000_000,
            downloadSpeedBps: 10_000_000,
            etaSeconds: 50
        )

        XCTAssertEqual(item.fraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(item.formattedETA, "50s")
        XCTAssertTrue(item.formattedSpeed.contains("/s"))
        XCTAssertTrue(item.formattedSizeProgress.contains("/"))

        item.etaSeconds = 125
        XCTAssertEqual(item.formattedETA, "2m 5s")

        item.etaSeconds = 3665
        XCTAssertEqual(item.formattedETA, "1h 1m")
    }

    @MainActor
    func testDownloadManagerServiceAddAndManage() {
        let service = DownloadManagerService()
        let initialCount = service.items.count

        // Add magnet
        let magnet = "magnet:?xt=urn:btih:FEDCBA9876543210FEDCBA9876543210FEDCBA98&dn=TestTorrent"
        let addedMagnet = service.addDownload(input: magnet)
        XCTAssertTrue(addedMagnet)
        XCTAssertEqual(service.items.count, initialCount + 1)
        let addedItem = service.items[0]
        XCTAssertEqual(addedItem.type, .torrent)
        XCTAssertEqual(addedItem.name, "TestTorrent")

        // Pause
        service.pause(id: addedItem.id)
        XCTAssertEqual(service.items.first(where: { $0.id == addedItem.id })?.state, .paused)

        // Resume
        service.resume(id: addedItem.id)
        XCTAssertEqual(service.items.first(where: { $0.id == addedItem.id })?.state, .active)

        // Cancel
        service.cancel(id: addedItem.id)
        XCTAssertNil(service.items.first(where: { $0.id == addedItem.id }))
    }
}
