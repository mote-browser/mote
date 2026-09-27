import AppKit
import MoteCore

/// Over the floating video: close, back to the tab, play or pause and jump,
/// shown while the pointer is over it; and moving and resizing the window by
/// dragging, two fingers, or pinching.
final class FloatControls: NSView {
    var onClose: (() -> Void)?
    var onReturn: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSkip: ((Double) -> Void)?

    var playing = true {
        didSet { playPause.image = Self.symbol(playing ? "pause.fill" : "play.fill", size: 17) }
    }

    /// How far the video is, from 0 to 1, along the bottom edge.
    var progress: Double = 0 {
        didSet { bar.through = progress }
    }

    private let close = NSButton()
    private let back = NSButton()
    private let playPause = NSButton()
    private let rewind = NSButton()
    private let ahead = NSButton()
    private let shade = CAGradientLayer()
    private let bar = ProgressBar()
    private var shown = false

    private var buttons: [NSButton] { [close, back, rewind, playPause, ahead] }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Darker at the top and bottom, so white buttons read on a bright video.
        shade.colors = [0.45, 0, 0, 0.5].map { NSColor(white: 0, alpha: $0).cgColor }
        shade.locations = [0, 0.28, 0.66, 1]
        shade.opacity = 0
        layer?.addSublayer(shade)
        setUp(close, "xmark", size: 11, radius: 15, action: #selector(closePressed))
        setUp(back, "arrow.up.forward", size: 12, radius: 15, action: #selector(backPressed))
        setUp(rewind, "gobackward.15", size: 15, radius: 19, action: #selector(rewindPressed))
        setUp(playPause, "pause.fill", size: 17, radius: 25, action: #selector(playPausePressed))
        setUp(ahead, "goforward.15", size: 15, radius: 19, action: #selector(aheadPressed))
        bar.alphaValue = 0
        addSubview(bar)
        buttons.forEach { $0.alphaValue = 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setUp(_ button: NSButton, _ symbol: String, size: CGFloat, radius: CGFloat, action: Selector) {
        button.image = Self.symbol(symbol, size: size)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.55).cgColor
        button.layer?.cornerRadius = radius
        addSubview(button)
    }

    private static func symbol(_ name: String, size: CGFloat) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .medium).applying(.init(paletteColors: [.white])))
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = bounds
        CATransaction.commit()
        close.frame = NSRect(x: 14, y: bounds.height - 44, width: 30, height: 30)
        back.frame = NSRect(x: bounds.width - 44, y: bounds.height - 44, width: 30, height: 30)
        let middle = bounds.midY - 25
        playPause.frame = NSRect(x: bounds.midX - 25, y: middle, width: 50, height: 50)
        rewind.frame = NSRect(x: bounds.midX - 79, y: middle + 6, width: 38, height: 38)
        ahead.frame = NSRect(x: bounds.midX + 41, y: middle + 6, width: 38, height: 38)
        bar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 3)
    }

    // MARK: - Showing on hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { show(true) }
    override func mouseExited(with event: NSEvent) { show(false) }

    private func show(_ on: Bool) {
        shown = on
        let alpha: CGFloat = on ? 1 : 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            buttons.forEach { $0.animator().alphaValue = alpha }
            bar.animator().alphaValue = alpha
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        shade.opacity = Float(alpha)
        CATransaction.commit()
    }

    /// Everything over the page comes here (the page would take drags before
    /// the window could), the buttons while they're showing.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return shown ? buttons.first { $0.frame.contains(local) } ?? self : self
    }

    // MARK: - Moving and resizing

    /// The bottom-right corner resizes.
    private let grip: CGFloat = 22
    private var pressedAt = NSPoint.zero
    private var startFrame = NSRect.zero
    private var resizing = false

    override func resetCursorRects() {
        addCursorRect(NSRect(x: bounds.maxX - grip, y: bounds.minY, width: grip, height: grip), cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        stopGliding()
        pressedAt = NSEvent.mouseLocation
        startFrame = window.frame
        let point = convert(event.locationInWindow, from: nil)
        resizing = point.x > bounds.maxX - grip && point.y < bounds.minY + grip
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - pressedAt.x
        if resizing {
            resize(toWidth: startFrame.width + dx, from: startFrame)
        } else {
            window.setFrameOrigin(NSPoint(x: startFrame.minX + dx, y: startFrame.minY + now.y - pressedAt.y))
        }
    }

    private var flick = FloatGeometry.Flick()
    /// A mouse wheel has no gesture phases: one flick every 0.4 s.
    private var lastWheelFlick = Date.distantPast

    /// Two fingers move the window, the pointer carried along so it doesn't
    /// slide out and lose the gesture; or, with flicks on, throw it to a corner.
    override func scrollWheel(with event: NSEvent) {
        guard let window, event.momentumPhase == [] else { return }
        if FloatingVideo.flicks { return flickScroll(event) }
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        guard dx != 0 || dy != 0 else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX + dx, y: window.frame.minY - dy))
        // AppKit counts up from the bottom; the cursor counts down from the main screen's top.
        guard let main = NSScreen.screens.first else { return }
        let pointer = NSEvent.mouseLocation
        CGWarpMouseCursorPosition(CGPoint(x: pointer.x + dx, y: main.frame.height - (pointer.y - dy)))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private func flickScroll(_ event: NSEvent) {
        // The fingers' direction, whatever natural scrolling says.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        let step = CGVector(dx: sign * event.scrollingDeltaX, dy: -sign * event.scrollingDeltaY)
        guard event.phase != [] else {
            guard step != .zero, Date().timeIntervalSince(lastWheelFlick) > 0.4 else { return }
            lastWheelFlick = Date()
            return throwWindow(step)
        }
        if event.phase.contains(.began) { flick.begin() }
        if let way = flick.move(by: step, lifted: event.phase.contains(.ended) || event.phase.contains(.cancelled)) { throwWindow(way) }
    }

    private func throwWindow(_ way: CGVector) {
        guard let window, let area = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        let target = FloatGeometry.corner(for: window.frame, in: area, toward: way)
        if target != window.frame.origin { glide(to: target) }
    }

    /// Gliding on a display link, at the display's own rate; AppKit's window
    /// animations stop at 60 fps.
    private var glider: CADisplayLink?
    private var glideFrom = NSPoint.zero
    private var glideTo = NSPoint.zero
    private var glideStart: CFTimeInterval = 0

    private func glide(to target: NSPoint) {
        guard let window else { return }
        glideFrom = window.frame.origin
        glideTo = target
        glideStart = CACurrentMediaTime()
        if glider == nil {
            let link = displayLink(target: self, selector: #selector(glideStep))
            link.add(to: .main, forMode: .common)
            glider = link
        }
    }

    @objc private func glideStep(_ link: CADisplayLink) {
        guard let window else { return stopGliding() }
        let along = FloatGeometry.glide(at: CACurrentMediaTime() - glideStart)
        window.setFrameOrigin(
            NSPoint(x: glideFrom.x + (glideTo.x - glideFrom.x) * along, y: glideFrom.y + (glideTo.y - glideFrom.y) * along))
        if along >= 1 { stopGliding() }
    }

    private func stopGliding() {
        glider?.invalidate()
        glider = nil
    }

    /// Pinching resizes around the pointer, in 2% steps: every event would
    /// stutter through window, page and video layout.
    private var pinch: CGFloat = 0

    override func magnify(with event: NSEvent) {
        guard let window else { return }
        if event.phase == .began { pinch = 0 }
        pinch += event.magnification
        guard abs(pinch) > 0.02 else { return }
        let by = pinch
        pinch = 0
        resize(toWidth: window.frame.width * (1 + by), from: window.frame, around: NSEvent.mouseLocation)
    }

    private func resize(toWidth width: CGFloat, from frame: NSRect, around anchor: NSPoint? = nil) {
        guard let window else { return }
        let resized = FloatGeometry.resized(
            frame, toWidth: width, narrowest: window.minSize.width, screenWidth: NSScreen.main?.visibleFrame.width ?? 1600, around: anchor)
        // Without a redraw each step, which stutters.
        window.setFrame(resized, display: false)
    }

    @objc private func closePressed() { onClose?() }
    @objc private func backPressed() { onReturn?() }
    @objc private func rewindPressed() { onSkip?(-15) }
    @objc private func aheadPressed() { onSkip?(15) }
    @objc private func playPausePressed() {
        playing.toggle()
        onPlayPause?()
    }

    /// How far the video is, along the bottom edge.
    private final class ProgressBar: NSView {
        var through: Double = 0 {
            didSet { needsDisplay = true }
        }

        override func draw(_ dirty: NSRect) {
            NSColor(white: 1, alpha: 0.22).setFill()
            bounds.fill()
            NSColor(white: 1, alpha: 0.85).setFill()
            NSRect(x: 0, y: 0, width: bounds.width * through, height: bounds.height).fill()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
