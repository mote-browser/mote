import AppKit
import MoteCore
import SwiftUI
import WebKit

// Bench commands that draw the browser to files: the whole window, parts of
// it drawn off screen, and frames while something animates.

extension Bench {
    var pictureCommands: [String: Command] {
        [
            "pages": Self.pages, "picture": Self.picture, "frames": Self.frames, "film": Self.film, "strip": Self.strip, "fold": Self.fold,
            "site": Self.site, "column": Self.column,
        ]
    }

    /// Lets a hidden test run's pages paint (for `picture`), without bringing
    /// it forward: every window on a screen is ordered out first, and if one
    /// would show anyway it hides again and says so.
    private static func pages(_ call: BenchCall) {
        guard Storage.testing, let window = AppDelegate.window else { return call.fail("pages only works on a --test run") }
        guard call.request.flag("on") else {
            NSApp.hide(nil)
            window.orderFront(nil)
            return call.answer(["pages": false])
        }
        let room = BenchRoom.made
        let onScreen = { (window: NSWindow) in NSScreen.screens.contains { $0.frame.intersects(window.frame) } }
        window.orderOut(nil)
        NSApp.windows.filter { $0 !== room && onScreen($0) }.forEach { $0.orderOut(nil) }
        NSApp.unhideWithoutActivation()
        let showing = NSApp.windows.filter { $0.isVisible && onScreen($0) }
        guard showing.isEmpty else {
            NSApp.hide(nil)
            return call.fail("a window would have shown: \(showing.map { "\(type(of: $0))" })")
        }
        call.answer(["pages": true])
    }

    /// The whole window as a PNG, pages drawn in from WebKit's snapshots.
    private static func picture(_ call: BenchCall) {
        guard call.testRun() else { return }
        guard let window = AppDelegate.window, let frame = window.contentView?.superview, let path = call.request.string("path"),
            !path.isEmpty
        else {
            return call.fail("picture needs a path")
        }
        let facts: [String: Any] = [
            "saved": path, "points": [Int(frame.bounds.width), Int(frame.bounds.height)], "lights": BenchCall.lights(of: window),
        ]
        // With pages painting (`pages on`), the tab in front, drawn in the room at its size.
        if !NSApp.isHidden, call.request.bool("page") != false, let tab = call.browser.active, let address = tab.address,
            let live = tab.built,
            live.window === window
        {
            return BenchPictures.windowWithPage(
                frame, page: live, address: address, fresh: call.request.flag("fresh"), settle: call.request.double("settle") ?? 3,
                path: path
            ) { out in call.answer(out.merging(facts) { mine, _ in mine }) }
        }
        BenchPictures.windowWithSnapshots(frame) { bitmap in
            guard let bitmap else { return call.fail("nothing drawn") }
            do {
                try BenchPictures.save(bitmap, to: path)
                call.answer(facts.merging(["pixels": [bitmap.pixelsWide, bitmap.pixelsHigh]]) { a, _ in a })
            } catch {
                call.fail(error.localizedDescription)
            }
        }
    }

    /// Runs an animation (fold, peek, unpeek) and notes when the display
    /// drew, to find the frames the main thread missed.
    private static func frames(_ call: BenchCall) {
        guard call.testRun() else { return }
        guard let window = AppDelegate.window, let view = window.contentView else { return call.fail("no window") }
        FrameWatch(view: view, seconds: call.request.double("seconds") ?? 0.7).start { stamps in
            let refresh = (window.screen?.maximumFramesPerSecond).map { 1000 / Double($0) } ?? 1000 / 60
            call.answer(BenchWire.frames(stamps, refreshMs: refresh))
        }
        animate(call.request.string("action") ?? "fold", in: call.browser)
    }

    private static func animate(_ action: String, in browser: Browser) {
        switch action {
        case "peek": browser.peek(true)
        case "unpeek": browser.peek(false)
        case "fold": browser.toggleFold()
        case "scroll": browser.active?.built.map { BenchInput.flick($0) }
        default: break
        }
    }

    /// The window's top left corner drawn again and again while something
    /// animates, with where the traffic lights are: cacheDisplay doesn't see
    /// Core Animation's transforms. Only the corner, as the whole window
    /// takes longer than a frame to draw, and without pages, which take a
    /// third of a second each; files are written at the end.
    private static func film(_ call: BenchCall) {
        guard call.testRun() else { return }
        guard let window = AppDelegate.window, let frame = window.contentView?.superview, let path = call.request.string("path"),
            !path.isEmpty
        else {
            return call.fail("film needs something to do and a path")
        }
        let count = min(60, max(1, call.request.int("frames") ?? 14))
        let every = min(0.5, max(0.01, call.request.double("every") ?? 0.03))
        let corner = NSRect(x: 0, y: frame.bounds.height - 460, width: min(380, frame.bounds.width), height: 460)
        let pages = BenchPictures.pages(in: frame).filter { !$0.isHidden }
        pages.forEach { $0.isHidden = true }
        var shots: [[String: Any]] = []
        var pictures: [NSBitmapImageRep] = []
        let started = CACurrentMediaTime()
        func take(_ index: Int) {
            guard index < count else {
                pages.forEach { $0.isHidden = false }
                for (index, picture) in pictures.enumerated() {
                    let file = path + String(format: "-%02d.png", index)
                    if (try? BenchPictures.save(picture, to: file)) != nil { shots[index]["file"] = file }
                }
                return call.answer(["frames": shots])
            }
            var shot: [String: Any] = ["t": Int((CACurrentMediaTime() - started) * 1000)]
            if let picture = frame.bitmapImageRepForCachingDisplay(in: corner) {
                frame.cacheDisplay(in: corner, to: picture)
                pictures.append(picture)
            }
            if let bar = SidebarFold.titlebar {
                let now = bar.layer?.presentation()
                let moved = now?.value(forKeyPath: "transform.translation.x") as? CGFloat ?? 0
                let lifted = now?.value(forKeyPath: "transform.translation.y") as? CGFloat ?? 0
                shot["lights"] = [
                    "hidden": bar.isHidden, "x": Int(moved.rounded()), "y": Int(lifted.rounded()),
                    "flipped": bar.superview?.isFlipped ?? false,
                ]
            }
            shots.append(shot)
            DispatchQueue.main.asyncAfter(deadline: .now() + every) { take(index + 1) }
        }
        take(0)
        animate(call.request.string("action") ?? "", in: call.browser)
    }

    private static func needPath(_ call: BenchCall) -> String? {
        guard let path = call.request.string("path") else {
            call.fail("\(call.verb) needs a path")
            return nil
        }
        return path
    }

    /// The tab strip, drawn off screen at a width.
    private static func strip(_ call: BenchCall) {
        guard let path = needPath(call) else { return }
        let width = call.request.double("width") ?? 1100
        let strip = TabBar(browser: call.browser).frame(width: width, height: ChromeLayout.strip).background(Palette.frame)
        BenchPictures.render(strip, size: NSSize(width: width, height: ChromeLayout.strip), wait: 0.3, to: path, call.answer)
    }

    /// The folded sidebar peeking out, drawn over red so anything see-through
    /// shows: `picture` draws pages over it.
    private static func fold(_ call: BenchCall) {
        guard call.testRun(), let path = needPath(call) else { return }
        let browser = call.browser
        guard browser.folded, browser.peeking else { return call.fail("fold and peek first: ui folded on, ui peek on") }
        let size = NSSize(width: call.request.double("width") ?? 1100, height: browser.prefs.sidebar ? 500 : 120)
        let peeking = ZStack(alignment: .topLeading) {
            Color.red
            SidebarFold(browser: browser, prefs: browser.prefs)
        }
        BenchPictures.render(peeking.frame(width: size.width, height: size.height), size: size, wait: 0.6, to: path, call.answer)
    }

    /// The tab in front's site card, or its security detail, on an opaque
    /// ground: off screen there's no material behind it.
    private static func site(_ call: BenchCall) {
        guard let path = needPath(call) else { return }
        guard let tab = call.browser.active, !tab.isBlank else { return call.fail("no page on screen") }
        let card = SiteCard(browser: call.browser, tab: tab, deeper: call.request.flag("security")) {}.fixedSize().background(
            Palette.ground)
        BenchPictures.render(card, size: nil, wait: 0.6, to: path, call.answer)
    }

    /// The sidebar at its width.
    private static func column(_ call: BenchCall) {
        guard let path = needPath(call) else { return }
        let size = NSSize(width: call.browser.prefs.sideWidth, height: call.request.double("height") ?? 600)
        let column = Sidebar(browser: call.browser, prefs: call.browser.prefs).frame(width: size.width, height: size.height)
        BenchPictures.render(column, size: size, wait: 0.4, to: path, call.answer)
    }
}

/// Drawing for the bench.
@MainActor
enum BenchPictures {
    static func save(_ bitmap: NSBitmapImageRep, to path: String) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: URL(fileURLWithPath: path))
    }

    /// A view drawn in a window of its own, off screen, `wait` seconds after
    /// it's laid out; nil `size` is its own fitting size.
    static func bitmap(of view: some View, size: NSSize?, wait: Double, then: @escaping @MainActor (NSBitmapImageRep?) -> Void) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size ?? host.fittingSize)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.effectiveAppearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if size == nil { host.frame = NSRect(origin: .zero, size: host.fittingSize) }
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            bitmap.map { host.cacheDisplay(in: host.bounds, to: $0) }
            then(bitmap)
            window.contentView = nil
        }
    }

    /// As `bitmap`, saved, and answered with where.
    static func render(_ view: some View, size: NSSize?, wait: Double, to path: String, _ answer: @escaping ([String: Any]) -> Void) {
        bitmap(of: view, size: size, wait: wait) { bitmap in
            guard let bitmap else { return answer(["error": "nothing drawn"]) }
            do {
                try save(bitmap, to: path)
                answer(["saved": path])
            } catch {
                answer(["error": error.localizedDescription])
            }
        }
    }

    static func pages(in view: NSView) -> [WKWebView] {
        (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(pages)
    }

    /// The window drawn with each showing page covered for a moment by its
    /// snapshot: cacheDisplay can't draw pages itself.
    static func windowWithSnapshots(_ frame: NSView, then: @escaping @MainActor (NSBitmapImageRep?) -> Void) {
        let shown = pages(in: frame).filter { !$0.isHidden && $0.alphaValue > 0 && !$0.frame.isEmpty }
        var taken: [(WKWebView, NSImage)] = []
        var left = shown.count
        func draw() {
            let covers = taken.map { web, image in
                let cover = NSImageView(frame: web.frame)
                cover.image = image
                cover.imageScaling = .scaleAxesIndependently
                cover.autoresizingMask = web.autoresizingMask
                web.superview?.addSubview(cover, positioned: .above, relativeTo: web)
                web.isHidden = true
                return cover
            }
            defer {
                covers.forEach { $0.removeFromSuperview() }
                taken.forEach { $0.0.isHidden = false }
            }
            frame.layoutSubtreeIfNeeded()
            let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds)
            bitmap.map { frame.cacheDisplay(in: frame.bounds, to: $0) }
            then(bitmap)
        }
        guard left > 0 else { return draw() }
        for web in shown {
            web.takeSnapshot(with: nil) { image, _ in
                MainActor.assumeIsolated {
                    if let image { taken.append((web, image)) }
                    left -= 1
                    if left == 0 { draw() }
                }
            }
        }
    }

    /// The window's chrome with the tab in front's page drawn in, painted in
    /// the room at its size: the live page lent and given back, or with
    /// `fresh` the address loaded in a new one.
    static func windowWithPage(
        _ frame: NSView, page live: WKWebView, address: URL, fresh: Bool, settle: Double, path: String,
        _ answer: @escaping ([String: Any]) -> Void
    ) {
        let rect = live.convert(live.bounds, to: nil)
        guard let chrome = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return answer(["error": "nothing drawn"]) }
        frame.cacheDisplay(in: frame.bounds, to: chrome)
        let home = live.superview, homeFrame = live.frame
        let page = fresh ? WKWebView(frame: NSRect(origin: .zero, size: rect.size), configuration: Web.configuration()) : live
        if !fresh {
            live.removeFromSuperview()
            live.frame = NSRect(origin: .zero, size: rect.size)
            live.alphaValue = 1
        }
        func giveBack() {
            page.removeFromSuperview()
            guard !fresh else { return }
            live.frame = homeFrame
            home?.addSubview(live)
        }
        // WebKit doesn't paint a window it thinks is covered.
        page.unpublished("_setWindowOcclusionDetectionEnabled:", false)
        BenchRoom.made.contentView?.addSubview(page)
        if fresh { page.load(URLRequest(url: address)) }
        func whenLoaded(_ tries: Int) {
            guard !page.isLoading || tries == 0 else {
                return DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { whenLoaded(tries - 1) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
                page.takeSnapshot(with: nil) { image, _ in
                    MainActor.assumeIsolated {
                        giveBack()
                        guard let drawn = compose(chrome, size: frame.bounds.size, page: image, at: rect) else {
                            return answer(["error": "nothing drawn"])
                        }
                        do {
                            try save(drawn, to: path)
                            answer([
                                "pixels": [drawn.pixelsWide, drawn.pixelsHigh], "page": BenchCall.topLeft(rect, in: frame.bounds.height),
                            ])
                        } catch {
                            answer(["error": error.localizedDescription])
                        }
                    }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { whenLoaded(80) }
    }

    private static func compose(_ chrome: NSBitmapImageRep, size: NSSize, page: NSImage?, at rect: NSRect) -> NSBitmapImageRep? {
        guard
            let drawn = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: chrome.pixelsWide, pixelsHigh: chrome.pixelsHigh, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        drawn.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: drawn)
        chrome.draw(in: NSRect(origin: .zero, size: size))
        page?.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        return drawn
    }
}

/// The display's frame times for a while (the bench's `frames`).
@MainActor
private final class FrameWatch: NSObject {
    private static var running: [FrameWatch] = []
    private var link: CADisplayLink?
    private var stamps: [CFTimeInterval] = []
    private let seconds: Double
    private var done: (([CFTimeInterval]) -> Void)?

    init(view: NSView, seconds: Double) {
        self.seconds = seconds
        super.init()
        link = view.displayLink(target: self, selector: #selector(tick))
    }

    func start(_ done: @escaping ([CFTimeInterval]) -> Void) {
        self.done = done
        Self.running.append(self)
        link?.add(to: .main, forMode: .common)
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
        guard let first = stamps.first, link.timestamp - first >= seconds else { return }
        link.invalidate()
        done?(stamps)
        done = nil
        Self.running.removeAll { $0 === self }
    }
}
