import AppKit
import ImageIO
import PDFKit
import XCTest
@testable import KatiKati

final class PDFReducePlanTests: XCTestCase {

    func testQualityClampsToLegibleRange() {
        XCTAssertEqual(PDFReducePlan.quality(0.6), 0.6)
        XCTAssertEqual(PDFReducePlan.quality(0.05), 0.2)
        XCTAssertEqual(PDFReducePlan.quality(2), 0.9)
        XCTAssertEqual(PDFReducePlan.quality(.nan), PDFReducePlan.defaultQuality)
    }

    func testRenderedSizeKeepsAspectAndClamps() {
        let full = PDFReducePlan.renderedSize(width: 600, height: 800, scale: 1)
        XCTAssertEqual(full.width, 600)
        XCTAssertEqual(full.height, 800)
        let half = PDFReducePlan.renderedSize(width: 600, height: 800, scale: 0.5)
        XCTAssertEqual(half.width, 300)
        XCTAssertEqual(half.height, 400)
        let floored = PDFReducePlan.renderedSize(width: 600, height: 800, scale: -3)
        XCTAssertEqual(floored.width, 60, "scale floors at 10 %")
        let tiny = PDFReducePlan.renderedSize(width: 1, height: 1, scale: 0.1)
        XCTAssertEqual(tiny.width, 1)
        XCTAssertEqual(tiny.height, 1)
    }
}

/// 55c: the image reduce numbers.
final class ImageReducePlanTests: XCTestCase {
    func testQualityClampsToLegibleRange() {
        XCTAssertEqual(ImageReducePlan.quality(0.6), 0.6)
        XCTAssertEqual(ImageReducePlan.quality(0.01), 0.2)
        XCTAssertEqual(ImageReducePlan.quality(5), 0.9)
        XCTAssertEqual(ImageReducePlan.quality(.infinity), ImageReducePlan.defaultQuality)
    }

    func testPixelCapClampsAndRounds() {
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000), 3000)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 1001, scale: 0.5), 501)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000, scale: 0), 400, "scale floors at 10 %")
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 1, scale: 0.1), 1)
        XCTAssertEqual(ImageReducePlan.maxPixelSize(longestEdge: 4000, scale: .nan), 3000)
    }
}

// MARK: - Phase 60: Shelf / File Tray Transforms (Slice D-TrayTransform)

final class FileTransformPlanTests: XCTestCase {
    func testBackgroundRemovalEligibilityAndDestination() {
        let png = URL(fileURLWithPath: "/Users/test/photo.png")
        let heic = URL(fileURLWithPath: "/Users/test/portrait.HEIC")
        let pdf = URL(fileURLWithPath: "/Users/test/document.pdf")

        XCTAssertTrue(FileTransformPlan.canRemoveBackground(for: png))
        XCTAssertTrue(FileTransformPlan.canRemoveBackground(for: heic))
        XCTAssertFalse(FileTransformPlan.canRemoveBackground(for: pdf))

        let noBg = FileTransformPlan.noBackgroundDestination(for: png)
        XCTAssertEqual(noBg.path, "/Users/test/photo_nobg.png")
    }

    func testZipDestination() {
        let single = [URL(fileURLWithPath: "/Users/test/report.docx")]
        XCTAssertEqual(FileTransformPlan.zipDestination(for: single)?.path, "/Users/test/report.zip")

        let multiple = [
            URL(fileURLWithPath: "/Users/test/img1.png"),
            URL(fileURLWithPath: "/Users/test/img2.png")
        ]
        XCTAssertEqual(FileTransformPlan.zipDestination(for: multiple)?.path, "/Users/test/Archive.zip")

        XCTAssertNil(FileTransformPlan.zipDestination(for: []))
    }

    func testImageConversionDestination() {
        let img = URL(fileURLWithPath: "/Users/test/graphic.png")
        XCTAssertEqual(FileTransformPlan.convertedDestination(for: img, format: .webp).path, "/Users/test/graphic.webp")
        XCTAssertEqual(FileTransformPlan.convertedDestination(for: img, format: .jpeg).path, "/Users/test/graphic.jpeg")
        XCTAssertEqual(ImageTargetFormat.webp.uniformTypeIdentifier, "org.webmproject.webp")
    }

    func testCombinedPDFDestination() {
        let single = [URL(fileURLWithPath: "/Users/test/page1.png")]
        XCTAssertEqual(FileTransformPlan.combinedPDFDestination(for: single)?.path, "/Users/test/page1_combined.pdf")

        let multi = [
            URL(fileURLWithPath: "/Users/test/page1.png"),
            URL(fileURLWithPath: "/Users/test/page2.png")
        ]
        XCTAssertEqual(FileTransformPlan.combinedPDFDestination(for: multi)?.path, "/Users/test/Combined.pdf")
        XCTAssertNil(FileTransformPlan.combinedPDFDestination(for: []))
    }
}

// MARK: - SLICE DP-1: Droppy Config, File Tray & Transform Engine Tests

final class DroppyTests: XCTestCase {
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "com.katikati.droppy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    func testShelfConfigStorePersistenceOrderAndReset() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DroppyShelfConfigStore(defaults: defaults)
        XCTAssertEqual(store.visibleWidgets(), DroppyShelfWidgetKind.allCases)
        store.move(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        store.setHidden(.clipboardNotes, true)
        store.setAccentTheme(.violetPulse)
        store.setGlassMaterial(.liquidGlass)
        let reloaded = DroppyShelfConfigStore(defaults: defaults)
        XCTAssertEqual(reloaded.order.last, .fileTray)
        XCTAssertFalse(reloaded.visibleWidgets().contains(.clipboardNotes))
        XCTAssertEqual(reloaded.accentTheme, .violetPulse)
        XCTAssertEqual(reloaded.glassMaterial, .liquidGlass)
        reloaded.reset()
        XCTAssertEqual(reloaded.visibleWidgets(), DroppyShelfWidgetKind.allCases)
        XCTAssertEqual(reloaded.glassMaterial, .dynamicGlass)
        XCTAssertEqual(reloaded.accentTheme, .oceanBlue)
    }

    func testDynamicGlassMaterialAndLowPowerMode() {
        XCTAssertEqual(DroppyGlassMaterial.dynamicGlass.resolvedTransparency(isLowPowerMode: false), 0.38, accuracy: 0.001)
        XCTAssertEqual(DroppyGlassMaterial.liquidGlass.resolvedTransparency(isLowPowerMode: false), 0.68, accuracy: 0.001)
        XCTAssertEqual(DroppyGlassMaterial.solidOLED.resolvedTransparency(isLowPowerMode: false), 0.0, accuracy: 0.001)
        XCTAssertEqual(DroppyGlassMaterial.liquidGlass.resolvedTransparency(isLowPowerMode: true), 0.0, accuracy: 0.001)
        XCTAssertTrue(DroppyGlassMaterial.dynamicGlass.shouldRenderBlur(isLowPowerMode: false))
        XCTAssertFalse(DroppyGlassMaterial.dynamicGlass.shouldRenderBlur(isLowPowerMode: true))
        XCTAssertFalse(DroppyGlassMaterial.solidOLED.shouldRenderBlur(isLowPowerMode: false))
    }

    func testFileTrayStoreAddDeduplicatePinAndClear() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let tray = DroppyFileTrayStore(defaults: defaults)
        let a = URL(fileURLWithPath: "/tmp/alpha.txt"), b = URL(fileURLWithPath: "/tmp/beta.txt")
        let t0 = Date(timeIntervalSince1970: 1000)
        tray.add(urls: [a, b], now: t0)
        tray.add(urls: [a], now: t0.addingTimeInterval(10))
        XCTAssertEqual(tray.items.count, 2)
        XCTAssertEqual(tray.items.first?.fileName, "alpha.txt")
        tray.togglePin(id: tray.items[1].id) // pin beta.txt
        XCTAssertEqual(tray.items.first?.fileName, "beta.txt")
        tray.clearUnpinned()
        XCTAssertEqual(tray.items.map(\.fileName), ["beta.txt"])
        let reloaded = DroppyFileTrayStore(defaults: defaults)
        XCTAssertEqual(reloaded.items.map(\.fileName), ["beta.txt"])
    }

    func testFileTransformEngineZipResizeAndMergePDF() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("droppy-engine-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func makePNG(_ name: String, width: Int, height: Int) throws -> URL {
            let url = dir.appendingPathComponent(name)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.systemBlue.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
            NSGraphicsContext.restoreGraphicsState()
            try rep.representation(using: .png, properties: [:])!.write(to: url)
            return url
        }

        let img1 = try makePNG("one.png", width: 200, height: 100)
        let img2 = try makePNG("two.png", width: 120, height: 120)
        let zipOut = try FileTransformEngine.zipFiles([img1, img2], destination: dir.appendingPathComponent("Bundle.zip"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipOut.path))

        let resized = try FileTransformEngine.resizeImage(at: img1, scale: 0.5, destination: dir.appendingPathComponent("one_half.png"))
        let src = CGImageSourceCreateWithURL(resized as CFURL, nil)!
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 100)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 50)

        let pdfOut = try FileTransformEngine.mergePDFs([img1, img2], destination: dir.appendingPathComponent("Out.pdf"))
        let pdfDoc = PDFDocument(url: pdfOut)
        XCTAssertEqual(pdfDoc?.pageCount, 2)
    }
}
