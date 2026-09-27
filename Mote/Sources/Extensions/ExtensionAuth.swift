import Combine
import WebKit

/// chrome.identity.launchWebAuthFlow. The sign-in opens in a tab; its step to
/// https://<id>.chromiumapp.org/ never loads, and is the answer.
@MainActor
enum ExtensionAuth {
    private struct Flow {
        let tab: Tab.ID
        let finish: (Result<URL, Error>) -> Void
    }

    private static var flows: [String: Flow] = [:]
    private static var closing: AnyCancellable?

    struct Declined: LocalizedError {
        var errorDescription: String? { "The user did not approve access." }
    }

    private static let redirectSuffix = ".chromiumapp.org"

    static func run(_ url: URL, extension id: String, browser: Browser) async throws -> URL {
        try await withCheckedThrowingContinuation { answer in
            flows.removeValue(forKey: id)?.finish(.failure(Declined()))
            flows[id] = Flow(tab: browser.open(url, foreground: true).id) { answer.resume(with: $0) }
            // Closing its tab says no.
            closing = browser.$tabs.sink { tabs in
                let open = Set(tabs.map(\.id))
                for (id, flow) in flows where !open.contains(flow.tab) {
                    flows[id] = nil
                    flow.finish(.failure(Declined()))
                }
            }
        }
    }

    /// Whether `url` ended a flow. Only from its own tab, or a popup it
    /// opened: any other page could forge the redirect.
    static func intercept(_ url: URL, browser: Browser, from webView: WKWebView) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), host.hasSuffix(redirectSuffix) else { return false }
        let id = String(host.dropLast(redirectSuffix.count))
        guard let flow = flows[id], let from = browser.tab(for: webView), from.id == flow.tab || from.opener == flow.tab else {
            return false
        }
        flows[id] = nil
        flow.finish(.success(url))
        // The popup too, or it would sit on a redirect that never loads.
        if from.id != flow.tab { browser.close(from) }
        if let tab = browser.tab(flow.tab) { browser.close(tab) }
        return true
    }
}
