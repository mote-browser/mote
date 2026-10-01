import Foundation
import Observation

/// A chat: its messages, the reply on its way, and what went wrong.
///
/// It keeps the whole history itself, so any provider can take over at any
/// turn. Providers that keep their own sessions are handed theirs back, and
/// only need the new message.
@MainActor
@Observable
public final class Conversation: Identifiable {
    /// Where a message goes: the provider, its model, and the service that answers.
    public struct Route: Sendable {
        public var provider: String
        public var model: String
        /// Shown over the reply ("Claude Code · sonnet").
        public var author: String
        public var service: any ChatService
        public var instructions: String?
        /// Search the web for the answer.
        public var search: Bool

        public init(
            provider: String, model: String, author: String, service: any ChatService, instructions: String? = nil, search: Bool = false
        ) {
            self.provider = provider
            self.model = model
            self.author = author
            self.service = service
            self.instructions = instructions
            self.search = search
        }
    }

    public enum Phase: Equatable, Sendable {
        case idle
        /// Asked, and nothing back yet.
        case waiting
        /// The reply is arriving.
        case answering
        /// The last reply failed, for this reason.
        case failed(String)
    }

    public let id: UUID
    public private(set) var messages: [Message] = []
    public let created: Date
    /// When the chat last changed: a question asked, a reply ended.
    public private(set) var updated: Date
    /// Called when the chat reaches a point worth keeping: a question asked,
    /// a reply ended or stopped.
    @ObservationIgnored public var changed: (@MainActor (Conversation) -> Void)?
    public private(set) var phase: Phase = .idle
    /// What the model is doing on the way to its reply.
    public private(set) var activities: [Activity] = []
    /// What the last reply cost.
    public private(set) var usage: Usage?
    /// The page the person has shared with this chat, if any. Kept as the tab
    /// moves: the page is detached on navigation, not thrown away.
    public private(set) var page: PageContext?

    /// Sessions providers opened, by provider.
    ///
    /// A session is only carried on while it has heard every message: it
    /// holds the chat up to `heard` messages, the reply included. Another
    /// provider answering, or a reply stopped halfway, leaves it behind, and
    /// the provider then starts afresh with the whole conversation.
    /// It was opened searching or not, and its instructions say so; a turn
    /// the other way starts afresh too.
    @ObservationIgnored private var sessions: [String: (id: String, heard: Int, search: Bool, shared: String?)] = [:]
    /// The session opened or carried on by the reply under way.
    @ObservationIgnored private var opened: String?
    /// Whether the reply under way searches.
    @ObservationIgnored private var searched = false
    /// Text and thinking that arrived since the reply was last shown; they
    /// go into the message together, at most every `pace`, so a reply that
    /// comes a word at a time doesn't redraw the chat per word. The chat
    /// shows them at a reader's pace of its own, so this can be slow.
    @ObservationIgnored private var held = (text: "", reasoning: "")
    @ObservationIgnored private var flushing: Task<Void, Never>?
    static let pace: Duration = .milliseconds(150)
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Counts replies, so a stopped one's late events are dropped.
    @ObservationIgnored private var turn = 0

    public init() {
        id = UUID()
        created = Date()
        updated = created
    }

    /// A chat kept earlier, ready to carry on.
    public init(saved: SavedChat) {
        id = saved.id
        created = saved.created
        updated = saved.updated
        messages = saved.messages
        title = SavedChat.title(of: saved.messages)
        sessions = saved.sessions.mapValues { ($0.id, $0.heard, $0.search, nil) }
    }

    /// The chat as it is now, for keeping. A reply still coming is kept as
    /// stopped, and its session left out.
    public var saved: SavedChat {
        var kept = messages
        if busy, let last = kept.indices.last, kept[last].role == .assistant {
            kept[last].text += held.text
            kept[last].reasoning += held.reasoning
            kept[last].interrupted = true
        }
        return SavedChat(
            id: id, messages: kept, sessions: sessions.mapValues { SavedChat.Session(id: $0.id, heard: $0.heard, search: $0.search) },
            created: created, updated: updated)
    }

    private func touch() {
        updated = Date()
        changed?(self)
    }

    public var busy: Bool { phase == .waiting || phase == .answering }

    /// The first question, cut short. Kept apart from `messages`, so what
    /// shows it (a tab's label, the window's title) isn't drawn again with
    /// every piece of a reply.
    public private(set) var title = SavedChat.title(of: [])

    /// Finds the route for a turn. Asked once the question is on screen, so
    /// it can take a moment (finding a program, listing models) or fail.
    public typealias Routing = @MainActor @Sendable () async throws -> Route

    /// Shares `page` with the chat, so the model answers about it from the
    /// next turn on. Replaces any page already shared.
    public func attach(_ page: PageContext) {
        var page = page
        page.attach()
        self.page = page
    }

    /// Stops sharing the page, keeping the chat. The next turn starts
    /// providers that keep their own sessions afresh, since what they were
    /// told has changed.
    public func detachPage() {
        page?.detach()
    }

    /// The address of the page shared with the model now, or nil when none
    /// is. A change starts a provider that keeps its own session afresh, as
    /// turning search on or off does.
    @ObservationIgnored private var shared: String? {
        guard let page, page.isActive else { return nil }
        return page.url.absoluteString
    }

    public func send(_ text: String, via route: Route) { send(text, routing: { route }) }

    public func send(_ text: String, routing: @escaping Routing) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        stop()
        messages.append(Message(role: .user, text: text))
        if messages.count == 1 { title = SavedChat.title(of: messages) }
        ask(routing: routing)
        touch()
    }

    public func retry(via route: Route) { retry(routing: { route }) }

    /// Asks again for the last reply, in place of the one that failed or was stopped.
    public func retry(routing: @escaping Routing) {
        stop()
        guard messages.contains(where: { $0.role == .user }) else { return }
        while messages.last?.role == .assistant { messages.removeLast() }
        ask(routing: routing)
    }

    /// Stops the reply, keeping what arrived.
    public func stop() {
        guard busy else { return }
        flush()
        turn += 1
        task?.cancel()
        task = nil
        if let last = messages.indices.last, messages[last].role == .assistant { messages[last].interrupted = true }
        activities = []
        phase = .idle
        touch()
    }

    private func ask(routing: @escaping Routing) {
        turn += 1
        let turn = turn
        messages.append(Message(role: .assistant, text: ""))
        phase = .waiting
        activities = []
        task = Task { [weak self] in
            var provider: String?
            do {
                let route = try await routing()
                guard let self, self.turn == turn else { return }
                provider = route.provider
                let request = self.request(for: route)
                for try await event in route.service.reply(to: request) {
                    guard self.turn == turn else { return }
                    self.take(event, from: route.provider)
                }
                self.end(turn, failure: nil, provider: route.provider)
            } catch {
                self?.end(turn, failure: error, provider: provider)
            }
        }
    }

    /// Signs the reply with the route's author and asks for it with everything
    /// before it.
    private func request(for route: Route) -> ChatRequest {
        let asked = Array(messages.dropLast())
        if let last = messages.indices.last { messages[last].author = route.author }
        // Up to date if it heard everything but the new question, and was
        // told the same things (search, shared page).
        let session = sessions[route.provider].flatMap {
            $0.heard == asked.count - 1 && $0.search == route.search && $0.shared == shared ? $0.id : nil
        }
        // An agent that carries a session on may not name it again.
        opened = session
        searched = route.search
        return ChatRequest(
            model: route.model, messages: asked, instructions: instructions(for: route), resume: session, search: route.search
        )
    }

    /// The route's standing instructions with the shared page described after
    /// them: exactly the route's instructions when no page is shared.
    private func instructions(for route: Route) -> String? {
        let page = Instructions.page(self.page)
        guard !page.isEmpty else { return route.instructions }
        guard let standing = route.instructions, !standing.isEmpty else { return page }
        return standing + "\n\n" + page
    }

    /// Shows what's held: the first words at once, the rest a pace later.
    private func show(_ last: Int) {
        phase = .answering
        if messages[last].text.isEmpty, messages[last].reasoning.isEmpty { return flush() }
        guard flushing == nil else { return }
        flushing = Task { [weak self] in
            try? await Task.sleep(for: Self.pace)
            self?.flush()
        }
    }

    /// Puts what's held into the reply.
    private func flush() {
        flushing?.cancel()
        flushing = nil
        guard !held.text.isEmpty || !held.reasoning.isEmpty, let last = messages.indices.last, messages[last].role == .assistant
        else { return }
        messages[last].text += held.text
        messages[last].reasoning += held.reasoning
        held = ("", "")
    }

    private func take(_ event: ChatEvent, from provider: String) {
        guard let last = messages.indices.last else { return }
        switch event {
        case .session(let id):
            opened = id
        case .text(let more):
            held.text += more
            show(last)
        case .reasoning(let more):
            held.reasoning += more
            show(last)
        case .activity(let activity):
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
            if let index = messages[last].steps.firstIndex(where: { $0.id == activity.id }) {
                messages[last].steps[index] = activity
            } else {
                messages[last].steps.append(activity)
            }
        case .usage(let spent):
            usage = spent
        case .source(let source):
            if !messages[last].sources.contains(where: { $0.id == source.id }) { messages[last].sources.append(source) }
        }
    }

    private func end(_ ended: Int, failure: Error?, provider: String?) {
        guard ended == turn else { return }
        flush()
        task = nil
        activities = []
        guard let failure, !(failure is CancellationError) else {
            if let provider, let opened { sessions[provider] = (opened, messages.count, searched, shared) }
            phase = .idle
            touch()
            return
        }
        // A reply that never started leaves nothing to show.
        if let last = messages.last, last.role == .assistant, last.text.isEmpty, last.reasoning.isEmpty { messages.removeLast() }
        // A session that failed may be gone; the next try starts afresh.
        if let provider { sessions[provider] = nil }
        phase = .failed((failure as? LocalizedError)?.errorDescription ?? failure.localizedDescription)
        touch()
    }
}
