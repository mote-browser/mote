import Combine
import MoteCore
import WebKit

// The Chrome Web Store, made to work in Mote: its "Switch to Chrome" prompts
// hidden, and its greyed-out "Add to Chrome" replaced with "Add to Mote".
// Which extension to add comes from the tab's address, never from the page,
// and adding still asks the person.

/// Hears the store page's button.
final class WebStoreBridge: NSObject, WKScriptMessageHandler {
    static let name = "moteStore"

    /// In every main frame, doing nothing outside the store. It finds the
    /// store's parts without its generated class names: the install button
    /// is the disabled one that mentions Chrome, the banner the smallest box
    /// around the enabled one that does. See Scripts/src/web-store-bridge.ts.
    static let script = InjectedScript.source("web-store-bridge")

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            guard let tab else { return }
            if body["add"] != nil { tab.addFromStorePressed() }
            if let placed = body["placed"] as? String { tab.storePlaced = placed }
        }
    }
}

extension Browser {
    /// The store's extensions, where Settings and the extensions menu send people.
    static let webStore = URL(string: "https://chromewebstore.google.com/category/extensions")!

    /// "Add to Mote": the extension at this tab's address.
    func addFromStore(_ tab: Tab) {
        guard #available(macOS 15.4, *), let page = storePage(of: tab) else { return }
        Extensions.shared.install(from: page.absoluteString)
    }

    /// Which extensions are in, and which is on its way, so the page's
    /// buttons say so.
    func tellStore(_ tab: Tab) {
        guard #available(macOS 15.4, *), storePage(of: tab) != nil else { return }
        tab.tellStore(installed: Extensions.shared.installed.map(\.id), busy: Extensions.shared.busy)
    }

    private func storePage(of tab: Tab) -> URL? {
        tab.address.flatMap { ExtensionRules.isStorePage($0) ? $0 : nil }
    }

    /// Store pages hear again whenever that changes.
    func followStore() {
        guard #available(macOS 15.4, *) else { return }
        let extensions = Extensions.shared
        storeWatch = Publishers.Merge(extensions.$installed.map { _ in () }, extensions.$busy.map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                tabs.filter { $0.built != nil }.forEach(tellStore)
            }
    }
}
