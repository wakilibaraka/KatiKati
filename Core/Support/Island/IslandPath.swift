import CoreGraphics
import Foundation

public struct IslandCornerShape: Equatable, Sendable {
    public var rx: Double
    public var ry: Double
    public var exponent: Double
    public var smoothing: Double

    public init(rx: Double, ry: Double, exponent: Double = 2.0, smoothing: Double = 0.0) {
        self.rx = rx
        self.ry = ry
        self.exponent = exponent
        self.smoothing = smoothing
    }
}

public struct IslandCircle: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var r: Double

    public init(x: Double, y: Double, r: Double) {
        self.x = x
        self.y = y
        self.r = r
    }
}

public struct IslandBridgeOptions: Equatable, Sendable {
    public var handleSize: Double
    public var spread: Double
    public var maxGap: Double
    public var power: Double

    public init(handleSize: Double, spread: Double, maxGap: Double, power: Double = 1.5) {
        self.handleSize = handleSize
        self.spread = spread
        self.maxGap = maxGap
        self.power = power
    }
}

private struct EdgeEase {
    let p: Double
    let a: Double
    let b: Double
    let along: Double
    let across: Double
}

private func computeEdgeEase(r: Double, smoothing: Double, room: Double) -> EdgeEase {
    guard r > 1e-6 else {
        return EdgeEase(p: 0, a: 0, b: 0, along: 0, across: 0)
    }
    let s = max(0.0, min(smoothing, room / r - 1.0))
    let angle = (.pi / 4.0) * s
    let p = (1.0 + s) * r
    let along = r * (1.0 - sin(angle))
    let across = r * (1.0 - cos(angle))
    let c = r * tan(angle / 2.0) * cos(angle)
    let b = max(0.0, (p - c - along) / 3.0)
    return EdgeEase(p: p, a: 2.0 * b, b: b, along: along, across: across)
}

@inline(__always)
private func pt(_ k: CGPoint, _ u: CGPoint, _ du: Double, _ v: CGPoint, _ dv: Double) -> CGPoint {
    CGPoint(x: k.x + u.x * du + v.x * dv, y: k.y + u.y * du + v.y * dv)
}

/// Pure `CGPath` continuous-corner rectangle (`smoothing` in `0...1`, typically `0.72`),
/// matching Apple's continuous rounded rectangle geometry without AppKit/SwiftUI dependencies.
public func continuousRectCGPath(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    radius: Double,
    smoothing: Double,
    leading: Double? = nil
) -> CGPath {
    let w = max(0.0, width)
    let h = max(0.0, height)
    let path = CGMutablePath()
    guard w > 0 && h > 0 else { return path }

    let leadingRadius = leading ?? radius
    let r = max(0.0, min(radius, w / 2.0, h / 2.0))
    let rl = max(0.0, min(leadingRadius, w / 2.0, h / 2.0))
    if r < 1e-3 && rl < 1e-3 {
        path.addRect(CGRect(x: x, y: y, width: w, height: h))
        return path
    }

    let across = computeEdgeEase(r: r, smoothing: smoothing, room: w / 2.0)
    let down = computeEdgeEase(r: r, smoothing: smoothing, room: h / 2.0)
    let acrossL = rl == r ? across : computeEdgeEase(r: rl, smoothing: smoothing, room: w / 2.0)
    let downL = rl == r ? down : computeEdgeEase(r: rl, smoothing: smoothing, room: h / 2.0)

    func appendCorner(k: CGPoint, u: CGPoint, v: CGPoint, inc: EdgeEase, out: EdgeEase, rc: Double) {
        path.addLine(to: pt(k, u, inc.p, v, 0))
        guard rc >= 1e-3 else {
            path.addLine(to: k)
            return
        }
        let arcStart = pt(k, u, inc.along, v, inc.across)
        let arcEnd = pt(k, v, out.along, u, out.across)
        path.addCurve(
            to: arcStart,
            control1: pt(k, u, inc.p - inc.a, v, 0),
            control2: pt(k, u, inc.p - inc.a - inc.b, v, 0)
        )
        let center = pt(k, u, rc, v, rc)
        let startAngle = atan2(arcStart.y - center.y, arcStart.x - center.x)
        let endAngle = atan2(arcEnd.y - center.y, arcEnd.x - center.x)
        path.addArc(center: center, radius: rc, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addCurve(
            to: pt(k, v, out.p, u, 0),
            control1: pt(k, v, out.p - out.a - out.b, u, 0),
            control2: pt(k, v, out.p - out.a, u, 0)
        )
    }

    let right = x + w
    let bottom = y + h
    path.move(to: CGPoint(x: x + acrossL.p, y: y))
    appendCorner(k: CGPoint(x: right, y: y), u: CGPoint(x: -1, y: 0), v: CGPoint(x: 0, y: 1), inc: across, out: down, rc: r)
    appendCorner(k: CGPoint(x: right, y: bottom), u: CGPoint(x: 0, y: -1), v: CGPoint(x: -1, y: 0), inc: down, out: across, rc: r)
    appendCorner(k: CGPoint(x: x, y: bottom), u: CGPoint(x: 1, y: 0), v: CGPoint(x: 0, y: -1), inc: acrossL, out: downL, rc: rl)
    appendCorner(k: CGPoint(x: x, y: y), u: CGPoint(x: 0, y: 1), v: CGPoint(x: 1, y: 0), inc: downL, out: acrossL, rc: rl)
    path.closeSubpath()
    return path
}

private let superellipseSegments = 24

private func appendSuperellipseQuadrant(
    to path: CGMutablePath,
    cx: Double,
    cy: Double,
    corner: IslandCornerShape,
    fromAngle: Double
) {
    guard corner.rx > 0 && corner.ry > 0 else { return }
    if abs(corner.exponent - 2.0) < 1e-3 && abs(corner.rx - corner.ry) < 1e-3 {
        path.addArc(
            center: CGPoint(x: cx, y: cy),
            radius: corner.rx,
            startAngle: fromAngle,
            endAngle: fromAngle + .pi / 2.0,
            clockwise: false
        )
        return
    }
    let power = 2.0 / corner.exponent
    for i in 1...superellipseSegments {
        let angle = fromAngle + (.pi / 2.0) * (Double(i) / Double(superellipseSegments))
        let cosA = cos(angle)
        let sinA = sin(angle)
        let px = cx + corner.rx * (cosA >= 0 ? 1.0 : -1.0) * pow(abs(cosA), power)
        let py = cy + corner.ry * (sinA >= 0 ? 1.0 : -1.0) * pow(abs(sinA), power)
        path.addLine(to: CGPoint(x: px, y: py))
    }
}

public func roundedRectCGPath(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    corner: IslandCornerShape,
    leading: IslandCornerShape? = nil
) -> CGPath {
    let leadCorner = leading ?? corner
    if corner.smoothing > 0 {
        return continuousRectCGPath(
            x: x,
            y: y,
            width: width,
            height: height,
            radius: corner.rx,
            smoothing: corner.smoothing,
            leading: leadCorner.rx
        )
    }
    let w = max(0.0, width)
    let h = max(0.0, height)
    let path = CGMutablePath()
    guard w > 0 && h > 0 else { return path }

    func clampTo(_ k: IslandCornerShape) -> IslandCornerShape {
        IslandCornerShape(
            rx: max(0.0, min(k.rx, w / 2.0)),
            ry: max(0.0, min(k.ry, h / 2.0)),
            exponent: k.exponent
        )
    }

    let c = clampTo(corner)
    let l = leading == nil ? c : clampTo(leadCorner)
    let r = x + w
    let b = y + h

    path.move(to: CGPoint(x: x + l.rx, y: y))
    path.addLine(to: CGPoint(x: r - c.rx, y: y))
    appendSuperellipseQuadrant(to: path, cx: r - c.rx, cy: y + c.ry, corner: c, fromAngle: -.pi / 2.0)
    path.addLine(to: CGPoint(x: r, y: b - c.ry))
    appendSuperellipseQuadrant(to: path, cx: r - c.rx, cy: b - c.ry, corner: c, fromAngle: 0)
    path.addLine(to: CGPoint(x: x + l.rx, y: b))
    appendSuperellipseQuadrant(to: path, cx: x + l.rx, cy: b - l.ry, corner: l, fromAngle: .pi / 2.0)
    path.addLine(to: CGPoint(x: x, y: y + l.ry))
    appendSuperellipseQuadrant(to: path, cx: x + l.rx, cy: y + l.ry, corner: l, fromAngle: .pi)
    path.closeSubpath()
    return path
}

public func capsuleCGPath(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    smoothing: Double = 0
) -> CGPath {
    let r = min(width, height) / 2.0
    return roundedRectCGPath(
        x: x,
        y: y,
        width: width,
        height: height,
        corner: IslandCornerShape(rx: r, ry: r, exponent: 2.0, smoothing: smoothing)
    )
}

@inline(__always)
private func polarPoint(_ c: IslandCircle, angle: Double, length: Double) -> CGPoint {
    CGPoint(x: c.x + length * cos(angle), y: c.y + length * sin(angle))
}

@inline(__always)
private func polarFromPoint(_ p: CGPoint, angle: Double, length: Double) -> CGPoint {
    CGPoint(x: p.x + length * cos(angle), y: p.y + length * sin(angle))
}

/// Metaball liquid bridge connecting two circular caps, thinning smoothly to `0` at `maxGap`.
public func bridgeCGPath(
    _ a: IslandCircle,
    _ b: IslandCircle,
    options: IslandBridgeOptions
) -> CGPath {
    let path = CGMutablePath()
    let dx = b.x - a.x
    let dy = b.y - a.y
    let d = hypot(dx, dy)
    guard a.r > 0 && b.r > 0 && d > abs(a.r - b.r) else { return path }
    let gap = d - a.r - b.r
    guard gap < options.maxGap else { return path }

    let reach = max(0.0, gap) / options.maxGap
    let v = options.spread * pow(1.0 - reach, options.power)
    guard v > 1e-4 else { return path }

    var u1 = 0.0
    var u2 = 0.0
    if d < a.r + b.r {
        u1 = acos(min(1.0, max(-1.0, (a.r * a.r + d * d - b.r * b.r) / (2.0 * a.r * d))))
        u2 = acos(min(1.0, max(-1.0, (b.r * b.r + d * d - a.r * a.r) / (2.0 * b.r * d))))
    }
    let between = atan2(dy, dx)
    let maxSpread = acos(min(1.0, max(-1.0, (a.r - b.r) / d)))

    let angle1 = between + u1 + (maxSpread - u1) * v
    let angle2 = between - u1 - (maxSpread - u1) * v
    let angle3 = between + .pi - u2 - (.pi - u2 - maxSpread) * v
    let angle4 = between - .pi + u2 + (.pi - u2 - maxSpread) * v

    let p1 = polarPoint(a, angle: angle1, length: a.r)
    let p2 = polarPoint(a, angle: angle2, length: a.r)
    let p3 = polarPoint(b, angle: angle3, length: b.r)
    let p4 = polarPoint(b, angle: angle4, length: b.r)

    let total = a.r + b.r
    let handle = min(v * options.handleSize, hypot(p1.x - p3.x, p1.y - p3.y) / total) * min(1.0, (d * 2.0) / total)
    let h1 = polarFromPoint(p1, angle: angle1 - .pi / 2.0, length: a.r * handle)
    let h2 = polarFromPoint(p2, angle: angle2 + .pi / 2.0, length: a.r * handle)
    let h3 = polarFromPoint(p3, angle: angle3 + .pi / 2.0, length: b.r * handle)
    let h4 = polarFromPoint(p4, angle: angle4 - .pi / 2.0, length: b.r * handle)

    path.move(to: p1)
    path.addCurve(to: p3, control1: h1, control2: h3)
    path.addLine(to: p4)
    path.addCurve(to: p2, control1: h4, control2: h2)
    path.closeSubpath()
    return path
}

/// Pointed separation nub left on a circular cap immediately after a metaball neck snaps.
public func cuspCGPath(
    _ c: IslandCircle,
    toward: CGPoint,
    length: Double,
    base: Double = 0.5
) -> CGPath {
    let path = CGMutablePath()
    let d = hypot(toward.x - c.x, toward.y - c.y)
    guard c.r > 0 && d >= 1e-6 && length >= 0.01 else { return path }

    let aim = atan2(toward.y - c.y, toward.x - c.x)
    let tip = polarPoint(c, angle: aim, length: c.r + length)

    path.move(to: polarPoint(c, angle: aim + base, length: c.r))
    path.addQuadCurve(to: tip, control: polarPoint(c, angle: aim + base * 0.25, length: c.r))
    path.addQuadCurve(to: polarPoint(c, angle: aim - base, length: c.r), control: polarPoint(c, angle: aim - base * 0.25, length: c.r))
    path.addLine(to: CGPoint(x: c.x, y: c.y))
    path.closeSubpath()
    return path
}

public func chamferCGPath(
    x: Double,
    y: Double,
    width: Double,
    height: Double,
    leg: Double
) -> CGPath {
    let w = max(0.0, width)
    let h = max(0.0, height)
    let path = CGMutablePath()
    guard w > 0 && h > 0 else { return path }

    let c = max(0.0, min(leg, w / 2.0, h / 2.0))
    let r = x + w
    let b = y + h
    path.move(to: CGPoint(x: x + c, y: y))
    path.addLine(to: CGPoint(x: r - c, y: y))
    path.addLine(to: CGPoint(x: r, y: y + c))
    path.addLine(to: CGPoint(x: r, y: b - c))
    path.addLine(to: CGPoint(x: r - c, y: b))
    path.addLine(to: CGPoint(x: x + c, y: b))
    path.addLine(to: CGPoint(x: x, y: b - c))
    path.addLine(to: CGPoint(x: x, y: y + c))
    path.closeSubpath()
    return path
}
