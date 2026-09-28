import SwiftUI

/// A tab's close button: there on hover, with a hit area bigger than its cross.
struct Shut: View {
    let shown: Bool
    let act: () -> Void

    @State private var hovering = false

    var body: some View {
        ZStack {
            if shown {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(hovering ? Palette.ink.opacity(0.8) : Palette.muted)
                    .frame(width: 18, height: 18)
                    .background(Palette.veil.opacity(hovering ? 1.8 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .frame(width: 18, height: 18)
        .overlay {
            Color.clear
                .frame(width: 30, height: 28)
                .contentShape(Rectangle())
                .onTapGesture { if shown { act() } }
                .onHover { hovering = $0 }
        }
        .help(shown ? "Close Tab   ⌘W" : "")
        .accessibilityLabel("Close Tab")
        .animation(Motion.hover, value: hovering)
        .animation(Motion.hover, value: shown)
    }
}

/// Mutes or unmutes a tab that's playing sound, or has been muted.
struct Speaker: View {
    @ObservedObject var tab: Tab
    @State private var hovering = false

    var body: some View {
        Button(action: tab.toggleMute) {
            Image(systemName: tab.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 8))
                .foregroundStyle(Palette.muted)
                .frame(width: 15, height: 15)
                .background(Palette.veil.opacity(hovering ? 1.4 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tab.muted ? "Unmute Tab" : "Mute Tab")
        .animation(Motion.quick, value: hovering)
    }
}

/// Small marks before a tab's title: a flask on the bench's tabs, a crossed
/// eye on private ones.
struct TabMarks: View {
    @ObservedObject var tab: Tab
    let colour: Color

    var body: some View {
        ForEach([tab.bench ? "flask" : nil, tab.shy ? "eye.slash" : nil].compactMap { $0 }, id: \.self) {
            Image(systemName: $0).font(.system(size: 9)).foregroundStyle(colour.opacity(0.7))
        }
    }
}

/// A title that fades out at its end rather than trailing off in an
/// ellipsis. It takes whatever room its row leaves and never pushes the
/// buttons after it out.
struct FadingTitle: View {
    let text: String
    var font = Font.system(size: 12.5)
    let colour: Color

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 16)
            .overlay(alignment: .leading) {
                Text(text).font(font).foregroundStyle(colour).lineLimit(1).fixedSize()
            }
            .clipped()
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 18)
                }
            }
    }
}

/// The active tab's ground in the sidebar: the card's colour lifted off the
/// frame by a hairline and a soft shadow, so it reads as part of the page.
struct Lifted<Content: View>: View {
    let corner: CGFloat
    let content: Content

    init(corner: CGFloat, @ViewBuilder content: () -> Content = { EmptyView() }) {
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .leading) {
            shape.fill(Palette.lift)
            content
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.edge, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.07), radius: 1, y: 0.5)
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// A tab's context menu.
struct TabMenu: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab
    let close: () -> Void

    var body: some View {
        if tab.pin == nil {
            Button("Pin") { browser.pin(tab) }.disabled(tab.isBlank)
        } else {
            Button("Change Letter") { browser.editLetter(tab) }
            Button("Unpin") { browser.unpin(tab) }
        }
        Divider()
        Button("Rename") { browser.beginTabRename(tab) }
        Group {
            Button("Duplicate") { onThisTab(browser.duplicate) }
            // The site card that hangs from the toolbar's padlock.
            Button("Site Information…") {
                if browser.activeID != tab.id { browser.select(tab) }
                SiteCardPanel.open(for: tab, in: browser)
            }
            Button("Copy Address") { onThisTab(browser.copyAddress) }
            Button("Copy as Markdown Link") { onThisTab(browser.copyMarkdownLink) }
        }
        .disabled(tab.isBlank)
        Button(tab.muted ? "Unmute Tab" : "Mute Tab") { tab.toggleMute() }
        Divider()
        Button("Close Tab", action: close)
        Button("Close Other Tabs") { browser.closeOthers(but: tab) }.disabled(browser.tabs.count < 2)
        Button("Reopen Closed Tab") { browser.reopen() }.disabled(browser.ghosts.isEmpty)
    }

    /// The window's actions work on the tab in front, so this one comes first.
    private func onThisTab(_ act: () -> Void) {
        browser.select(tab)
        act()
    }
}

extension View {
    /// A short sideways shake whenever `refusals` goes up while `editing`.
    func shakesOnRefusal(_ refusals: Int, while editing: Bool, travel: Binding<CGFloat>) -> some View {
        modifier(Shake(travel: travel.wrappedValue))
            .onChange(of: refusals) {
                guard editing else { return }
                travel.wrappedValue = 0
                withAnimation(.easeOut(duration: 0.5)) { travel.wrappedValue = 1 }
            }
    }
}

/// How far the page is read, as a thin line along the top of a tab in the row.
/// It watches only the reading, so scrolling redraws nothing else on the tab,
/// and it grows by scaling, which needs no layout, without animating: the
/// reading changes on most frames of a scroll, and a layout or an animation
/// in the window on each one makes the page's frames reach the screen unevenly.
struct ReadLine: View {
    @ObservedObject var reading: Reading
    let span: CGFloat

    var body: some View {
        Capsule()
            .fill(Palette.ink.opacity(0.3))
            .frame(width: span, height: 2)
            .scaleEffect(x: reading.fraction, anchor: .leading)
            .opacity(reading.fraction > 0 ? 1 : 0)
    }
}

/// How far the page is read, as a faint fill across a row in the sidebar;
/// scaled rather than laid out, as ReadLine is.
struct ReadFill: View {
    @ObservedObject var reading: Reading

    var body: some View {
        Rectangle().fill(Palette.ink.opacity(0.05))
            .scaleEffect(x: reading.fraction, anchor: .leading)
    }
}
