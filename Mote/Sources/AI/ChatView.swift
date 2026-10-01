import MoteAI
import SwiftUI

/// A chat in a tab: the conversation in a readable column, and a composer
/// along the bottom for the next message. Questions sit in bubbles on the
/// right; answers read as plain text, signed with who wrote them.
///
/// Its two slots are for the page chat: `start` stands in for the empty
/// conversation (its quick actions), and `accessory` sits above the composer
/// (its context chip). A blank tab's chat leaves both empty.
struct ChatView<Accessory: View, Start: View>: View {
    let browser: Browser
    let conversation: Conversation
    @ViewBuilder let accessory: () -> Accessory
    @ViewBuilder let start: () -> Start
    /// Run before a question goes, so the page chat can share the page on its
    /// first turn; the question waits for it.
    var beforeSend: (() async -> Void)? = nil
    /// The surface the conversation reads on: the card for a chat in a tab, the
    /// window frame for the page chat docked on it, the mirror of the sidebar.
    var ground: Color = Palette.ground

    @State private var draft = ""
    @State private var inputHeight = ChatInput.line
    @State private var focus = 0
    /// How far the end of the conversation is below the view: only which
    /// zone, so scrolling changes it a few times rather than every frame.
    @State private var distance = ScrollDistance.end
    /// Keeping to the end as the reply grows; scrolling up to read lets go,
    /// and coming back down takes it up again.
    @State private var pinned = true

    static var column: CGFloat { 720 }
    private static var end: String { "end" }

    var body: some View {
        ScrollViewReader { scroller in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        if conversation.messages.isEmpty { start() }
                        ForEach(conversation.messages) { message in
                            let last = message.id == conversation.messages.last?.id
                            MessageRow(message: message, last: last, streaming: last && conversation.busy).equatable()
                                .environment(\.chatActions, actions)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                        Status(browser: browser, conversation: conversation, retry: retry)
                        // Room for the composer over the end; scrolling to it shows the last line above the composer.
                        Color.clear.frame(height: inputHeight + 96).id(Self.end)
                            .onGeometryChange(for: ScrollDistance.self) { proxy in
                                let view = proxy.bounds(of: .named("chat"))?.height ?? 0
                                return ScrollDistance(below: proxy.frame(in: .named("chat")).maxY - view)
                            } action: {
                                distance = $0
                            }
                    }
                    .frame(maxWidth: Self.column, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                    .animation(Motion.settle, value: conversation.messages.count)
                }
                .coordinateSpace(name: "chat")
                // Follows the reply as it grows, unless scrolled up to read.
                .onChange(of: conversation.messages.last?.text) {
                    if pinned { scroller.scrollTo(Self.end, anchor: .bottom) }
                }
                .onChange(of: conversation.messages.count) {
                    pinned = true
                    withAnimation(Motion.settle) { scroller.scrollTo(Self.end, anchor: .bottom) }
                }
                .onChange(of: distance) { _, now in if now == .end { pinned = true } }
                .onScrollUp { pinned = false }

                VStack(spacing: 10) {
                    if distance == .far {
                        JumpDown {
                            pinned = true
                            withAnimation(Motion.glide) { scroller.scrollTo(Self.end, anchor: .bottom) }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
                    accessory()
                    ChatComposer(
                        browser: browser, conversation: conversation, draft: $draft, height: $inputHeight, focus: focus,
                        send: send
                    )
                    .frame(maxWidth: Self.column)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity)
                .background(alignment: .bottom) {
                    // The conversation fades out under the composer.
                    LinearGradient(colors: [ground.opacity(0), ground], startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                        .frame(height: inputHeight + 110)
                        .allowsHitTesting(false)
                }
                .animation(Motion.quick, value: distance == .far)
            }
        }
        .background(ground)
        .onAppear { focus += 1 }
        .environment(
            \.openURL,
            OpenURLAction { url in
                // From the chat's tab, so a private chat's links open privately.
                browser.open(url, foreground: true, from: browser.active)
                return .handled
            })
    }

    private var actions: ChatActions { ChatActions(retry: retry) }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        guard let beforeSend else { return Assistant.shared.ask(text, in: conversation) }
        Task {
            await beforeSend()
            Assistant.shared.ask(text, in: conversation)
        }
    }

    private func retry() { Assistant.shared.retry(in: conversation) }

}

extension ChatView where Accessory == EmptyView, Start == EmptyView {
    /// A chat with no page slots: the blank tab's, as before.
    init(browser: Browser, conversation: Conversation) {
        self.init(browser: browser, conversation: conversation, accessory: { EmptyView() }, start: { EmptyView() })
    }
}

/// How far below the view the end of the conversation is.
nonisolated enum ScrollDistance: Equatable, Sendable {
    /// At the end, or nearly: following the reply.
    case end
    /// A little way up.
    case near
    /// Far enough up to offer the way back down.
    case far

    init(below: CGFloat) {
        self = below < 24 ? .end : below < 240 ? .near : .far
    }
}

/// What a message's buttons do, handed down to the rows.
struct ChatActions {
    var retry: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var chatActions = ChatActions()
}

// MARK: - Messages

/// One message. Equatable, so a streaming reply redraws only itself.
private struct MessageRow: View, Equatable {
    let message: Message
    let last: Bool
    let streaming: Bool

    var body: some View {
        switch message.role {
        case .user: Question(text: message.text)
        case .assistant: Answer(message: message, last: last, streaming: streaming)
        }
    }
}

private struct Question: View {
    let text: String
    @State private var pointer = Pointer()

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 90)
            Revealed(pointer: pointer) { CopyButton(text: text) }
            Text(text)
                .font(.system(size: MarkdownView.size))
                .lineSpacing(MarkdownView.leading)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .onHover { pointer.over = $0 }
    }
}

/// Whether the pointer is over a message, kept apart from the message so
/// only what shows on hover redraws when it changes.
@MainActor
@Observable
private final class Pointer {
    var over = false
}

/// Content shown while the pointer is over its message.
private struct Revealed<Content: View>: View {
    let pointer: Pointer
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().opacity(pointer.over ? 1 : 0).animation(Motion.hover, value: pointer.over)
    }
}

/// Copy, and ask again for the last answer: always there on the last,
/// on hover on the others.
private struct AnswerButtons: View {
    let text: String
    let last: Bool
    let retry: () -> Void
    let pointer: Pointer

    var body: some View {
        HStack(spacing: 2) {
            CopyButton(text: text)
            if last { RetryButton(act: retry) }
        }
        .padding(.leading, -7)
        .opacity(pointer.over || last ? 1 : 0)
        .animation(Motion.hover, value: pointer.over)
    }
}

private struct Answer: View {
    let message: Message
    let last: Bool
    /// Still arriving: its buttons wait until it's done.
    let streaming: Bool

    @Environment(\.chatActions) private var actions
    /// Read only by the buttons: the answer's own body doesn't redraw as the
    /// pointer comes and goes, which scrolling past does all the time.
    @State private var pointer = Pointer()
    @State private var thoughtsOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let author = message.author {
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 9.5, weight: .semibold))
                    Text(author).font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(Palette.muted)
            }
            // Kept from draw to draw (hovering redraws this): it reads the whole
            // reply for links and matches them against every source.
            let rendered = RenderedReply.of(message, searched: searched)
            let (text, entries) = (rendered.text, rendered.entries)
            if message.steps.contains(where: { $0.kind == .task || $0.kind == .phase }) {
                ResearchProgress(steps: message.steps, live: streaming)
            } else if !message.steps.isEmpty {
                StepsSummary(steps: message.steps)
            }
            if !entries.isEmpty { SourcesStrip(entries: entries).padding(.bottom, 2) }
            if !message.reasoning.isEmpty { thoughts }
            if !text.isEmpty { ReplyText(text: text, cites: rendered.cites, reply: message.id, streaming: streaming) }
            if message.interrupted {
                Text("Stopped").font(.system(size: 11.5)).foregroundStyle(Palette.muted)
            }
            if !message.text.isEmpty, !streaming {
                AnswerButtons(text: message.text, last: last, retry: actions.retry, pointer: pointer)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { pointer.over = $0 }
    }

    /// A reply that looked things up on the web, whose links are citations.
    private var searched: Bool { !message.sources.isEmpty || message.steps.contains { $0.kind != .tool } }

    /// The model's thinking, folded away unless asked for.
    private var thoughts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(Motion.settle) { thoughtsOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text(message.text.isEmpty && !message.interrupted ? "Thinking" : "Thought it through")
                        .font(.system(size: 12.5))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .rotationEffect(.degrees(thoughtsOpen ? 90 : 0))
                }
                .foregroundStyle(Palette.muted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if thoughtsOpen {
                Text(message.reasoning.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.muted)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) { Capsule().fill(Palette.hairline).frame(width: 2) }
                    .transition(.opacity)
            }
        }
    }
}

/// A reply's words: as it streams in, shown by a typewriter at a reader's
/// pace, each word fading in; the rest of the answer doesn't redraw as they
/// come, since only this reads the typewriter.
private struct ReplyText: View {
    let text: String
    let cites: [String: String]
    let reply: UUID
    let streaming: Bool
    @State private var typewriter = Typewriter()

    var body: some View {
        let shown = typewriter.busy || streaming ? typewriter.shown : text
        MarkdownView(
            text: shown, cites: cites, reply: reply,
            tail: typewriter.busy || streaming ? MarkdownView.Tail(fresh: typewriter.fresh) : nil
        )
        .equatable()
        .onAppear { typewriter.follow(text, finished: !streaming) }
        .onChange(of: text) { _, text in typewriter.follow(text, finished: !streaming) }
        .onChange(of: streaming) { _, streaming in typewriter.follow(text, finished: !streaming) }
    }
}

private struct RetryButton: View {
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(hovering ? Palette.ink.opacity(0.8) : Palette.muted)
                .frame(width: 26, height: 22)
                .background(hovering ? Palette.veil : .clear, in: Rounded.row)
                .contentShape(Rounded.row)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Ask again")
        .accessibilityLabel("Ask again")
        .animation(Motion.hover, value: hovering)
    }
}

// MARK: - Status

/// Under the last message: that the model is thinking or busy, or why the
/// reply failed and what to do about it.
private struct Status: View {
    let browser: Browser
    let conversation: Conversation
    let retry: () -> Void

    var body: some View {
        Group {
            switch conversation.phase {
            case .waiting where researching, .answering where researching:
                // The research card above shows its own progress.
                EmptyView()
            case .waiting:
                Working(title: conversation.activities.last(where: { !$0.done })?.title ?? waitingWords)
            case .answering:
                if let activity = conversation.activities.last(where: { !$0.done }) {
                    Working(title: activity.title)
                } else if conversation.messages.last?.text.isEmpty != false {
                    Working(title: "Thinking")
                }
            case .failed(let reason):
                Failure(reason: reason, retry: retry) { browser.openSettings(at: .ai) }
            case .idle:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(Motion.quick, value: conversation.phase)
    }

    private var researching: Bool {
        conversation.messages.last?.steps.contains { $0.kind == .phase } == true && conversation.messages.last?.text.isEmpty != false
    }

    private var waitingWords: String {
        conversation.messages.last?.reasoning.isEmpty == false ? "Thinking" : "Asking \(Assistant.shared.provider.name)"
    }
}

/// A line of shimmering words while waiting.
private struct Working: View {
    let title: String
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "sparkle").font(.system(size: 10, weight: .semibold))
            Text(title + "…").font(.system(size: 13))
        }
        .foregroundStyle(Palette.muted)
        .overlay {
            if !still {
                GeometryReader { geo in
                    LinearGradient(
                        colors: [.clear, Palette.ground.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.5)
                    .offset(x: sweep ? geo.size.width : -geo.size.width * 0.5)
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { sweep = true }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct Failure: View {
    let reason: String
    let retry: () -> Void
    let settings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.unsafe)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 9) {
                Text(reason)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Pill("Try Again", filled: true, action: retry)
                    Pill("AI Settings…", action: settings)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.wash.opacity(0.55), in: Rounded.card)
        .overlay(Rounded.card.strokeBorder(Palette.hairline))
    }
}

private struct JumpDown: View {
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.ink.opacity(hovering ? 0.9 : 0.7))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.ground).shadow(color: .black.opacity(0.12), radius: 8, y: 3))
                .overlay(Circle().strokeBorder(Palette.hairline))
                .contentShape(Circle())
        }
        .buttonStyle(Pressed())
        .onHover { hovering = $0 }
        .help("Go to the latest")
        .accessibilityLabel("Go to the latest")
    }
}

// MARK: - Composer

/// The next message, and who it goes to, in the same rounded box as the new
/// tab's composer. While a reply comes, the send button stops it.
private struct ChatComposer: View {
    let browser: Browser
    let conversation: Conversation
    @Binding var draft: String
    @Binding var height: CGFloat
    let focus: Int
    let send: () -> Void

    private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatInput(
                text: $draft, height: $height, placeholder: "Ask a follow-up", focus: focus,
                submit: { if !conversation.busy || hasText { send() } },
                escape: {
                    guard conversation.busy else { return false }
                    conversation.stop()
                    return true
                }
            )
            .frame(height: height)
            .overlay(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Ask a follow-up")
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.ink.opacity(0.35))
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 8) {
                ToolToggles()
                Spacer(minLength: 0)
                AIChip(browser: browser)
                if conversation.busy, !hasText {
                    RoundButton(symbol: "stop.fill", filled: true, help: "Stop   esc") { conversation.stop() }
                } else {
                    RoundButton(symbol: "arrow.up", filled: hasText, help: "Send   ↩", act: send)
                }
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Palette.ground)
                .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
                .shadow(color: .black.opacity(0.08), radius: 22, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1).allowsHitTesting(false)
        }
        .animation(Motion.quick, value: conversation.busy)
    }
}

/// The composer's round button: send, or stop while a reply comes.
struct RoundButton: View {
    let symbol: String
    let filled: Bool
    let help: String
    let act: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: act) {
            Image(systemName: symbol)
                .font(.system(size: symbol == "stop.fill" ? 10 : 13, weight: .semibold))
                .foregroundStyle(filled ? Palette.ground : Palette.muted)
                .frame(width: 30, height: 30)
                .background(Circle().fill(filled ? Palette.ink.opacity(hovering ? 0.8 : 1) : Palette.veil))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(Pressed())
        .disabled(!filled)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help.components(separatedBy: "   ")[0])
        .animation(Motion.quick, value: filled)
        .animation(Motion.hover, value: hovering)
    }
}

/// What an answer shows, worked out from its message once and kept until
/// the message changes: the text without a closing list of sources, the
/// sources to list, and the chip name for each cited page.
@MainActor
struct RenderedReply {
    let text: String
    let entries: [Citations.Entry]
    let cites: [String: String]

    private static var kept: [UUID: (key: [Int], reply: RenderedReply)] = [:]

    static func of(_ message: Message, searched: Bool) -> RenderedReply {
        // The text only grows while it streams, so its length tells versions apart.
        let key = [message.text.utf8.count, message.sources.count, searched ? 1 : 0]
        if let kept = kept[message.id], kept.key == key { return kept.reply }
        let text = searched ? Citations.shown(message.text) : message.text
        let entries = searched ? Citations.arrange(message.sources, for: text) : []
        let cites = Dictionary(
            entries.filter { $0.number != nil }.map { ($0.source.id, $0.source.brand) }, uniquingKeysWith: { first, _ in first })
        let reply = RenderedReply(text: text, entries: entries, cites: cites)
        if kept.count > 200 { kept.removeAll() }
        kept[message.id] = (key, reply)
        return reply
    }
}
