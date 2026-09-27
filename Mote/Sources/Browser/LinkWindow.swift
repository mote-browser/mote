import MoteCore
import SwiftUI

// Links from other apps can open in a small window of their own, with the
// site's name and an Open in Mote button (Settings › General). The page is an
// ordinary tab that moves into the browser when kept.

@MainActor
final class LinkWindow: NSObject, NSWindowDelegate {
    /// Every one open, oldest first, until closed or kept.
    private(set) static var all: [LinkWindow] = []

    let tab: Tab
    private weak var browser: Browser?
    private let window: NSWindow
    private var kept = false

    /// `front: false` makes it without showing it, for the bench.
    static func show(_ url: URL, for browser: Browser, front: Bool = true) {
        let tab = Tab()
        browser.prepare(tab)
        tab.go(to: url)
        let little = LinkWindow(tab: tab, browser: browser)
        all.append(little)
        little.window.center()
        guard front else { return }
        little.window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    static func owning(_ window: NSWindow?) -> LinkWindow? {
        all.first { $0.window === window }
    }

    private init(tab: Tab, browser: Browser) {
        self.tab = tab
        self.browser = browser
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 320)
        window.delegate = self
        window.contentView = NSHostingView(rootView: LinkWindowView(tab: tab, keep: { [weak self] in self?.keep() }))
    }

    /// As the close button does.
    func close() { window.performClose(nil) }

    /// Its own keys, before the browser's; false leaves the key to the page.
    func take(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let press = KeyMap.Press(
            key: event.charactersIgnoringModifiers ?? "", code: event.keyCode, command: flags.contains(.command),
            shift: flags.contains(.shift), option: flags.contains(.option), control: flags.contains(.control))
        switch KeyMap.linkWindow(press) {
        case .keep: keep()
        case .close: close()
        case nil: return false
        }
        return true
    }

    /// Moves the page into the browser after the current tab and brings the
    /// browser forward.
    func keep() {
        guard let browser else { return }
        kept = true
        browser.insert(tab, at: browser.placeForNew())
        browser.select(tab)
        window.close()
        let main = AppDelegate.window ?? NSApp.windows.first { $0.contentView != nil && !($0 is NSPanel) && $0 !== window }
        main?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if !kept { tab.close() }
        Self.all.removeAll { $0 === self }
    }
}

/// The site's bar over the page.
private struct LinkWindowView: View {
    @ObservedObject var tab: Tab
    let keep: () -> Void

    /// The traffic lights sit on the bar.
    private static let lightsRoom: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Color.clear.frame(width: Self.lightsRoom)
                Spacer(minLength: 0)
                Text(tab.address.map(Address.siteName) ?? "")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Pill("Open in Mote", action: keep).help("Open in Mote   ⌘O")
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            WebStage(page: tab.built ?? tab.web)
        }
        .background(Palette.ground)
        .ignoresSafeArea()
    }
}
