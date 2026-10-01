import MoteCore
import WebKit

/// Progress of a swipe, for the indicator at the page's edge.
typealias Pull = SwipeTracker.Pull

/// The web view in a tab. On top of WKWebView it adds Mote's own swipe
/// navigation, mouse back and forward buttons, smart zoom, a fade-in instead
/// of a white first frame, and its own items in the context menu.
final class PageView: WKWebView {
    /// The engine's name for "Search with …", and what to do with the words.
    var searchName: (() -> String?)?
    var onSearch: ((String) -> Void)?
    /// "Ask about This": what to do with the selected text, as a chat about
    /// the page the selection sits on.
    var onAsk: ((String) -> Void)?
    /// A swipe's progress, or nil when there is none to show.
    var onPull: ((Pull?) -> Void)?
    /// Any click or scroll, so a wake snapshot never gets in the way.
    var onTouch: (() -> Void)?

    // MARK: - Context menu

    private var selection: String?
    private var webSearch: (target: AnyObject?, action: Selector?)

    /// Reads the selected text: a focused field's selection first, then the
    /// page and its same-origin frames. Cross-origin frames and password
    /// fields read as empty, and WebKit's own search runs instead.
    /// See Scripts/src/selected-text.ts.
    static let selected = InjectedScript.call("selected-text")

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if let search = menu.items.first(where: { $0.identifier?.rawValue == "WKMenuItemIdentifierSearchWeb" }) {
            // Read the selection once, for both items: the search, and the
            // chat about the page the selection sits on. WebKit offers its own
            // search only when text is selected, so the two live together.
            selection = nil
            callAsyncJavaScript(Self.selected, arguments: [:], in: nil, in: .defaultClient) { [weak self] result in
                self?.selection = (try? result.get()) as? String ?? ""
            }
            if let name = searchName?() {
                webSearch = (search.target, search.action)
                search.title = "Search with \(name)"
                search.target = self
                search.action = #selector(searchSelection(_:))
            }
            if let index = menu.items.firstIndex(of: search) {
                menu.insertItem(ask(), at: index + 1)
            }
        }
        // Extensions' items go last.
        guard #available(macOS 15.4, *), let tab = Extensions.shared.browser?.tab(for: self) else { return }
        let items = Extensions.shared.menuItems(for: tab)
        guard !items.isEmpty else { return }
        menu.addItem(.separator())
        items.forEach(menu.addItem)
    }

    /// The chat's way in from the page: the words under the pointer are quoted
    /// in the composer, and the page they sit on is shared with it.
    private func ask() -> NSMenuItem {
        let item = NSMenuItem(title: "Ask about This", action: #selector(askAboutSelection(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)
        return item
    }

    @objc private func askAboutSelection(_ item: NSMenuItem) {
        defer { selection = nil }
        let words = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !words.isEmpty else { return }
        onAsk?(words)
    }

    @objc private func searchSelection(_ item: NSMenuItem) {
        defer { selection = nil }
        let words = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !words.isEmpty else {
            if let action = webSearch.action { NSApp.sendAction(action, to: webSearch.target, from: item) }
            return
        }
        onSearch?(words)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        onTouch?()
        super.mouseDown(with: event)
    }

    /// Side buttons, numbered as most mouse drivers do: 3 back, 4 forward.
    override func otherMouseDown(with event: NSEvent) {
        switch event.buttonNumber {
        case 3 where canGoBack: goBack()
        case 4 where canGoForward: goForward()
        default: super.otherMouseDown(with: event)
        }
    }

    /// Logi Options+ sends its back and forward buttons as swipes, as Safari
    /// reads them: positive for back.
    override func swipe(with event: NSEvent) {
        if event.deltaX > 0, canGoBack {
            goBack()
        } else if event.deltaX < 0, canGoForward {
            goForward()
        } else {
            super.swipe(with: event)
        }
    }

    // MARK: - Keys the page didn't use

    /// The last key given to the page. WebKit sends a key the page didn't
    /// handle back up the responder chain, where nothing takes it and macOS
    /// beeps; editors that insert text themselves (Draft.js) get reported as
    /// unhandled, so the second delivery is dropped, as Safari does.
    private var handed: NSEvent?
    /// Keys dropped that way, for the bench.
    static var quieted = 0

    override func keyDown(with event: NSEvent) {
        if let handed, Self.same(handed, event) {
            self.handed = nil
            Self.quieted += 1
            return
        }
        handed = event
        super.keyDown(with: event)
    }

    /// Whether two events are one key press. WebKit sends back the original
    /// event, and no two presses share a timestamp.
    static func same(_ one: NSEvent, _ other: NSEvent) -> Bool {
        one === other || (one.timestamp == other.timestamp && one.keyCode == other.keyCode && one.type == other.type)
    }

    // MARK: - First frame

    /// A web view that has never drawn is opaque white, which flashes in a
    /// dark window. New views stay transparent until their first layout with
    /// content, then fade in.
    private(set) var unpainted = false

    /// `_WKRenderingProgressEventFirstVisuallyNonEmptyLayout`.
    static let firstFrame: UInt = 1 << 1

    /// Asks WebKit (privately) for the first-paint event; without it the view
    /// just shows at once.
    func holdForFirstFrame() {
        let observe = NSSelectorFromString("_setObservedRenderingProgressEvents:")
        guard responds(to: observe) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        unsafeBitCast(method(for: observe), to: Setter.self)(self, observe, Self.firstFrame)
        unpainted = true
        alphaValue = 0
    }

    func showFirstFrame() {
        guard unpainted else { return }
        unpainted = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
    }

    // MARK: - Smart zoom

    // Pinching is left to WebKit, which scales on the GPU during the gesture
    // and lays out once at the end; only the two-finger double-tap is Mote's.

    /// Returns, as JSON, the scale fitting the block under the pointer to the
    /// width and the scroll that keeps the tapped point in place, or the way
    /// back when already zoomed. See Scripts/src/smart-zoom.ts.
    static let smart = InjectedScript.call("smart-zoom", arguments: ["x", "y", "scale", "width"])

    private struct SmartZoom: Decodable {
        var scale: CGFloat
        var x: CGFloat
        var y: CGFloat
    }

    /// Fits the block under the pointer to the width, like Safari; again to go back.
    override func smartMagnify(with event: NSEvent) {
        guard allowsMagnification else { return super.smartMagnify(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let tap: [String: Any] = ["x": point.x, "y": point.y, "scale": magnification, "width": bounds.width]
        callAsyncJavaScript(Self.smart, arguments: tap, in: nil, in: .page) { [weak self] result in
            guard let self, let text = (try? result.get()) as? String,
                let zoom = try? JSONDecoder().decode(SmartZoom.self, from: Data(text.utf8))
            else { return }
            setMagnification(zoom.scale, centeredAt: point)
            callAsyncJavaScript("window.scrollTo(x, y)", arguments: ["x": zoom.x, "y": zoom.y], in: nil, in: .page)
        }
    }

    // MARK: - Swipe navigation

    private var swipe = SwipeTracker()
    /// A navigation's indicator is still leaving; counts gestures so a late
    /// hide doesn't touch a newer one.
    private var leaving = false
    private var gestures = 0

    override func scrollWheel(with event: NSEvent) {
        onTouch?()
        // The page sees every event; the swipe only watches.
        super.scrollWheel(with: event)
        // Live trackpad gestures only: momentum and mouse wheels have no phases.
        guard event.momentumPhase == [] else { return }
        switch event.phase {
        case .mayBegin, .began:
            swipe.begin()
            gestures += 1
            if leaving {
                leaving = false
                onPull?(nil)
            }
        case .changed:
            apply(
                swipe.move(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: Date()) { [unowned self] back in
                    back ? canGoBack : canGoForward
                })
        case .ended:
            apply(swipe.end(at: Date()))
        case .cancelled:
            apply(swipe.cancel())
        default:
            break
        }
    }

    /// The page's answer: whether the swipe would scroll something on it.
    func swipeAnswered(free: Bool) {
        apply(swipe.pageAnswered(free: free, at: Date()))
    }

    private func apply(_ effects: [SwipeTracker.Effect]) {
        for effect in effects {
            switch effect {
            case .show(let pull):
                onPull?(pull)
            case .tick(let armed):
                NSHapticFeedbackManager.defaultPerformer.perform(armed ? .levelChange : .alignment, performanceTime: .now)
            case .navigate(let back):
                if back { goBack() } else { goForward() }
                leaving = true
                gestures += 1
                let mine = gestures
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.32))
                    guard let self, gestures == mine else { return }
                    leaving = false
                    onPull?(nil)
                }
            }
        }
    }
}

extension WKWebView {
    /// Loads a URL. A file needs its folder granted, or WebKit shows nothing.
    func open(_ url: URL) {
        if url.isFileURL {
            loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            load(URLRequest(url: url))
        }
    }

    /// Runs JavaScript in Mote's world (see Web.world); `then` gets the
    /// result, or nil on error or no value.
    func evaluateInAppWorld(_ js: String, then: ((Any?) -> Void)? = nil) {
        evaluateJavaScript(js, in: nil, in: Web.world) { then?(try? $0.get()) }
    }

    /// Runs `body` as an async function in Mote's world with each argument as
    /// a variable. WebKit serializes the values, so no Swift string becomes code.
    func callInAppWorld(_ body: String, arguments: [String: Any], then: ((Any?) -> Void)? = nil) {
        callAsyncJavaScript(body, arguments: arguments, in: nil, in: Web.world) { then?(try? $0.get()) }
    }
}
