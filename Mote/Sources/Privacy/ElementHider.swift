import Combine
import Foundation
import MoteCore
import WebKit

// Elements someone hid, kept per site as CSS selectors. A style added at
// document start hides them, so they never show for a moment first.

/// What is hidden on each site, saved to hidden.json.
@MainActor
final class ElementHider: ObservableObject {
    @Published private(set) var hidden: HiddenElements
    private let file = JSONFile<HiddenElements>("hidden.json")
    private var saving: Task<Void, Never>?

    /// Changes close together are saved once.
    private static let settle: Duration = .milliseconds(400)

    init() { hidden = file.load() ?? HiddenElements() }

    func hiddenElements(on site: String?) -> [HiddenElement] { hidden.on(site) }

    func hide(_ selector: String, label: String, note: String, on site: String) {
        if hidden.hide(HiddenElement(selector: selector, label: label, note: note), on: site) { save() }
    }

    func restore(_ element: HiddenElement, on site: String) {
        hidden.restore(element.selector, on: site)
        save()
    }

    /// ⌘Z while picking.
    @discardableResult
    func undo(on site: String) -> HiddenElement? {
        defer { save() }
        return hidden.undo(on: site)
    }

    func restoreAll(on site: String) {
        hidden.restoreAll(on: site)
        save()
    }

    /// What the page hides, less `spared` while it's being shown in the list.
    /// The page makes each selector a rule of its own, so one that doesn't
    /// parse spoils only itself.
    func hiding(on site: String?, without spared: String? = nil) -> ElementHidingStyle.Config {
        ElementHidingStyle.config(selectors: hidden.on(site).map(\.selector), sparing: spared)
    }

    private func save() {
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: Self.settle)
            guard let self else { return }
            saving = nil
            file.save(hidden)
        }
    }
}

/// Hears the picker: an element picked, picking over, or a page that can't.
final class ElementHiderRelay: NSObject, WKScriptMessageHandler {
    static let name = "moteVeil"

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            if let trouble = body["trouble"] as? String {
                tab?.pickingFailed(trouble)
            } else if body["off"] as? Bool == true {
                tab?.pickingEnded()
            } else if let selector = body["selector"] as? String {
                tab?.picked(selector: selector, label: body["label"] as? String ?? selector, note: body["note"] as? String ?? "")
            }
        }
    }
}

enum ElementPicker {
    /// In every page, doing nothing until `window.__moteVeil.on()`.
    /// See Scripts/src/element-picker.ts.
    static let picker = InjectedScript.source("element-picker")

    /// Hides what `config` selects, instead of what was hidden before; added
    /// at document start and run on the page already there. The selectors
    /// travel as `moteConfig`, never inside CSS or script text.
    /// See Scripts/src/element-hiding.ts.
    static func hiding(_ config: ElementHidingStyle.Config) -> String {
        InjectedScript.source("element-hiding", config: config)
    }
}
