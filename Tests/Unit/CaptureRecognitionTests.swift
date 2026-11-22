import AppKit
import CoreImage
import XCTest
@testable import KatiKati

final class CaptureRecognitionTests: XCTestCase {
    /// Rendered into an explicit 2× bitmap: `lockFocus` inherits the window backing scale, and under
    /// a full-suite run it occasionally handed Vision a blank or half-sized image.
    private func png(_ rep: NSBitmapImageRep) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
        return url
    }

    func testRecognisesRenderedTextAndAQRCode() throws {
        let size = NSSize(width: 520, height: 320)
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("Invoice 4821" as NSString).draw(at: NSPoint(x: 20, y: 250), withAttributes: [.font: NSFont.systemFont(ofSize: 44), .foregroundColor: NSColor.black])
        let qr = CIFilter(name: "CIQRCodeGenerator")!
        qr.setValue(Data("https://example.com/hello".utf8), forKey: "inputMessage")
        let ci = qr.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        NSImage(cgImage: CIContext().createCGImage(ci, from: ci.extent)!, size: ci.extent.size).draw(at: NSPoint(x: 20, y: 10), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let url = try png(rep)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try XCTUnwrap(CaptureController.recognise(url))
        XCTAssertTrue(result.text.contains("Invoice"), "text: \(result.text)")
        XCTAssertEqual(result.codes, ["https://example.com/hello"])
    }

    func testMissingFileMeansCancelled() {
        XCTAssertNil(CaptureController.recognise(URL(fileURLWithPath: "/nonexistent/none.png")))
    }
}
