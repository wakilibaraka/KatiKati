import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class DesktopAssetStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        DesktopAssetStore.clearCache()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("katikati-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        DesktopAssetStore.clearCache()
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeSyntheticPNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw XCTSkip("Could not create synthetic test PNG")
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    func testImportDecodeDownsamplesAndCachesAndPrunesUnused() throws {
        let rawImage = tempRoot.appendingPathComponent("wallpaper.png")
        try writeSyntheticPNG(to: rawImage, width: 400, height: 200)

        let assetsDir = tempRoot.appendingPathComponent("DesktopAssets", isDirectory: true)
        let importedKeep = try DesktopAssetStore.importImage(from: rawImage, kind: .widgetBackground, directory: assetsDir)
        let importedDrop = try DesktopAssetStore.importImage(from: rawImage, kind: .widgetIcon, directory: assetsDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedKeep.path))

        let decoded = try XCTUnwrap(DesktopAssetStore.decodedImage(at: importedKeep.path, maxPixelDimension: 100))
        XCTAssertLessThanOrEqual(max(decoded.size.width, decoded.size.height), 100)

        let cachedHit = DesktopAssetStore.decodedImage(at: importedKeep.path, maxPixelDimension: 100)
        XCTAssertTrue(decoded === cachedHit)

        DesktopAssetStore.pruneUnusedAssets(referencedPaths: [importedKeep.path], in: assetsDir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedKeep.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedDrop.path))
    }

    func testImportRejectsNonImageFile() throws {
        let txt = tempRoot.appendingPathComponent("not-image.txt")
        try Data("hello".utf8).write(to: txt)
        let assetsDir = tempRoot.appendingPathComponent("DesktopAssets", isDirectory: true)
        XCTAssertThrowsError(try DesktopAssetStore.importImage(from: txt, kind: .panorama, directory: assetsDir))
    }
}
