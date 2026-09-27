import AppKit
import Combine
import SwiftUI

/// The first-launch arrival: the screen dims, a speck grows into the pebble,
/// "Mote" writes itself in, and the pebble stretches into the browser window,
/// which fades in underneath. A click or Escape skips straight to the window.
///
/// Runs in its own borderless window over the whole screen so the effect can
/// reach past the browser window. The browser window is kept transparent until
/// the pebble has taken its shape.
@available(macOS 15, *)
@MainActor
final class Arrival: ObservableObject {
    enum Stage: Int, Comparable {
        case dark, dimmed, speck, pebble, named, quiet, opening, gone
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    }

    @Published private(set) var stage = Stage.dark
    /// The browser window's frame in the overlay's SwiftUI coordinates.
    @Published private(set) var target = CGRect.zero

    private static var playing: Arrival?

    private let browser: NSWindow
    private var overlay: NSWindow?
    private var script: Task<Void, Never>?
    private var done: () -> Void = {}
    private var keys: Any?

    /// Plays the arrival over `window`, then calls `done`. Returns false (and
    /// does nothing) when Reduce Motion is on or an arrival is already playing.
    @discardableResult
    static func play(over window: NSWindow, done: @escaping () -> Void) -> Bool {
        guard playing == nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            let screen = window.screen ?? NSScreen.main
        else { return false }
        let arrival = Arrival(browser: window)
        playing = arrival
        arrival.done = done
        arrival.start(on: screen)
        return true
    }

    private init(browser: NSWindow) { self.browser = browser }

    private func start(on screen: NSScreen) {
        browser.alphaValue = 0

        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Above the menu bar and Dock, like a curtain.
        window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.alphaValue = 0
        let host = NSHostingView(rootView: ArrivalView(arrival: self, skip: { [weak self] in self?.skip() }))
        host.frame = blur.bounds
        host.autoresizingMask = [.width, .height]
        blur.addSubview(host)
        window.contentView = blur
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        overlay = window

        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 || event.keyCode == 36 || event.keyCode == 49 else { return event }
            self?.skip()
            return nil
        }

        measure()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.8
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            blur.animator().alphaValue = 1
        }
        script = Task { await run() }
    }

    /// The timeline. Each step waits on the clock, so cancelling it (a skip)
    /// stops the sequence wherever it is.
    private func run() async {
        let steps: [(Double, Stage, Animation)] = [
            (0.05, .dimmed, .easeOut(duration: 0.8)),
            (0.35, .speck, .spring(response: 0.3, dampingFraction: 0.7)),
            (0.25, .pebble, .spring(response: 0.75, dampingFraction: 0.62)),
            (0.55, .named, .easeOut(duration: 1.1)),
            (1.9, .quiet, .easeIn(duration: 0.3)),
        ]
        for (wait, stage, animation) in steps {
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
            withAnimation(animation) { self.stage = stage }
        }
        try? await Task.sleep(for: .seconds(0.2))
        if Task.isCancelled { return }
        open()
    }

    private func skip() {
        guard stage < .opening else { return }
        script?.cancel()
        withAnimation(.easeIn(duration: 0.2)) { stage = .quiet }
        open()
    }

    /// Stretches the pebble into the window, then swaps the real window in.
    private func open() {
        measure()
        withAnimation(.spring(response: 0.7, dampingFraction: 0.86)) { stage = .opening }
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.4
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.browser.animator().alphaValue = 1
                self.overlay?.animator().alphaValue = 0
            }
            finish()
        }
    }

    private func finish() {
        stage = .gone
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        overlay?.orderOut(nil)
        overlay = nil
        browser.alphaValue = 1
        NSApp.activate()
        browser.makeKeyAndOrderFront(nil)
        Arrival.playing = nil
        done()
    }

    /// Converts the browser window's frame (bottom-left screen coordinates)
    /// into the overlay's top-left SwiftUI space.
    private func measure() {
        guard let overlay else { return }
        let screen = overlay.frame
        let frame = browser.frame
        target = CGRect(
            x: frame.minX - screen.minX,
            y: screen.maxY - frame.maxY,
            width: frame.width,
            height: frame.height)
    }
}

// MARK: - The view

@available(macOS 15, *)
private struct ArrivalView: View {
    @ObservedObject var arrival: Arrival
    let skip: () -> Void

    /// macOS 26 windows round their corners by about this much.
    private let windowRadius: CGFloat = 16

    var body: some View {
        let stage = arrival.stage
        let target = arrival.target
        let center = CGPoint(x: target.midX, y: target.midY)
        let pebble: CGFloat =
            switch stage {
            case .dark, .dimmed: 0
            case .speck: 10
            default: PebbleFill.size.width
            }
        let opening = stage >= .opening

        ZStack {
            // The dim, over the blurred desktop.
            Color.black.opacity(stage >= .dimmed ? (opening ? 0.1 : 0.4) : 0)

            // The pebble, which becomes the window. The lit pebble is scaled on
            // the same spring as the outline, so it always covers it; the
            // window's own colour arrives last.
            ZStack {
                // Drawn larger than the pebble so the spring's overshoot never
                // runs past its edge.
                PebbleFill()
                    .frame(width: PebbleFill.size.width * 1.5, height: PebbleFill.size.height * 1.5)
                    .scaleEffect(
                        x: opening ? target.width / PebbleFill.size.width : 1,
                        y: opening ? target.height / PebbleFill.size.height : 1
                    )
                    .position(center)
                Palette.frame.opacity(opening ? 1 : 0)
                    .animation(.easeIn(duration: 0.3).delay(0.3), value: opening)
            }
            .clipShape(
                PebbleMorph(
                    center: center, size: pebble, target: target.size, radius: windowRadius,
                    progress: opening ? 1 : 0)
            )
            .shadow(color: PebbleFill.glow.opacity(opening ? 0 : 0.55), radius: 60)

            // The name, under the pebble.
            VStack(spacing: 10) {
                Text("Mote")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white)
                    .textRenderer(GlyphReveal(progress: stage >= .named ? 1 : 0))
                Text("A browser with nothing in the way")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .opacity(stage >= .named ? 1 : 0)
                    .blur(radius: stage >= .named ? 0 : 6)
                    .animation(.easeOut(duration: 0.9).delay(0.6), value: stage >= .named)
            }
            .opacity(stage >= .quiet ? 0 : 1)
            .blur(radius: stage >= .quiet ? 10 : 0)
            .scaleEffect(stage >= .quiet ? 0.96 : 1)
            .position(x: center.x, y: center.y + 150)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: skip)
    }
}

// MARK: - Pieces

/// The pebble's warm fill: the icon's colours as a slowly drifting mesh, with
/// a highlight in the upper left like the glass on the app icon.
@available(macOS 15, *)
struct PebbleFill: View {
    /// The pebble's size once grown.
    static let size = CGSize(width: 150, height: 150 * Logomark.canvas.height / Logomark.canvas.width)

    static let glow = Color(red: 0.96, green: 0.78, blue: 0.66)

    private static let colors: [Color] = [
        Color(red: 1.00, green: 0.95, blue: 0.90), Color(red: 0.98, green: 0.90, blue: 0.82),
        Color(red: 0.96, green: 0.78, blue: 0.66),
        Color(red: 0.96, green: 0.86, blue: 0.75), Color(red: 0.95, green: 0.85, blue: 0.77),
        Color(red: 0.93, green: 0.72, blue: 0.62),
        Color(red: 0.96, green: 0.86, blue: 0.75), Color(red: 0.91, green: 0.65, blue: 0.56),
        Color(red: 0.90, green: 0.62, blue: 0.52),
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let drift = SIMD2<Float>(Float(sin(t * 0.9)) * 0.14, Float(cos(t * 0.7)) * 0.12)
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.5], SIMD2(0.5, 0.5) + drift, [1, 0.5],
                    [0, 1], [0.5, 1], [1, 1],
                ],
                colors: Self.colors)
        }
        // Light from the upper left and a little shade underneath, like the
        // glass on the app icon.
        .overlay { shading }
    }

    private var shading: some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(0.6), .clear], center: UnitPoint(x: 0.37, y: 0.31),
                startRadius: 0, endRadius: 120)
            RadialGradient(
                colors: [.clear, Color(red: 0.55, green: 0.3, blue: 0.22).opacity(0.3)], center: UnitPoint(x: 0.43, y: 0.4),
                startRadius: 40, endRadius: 170)
        }
    }
}

/// A shape that is the pebble (`size` points wide, centred on `center`) at
/// progress 0 and a rounded rectangle the size of `target` at progress 1.
///
/// Both outlines are sampled along the same rays from the centre and the
/// points blended, so the pebble visibly stretches into the window instead
/// of cross-fading.
nonisolated struct PebbleMorph: Shape {
    var center: CGPoint
    var size: CGFloat
    var target: CGSize
    var radius: CGFloat
    var progress: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size, progress) }
        set {
            size = newValue.first
            progress = newValue.second
        }
    }

    private static let rays = 720

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard size > 0 || progress > 0 else { return path }
        let scale = size / Logomark.canvas.width
        for i in 0..<Self.rays {
            let angle = Double(i) / Double(Self.rays) * 2 * .pi
            let a = PebbleMorph.pebble[i]
            let b = PebbleMorph.box(angle: angle, size: target, radius: radius)
            let x = center.x + a.x * scale * (1 - progress) + b.x * progress
            let y = center.y + a.y * scale * (1 - progress) + b.y * progress
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    /// Where a ray from the centre at `angle` leaves a rounded rectangle.
    private static func box(angle: Double, size: CGSize, radius: CGFloat) -> CGPoint {
        let dx = cos(angle)
        let dy = sin(angle)
        let a = size.width / 2
        let b = size.height / 2
        let s = min(abs(dx) > 1e-9 ? a / abs(dx) : .infinity, abs(dy) > 1e-9 ? b / abs(dy) : .infinity)
        let p = CGPoint(x: s * dx, y: s * dy)
        let r = min(radius, a, b)
        guard abs(p.x) > a - r, abs(p.y) > b - r else { return p }
        // In a corner: meet the corner's circle instead.
        let q = CGPoint(x: (dx < 0 ? -1 : 1) * (a - r), y: (dy < 0 ? -1 : 1) * (b - r))
        let dot = dx * q.x + dy * q.y
        let t = dot + sqrt(max(0, dot * dot - (q.x * q.x + q.y * q.y - r * r)))
        return CGPoint(x: t * dx, y: t * dy)
    }

    /// The pebble outline in canvas points around its centre, one point per ray.
    private static let pebble: [CGPoint] = {
        let outline = Logomark().path(in: CGRect(origin: .zero, size: Logomark.canvas))
        let mid = CGPoint(x: Logomark.canvas.width / 2, y: Logomark.canvas.height / 2)
        // Dense points along the outline, as (angle, point) pairs.
        var samples: [(Double, CGPoint)] = []
        var last = CGPoint.zero
        outline.forEach { element in
            switch element {
            case .move(let p): last = p
            case .line(let p): last = p
            case .curve(let p, let c1, let c2):
                for k in 1...200 {
                    let t = CGFloat(k) / 200
                    let u = 1 - t
                    let x = u * u * u * last.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x
                    let y = u * u * u * last.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y
                    let point = CGPoint(x: x - mid.x, y: y - mid.y)
                    var angle = atan2(Double(point.y), Double(point.x))
                    if angle < 0 { angle += 2 * .pi }
                    samples.append((angle, point))
                }
                last = p
            default: break
            }
        }
        samples.sort { $0.0 < $1.0 }
        // For each ray, the nearest sample by angle (samples are dense enough).
        var out: [CGPoint] = []
        var j = 0
        for i in 0..<rays {
            let angle = Double(i) / Double(rays) * 2 * .pi
            while j + 1 < samples.count, samples[j + 1].0 <= angle { j += 1 }
            out.append(samples[j].1)
        }
        return out
    }()
}

/// Reveals text one glyph at a time: each rises, sharpens and turns upright.
@available(macOS 15, *)
nonisolated struct GlyphReveal: TextRenderer, Animatable {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let glyphs = layout.flatMap { $0 }.flatMap { $0 }
        let spread = 0.45
        for (i, glyph) in glyphs.enumerated() {
            let start = glyphs.count > 1 ? Double(i) / Double(glyphs.count - 1) * spread : 0
            let local = min(max((progress - start) / (1 - spread), 0), 1)
            let eased = 1 - pow(1 - local, 3)
            let bounds = glyph.typographicBounds.rect
            var copy = context
            copy.opacity = eased
            copy.addFilter(.blur(radius: (1 - eased) * 10))
            copy.translateBy(x: bounds.midX, y: bounds.midY + (1 - eased) * 18)
            copy.rotate(by: .degrees((1 - eased) * -14))
            copy.translateBy(x: -bounds.midX, y: -bounds.midY)
            copy.draw(glyph)
        }
    }
}
