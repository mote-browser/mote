import AppKit
import MoteCore
import WebKit

// Extension popups, in Mote's own popover: in WebKit's, some extensions'
// messages never reach their worker, and a web view made from the extension's
// configuration doesn't have that trouble. Sized as Chrome sizes them
// (PopupSizing).

@available(macOS 15.4, *)
@MainActor
final class ExtensionPopup: NSObject, WKUIDelegate, WKNavigationDelegate, NSPopoverDelegate {
    static let shared = ExtensionPopup()

    private var popover: NSPopover?
    private var web: WKWebView?
    /// The popup, as WebKit is told of it: a tab of the browser window that
    /// isn't among its tabs, so the popup's "current window" is the browser's.
    private var page: PopupPage?
    private(set) var extensionID: String?
    /// Its extension's button, when it hangs from there.
    private weak var button: NSView?
    /// A press on its own button that closed it (PopupSizing.reopenGuard).
    private var closedByButton: (id: String, at: Date)?
    private var shown = false
    private var measuring: Timer?
    private var tick = 0
    /// Each extension's last popup size, to open at next time.
    private static var lastSize: [String: NSSize] = [:]

    /// The page, for the bench.
    var view: WKWebView? { web }

    func show(_ url: URL, for context: WKWebExtensionContext, from anchor: NSView?) {
        close()
        guard let setup = context.webViewConfiguration else { return }
        let id = context.uniqueIdentifier
        // Measured while hidden, in the popover at the last size: a page out
        // of any window is suspended by WebKit.
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 25, height: 25), configuration: setup)
        web.uiDelegate = self
        web.navigationDelegate = self
        web.alphaValue = 0
        web.load(URLRequest(url: Extensions.unpopped(url)))

        let size = Self.lastSize[id] ?? PopupSizing.first
        let stage = NSView(frame: NSRect(origin: .zero, size: size))
        stage.addSubview(web)
        let holder = NSViewController()
        holder.view = stage
        // Without it the popover grows in from nothing.
        holder.preferredContentSize = size
        let popover = NSPopover()
        popover.contentViewController = holder
        popover.contentSize = size
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        self.web = web
        self.popover = popover
        extensionID = id
        button = anchor != nil && anchor === Extensions.shared.anchors[id]?.view ? anchor : nil
        page = PopupPage(web: web)
        page.map(Extensions.shared.controller.didOpenTab)
        shown = false
        present(popover, from: anchor)

        // It's measured when its document or page loads; these are for pages
        // slow to get there.
        after(3) {
            $0.firstMeasure(); $0.follow()
        }
        after(5) { $0.reveal() }
    }

    private func present(_ popover: NSPopover, from anchor: NSView?) {
        if let anchor, anchor.window != nil { return popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY) }
        let window = NSApp.mainWindow ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain && $0.frame.minX > -10_000 }
        guard let content = window?.contentView else { return }
        popover.show(
            relativeTo: NSRect(x: content.bounds.maxX - 60, y: content.bounds.maxY - 40, width: 1, height: 1), of: content,
            preferredEdge: .minY)
    }

    /// Runs `then` in `seconds`, if this popup is still the one open.
    private func after(_ seconds: Double, _ then: @escaping @MainActor (ExtensionPopup) -> Void) {
        let popover = popover
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, let popover, popover === self.popover else { return }
            then(self)
        }
    }

    func close() {
        stopMeasuring()
        let closing = popover
        forget()
        closing?.performClose(nil)
    }

    private func forget() {
        page.map { Extensions.shared.controller.didCloseTab($0, windowIsClosing: false) }
        page = nil
        popover = nil
        web = nil
        extensionID = nil
        button = nil
    }

    /// Whether pressing extension `id`'s button only closes its popup, as in
    /// Chrome; also when the popover already closed as the press began.
    func closes(_ id: String) -> Bool {
        defer { closedByButton = nil }
        if popover != nil, extensionID == id {
            close()
            return true
        }
        guard let closed = closedByButton, closed.id == id else { return false }
        return Date().timeIntervalSince(closed.at) < PopupSizing.reopenGuard
    }

    // MARK: - Sizing

    /// Near enough Blink's popup sizing. At "fit", run while the view is 25
    /// points square, it gives the popup's size: the page's own width, else
    /// its min-content, else its scroll width for very narrow pages; its
    /// height at that width. At "grow", the width by the same rules and the
    /// scroll height when the page overflows, else 0. The page's inline
    /// styles are put back after. See Scripts/src/popup-size.ts.
    static let size = InjectedScript.call("popup-size", arguments: ["stage"])

    private static func measure(_ web: WKWebView, _ stage: String, then: @escaping @MainActor (NSSize) -> Void) {
        web.callAsyncJavaScript(size, arguments: ["stage": stage], in: nil, in: .page) { result in
            guard let pair = (try? result.get()) as? [Double], pair.count == 2 else { return }
            then(NSSize(width: pair[0], height: pair[1]))
        }
    }

    /// WebKit's unpublished DOMContentLoaded callback: when Chrome sizes
    /// popups, and some read their viewport only then. A user script can't do
    /// it: the extension's configuration is shared.
    @objc(_webView:navigationDidFinishDocumentLoad:)
    func webView(_ webView: WKWebView, navigationDidFinishDocumentLoad navigation: WKNavigation?) {
        if webView === web { firstMeasure() }
    }

    private func firstMeasure() {
        guard let web, !shown else { return }
        Self.measure(web, "fit") { [weak self] size in
            guard let self, web === self.web, !shown else { return }
            resize(to: size)
        }
    }

    /// The page keeps changing after it loads, often as the worker answers.
    private func follow() {
        guard measuring == nil else { return }
        if !shown { firstMeasure() }
        tick = 0
        measuring = Timer.scheduledTimer(withTimeInterval: PopupSizing.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.measureAgain() }
        }
    }

    private func stopMeasuring() {
        measuring?.invalidate()
        measuring = nil
    }

    private func measureAgain() {
        guard shown, let web, let popover else { return }
        tick += 1
        switch PopupSizing.step(tick) {
        case .fit:
            Self.measure(web, "fit") { [weak self] wanted in
                if PopupSizing.differs(wanted, from: popover.contentSize, slack: 2) { self?.resize(to: wanted) }
            }
        case .grow:
            Self.measure(web, "grow") { [weak self] extent in
                let wanted = PopupSizing.grown(popover.contentSize, toTakeIn: extent)
                if wanted != popover.contentSize { self?.resize(to: wanted) }
            }
        case .stop:
            stopMeasuring()
        }
    }

    private func resize(to size: NSSize) {
        guard let popover else { return }
        if PopupSizing.differs(size, from: popover.contentSize, slack: 1) {
            // The popover goes back to its controller's preferred size: both change.
            popover.contentViewController?.preferredContentSize = size
            popover.contentSize = size
            popover.contentViewController?.view.setFrameSize(size)
            if shown { web?.frame = NSRect(origin: .zero, size: size) }
        }
        if let id = extensionID { Self.lastSize[id] = size }
        reveal()
    }

    /// The page fades in at the popover's size.
    private func reveal() {
        guard !shown, let web, let popover, let stage = popover.contentViewController?.view else { return }
        shown = true
        web.frame = NSRect(origin: .zero, size: popover.contentSize == .zero ? stage.bounds.size : popover.contentSize)
        web.autoresizingMask = [.width, .height]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            web.animator().alphaValue = 1
        }
    }

    // MARK: - The page and the popover

    func webViewDidClose(_ webView: WKWebView) { close() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { follow() }

    /// A new window opens as a tab and the popup closes, as in Chrome.
    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = action.request.url { Extensions.shared.browser?.open(url, foreground: true) }
        close()
        return nil
    }

    /// Notes a close caused by pressing the popup's own button.
    func popoverWillClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover, let id = extensionID, let button, let window = button.window,
            NSEvent.pressedMouseButtons & 1 != 0
        else { return }
        let spot = button.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        if button.bounds.contains(spot) { closedByButton = (id, Date()) }
    }

    /// Only the popover still open: an old one's closing can finish after a
    /// new popup opened.
    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === popover else { return }
        stopMeasuring()
        forget()
    }
}

/// The popup as WebKit sees it: in the browser window, not among its tabs.
@available(macOS 15.4, *)
@MainActor
final class PopupPage: NSObject, WKWebExtensionTab {
    weak var web: WKWebView?

    init(web: WKWebView) { self.web = web }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { Extensions.shared.window }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { NSNotFound }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { web }
    func title(for context: WKWebExtensionContext) -> String? { web?.title }
    func url(for context: WKWebExtensionContext) -> URL? { web?.url }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { web?.isLoading != true }
    func isSelected(for context: WKWebExtensionContext) -> Bool { false }
    func close(for context: WKWebExtensionContext) async throws { ExtensionPopup.shared.close() }
}
