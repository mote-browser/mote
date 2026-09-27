import WebKit

// The Web Inspector for the tab in front. WebKit only offers it through
// selectors it doesn't publish; without them these do nothing.

extension Browser {
    /// ⌥⌘I.
    func toggleInspector() {
        guard let inspector = inspector() else { return }
        inspector.unpublished(Self.inspectorShows(inspector) ? "close" : "show")
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
        return tab.web.unpublishedObject("_inspector")
    }

    private static func inspectorShows(_ inspector: NSObject) -> Bool {
        inspector.unpublishedFlag("isVisible") ?? false
    }
}
