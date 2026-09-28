import MoteAI
import SwiftUI

/// A chat in a tab: the conversation in a readable column, and a composer
/// along the bottom for the next message. Questions sit in bubbles on the
/// right; answers read as plain text, signed with who wrote them.
struct ChatView: View {
    let browser: Browser
    let conversation: Conversation

    @State private var draft = ""
    @State private var inputHeight = ChatInput.line
    @State private var focus = 0
    /// Where the end of the conversation is, and the height of the view.
    @State private var end: CGFloat = 0
    @State private var viewport: CGFloat = 0
    /// Keeping to the end as the reply grows; scrolling up to read lets go,
    /// and coming back down takes it up again.
    @State private var pinned = true

    static let column: CGFloat = 720
    private static let end = "end"

    var body: some View {
        ScrollViewReader { scroller in
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(conversation.messages) { message in
                            let last = message.id == conversation.messages.last?.id
                            MessageRow(message: message, last: last, streaming: last && conversation.busy).equatable()
                                .environment(\.chatActions, actions)
                                .transition(.opacity.combined(with: .offset(y: 6)))
                        }
                        Status(browser: browser, conversation: conversation, retry: retry)
                        // Room for the composer over the end; scrolling to it shows the last line above the composer.
                        Color.clear.frame(height: inputHeight + 96).id(Self.end)
                            .onGeometryChange(for: CGFloat.self) {
                                $0.frame(in: .named("chat")).maxY
                            } action: {
                                end = $0
                            }
                    }
                    .frame(maxWidth: Self.column, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 32)
                    .frame(maxWidth: .infinity)
                    .animation(Motion.settle, value: conversation.messages.count)
                }
                .coordinateSpace(name: "chat")
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    viewport = $0
                }
                // Follows the reply as it grows, unless scrolled up to read.
                .onChange(of: conversation.messages.last?.text) {
                    if pinned { scroller.scrollTo(Self.end, anchor: .bottom) }
                }
                .onChange(of: conversation.messages.count) {
                    pinned = true
                    withAnimation(Motion.settle) { scroller.scrollTo(Self.end, anchor: .bottom) }
                }
                .onChange(of: below < 24) { _, atEnd in if atEnd { pinned = true } }
                .onScrollUp { pinned = false }

                VStack(spacing: 10) {
                    if below > 240 {
                        JumpDown {
                            pinned = true
                            withAnimation(Motion.glide) { scroller.scrollTo(Self.end, anchor: .bottom) }
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }
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
                    LinearGradient(colors: [Palette.ground.opacity(0), Palette.ground], startPoint: .top, endPoint: .init(x: 0.5, y: 0.45))
                        .frame(height: inputHeight + 110)
                        .allowsHitTesting(false)
                }
                .animation(Motion.quick, value: below > 240)
            }
        }
        .background(Palette.ground)
        .onAppear { focus += 1 }
        .environment(
            \.openURL,
            OpenURLAction { url in
                // From the chat's tab, so a private chat's links open privately.
                browser.open(url, foreground: true, from: browser.active)
                return .handled
            })
    }

    /// How far the end of the conversation is below the bottom of the view.
    private var below: CGFloat { end - viewport }

    private var actions: ChatActions { ChatActions(retry: retry) }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Assistant.shared.ask(text, in: conversation)
    }

    private func retry() { Assistant.shared.retry(in: conversation) }

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
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 90)
            CopyButton(text: text).opacity(hovering ? 1 : 0)
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
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }
}

private struct Answer: View {
    let message: Message
    let last: Bool
    /// Still arriving: its buttons wait until it's done.
    let streaming: Bool

    @Environment(\.chatActions) private var actions
    @State private var hovering = false
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
            if !message.reasoning.isEmpty { thoughts }
            if !message.text.isEmpty { MarkdownView(text: message.text) }
            if message.interrupted {
                Text("Stopped").font(.system(size: 11.5)).foregroundStyle(Palette.muted)
            }
            if !message.text.isEmpty, !streaming {
                HStack(spacing: 2) {
                    CopyButton(text: message.text)
                    if last { RetryButton(act: actions.retry) }
                }
                .padding(.leading, -7)
                .opacity(hovering || last ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hovering = $0 }
        .animation(Motion.hover, value: hovering)
    }

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
                ModelChip(browser: browser, eager: true)
                Spacer(minLength: 0)
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
