import Combine
import MoteCore
import WebKit

// Ads and trackers are blocked by a WebKit content rule list, compiled once
// per launch. WebKit applies it in its network layer: no script runs per
// request.

@MainActor
final class AdBlocker: ObservableObject {
    static let shared = AdBlocker()

    private(set) var list: WKContentRuleList?
    /// Pages made before the list was ready; they get it when it is.
    private var waiting: [WKUserContentController] = []

    /// Why the list couldn't be made. Nothing is blocked then, whatever
    /// Settings says, so Settings shows it.
    @Published private(set) var trouble: String?

    /// Open pages follow it after `apply(to:)`, from their next request.
    var enabled = true

    /// Sites where blocking is off because it broke them.
    private(set) var paused = Set(Storage.settings.stringArray(forKey: pausedKey) ?? [])
    private static let pausedKey = "shield.paused"

    func isPaused(on site: String?) -> Bool {
        site.map(paused.contains) ?? false
    }

    func pause(_ site: String, _ off: Bool) {
        if off { paused.insert(site) } else { paused.remove(site) }
        Storage.settings.set(paused.sorted(), forKey: Self.pausedKey)
    }

    private func blocks(_ site: String?) -> Bool { enabled && !isPaused(on: site) }

    func compile() {
        guard list == nil else { return }
        trouble = nil
        guard let rules = try? ContentBlockingRules.json() else { return trouble = "Couldn't build the block list" }
        guard let store = WKContentRuleListStore.default() else { return trouble = "WebKit has nowhere to compile it" }
        store.compileContentRuleList(forIdentifier: "mote-ad-blocker", encodedContentRuleList: rules) { [weak self] compiled, error in
            MainActor.assumeIsolated { self?.compiled(compiled, error) }
        }
    }

    private func compiled(_ compiled: WKContentRuleList?, _ error: Error?) {
        guard let compiled else { return trouble = error?.localizedDescription ?? "Compiling the block list failed" }
        list = compiled
        if enabled { waiting.forEach { $0.add(compiled) } }
        waiting = []
    }

    /// A new page: the list now, or once it's compiled.
    func protect(_ controller: WKUserContentController) {
        guard let list else { return waiting.append(controller) }
        if enabled { controller.add(list) }
    }

    /// Before loading a page from `site`: the list only counts from when
    /// it's added, so this runs as the navigation starts.
    func tune(_ controller: WKUserContentController, for site: String?) {
        set(controller, blocking: blocks(site))
    }

    /// `enabled` changed: open pages follow.
    func apply(to controllers: [WKUserContentController]) {
        controllers.forEach { set($0, blocking: enabled) }
    }

    private func set(_ controller: WKUserContentController, blocking: Bool) {
        guard let list else { return }
        controller.remove(list)
        if blocking { controller.add(list) }
    }
}
