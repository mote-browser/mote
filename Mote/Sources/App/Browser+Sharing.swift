import AppKit

extension Browser {
    /// File › Share: the system's share menu, pointing into the page's top
    /// right corner (or the window's, with no page showing).
    func share() {
        guard let address = active?.address, let window = AppDelegate.window else { return }
        let page = active?.built.flatMap { $0.window === window ? $0 : nil }
        guard let view = page ?? window.contentView else { return }
        // A little in, so the arrow points at the page rather than its edge.
        let inset: CGFloat = 12
        let top = view.isFlipped ? inset : view.bounds.maxY - inset
        NSSharingServicePicker(items: [address])
            .show(
                relativeTo: NSRect(x: view.bounds.maxX - inset, y: top, width: 1, height: 1), of: view,
                preferredEdge: view.isFlipped ? .maxY : .minY)
    }
}
