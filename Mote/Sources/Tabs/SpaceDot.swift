import MoteCore
import SwiftUI

/// This space's icon; a click opens the spaces menu. The icon slides the
/// way the spaces moved.
struct SpaceDot: View {
    @ObservedObject var browser: Browser
    @State private var hovering = false
    /// The icon on show, changed a turn after the space: `SpaceSwipe.slide`
    /// switches with animations off, so the icon needs its own transaction.
    @State private var shown: (key: String, symbol: String)?

    static let width: CGFloat = 26

    private var symbol: String { browser.makingSpace ? "plus" : browser.space.symbol }
    private var key: String { browser.makingSpace ? "new" : "\(browser.spaceID.uuidString)-\(browser.space.symbol)" }

    /// Sideways in the sidebar, up and down in the strip.
    private var arrival: Edge {
        let forward = browser.spaceStep > 0
        return browser.prefs.sidebar ? (forward ? .trailing : .leading) : (forward ? .bottom : .top)
    }

    var body: some View {
        Button {
            SpaceMenu.show(for: browser)
        } label: {
            Image(systemName: shown?.symbol ?? symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                .id(shown?.key ?? key)
                .transition(.push(from: arrival))
                .frame(width: Self.width, height: 26)
                .clipped()
                .background(hovering ? Palette.hover : .clear, in: Rounded.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(browser.space.name). Switch with ⌃1–⌃9, or two fingers \(browser.prefs.sidebar ? "sideways" : "up or down") over the tabs")
        .onChange(of: key) { _, now in
            let symbol = symbol
            Task { @MainActor in withAnimation(.easeOut(duration: 0.22)) { shown = (now, symbol) } }
        }
        .animation(Motion.quick, value: hovering)
    }
}
