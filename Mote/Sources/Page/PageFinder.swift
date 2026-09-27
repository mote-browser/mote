import Observation
import WebKit

/// Find in page (⌘F): the bar's state and the searches it runs in the page.
@MainActor
@Observable
final class PageFinder {
    private(set) var showing = false
    var query = "" {
        didSet { look(forward: true) }
    }
    /// The query isn't on the page.
    private(set) var missed = false
    /// Incremented to put the keyboard back in the bar.
    private(set) var focusRequest = 0

    /// The page being searched.
    @ObservationIgnored var page: () -> WKWebView? = { nil }

    func show() {
        showing = true
        focusRequest += 1
    }

    func hide() {
        guard showing else { return }
        showing = false
        query = ""
        missed = false
        // WebKit has no call to end a find; clearing the selection drops the highlight.
        page()?.evaluateJavaScript("window.getSelection().removeAllRanges()")
    }

    func look(forward: Bool) {
        guard let page = page(), !query.isEmpty else {
            missed = false
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = !forward
        configuration.caseSensitive = false
        configuration.wraps = true
        page.find(query, configuration: configuration) { [weak self] result in
            MainActor.assumeIsolated { self?.missed = !result.matchFound }
        }
    }
}
