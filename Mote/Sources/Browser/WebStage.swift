import SwiftUI
import WebKit

/// Holds the active tab's web view. Tabs hand theirs over when they come to
/// the front and get it back as it was: not reloaded, scroll and forms kept.
struct WebStage: NSViewRepresentable {
    let page: NSView?
    var overlay: NSView? = nil
    var stage: StageView? = nil

    func makeNSView(context: Context) -> StageView { stage ?? StageView() }
    func updateNSView(_ view: StageView, context: Context) { view.show(page, overlay: overlay) }
}

final class StageView: NSView {
    /// The view to show; the one thing kept. Every layout brings the subviews
    /// in line with it, so they can't drift apart.
    private weak var wanted: NSView?
    private weak var overlay: NSView?
    private var previousFrameNotifications = false
    private weak var observedInspector: NSView?
    private var previousInspectorNotifications = false

    override func layout() {
        super.layout()
        settle()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        if isInspector(subview) { observeInspector(subview) }
    }

    override func willRemoveSubview(_ subview: NSView) {
        if subview === observedInspector { observeInspector(nil) }
        super.willRemoveSubview(subview)
    }

    func show(_ page: NSView?, overlay: NSView? = nil) {
        if wanted !== page {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: wanted)
            wanted?.postsFrameChangedNotifications = previousFrameNotifications
            wanted = page
            previousFrameNotifications = page?.postsFrameChangedNotifications ?? false
            if let page {
                page.postsFrameChangedNotifications = true
                NotificationCenter.default.addObserver(
                    self, selector: #selector(pageFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: page)
            }
        }
        self.overlay = overlay
        overlay?.wantsLayer = true
        overlay?.layer?.masksToBounds = true
        settle()
    }

    /// WebKit resizes the page directly while dragging its dock divider; the
    /// parent's SwiftUI layout need not run. Follow that frame without laying out WebKit.
    @objc private func pageFrameChanged(_ notification: Notification) {
        guard let wanted, wanted.superview === self else { return }
        updateOverlayFrame()
    }

    private func observeInspector(_ view: NSView?) {
        guard observedInspector !== view else { return }
        if let old = observedInspector {
            NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: old)
            old.postsFrameChangedNotifications = previousInspectorNotifications
        }
        observedInspector = view
        previousInspectorNotifications = view?.postsFrameChangedNotifications ?? false
        if let view {
            view.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(pageFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: view)
        }
        updateOverlayFrame()
    }

    private func updateOverlayFrame() {
        guard let wanted, let overlay else { return }
        var available = wanted.frame
        if let dock = observedInspector, dock.superview === self {
            let occupied = dock.frame.intersection(bounds)
            if !occupied.isEmpty, abs(occupied.width - bounds.width) < 1 {
                available = bounds
                if abs(occupied.minY - bounds.minY) < 1 {
                    available.origin.y = occupied.maxY
                    available.size.height = max(0, bounds.maxY - occupied.maxY)
                } else {
                    available.size.height = max(0, occupied.minY - bounds.minY)
                }
            } else if !occupied.isEmpty, abs(occupied.height - bounds.height) < 1 {
                available = bounds
                if abs(occupied.minX - bounds.minX) < 1 {
                    available.origin.x = occupied.maxX
                    available.size.width = max(0, bounds.maxX - occupied.maxX)
                } else {
                    available.size.width = max(0, occupied.minX - bounds.minX)
                }
            }
        }
        overlay.frame = available
    }

    private func settle() {
        // A full-screen video's web view lives in WebKit's own window, with a
        // stand-in here; taking it back then leaves a black screen with the sound
        // still playing. WebKit returns it when full screen ends.
        if let web = wanted as? WKWebView, web.fullscreenState != .notInFullscreen { return }

        // Everything else goes, except a docked Web Inspector: WebKit puts it
        // beside the page and narrows the page to fit, so removing it would leave
        // the page narrow beside an empty space.
        let inspecting = inspectorOpen
        for view in subviews where view !== wanted && view !== overlay && !(inspecting && isInspector(view)) {
            view.removeFromSuperview()
        }

        guard let wanted, window != nil else { return }
        if wanted.superview !== self {
            // Adding it takes it from wherever it was.
            wanted.removeFromSuperview()
            // Hidden until it has painted, so it doesn't flash white.
            wanted.alphaValue = (wanted as? PageView)?.unpainted == true ? 0 : 1
            addSubview(wanted)
            // A web view back in a window can keep an empty backing store.
            wanted.needsLayout = true
            wanted.needsDisplay = true
            wanted.layer?.setNeedsDisplay()
        }
        // With the inspector docked, WebKit lays both out; a frame here would cover the inspector.
        let dock = inspecting ? subviews.first(where: isInspector) : nil
        observeInspector(dock)
        if dock == nil { wanted.frame = bounds }
        if let overlay {
            if overlay.superview !== self { addSubview(overlay, positioned: .above, relativeTo: wanted) }
            updateOverlayFrame()
        }
    }

    /// Whether the page's Web Inspector is open, through private WebKit
    /// calls checked before use (see Inspector.swift).
    private var inspectorOpen: Bool {
        let inspector = NSSelectorFromString("_inspector")
        let visible = NSSelectorFromString("isVisible")
        guard let web = wanted as? WKWebView, web.responds(to: inspector),
            let object = web.perform(inspector)?.takeUnretainedValue() as? NSObject, object.responds(to: visible)
        else { return false }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(object.method(for: visible), to: Getter.self)(object, visible)
    }

    private func isInspector(_ view: NSView) -> Bool {
        if let web = wanted as? WKWebView,
            let inspector = web.unpublishedObject("_inspector"),
            inspector.unpublishedObject("extensionHostWebView") === view
        {
            return true
        }
        return String(describing: type(of: view)).hasPrefix("WKInspector")
    }
}
