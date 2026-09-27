import MoteCore

// Hiding page elements for good (⌘⇧H), per site. ElementHider keeps what is
// hidden; this runs the picker and the review list for the current page.
extension Browser {
    var hereHost: String? { Address.siteHost(of: active?.address) }
    var hereVeils: [HiddenElement] { elementHider.hiddenElements(on: hereHost) }

    /// ⌘⇧H: starts or stops picking elements to hide.
    func toggleHiding() {
        guard let tab = active, !tab.isBlank else { return }
        pickingElement.toggle()
        if pickingElement {
            reviewing = false
            tab.startPicking()
        } else {
            tab.stopPicking()
        }
    }

    /// An element picked in `tab`: hidden on its site from now on.
    func hide(_ selector: String, label: String, note: String, in tab: Tab) {
        guard let host = Address.siteHost(of: tab.address) else { return }
        elementHider.hide(selector, label: label, note: note, on: host)
        dress(tab, for: host)
        announce("Hidden — ⌘Z puts it back")
    }

    /// ⌘Z while picking: brings back the last hidden element.
    func undoHiding() {
        guard let host = hereHost, let back = elementHider.undo(on: host) else { return }
        dressActive()
        announce("\(back.label) is back")
    }

    /// While its row is hovered, shows a hidden element outlined and scrolls to it.
    func peek(_ hidden: HiddenElement) {
        active?.peek(hidden.selector, keeping: elementHider.hiding(on: hereHost, without: hidden.selector))
    }

    func stopPeeking() {
        active?.unpeek(elementHider.hiding(on: hereHost))
    }

    func restore(_ hidden: HiddenElement) {
        guard let host = hereHost else { return }
        elementHider.restore(hidden, on: host)
        dressActive()
    }

    func restoreAll() {
        guard let host = hereHost else { return }
        elementHider.restoreAll(on: host)
        dressActive()
        reviewing = false
        announce("Everything is back")
    }

    private func dressActive() {
        if let tab = active, let host = hereHost { dress(tab, for: host) }
    }

    /// Applies the site's stylesheet to the page now and to its next load.
    private func dress(_ tab: Tab, for host: String) {
        let hiding = elementHider.hiding(on: host)
        tab.arm(hiding: hiding)
        tab.applyVeils(hiding)
    }
}
