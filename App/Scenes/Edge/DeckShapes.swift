import SwiftUI

/// Rounded on the outward-facing side only, so a tab reads as docked to the screen edge
/// (`UnevenRoundedRectangle` is macOS 13+; the floor is 12, so the corners are drawn by hand).
struct EdgeTabShape: Shape {
    let onRight: Bool
    var radius: CGFloat = 11

    func path(in r: CGRect) -> Path {
        let rad = min(radius, r.width / 2, r.height / 2)
        var p = Path()
        if onRight {
            // Round the left corners.
            p.move(to: CGPoint(x: r.minX + rad, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + rad))
            p.addArc(center: CGPoint(x: r.minX + rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // Round the right corners.
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - rad, y: r.minY))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.minY + rad), radius: rad,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
            p.addArc(center: CGPoint(x: r.maxX - rad, y: r.maxY - rad), radius: rad,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }
}

/// The dashed rule the deck hangs from, right at the screen edge.
struct EdgeLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        return p
    }
}

struct DeckPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension NotePaletteEntry {
    private static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
              blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
    var paperColor: Color { Self.color(paper) }
    var dashColor: Color { Self.color(dash) }
    var inkColor: Color { Self.color(ink) }
}
