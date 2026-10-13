#!/usr/bin/env swift
// Phase 10c-3 — regenerates KatiKati's own icon art so it is reproducible (no binary-only sources).
//
//   swift Scripts/make_icons.swift          # from the repo root
//
// Writes:
//   Resources/AppIcon.icon/Assets/glyph.svg                        (white glyph layer for the Icon Composer bundle)
//   Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf (vector template image for the status item)
//
// Design: a dock pill carrying four app dots, with a small "island" capsule floating above it. Original
// geometry only — never derived from Tungsten Edge marks (TRADEMARK.md / HYBRID_PLAN §6).

import CoreGraphics
import Foundation

// MARK: - Shared geometry (unit square, y up, 0…1)

struct Capsule { var x, y, w, h: Double }

enum Glyph {
    /// The dock pill.
    static let pill = Capsule(x: 0.18, y: 0.26, w: 0.64, h: 0.26)
    /// Four app dots punched out of the pill (centres on the pill's midline).
    static let dotRadius = 0.045
    static let dotCenters: [(Double, Double)] = (0..<4).map { (0.285 + Double($0) * 0.143, 0.39) }
    /// The island capsule above the pill.
    static let island = Capsule(x: 0.38, y: 0.60, w: 0.24, h: 0.085)
}

func capsulePath(_ c: Capsule, scale s: Double, flipY: Bool = false, height: Double = 1) -> String {
    func Y(_ y: Double) -> Double { flipY ? (height - y) * s : y * s }
    let r = c.h / 2
    let x0 = c.x * s, x1 = (c.x + c.w) * s, rr = r * s
    let yTop = Y(c.y + c.h), yBot = Y(c.y)
    return "M \(x0 + rr) \(yTop) H \(x1 - rr) A \(rr) \(rr) 0 0 1 \(x1 - rr) \(yBot) H \(x0 + rr) A \(rr) \(rr) 0 0 1 \(x0 + rr) \(yTop) Z"
}

func circlePath(cx: Double, cy: Double, r: Double, scale s: Double, flipY: Bool = false) -> String {
    let X = cx * s, Y = flipY ? (1 - cy) * s : cy * s, R = r * s
    return "M \(X - R) \(Y) a \(R) \(R) 0 1 0 \(2 * R) 0 a \(R) \(R) 0 1 0 \(-2 * R) 0 Z"
}

// MARK: - SVG (Icon Composer glyph layer)

func makeSVG() -> String {
    var d = capsulePath(Glyph.pill, scale: 1024, flipY: true)
    for (cx, cy) in Glyph.dotCenters { d += "\n    " + circlePath(cx: cx, cy: cy, r: Glyph.dotRadius, scale: 1024, flipY: true) }
    d += "\n    " + capsulePath(Glyph.island, scale: 1024, flipY: true)
    return """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      <path fill="#FFFFFF" fill-rule="evenodd" d="\(d)"/>
    </svg>

    """
}

// MARK: - PDF (menu-bar template, 18×18 pt)

func cgCapsule(_ c: Capsule, scale s: Double) -> CGPath {
    CGPath(roundedRect: CGRect(x: c.x * s, y: c.y * s, width: c.w * s, height: c.h * s),
           cornerWidth: c.h * s / 2, cornerHeight: c.h * s / 2, transform: nil)
}

func makeMenuBarPDF(to url: URL) {
    // The menu bar wants the mark to fill its box, so re-map the glyph's bounding area onto 18×18.
    let size = 18.0
    var box = CGRect(x: 0, y: 0, width: size, height: size)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { fatalError("cannot create PDF context") }
    ctx.beginPDFPage(nil)
    let minX = Glyph.pill.x, maxX = Glyph.pill.x + Glyph.pill.w
    let minY = Glyph.pill.y, maxY = Glyph.island.y + Glyph.island.h
    let k = size / max(maxX - minX, maxY - minY)
    ctx.translateBy(x: (size - (maxX - minX) * k) / 2, y: (size - (maxY - minY) * k) / 2)
    ctx.scaleBy(x: k, y: k)
    ctx.translateBy(x: -minX, y: -minY)
    let path = CGMutablePath()
    path.addPath(cgCapsule(Glyph.pill, scale: 1))
    for (cx, cy) in Glyph.dotCenters {
        path.addEllipse(in: CGRect(x: cx - Glyph.dotRadius, y: cy - Glyph.dotRadius, width: Glyph.dotRadius * 2, height: Glyph.dotRadius * 2))
    }
    path.addPath(cgCapsule(Glyph.island, scale: 1))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.addPath(path)
    ctx.fillPath(using: .evenOdd)
    ctx.endPDFPage()
    ctx.closePDF()
}

// MARK: - Run

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let svgURL = root.appendingPathComponent("Resources/AppIcon.icon/Assets/glyph.svg")
let pdfURL = root.appendingPathComponent("Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.pdf")
guard FileManager.default.fileExists(atPath: svgURL.deletingLastPathComponent().path) else {
    fatalError("run from the repository root")
}
try makeSVG().write(to: svgURL, atomically: true, encoding: .utf8)
makeMenuBarPDF(to: pdfURL)
print("wrote \(svgURL.path)\nwrote \(pdfURL.path)")
