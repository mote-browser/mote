import WebKit

// Message handlers for Mote's page scripts. A content controller holds its
// handlers strongly, so each keeps only a weak reference to its tab and a
// page can't keep a closed tab alive.

/// A message handler that reports to one tab.
@MainActor
protocol TabRelay: AnyObject {
    var tab: Tab? { get set }
}

extension ScrollRelay: TabRelay {}
extension MiddleRelay: TabRelay {}
extension ElementHiderRelay: TabRelay {}
extension FormRelay: TabRelay {}
extension ImageRelay: TabRelay {}
extension WebStoreBridge: TabRelay {}
extension HoveredLink: TabRelay {}

/// Scroll position, and whether a sideways swipe would scroll the page.
final class ScrollRelay: NSObject, WKScriptMessageHandler {
    static let name = "moteScroll"
    /// Reports the position on load and while scrolling, at most once a frame.
    /// See Scripts/src/scroll-report.ts.
    static let script = InjectedScript.source("scroll-report")

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            if let side = body["side"] as? String {
                tab?.built?.swipeAnswered(free: side == "free")
            } else if let y = body["y"] as? Double, let ceiling = body["max"] as? Double {
                tab?.scrolled(to: y, of: ceiling)
            }
        }
    }
}

/// Middle-clicked links, which WebKit gives no navigation action for.
///
/// The script listens for trusted `auxclick` events in the main frame only,
/// after the page's own handlers, and skips any the page cancelled, so
/// neither synthetic events nor ads in frames can open tabs.
final class MiddleRelay: NSObject, WKScriptMessageHandler {
    static let name = "moteMiddle"
    /// See Scripts/src/middle-click.ts.
    static let watch = InjectedScript.source("middle-click")

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let href = (message.body as? [String: Any])?["href"] as? String,
            let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased())
        else { return }
        MainActor.assumeIsolated {
            guard let tab else { return }
            tab.owner?.tab(tab, middleClicked: url)
        }
    }
}
