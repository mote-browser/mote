import SwiftUI

/// Mote's pebble, from Mote.icon, as a shape.
nonisolated struct Logomark: Shape {
    /// The pebble's bounds on the icon's 1024-point canvas.
    static let canvas = CGSize(width: 564, height: 550)

    /// pebble.svg's outline, moved to the canvas's origin: a start point and
    /// four cubic curves (control, control, end).
    private static let start = CGPoint(x: 234, y: 32)
    private static let curves: [(CGPoint, CGPoint, CGPoint)] = [
        (CGPoint(x: 404, y: 0), CGPoint(x: 564, y: 100), CGPoint(x: 560, y: 270)),
        (CGPoint(x: 556, y: 420), CGPoint(x: 454, y: 530), CGPoint(x: 284, y: 540)),
        (CGPoint(x: 124, y: 550), CGPoint(x: 0, y: 470), CGPoint(x: 2, y: 318)),
        (CGPoint(x: 4, y: 170), CGPoint(x: 94, y: 58), CGPoint(x: 234, y: 32)),
    ]

    /// Fitted and centred in `rect`, keeping its proportions.
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.canvas.width, rect.height / Self.canvas.height)
        let origin = CGPoint(x: rect.midX - Self.canvas.width * scale / 2, y: rect.midY - Self.canvas.height * scale / 2)
        func place(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }
        var path = Path()
        path.move(to: place(Self.start))
        for (one, two, end) in Self.curves { path.addCurve(to: place(end), control1: place(one), control2: place(two)) }
        path.closeSubpath()
        return path
    }
}

/// A sideways shake for input that goes nowhere: three swings that die away.
struct Shake: GeometryEffect {
    /// 0 to 1 through the shake.
    var travel: CGFloat

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(travel * .pi * 6) * 7 * (1 - travel), y: 0))
    }
}
