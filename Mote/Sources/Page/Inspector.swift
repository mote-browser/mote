import WebKit

// The Web Inspector for the tab in front. WebKit only offers it through
// selectors it doesn't publish; without them these do nothing.

extension Browser {
    /// ⌥⌘I.
    func toggleInspector() {
        guard let inspector = inspector() else { return }
        if Self.inspectorShows(inspector) {
            active?.development?.closeInspector()
        } else {
            inspector.unpublished("show")
        }
    }

    func showResponsive() {
        guard inspector() != nil else { return }
        active?.development?.showResponsive()
    }

    /// ⌥⌘J: the inspector at its console.
    func showConsole() {
        inspector()?.unpublished("showConsole")
    }

    /// ⌥⌘C: the inspector, picking an element on the page.
    func inspectElement() {
        guard let inspector = inspector() else { return }
        if !Self.inspectorShows(inspector) { inspector.unpublished("show") }
        inspector.unpublished("toggleElementSelection")
    }

    private func inspector() -> NSObject? {
        guard let tab = active, !tab.isBlank else { return nil }
        guard let inspector = tab.web.unpublishedObject("_inspector") else { return nil }
        if tab.development == nil { tab.development = ResponsiveInspector(tab: tab, inspector: inspector) }
        tab.development?.prepareToOpen()
        return inspector
    }

    private static func inspectorShows(_ inspector: NSObject) -> Bool {
        inspector.unpublishedFlag("isVisible") ?? false
    }
}
