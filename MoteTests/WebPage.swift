import WebKit

/// A web view that loads HTML and runs JavaScript for integration tests.
@MainActor
final class WebPage: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var loading: CheckedContinuation<Void, Error>?

    init(configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(html: String, baseURL: URL = URL(string: "https://example.com/")!) async throws {
        try await withCheckedThrowingContinuation { continuation in
            loading = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    /// Runs `body` as the body of an async function and returns its string result.
    func call(_ body: String) async throws -> String? {
        try await webView.callAsyncJavaScript(body, contentWorld: .page) as? String
    }

    /// Runs `script`, which must return a string.
    func string(_ script: String) async throws -> String? {
        try await webView.evaluateJavaScript(script) as? String
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated { finish(error) }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        MainActor.assumeIsolated { finish(error) }
    }

    private func finish(_ error: Error?) {
        guard let loading else { return }
        self.loading = nil
        if let error { loading.resume(throwing: error) } else { loading.resume() }
    }
}

struct TimedOut: Error {}

/// Polls `value` on the main actor until it returns something, or fails after `timeout`.
@MainActor
func eventually<T>(timeout: Duration = .seconds(10), _ value: () -> T?) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let result = value() { return result }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw TimedOut()
}
