import Combine
import MoteCore
import WebKit

/// Owns only the responsive workspace's pages. Closing it drops every handler and web view.
@MainActor
final class ResponsiveSession: NSObject, ObservableObject, WKScriptMessageHandler {
    static let savedKey = "development.responsive.layouts"
    static let currentKey = "development.responsive.current"
    static let world = WKContentWorld.world(name: "MoteResponsive")
    static let script = InjectedScript.source("responsive-sync") + "\nmoteResponsiveSync.install();"

    @Published private(set) var panes: [ResponsivePane] = []
    @Published private(set) var saved: [ResponsiveLayout] = []
    @Published var address = ""
    @Published var syncing = true {
        didSet { panes.forEach { $0.setSyncing(syncing) } }
    }
    @Published var scale = 0.5
    @Published var notice: String?
    private let store: WKWebsiteDataStore
    private let defaults: UserDefaults
    private var url: URL?

    init(store: WKWebsiteDataStore, defaults: UserDefaults = Storage.settings) {
        self.store = store
        self.defaults = defaults
        super.init()
        saved = read([ResponsiveLayout].self, key: Self.savedKey) ?? []
        let current = read(ResponsiveLayout.self, key: Self.currentKey)
        apply(current?.viewports ?? ResponsiveViewport.presets)
    }

    private func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do { return try JSONDecoder().decode(type, from: data) } catch {
            defaults.set(data, forKey: key + ".unreadable")
            defaults.removeObject(forKey: key)
            notice = "Saved views could not be read. A copy was preserved; default views are available."
            return nil
        }
    }

    func navigate(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = text.contains("://") ? text : "https://" + text
        guard let url = URL(string: candidate), Self.allows(url), !text.isEmpty else {
            throw URLError(.unsupportedURL)
        }
        self.url = url
        address = url.absoluteString
        for pane in panes { pane.load(URLRequest(url: url)) }
    }

    static func allows(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
            && url.user == nil && url.password == nil
    }

    func reload() {
        for pane in panes { pane.web.reload() }
    }

    /// Reuses unchanged pages, including their scroll position and form state.
    func apply(_ profiles: [ResponsiveViewport]) {
        guard (try? ResponsiveLayout(name: "Current", viewports: profiles)) != nil else {
            notice = ResponsiveError.views.localizedDescription
            return
        }
        let old = panes
        panes = profiles.map { profile in
            if let pane = old.first(where: { $0.id == profile.id && $0.profile.userAgent == profile.userAgent }) {
                pane.profile = profile
                return pane
            }
            let pane = ResponsivePane(profile: profile, store: store, session: self)
            if let url { pane.load(URLRequest(url: url)) }
            return pane
        }
        for pane in old where !panes.contains(where: { $0 === pane }) { pane.close() }
        remember()
    }

    func replace(_ profile: ResponsiveViewport) {
        apply(panes.map { $0.id == profile.id ? profile : $0.profile })
    }

    func add(_ profile: ResponsiveViewport) {
        guard panes.count < ResponsiveLayout.maximumViews else { return }
        do {
            let copy = try ResponsiveViewport(
                name: profile.name, width: profile.width, height: profile.height, userAgent: profile.userAgent)
            apply(panes.map(\.profile) + [copy])
        } catch { notice = error.localizedDescription }
    }

    func remove(_ id: UUID) {
        guard panes.count > 1 else { return }
        apply(panes.filter { $0.id != id }.map(\.profile))
    }

    func save(name: String) throws {
        let existing = saved.first { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
        let layout = try ResponsiveLayout(id: existing?.id ?? UUID(), name: name, viewports: panes.map(\.profile))
        let next = saved.filter { $0.id != layout.id } + [layout]
        let data = try JSONEncoder().encode(next)
        defaults.set(data, forKey: Self.savedKey)
        saved = next
    }

    func deleteSaved(_ id: UUID) {
        let next = saved.filter { $0.id != id }
        do {
            defaults.set(try JSONEncoder().encode(next), forKey: Self.savedKey)
            saved = next
        } catch { notice = error.localizedDescription }
    }

    private func remember() {
        do {
            let layout = try ResponsiveLayout(name: "Current", viewports: panes.map(\.profile))
            defaults.set(try JSONEncoder().encode(layout), forKey: Self.currentKey)
        } catch { notice = error.localizedDescription }
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard syncing, message.frameInfo.isMainFrame,
            let source = panes.first(where: { $0.web === message.webView }),
            let event = message.body as? [String: Any],
            let pageURL = event["url"] as? String, pageURL == source.web.url?.absoluteString,
            JSONSerialization.isValidJSONObject(event),
            let bytes = try? JSONSerialization.data(withJSONObject: event), bytes.count <= 65536
        else { return }
        for pane in panes where pane !== source && pane.web.url?.absoluteString == pageURL {
            pane.web.callAsyncJavaScript(
                "return moteResponsiveSync.receive(event);", arguments: ["event": event], in: nil, in: Self.world
            ) { _ in }
        }
    }

    /// Real link navigation is mirrored through WebKit, so browser defaults don't depend on synthetic key events.
    func follow(_ request: URLRequest, from source: ResponsivePane) {
        guard syncing, let target = request.url, Self.allows(target), request.httpMethod == nil || request.httpMethod == "GET" else {
            return
        }
        url = target
        address = target.absoluteString
        for pane in panes where pane !== source && pane.requestedURL != target { pane.load(request) }
    }

    func close() {
        panes.forEach { $0.close() }
        panes = []
    }
}

@MainActor
final class ResponsivePane: NSObject, ObservableObject, Identifiable, WKNavigationDelegate {
    var id: UUID { profile.id }
    @Published var profile: ResponsiveViewport
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    let web: WKWebView
    private(set) var requestedURL: URL?
    private weak var session: ResponsiveSession?

    init(profile: ResponsiveViewport, store: WKWebsiteDataStore, session: ResponsiveSession) {
        self.profile = profile
        self.session = session
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.applicationNameForUserAgent = Web.userAgentName
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(session, contentWorld: ResponsiveSession.world, name: "moteResponsive")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: profile.width, height: profile.height), configuration: config)
        web.customUserAgent = profile.userAgent
        web.isInspectable = true
        super.init()
        web.navigationDelegate = self
        setSyncing(session.syncing)
    }

    func setSyncing(_ enabled: Bool) {
        let controller = web.configuration.userContentController
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(
                source: ResponsiveSession.script + "\nmoteResponsiveSync.setEnabled(\(enabled));",
                injectionTime: .atDocumentStart, forMainFrameOnly: true, in: ResponsiveSession.world))
        web.callAsyncJavaScript(
            "if (typeof moteResponsiveSync !== 'undefined') moteResponsiveSync.setEnabled(enabled);",
            arguments: ["enabled": enabled], in: nil, in: ResponsiveSession.world
        ) { _ in }
    }

    func load(_ request: URLRequest) {
        requestedURL = request.url
        error = nil
        loading = true
        web.load(request)
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url,
            ResponsiveSession.allows(url)
                || (navigationAction.targetFrame?.isMainFrame == false && ["about", "data", "blob"].contains(url.scheme ?? ""))
        else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame == nil {
            load(navigationAction.request)
            session?.follow(navigationAction.request, from: self)
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            requestedURL = url
            if navigationAction.navigationType == .linkActivated { session?.follow(navigationAction.request, from: self) }
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loading = true
        error = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { failed(error) }

    private func failed(_ error: any Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false
        self.error = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        error = "This view stopped. Reload to continue."
    }

    func close() {
        web.stopLoading()
        web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "moteResponsive", contentWorld: ResponsiveSession.world)
        web.removeFromSuperview()
        session = nil
    }
}
