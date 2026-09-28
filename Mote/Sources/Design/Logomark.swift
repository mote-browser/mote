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

    /// How far each of the four corners of the outline (the start, then
    /// each curve's end) sits from the middle, as a share of where the pebble
    /// has it, its two handles moving with it so the outline stays smooth;
    /// and how long those handles are, as a share of theirs. Empty for the
    /// pebble itself; others make it flow into another shape.
    var bends: [CGFloat] = []
    var handles: [CGFloat] = []

    /// Fitted and centred in `rect`, keeping its proportions.
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / Self.canvas.width, rect.height / Self.canvas.height)
        let origin = CGPoint(x: rect.midX - Self.canvas.width * scale / 2, y: rect.midY - Self.canvas.height * scale / 2)
        let middle = CGPoint(x: Self.canvas.width / 2, y: Self.canvas.height / 2)
        // Corner `k` is the start (and last end) for 0, else curve k-1's end.
        let corners = [Self.start] + Self.curves.dropLast().map(\.2)
        func bent(_ point: CGPoint, near corner: Int) -> CGPoint {
            let k = corner % 4
            let bend = bends.indices.contains(k) ? bends[k] : 1
            let handle = handles.indices.contains(k) ? handles[k] : 1
            let anchor = corners[k]
            let moved = CGPoint(x: anchor.x + (point.x - anchor.x) * handle, y: anchor.y + (point.y - anchor.y) * handle)
            let bentPoint = CGPoint(x: middle.x + (moved.x - middle.x) * bend, y: middle.y + (moved.y - middle.y) * bend)
            return CGPoint(x: origin.x + bentPoint.x * scale, y: origin.y + bentPoint.y * scale)
        }
        var path = Path()
        path.move(to: bent(Self.start, near: 0))
        for (index, (one, two, end)) in Self.curves.enumerated() {
            // A curve's first handle belongs to the corner it leaves, its second to the one it reaches.
            path.addCurve(to: bent(end, near: index + 1), control1: bent(one, near: index), control2: bent(two, near: index + 1))
        }
        path.closeSubpath()
        return path
    }

    /// The pebble's outline as a line from its lowest point all the way round
    /// back to it, clockwise on screen when `forward`, else the other way.
    static func round(in rect: CGRect, forward: Bool) -> Path {
        let scale = min(rect.width / canvas.width, rect.height / canvas.height)
        let origin = CGPoint(x: rect.midX - canvas.width * scale / 2, y: rect.midY - canvas.height * scale / 2)
        func place(_ point: CGPoint) -> CGPoint { CGPoint(x: origin.x + point.x * scale, y: origin.y + point.y * scale) }
        // The curves as (from, control, control, to), starting with the one that
        // leaves the lowest corner, the second curve's end.
        var segments: [(CGPoint, CGPoint, CGPoint, CGPoint)] = []
        var from = start
        for (one, two, end) in curves {
            segments.append((from, one, two, end))
            from = end
        }
        segments = Array(segments[2...] + segments[..<2])
        if !forward { segments = segments.reversed().map { ($0.3, $0.2, $0.1, $0.0) } }
        var path = Path()
        path.move(to: place(segments[0].0))
        for (_, one, two, end) in segments { path.addCurve(to: place(end), control1: place(one), control2: place(two)) }
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
