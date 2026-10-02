import MoteAI
import MoteCore
import SwiftUI

/// The chat about the page showing, docked on the window's trailing edge as the
/// mirror of the sidebar: full height, on the frame, the page card losing width
/// beside it.
///
/// The page is taken up as the panel opens: the chip shows it at once with its
/// address and title, and its text is read a moment later, so the model always
/// answers about the page on screen. The chip lets the page go, and offers it
/// again once it has.
struct PageChatPanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var tab: Tab

    /// The brand moment on opening: a short breath of the logo's light.
    @State private var glowing = false

    /// Whether the conversation is built. It is kept through the close slide,
    /// so the panel does not empty as it goes, and dropped after it, so a chat
    /// the panel is not showing never takes the keyboard (see ChatView's
    /// `onAppear`).
    @State private var filled = false

    /// Whether this page may be shared with the assistant at all.
    private var shareable: Bool { PageSharing.canShare(tab.address) }

    var body: some View {
        Group {
            if let chat = tab.pageChat, tab.chatOpen || filled {
                ChatView(
                    browser: browser, conversation: chat,
                    accessory: { chip(chat) },
                    start: { start() },
                    beforeSend: { await shareIfNeeded() },
                    ground: Palette.frame,
                    seed: tab.pendingAsk,
                    took: { tab.pendingAsk = nil }
                )
                .id(chat.id)
            } else {
                Palette.frame
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // On the window's frame, like the sidebar it mirrors; the ask glow
            // gathers behind the panel on opening.
            Palette.frame
            AskAura(on: glowing)
        }
        .onAppear {
            // The panel is in the tree as soon as a page shows; the brand
            // moment is for the moment it is opened, not merely built.
            if tab.chatOpen { show() }
        }
        .onChange(of: tab.chatOpen) { _, open in
            if open {
                show()
            } else {
                // Let the conversation ride the slide out, then let it go. The
                // check reads the live state, so reopening (or a tab whose own
                // panel is open taking over) keeps the conversation.
                Task {
                    try? await Task.sleep(for: .seconds(Motion.foldResponse))
                    if !browser.chatting { filled = false }
                }
            }
        }
    }

    /// Brings the conversation out and plays the brand moment.
    private func show() {
        filled = true
        glow()
    }

    // MARK: - What is shared

    /// The chip over the composer: the page shared, or the way to share it.
    @ViewBuilder
    private func chip(_ chat: Conversation) -> some View {
        // With nothing kept and nothing shareable, the empty state says so;
        // there is no chip to stand above a composer no page can reach.
        if chat.page != nil || shareable {
            HStack(spacing: 7) {
                if let page = chat.page {
                    if page.isActive {
                        attached(page)
                    } else {
                        offer("Share the page again")
                    }
                    Spacer(minLength: 4)
                    if page.isActive {
                        Button {
                            tab.detachPage()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.muted)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Stop sharing this page")
                        .accessibilityLabel("Stop sharing this page")
                    }
                } else {
                    offer("Share this page")
                    Spacer(minLength: 0)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 6)
            .frame(height: 30)
            .frame(maxWidth: ChatView<EmptyView, EmptyView>.column, alignment: .leading)
            .background(Palette.wash, in: Rounded.card)
            .overlay(Rounded.card.strokeBorder(Palette.hairline))
        }
    }

    /// The page in hand: its icon and name, or its host when it has no title.
    private func attached(_ page: PageContext) -> some View {
        HStack(spacing: 7) {
            icon
            Text(page.title.isEmpty ? (page.url.host() ?? page.url.absoluteString) : page.title)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    /// The way back to sharing, once the page has been let go.
    private func offer(_ title: String) -> some View {
        Button {
            share()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 10, weight: .medium))
                Text(title).font(.system(size: 12))
            }
            .foregroundStyle(Palette.muted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Share the page with the assistant")
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private var icon: some View {
        if let image = tab.icon {
            Image(nsImage: image).resizable().frame(width: 14, height: 14)
        } else {
            Image(systemName: "globe")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
                .frame(width: 14, height: 14)
        }
    }

    // MARK: - The empty conversation

    /// What stands in for the conversation before the first question: the
    /// page's name, and three ways in.
    @ViewBuilder
    private func start() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ask about this page")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Palette.ink)
            if let title = heading {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if shareable {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Self.suggestions, id: \.title) { suggestion in
                        Suggestion(suggestion.title) { ask(suggestion.prompt) }
                    }
                }
                .padding(.top, 2)
            } else {
                Text("Mote can't read this page, but you can still ask about it.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The page's own name, from its title or its address.
    private var heading: String? {
        let title = tab.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return tab.address?.host()
    }

    /// Three ways in, each a question the shared page answers. The wording is
    /// the `/` skills' own, so the two never drift.
    private static let suggestions: [(title: String, prompt: String)] = [
        (Skill.summary.title, Skill.summary.prompt),
        (Skill.eli5.title, Skill.eli5.prompt),
        (Skill.keypoints.title, Skill.keypoints.prompt),
    ]

    // MARK: - Sharing

    /// The page is taken up as the panel opens; this reads its text if the
    /// first question beats that read, so the model is never asked about a
    /// page it cannot see. A page let go is left let go.
    private func shareIfNeeded() async {
        guard let page = tab.pageChat?.page, page.isActive, page.text == nil else { return }
        await tab.attachCurrentPage()
    }

    private func share() {
        Task { await tab.attachCurrentPage() }
    }

    /// A quick action asks directly; the page is shared first, as a first
    /// question would.
    private func ask(_ prompt: String) {
        guard let chat = tab.pageChat else { return }
        Task {
            await shareIfNeeded()
            Assistant.shared.ask(prompt, in: chat)
        }
    }

    /// The brand moment: the logo's light gathers behind the panel and settles.
    private func glow() {
        guard !glowing else { return }
        Task {
            glowing = true
            try? await Task.sleep(for: .seconds(2.6))
            glowing = false
        }
    }
}

/// One of the empty conversation's ways in: a quiet row that asks.
private struct Suggestion: View {
    let title: String
    let act: () -> Void

    @State private var hovering = false

    init(_ title: String, act: @escaping () -> Void) {
        self.title = title
        self.act = act
    }

    var body: some View {
        Button(action: act) {
            HStack(spacing: 9) {
                Image(systemName: "sparkle").font(.system(size: 10.5, weight: .medium))
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.ink.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(hovering ? Palette.hover : Palette.wash, in: Rounded.card)
            .contentShape(Rounded.card)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}
