import SwiftUI
import WebKit

/// Holds the active tab's web view. Tabs hand theirs over when they come to
/// the front and get it back as it was: not reloaded, scroll and forms kept.
struct WebStage: NSViewRepresentable {
    let page: NSView?

    func makeNSView(context: Context) -> StageView { StageView() }
    func updateNSView(_ view: StageView, context: Context) { view.show(page) }
}

final class StageView: NSView {
    /// The view to show; the one thing kept. Every layout brings the subviews
    /// in line with it, so they can't drift apart.
    private weak var wanted: NSView?

    override func layout() {
        super.layout()
        settle()
    }

    func show(_ page: NSView?) {
        wanted = page
        settle()
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
        for view in subviews where view !== wanted && !(inspecting && Self.isInspector(view)) { view.removeFromSuperview() }

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
        if !(inspecting && subviews.contains(where: Self.isInspector)) { wanted.frame = bounds }
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

    private static func isInspector(_ view: NSView) -> Bool {
        String(describing: type(of: view)).hasPrefix("WKInspector")
    }
}
