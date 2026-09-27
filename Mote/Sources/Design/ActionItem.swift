import AppKit

/// A menu item that runs a block, its own target.
nonisolated final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, key: String = "", _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}
