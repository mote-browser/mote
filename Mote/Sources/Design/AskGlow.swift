import AppKit
import SwiftUI

// The composer's look while it asks the assistant: a halo of the logo's
// colours running round its border, and the logo's lights drifting. Both are
// Core Animation, so they run in the render server and cost the main thread
// nothing while idle. With Reduce Motion they stand still.

/// The logo's lights, for the halo and the logo.
enum Glow {
    static let cream = NSColor(srgbRed: 1, green: 0xF3 / 255, blue: 0xE6 / 255, alpha: 1)
    static let peach = NSColor(srgbRed: 0xF6 / 255, green: 0xC6 / 255, blue: 0xA8 / 255, alpha: 1)
    static let clay = NSColor(srgbRed: 0xE7 / 255, green: 0xA5 / 255, blue: 0x8E / 255, alpha: 1)
    static let sand = NSColor(srgbRed: 0xF4 / 255, green: 0xDC / 255, blue: 0xC0 / 255, alpha: 1)
    static let base = NSColor(srgbRed: 0xF2 / 255, green: 0xD9 / 255, blue: 0xC4 / 255, alpha: 1)

    static var stillness: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Asking begins: the logo gathers its light and lets a drop of it fall,
    /// which lands on the composer this long after, lighting its border.
    static var impact: CFTimeInterval { stillness ? 0 : 0.8 }

    /// The halo's colours round the circle, a cream highlight in the clay, and
    /// back to where they began so there is no seam.
    static let sweep: [CGColor] = [
        clay, peach, cream, peach, sand, clay, peach.blended(withFraction: 0.4, of: clay)!, sand, clay,
    ].map(\.cgColor)
    static let sweepStops: [NSNumber] = [0, 0.12, 0.2, 0.28, 0.45, 0.6, 0.72, 0.86, 1]

    /// Stops a layer's animations where they are, or lets them carry on from there.
    static func run(_ layer: CALayer, _ running: Bool) {
        if running, layer.speed == 0 {
            let paused = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if !running, layer.speed != 0 {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = now
        }
    }
}

/// A halo running round a rounded rectangle: the border drawn in the logo's
/// colours, one after another all the way round with a brighter cream light
/// among them, turning slowly; under it a soft glow of the same colours.
/// Drawn `spill` points beyond its frame, for the glow.
struct AskHalo: NSViewRepresentable {
    let on: Bool
    var radius: CGFloat = 18
    static let spill: CGFloat = 24

    func makeNSView(context: Context) -> HaloView { HaloView(radius: radius) }
    func updateNSView(_ view: HaloView, context: Context) { view.show(on) }

    final class HaloView: NSView {
        /// Seconds for the colours to go once round.
        private static let lap: CFTimeInterval = 7

        private let radius: CGFloat
        private let glow = CALayer()
        private let glowMask = CALayer()
        private let line = CALayer()
        private let lineMask = CAShapeLayer()
        private let turning = CALayer()
        /// Draws the halo on round the border, both ways from where it starts.
        private let reveal = CALayer()
        private let reveals = [CAShapeLayer(), CAShapeLayer()]
        private let glowSweep = CAGradientLayer()
        private let lineSweep = CAGradientLayer()
        private var drawn: CGSize = .zero
        private var shown = false

        init(radius: CGFloat) {
            self.radius = radius
            super.init(frame: .zero)
            wantsLayer = true
            let root = layer!
            root.opacity = 0
            for (sweep, holder, mask) in [(glowSweep, glow, glowMask as CALayer), (lineSweep, line, lineMask as CALayer)] {
                sweep.type = .conic
                sweep.startPoint = CGPoint(x: 0.5, y: 0.5)
                sweep.endPoint = CGPoint(x: 0.5, y: 0)
                sweep.colors = Glow.sweep
                sweep.locations = Glow.sweepStops
                holder.mask = mask
                holder.addSublayer(sweep)
                turning.addSublayer(holder)
            }
            root.addSublayer(turning)
            for half in reveals {
                half.fillColor = nil
                half.strokeColor = NSColor.white.cgColor
                half.lineWidth = AskHalo.spill * 2 + 8
                half.lineCap = .butt
                // A little over half, so the two meet without a seam.
                half.strokeEnd = 0.52
                reveal.addSublayer(half)
            }
            turning.mask = reveal
            lineMask.fillColor = nil
            lineMask.strokeColor = NSColor.white.cgColor
            lineMask.lineWidth = 1
            glow.opacity = 0.5
            turning.speed = 0
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard bounds.size != drawn, bounds.width > 0 else { return }
            drawn = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let edge = bounds.insetBy(dx: AskHalo.spill, dy: AskHalo.spill)
            let path = CGPath(roundedRect: edge, cornerWidth: radius, cornerHeight: radius, transform: nil)
            turning.frame = bounds
            reveal.frame = bounds
            for (half, forward) in zip(reveals, [true, false]) {
                half.frame = bounds
                half.path = Self.border(edge, radius: radius, forward: forward)
            }
            // A square round the middle, big enough to cover the corners as it turns.
            let side = hypot(bounds.width, bounds.height)
            let square = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            for holder in [glow, line] { holder.frame = bounds }
            for sweep in [glowSweep, lineSweep] {
                sweep.frame = square
                sweep.removeAnimation(forKey: "turn")
                guard !Glow.stillness else { continue }
                let turn = CABasicAnimation(keyPath: "transform.rotation.z")
                turn.fromValue = 0
                turn.toValue = -Double.pi * 2
                turn.duration = Self.lap
                turn.repeatCount = .infinity
                sweep.add(turn, forKey: "turn")
            }
            lineMask.frame = bounds
            lineMask.path = path
            glowMask.frame = bounds
            glowMask.contents = Self.softRing(size: bounds.size, edge: edge, radius: radius, scale: window?.backingScaleFactor ?? 2)
            CATransaction.commit()
        }

        /// The glow's mask: the border drawn wide and blurred, once per size.
        private static func softRing(size: CGSize, edge: CGRect, radius: CGFloat, scale: CGFloat) -> CGImage? {
            let width = Int(size.width * scale), height = Int(size.height * scale)
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
            else { return nil }
            context.scaleBy(x: scale, y: scale)
            context.setShadow(offset: .zero, blur: 12, color: NSColor.white.cgColor)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1.5)
            context.addPath(CGPath(roundedRect: edge, cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
            return context.makeImage()
        }

        /// The border as one line from the middle of its top edge, where the
        /// logo's drop lands, all the way round back to it, `forward` to the
        /// right or else to the left. Half of each makes the whole border,
        /// meeting at the bottom.
        private static func border(_ rect: CGRect, radius r: CGFloat, forward: Bool) -> CGPath {
            // The layer counts up from the bottom: the top is maxY.
            let start = CGPoint(x: rect.midX, y: rect.maxY)
            let corners = [
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.minX, y: rect.maxY),
            ]
            let order = forward ? corners : corners.reversed()
            let path = CGMutablePath()
            path.move(to: start)
            for (index, corner) in order.enumerated() {
                path.addArc(tangent1End: corner, tangent2End: index + 1 < order.count ? order[index + 1] : start, radius: r)
            }
            path.addLine(to: start)
            return path
        }

        func show(_ on: Bool) {
            guard on != shown, let root = layer else { return }
            shown = on
            if on { Glow.run(turning, true) }
            CATransaction.begin()
            // Still once out of sight.
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, !self.shown else { return }
                Glow.run(self.turning, false)
            }
            // Coming on, it waits for the logo's drop to land.
            let landing = on ? root.convertTime(CACurrentMediaTime(), from: nil) + Glow.impact : 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = on ? 0 : root.presentation()?.opacity ?? root.opacity
            fade.toValue = on ? 1 : 0
            fade.duration = on ? 0.2 : 0.35
            fade.beginTime = landing
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            root.opacity = on ? 1 : 0
            root.add(fade, forKey: "fade")
            if on, !Glow.stillness {
                // From where the drop lands both ways round, meeting at the
                // bottom: quick off the impact, settling slowly.
                let curve = CAMediaTimingFunction(controlPoints: 0.25, 0.6, 0.2, 1)
                for half in reveals {
                    let draw = CABasicAnimation(keyPath: "strokeEnd")
                    draw.fromValue = 0
                    draw.toValue = 0.52
                    draw.duration = 1.1
                    draw.beginTime = half.convertTime(CACurrentMediaTime(), from: nil) + Glow.impact
                    draw.fillMode = .backwards
                    draw.timingFunction = curve
                    half.add(draw, forKey: "draw")
                }
            }
            CATransaction.commit()
        }
    }
}

/// A soft glow of the logo's colours behind a rounded rectangle, breathing
/// slowly while `on`. Drawn `spill` points beyond its frame.
struct AskAura: NSViewRepresentable {
    let on: Bool
    var radius: CGFloat = 18
    static let spill: CGFloat = 40

    func makeNSView(context: Context) -> AuraView { AuraView(radius: radius) }
    func updateNSView(_ view: AuraView, context: Context) { view.show(on) }

    final class AuraView: NSView {
        private let radius: CGFloat
        private let glow = CALayer()
        private var drawn: CGSize = .zero
        private var shown = false

        init(radius: CGFloat) {
            self.radius = radius
            super.init(frame: .zero)
            wantsLayer = true
            layer!.opacity = 0
            glow.shadowColor = Glow.clay.cgColor
            glow.shadowOpacity = 0.3
            glow.shadowRadius = 26
            glow.shadowOffset = .zero
            layer!.addSublayer(glow)
            glow.speed = 0
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard bounds.size != drawn, bounds.width > 0 else { return }
            drawn = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.frame = bounds
            let edge = bounds.insetBy(dx: AskAura.spill, dy: AskAura.spill)
            glow.shadowPath = CGPath(roundedRect: edge, cornerWidth: radius, cornerHeight: radius, transform: nil)
            glow.removeAnimation(forKey: "breath")
            if !Glow.stillness {
                let breath = CABasicAnimation(keyPath: "shadowOpacity")
                breath.fromValue = 0.18
                breath.toValue = 0.42
                breath.duration = 2.8
                breath.autoreverses = true
                breath.repeatCount = .infinity
                breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(breath, forKey: "breath")
            }
            CATransaction.commit()
        }

        func show(_ on: Bool) {
            guard on != shown, let root = layer else { return }
            shown = on
            if on { Glow.run(glow, true) }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = on ? 0 : root.presentation()?.opacity ?? root.opacity
            fade.toValue = on ? 1 : 0
            fade.duration = on ? 1.4 : 0.35
            // Coming on, it glows up as the logo's drop lands.
            fade.beginTime = on ? root.convertTime(CACurrentMediaTime(), from: nil) + Glow.impact : 0
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, !self.shown else { return }
                Glow.run(self.glow, false)
            }
            root.opacity = on ? 1 : 0
            root.add(fade, forKey: "fade")
            CATransaction.commit()
        }
    }
}

/// The pebble from the app icon: the same outline, filled with the same four
/// soft lights. While `alive` it flows gently from shape to shape like a drop
/// and its lights swirl inside it, starting slowly; let go, it settles back
/// into the pebble. Drawn `spill` points beyond its frame, for its shadow.
struct MoteLogo: NSViewRepresentable {
    var alive = false
    static let spill: CGFloat = 20

    func makeNSView(context: Context) -> LogoView { LogoView() }
    func updateNSView(_ view: LogoView, context: Context) { view.live(alive) }

    final class LogoView: NSView {
        /// Centres as fractions of the pebble's box, radii as fractions of its
        /// width: pebble.svg's gradients.
        private static let lights: [(colour: NSColor, centre: CGPoint, radius: CGFloat)] = [
            (Glow.cream, CGPoint(x: 124.0 / 564, y: 100.0 / 550), 330.0 / 564),
            (Glow.peach, CGPoint(x: 474.0 / 564, y: 160.0 / 550), 310.0 / 564),
            (Glow.clay, CGPoint(x: 384.0 / 564, y: 490.0 / 550), 330.0 / 564),
            (Glow.sand, CGPoint(x: 84.0 / 564, y: 450.0 / 550), 290.0 / 564),
        ]
        /// Shapes the outline flows through: how far out each corner goes,
        /// and how full the curves between them are (see `Logomark.bends`).
        private static let shapes: [(bends: [CGFloat], handles: [CGFloat])] = [
            ([1.05, 0.95, 1.04, 0.96], [1.12, 0.9, 1.08, 0.95]),
            ([0.96, 1.05, 0.95, 1.04], [0.92, 1.1, 0.95, 1.12]),
            ([1.03, 0.97, 1.06, 0.95], [1.05, 1.15, 0.9, 1.05]),
            ([0.97, 1.04, 0.98, 1.05], [1.15, 0.95, 1.1, 0.9]),
        ]
        /// Seconds for the outline to go through its shapes, and for the lights to go round.
        private static let flow: CFTimeInterval = 7
        private static let swirl: CFTimeInterval = 6
        /// Seconds to come to life, and to settle again.
        private static let waking: CFTimeInterval = 1.8
        private static let settling: CFTimeInterval = 0.8

        private let body = CALayer()
        private let pebble = CALayer()
        private let outline = CAShapeLayer()
        private let drifting = CALayer()
        /// Light filling the pebble as it gathers itself to let its drop fall.
        private let flash = CAGradientLayer()
        /// The composer's halo, first round the pebble: it closes in on the
        /// pebble's lowest point, where the drop falls from.
        private let ring = CALayer()
        /// Holds the ring's mask, inside `ring`, which glows: a mask would clip the glow.
        private let ringLine = CALayer()
        private let ringSweep = CAGradientLayer()
        private let ringMask = CALayer()
        private let ringHalves = [CAShapeLayer(), CAShapeLayer()]
        private var spots: [CAGradientLayer] = []
        private var rest = CGMutablePath() as CGPath
        private var drawn: CGSize = .zero
        private var alive = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            body.shadowColor = NSColor(srgbRed: 0.55, green: 0.33, blue: 0.22, alpha: 1).cgColor
            body.shadowOpacity = 0.18
            body.shadowRadius = 10
            body.shadowOffset = CGSize(width: 0, height: -5)
            pebble.backgroundColor = Glow.base.cgColor
            pebble.mask = outline
            pebble.addSublayer(drifting)
            flash.type = .radial
            flash.startPoint = CGPoint(x: 0.5, y: 0.5)
            flash.endPoint = CGPoint(x: 1, y: 1)
            flash.colors = [Glow.cream.cgColor, Glow.peach.cgColor, Glow.clay.cgColor]
            flash.locations = [0, 0.55, 1]
            flash.opacity = 0
            pebble.addSublayer(flash)
            ringSweep.type = .conic
            ringSweep.startPoint = CGPoint(x: 0.5, y: 0.5)
            ringSweep.endPoint = CGPoint(x: 0.5, y: 0)
            ringSweep.colors = Glow.sweep
            ringSweep.locations = Glow.sweepStops
            for half in ringHalves {
                half.fillColor = nil
                half.strokeColor = NSColor.white.cgColor
                half.lineWidth = 2.5
                half.lineCap = .round
                half.strokeEnd = 0
                ringMask.addSublayer(half)
            }
            ringLine.addSublayer(ringSweep)
            ringLine.mask = ringMask
            ring.addSublayer(ringLine)
            ring.opacity = 0
            ring.shadowColor = Glow.clay.cgColor
            // A glow behind it.
            ring.shadowOpacity = 1
            ring.shadowRadius = 9
            ring.shadowOffset = .zero
            layer!.addSublayer(ring)
            body.addSublayer(pebble)
            layer!.addSublayer(body)
            for light in Self.lights {
                let spot = CAGradientLayer()
                spot.type = .radial
                spot.startPoint = CGPoint(x: 0.5, y: 0.5)
                spot.endPoint = CGPoint(x: 1, y: 1)
                spot.colors = [
                    light.colour.cgColor, light.colour.withAlphaComponent(0.75).cgColor, light.colour.withAlphaComponent(0).cgColor,
                ]
                spot.locations = [0, 0.45, 1]
                drifting.addSublayer(spot)
                spots.append(spot)
            }
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// The outline, bent by `bends` and `handles`, in the layer's coordinates (which
        /// count up from the bottom, where the outline counts down).
        private func outline(in size: CGSize, bends: [CGFloat] = [], handles: [CGFloat] = []) -> CGPath {
            var flip = CGAffineTransform(translationX: 0, y: size.height).scaledBy(x: 1, y: -1)
            return Logomark(bends: bends, handles: handles).path(in: CGRect(origin: .zero, size: size)).cgPath.copy(using: &flip)!
        }

        override func layout() {
            super.layout()
            guard bounds.size != drawn, bounds.width > 0 else { return }
            drawn = bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let frame = bounds.insetBy(dx: MoteLogo.spill, dy: MoteLogo.spill)
            rest = outline(in: frame.size)
            let box = rest.boundingBox
            body.frame = frame
            // No shadow path: the shadow follows the outline as it flows.
            pebble.frame = body.bounds
            outline.frame = body.bounds
            outline.path = rest
            drifting.frame = body.bounds
            flash.frame = body.bounds.insetBy(dx: -body.bounds.width * 0.2, dy: -body.bounds.height * 0.2)
            ring.frame = bounds
            ringLine.frame = bounds
            ringMask.frame = bounds
            let side = hypot(bounds.width, bounds.height)
            ringSweep.frame = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            // On the pebble's edge, just outside it, in the layer's upward coordinates.
            var up = CGAffineTransform(translationX: 0, y: bounds.height).scaledBy(x: 1, y: -1)
            for (half, forward) in zip(ringHalves, [true, false]) {
                half.frame = bounds
                half.path = Logomark.round(in: frame.insetBy(dx: -1.25, dy: -1.25), forward: forward).cgPath.copy(using: &up)
            }
            for (spot, light) in zip(spots, Self.lights) {
                let side = light.radius * box.width * 2
                // pebble.svg counts down from the top too.
                spot.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                spot.position = CGPoint(x: box.minX + light.centre.x * box.width, y: box.maxY - light.centre.y * box.height)
            }
            CATransaction.commit()
            if alive { wake() }
        }

        func live(_ alive: Bool) {
            guard alive != self.alive else { return }
            self.alive = alive
            guard !Glow.stillness, drawn != .zero else { return }
            if alive { gather() }
            alive ? wake() : settle()
        }

        /// Seconds from asking to the ring round the pebble having closed on its
        /// lowest point, where the drop leaves.
        static let release: CFTimeInterval = 0.5

        /// Gathers itself to let its drop fall: it fills with light as the
        /// halo comes round it; the halo closes in both ways on its lowest
        /// point, and as it does it crouches and springs, letting the drop go.
        private func gather() {
            let now = layer!.convertTime(CACurrentMediaTime(), from: nil)
            let light = CAKeyframeAnimation(keyPath: "opacity")
            light.values = [0, 0.85, 0.85, 0]
            light.keyTimes = [0, 0.25, 0.55, 1]
            light.duration = 0.85
            flash.add(light, forKey: "light")
            // The halo appears round the pebble, turns a little, then closes in on the bottom.
            let shown = CAKeyframeAnimation(keyPath: "opacity")
            shown.values = [0, 1, 1]
            shown.keyTimes = [0, 0.25, 1]
            shown.duration = Self.release
            ring.add(shown, forKey: "shown")
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            turn.toValue = -Double.pi * 0.4
            turn.duration = Self.release
            ringSweep.add(turn, forKey: "turn")
            for half in ringHalves {
                let close = CAKeyframeAnimation(keyPath: "strokeEnd")
                // Over half each: the pebble isn't symmetric, so its top isn't halfway round.
                close.values = [0.62, 0.62, 0]
                close.keyTimes = [0, 0.4, 1]
                close.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(controlPoints: 0.5, 0, 0.75, 0.6)]
                close.duration = Self.release
                half.add(close, forKey: "close")
            }
            // It crouches as the halo closes, and springs as the drop leaves.
            for (path, values) in [("transform.scale.y", [0, -0.07, 0.06, 0]), ("transform.scale.x", [0, 0.05, -0.04, 0])]
                as [(String, [Double])]
            {
                let crouch = CAKeyframeAnimation(keyPath: path)
                crouch.values = values
                crouch.keyTimes = [0, 0.5, 0.75, 1]
                crouch.beginTime = now + Self.release - 0.22
                crouch.duration = 0.45
                crouch.isAdditive = true
                crouch.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
                body.add(crouch, forKey: "crouch." + path)
            }
            let still = body.shadowColor
            for (path, values) in [
                ("shadowColor", [still as Any, Glow.clay.cgColor, still as Any]), ("shadowOpacity", [0.18, 0.6, 0.18]),
                ("shadowRadius", [10.0, 16.0, 10.0]),
            ] as [(String, [Any])] {
                let flare = CAKeyframeAnimation(keyPath: path)
                flare.values = values
                flare.keyTimes = [0, 0.3, 1]
                flare.duration = 0.9
                body.add(flare, forKey: "flare." + path)
            }
        }

        /// Every movement: the layer, its key, what it moves, and where it rests.
        private var movements: [(layer: CALayer, key: String, path: String, rest: Any)] {
            [
                (outline, "flow", "path", rest), (drifting, "swirl", "transform.rotation.z", 0.0),
                (body, "squash", "transform.scale.x", 1.0), (body, "stretch", "transform.scale.y", 1.0),
                (body, "sway", "transform.rotation.z", 0.0),
            ]
        }

        /// Starts from the pebble at rest: every loop begins where it rests and
        /// eases out of it, and the lights speed up to their pace.
        private func wake() {
            guard !Glow.stillness else { return }
            let size = body.bounds.size
            let ease = CAMediaTimingFunction(name: .easeInEaseOut)
            // The outline flows from shape to shape like a drop.
            let flow = CAKeyframeAnimation(keyPath: "path")
            flow.values = [rest] + Self.shapes.map { outline(in: size, bends: $0.bends, handles: $0.handles) } + [rest]
            flow.duration = Self.flow
            flow.repeatCount = .infinity
            flow.timingFunctions = Array(repeating: ease, count: Self.shapes.count + 1)
            outline.add(flow, forKey: "flow")
            // It squashes and stretches like jelly, a beat apart from its outline.
            for (key, path, values) in [
                ("squash", "transform.scale.x", [1, 1.025, 0.98, 1.015, 1]), ("stretch", "transform.scale.y", [1, 0.98, 1.025, 0.985, 1]),
                ("sway", "transform.rotation.z", [0, 0.05, 0, -0.05, 0]),
            ] as [(String, String, [Double])] {
                let move = CAKeyframeAnimation(keyPath: path)
                move.values = values
                move.duration = key == "sway" ? 7 : 3.5
                move.repeatCount = .infinity
                move.timingFunctions = Array(repeating: ease, count: values.count - 1)
                body.add(move, forKey: key)
            }
            // The lights begin to turn slowly, then go round at an even pace.
            let start = (drifting.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double) ?? 0
            let speeding = CABasicAnimation(keyPath: "transform.rotation.z")
            speeding.fromValue = start
            speeding.toValue = start - .pi / 2
            speeding.duration = Self.waking
            speeding.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let round = CABasicAnimation(keyPath: "transform.rotation.z")
            round.fromValue = start - .pi / 2
            round.toValue = start - .pi / 2 - .pi * 2
            round.duration = Self.swirl
            round.repeatCount = .infinity
            then(drifting, speeding, round, key: "swirl")
        }

        /// `first`, held at its end, then `after` from then on, under `key`.
        private func then(_ layer: CALayer, _ first: CABasicAnimation, _ after: CAAnimation, key: String) {
            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            first.fillMode = .forwards
            first.isRemovedOnCompletion = false
            after.beginTime = now + first.duration
            layer.add(first, forKey: key + ".start")
            layer.add(after, forKey: key)
        }

        /// Goes back to the pebble from wherever it has got to.
        private func settle() {
            for half in ringHalves { half.removeAnimation(forKey: "close") }
            ring.removeAnimation(forKey: "shown")
            for movement in movements {
                let layer = movement.layer
                let from = layer.presentation()?.value(forKeyPath: movement.path)
                layer.removeAnimation(forKey: movement.key)
                layer.removeAnimation(forKey: movement.key + ".start")
                let back = CABasicAnimation(keyPath: movement.path)
                back.fromValue = from
                back.toValue = movement.rest
                back.duration = Self.settling
                back.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(back, forKey: movement.key)
            }
        }
    }
}
