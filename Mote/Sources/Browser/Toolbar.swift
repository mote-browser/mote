import MoteAI
import MoteCore
import SwiftUI

/// The bar across the top of the card: the sidebar button, back, forward and
/// reload, the address across the rest of the bar, and extensions (and, above
/// a strip of tabs, bookmarks) at the far end.
struct Toolbar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    var body: some View {
        Row(browser: browser, prefs: prefs)
            .background(Palette.ground)
            .overlay(alignment: .bottom) {
                if let tab = browser.active { Seam(tab: tab).allowsHitTesting(false) }
            }
    }

    /// The hairline between the bar and a page, and the page's loading progress along it.
    private struct Seam: View {
        @ObservedObject var tab: Tab

        var body: some View {
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(height: 1)
                    .opacity(tab.isBlank ? 0 : 1)
                LoadLine(tab: tab)
            }
        }
    }

    private struct Row: View {
        @ObservedObject var browser: Browser
        @ObservedObject var prefs: Preferences

        var body: some View {
            HStack(spacing: 2) {
                if prefs.sidebar {
                    Door(icon: "sidebar.left", help: browser.folded ? "Show Sidebar   ⌘S" : "Hide Sidebar   ⌘S") {
                        browser.toggleFold()
                    }
                    .padding(.trailing, 4)
                }
                Helm(browser: browser)
                AddressBar(browser: browser, prefs: prefs)
                    .padding(.horizontal, 6)
                    .layoutPriority(1)
                ExtensionSlot()
                Door(icon: "sparkle", on: browser.chatting, help: "Chat about this page") {
                    browser.togglePageChat()
                }
                .disabled(!browser.pageChatPossible)
                .opacity(browser.pageChatPossible ? 1 : 0.3)
                // Beside a sidebar, bookmarks live at its foot instead (see Sidebar).
                if !prefs.sidebar {
                    Door(icon: "bookmark", help: "Bookmarks") { browser.bookmarksOpen.toggle() }
                        .menuPanel(isPresented: $browser.bookmarksOpen, edge: .bottom) {
                            BookmarksDropdown(browser: browser, bookmarks: browser.bookmarks)
                        }
                }
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Navigation

/// Back, forward and reload (stop while loading) for the tab in front.
struct Helm: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if let tab = browser.active {
            NavigationButtons(browser: browser, tab: tab)
        } else {
            // The same buttons, dimmed and dead, so nothing moves when a tab comes.
            HStack(spacing: 2) {
                ForEach(["chevron.left", "chevron.right", "arrow.clockwise"], id: \.self) { Door(icon: $0) {} }
            }
            .opacity(0.3)
            .allowsHitTesting(false)
        }
    }

    private struct NavigationButtons: View {
        let browser: Browser
        @ObservedObject var tab: Tab

        private struct Action {
            let symbol: String
            let help: String
            let usable: Bool
            let act: () -> Void
        }

        private var buttons: [Action] {
            let page = !tab.isBlank
            return [
                Action(symbol: "chevron.left", help: "Back   ⌘[", usable: page && tab.canGoBack, act: browser.back),
                Action(symbol: "chevron.right", help: "Forward   ⌘]", usable: page && tab.canGoForward, act: browser.forward),
                tab.loading
                    ? Action(symbol: "xmark", help: "Stop   ⌘.", usable: page, act: tab.stop)
                    : Action(symbol: "arrow.clockwise", help: "Reload   ⌘R", usable: page, act: browser.reload),
            ]
        }

        var body: some View {
            HStack(spacing: 2) {
                ForEach(buttons, id: \.help) { button in
                    Door(icon: button.symbol, help: button.help, act: button.act).disabled(!button.usable).opacity(button.usable ? 1 : 0.3)
                }
            }
            .animation(Motion.quick, value: tab.canGoBack)
            .animation(Motion.quick, value: tab.canGoForward)
            .animation(Motion.quick, value: tab.loading)
        }
    }
}

// MARK: - Address

/// The page's address in the toolbar, across all the room the bar has: its
/// site, quietly, until clicked; then the full address, selected, with
/// suggestions below it.
struct AddressBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @State private var hovering = false
    @State private var shake: CGFloat = 0

    private var editing: Bool { browser.editingInBar }

    var body: some View {
        HStack(spacing: 7) {
            if let tab = browser.active, !editing {
                SiteButton(browser: browser, tab: tab)
            } else {
                Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted).frame(
                    width: 16)
            }
            if editing {
                AddressField(browser: browser, size: 13, placeholder: "Search or enter address") {
                    browser.dismiss()
                }
                .frame(height: 18)
                .transition(.opacity)
            } else if let tab = browser.active {
                Shown(tab: tab, whole: prefs.showsFullAddress)
                    .transition(.opacity)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(height: Metrics.button)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Rounded.row.fill(Palette.veil.opacity(editing ? 1.6 : hovering ? 1 : 0))
        }
        .overlay { Rounded.row.strokeBorder(Palette.ink.opacity(editing ? 0.14 : 0)).allowsHitTesting(false) }
        .contentShape(Rounded.row)
        .onTapGesture {
            guard !editing else { return }
            if browser.active?.isStart != false { browser.field.askFocus() } else { browser.edit() }
        }
        .onHover { hovering = $0 }
        .background(KeepZone())
        .anchorPreference(key: AddressBar.Bounds.self, value: .bounds) { $0 }
        .shakesOnRefusal(browser.field.refusals, while: editing, travel: $shake)
        .help(editing ? "" : "Edit the address   ⌘L")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.glide, value: editing)
    }

    /// Where the bar is, so the suggestions can open under it (see `PageCard`).
    struct Bounds: PreferenceKey {
        static let defaultValue: Anchor<CGRect>? = nil
        static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
            value = value ?? nextValue()
        }
    }

    /// The address of the page, or a prompt on a blank tab.
    private struct Shown: View {
        @ObservedObject var tab: Tab
        let whole: Bool

        var body: some View {
            Group {
                if let url = tab.address {
                    Text(AddressBar.display(url, whole: whole))
                        .foregroundStyle(Palette.ink.opacity(0.88))
                } else if let chat = tab.chat {
                    Text(chat.title)
                        .foregroundStyle(Palette.ink.opacity(0.88))
                } else {
                    Text("Search or enter address")
                        .foregroundStyle(Palette.muted)
                }
            }
            .font(.system(size: 13))
            .lineLimit(1)
            .truncationMode(.middle)
        }
    }

    /// What the bar shows for an address (see `Address.shown`).
    static func display(_ url: URL, whole: Bool) -> String { Address.shown(url, whole: whole) }
}

/// The connection's padlock at the start of the address, which opens the site
/// card (security, zoom, print) below it.
private struct SiteButton: View {
    let browser: Browser
    @ObservedObject var tab: Tab

    @State private var hovering = false

    private var symbol: (name: String, tint: Color) {
        switch tab.address?.scheme?.lowercased() {
        case "https": ("lock.fill", Palette.muted)
        case "http": ("exclamationmark.triangle.fill", Palette.unsafe)
        case nil: ("magnifyingglass", Palette.muted)
        default: ("globe", Palette.muted)
        }
    }

    var body: some View {
        Button {
            SiteCardPanel.toggle(for: tab, in: browser)
        } label: {
            Image(systemName: symbol.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(symbol.tint)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Palette.veil.opacity(hovering ? 1.4 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(Pressed())
        .disabled(tab.isBlank)
        .onHover { hovering = $0 }
        .background(SiteCardAnchor())
        .help("Site Information")
        .accessibilityLabel("Site Information")
        .animation(Motion.hover, value: hovering)
    }
}

/// A hairline along the bottom of the toolbar that fills as the page loads,
/// then fades, as Safari's does.
private struct LoadLine: View {
    @ObservedObject var tab: Tab

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(Palette.ink.opacity(0.45))
                .frame(width: geo.size.width * max(0.08, tab.progress), height: 2)
                .opacity(tab.loading && !tab.isBlank ? 1 : 0)
                .animation(tab.loading ? .easeOut(duration: 0.25) : .easeOut(duration: 0.3).delay(0.1), value: tab.progress)
                .animation(.easeOut(duration: 0.25), value: tab.loading)
        }
        .frame(height: 2)
    }
}

// MARK: - Suggestions

/// The suggestions under the toolbar's address field, as wide as the field.
struct BarSuggestions: View {
    @ObservedObject var browser: Browser
    let bar: CGRect

    var body: some View {
        SuggestionList(browser: browser)
            .background(KeepZone())
            .frame(width: bar.width)
            .offset(x: bar.minX, y: bar.maxY + 6)
    }
}

// MARK: - Clicks Outside

/// Marks a region where a click doesn't end address editing (the field itself,
/// its suggestions). See `AddressField.outside`.
struct KeepZone: NSViewRepresentable {
    @MainActor static let views = NSHashTable<NSView>.weakObjects()

    func makeNSView(context: Context) -> NSView {
        let view = Zone()
        KeepZone.views.add(view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}

    /// Whether a click in `window` at `point` (window coordinates) lands in a zone.
    @MainActor static func contains(_ point: NSPoint, in window: NSWindow?) -> Bool {
        views.allObjects.contains { view in
            view.window === window && view.bounds.contains(view.convert(point, from: nil))
        }
    }

    private final class Zone: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A press that sinks the control slightly, for the toolbar's buttons.
struct Pressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}
