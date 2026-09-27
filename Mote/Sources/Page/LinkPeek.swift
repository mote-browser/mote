import SwiftUI

// Shift-clicking a link shows it over the page instead of leaving it
// (Settings › General, off by default: some sites use shift-click). The
// preview is a tab of its own that isn't in the list yet, so keeping it
// doesn't load it again.

extension Browser {
    func peek(_ url: URL, from tab: Tab) {
        let preview = Tab(shy: tab.shy)
        prepare(preview)
        preview.go(to: url)
        withAnimation(Motion.settle) { peekTab = preview }
    }

    func closePeek() {
        guard let preview = takePeek() else { return }
        preview.close()
    }

    /// The preview becomes a tab after the one it came from, and is picked.
    func keepPeek() {
        let place = placeForNew()
        guard let preview = takePeek() else { return }
        insert(preview, at: place)
        select(preview)
    }

    private func takePeek() -> Tab? {
        defer { withAnimation(Motion.quick) { peekTab = nil } }
        return peekTab
    }
}

/// The page dimmed, with the preview over it.
struct PeekLayer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        ZStack {
            // The dimming only fades: grown with the preview, its edges would move.
            if browser.peekTab != nil {
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: browser.closePeek)
                    .transition(.opacity)
            }
            if let preview = browser.peekTab {
                PeekCard(browser: browser, preview: preview)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
    }
}

private struct PeekCard: View {
    @ObservedObject var browser: Browser
    @ObservedObject var preview: Tab

    private static let widthShare: CGFloat = 0.82
    private static let heightShare: CGFloat = 0.86
    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        GeometryReader { room in
            HStack(alignment: .top, spacing: 10) {
                Page(tab: preview)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
                VStack(spacing: 8) {
                    Bubble(icon: "xmark", help: "Close (esc)", act: browser.closePeek)
                    Bubble(icon: "arrow.up.left.and.arrow.down.right", help: "Open as a tab", act: browser.keepPeek)
                }
            }
            .frame(width: room.size.width * Self.widthShare, height: room.size.height * Self.heightShare)
            // Half the buttons' column over, so the page itself sits in the middle.
            .offset(x: 21)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A round button beside the preview.
private struct Bubble: View {
    let icon: String
    let help: String
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .frame(width: 28, height: 28)
                .background(hovering ? Palette.hover : Palette.ground, in: Circle())
                .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}
