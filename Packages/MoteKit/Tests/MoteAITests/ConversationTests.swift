import Foundation
import Testing

@testable import MoteAI

/// Replies with scripted events, then fails or ends; can hold the reply open
/// until let go, and remembers every request.
final class ScriptedService: ChatService, @unchecked Sendable {
    var events: [ChatEvent] = []
    var failure: Error?
    /// Holds the reply open after its events until the stream is ended.
    var hold = false
    private(set) var requests: [ChatRequest] = []
    private(set) var stopped = false

    func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        requests.append(request)
        let (events, failure, hold) = (events, failure, hold)
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        for event in events { continuation.yield(event) }
        continuation.onTermination = { [weak self] reason in
            if case .cancelled = reason { self?.stopped = true }
        }
        if !hold { continuation.finish(throwing: failure) }
        return stream
    }
}

@MainActor
@Suite("Conversation")
struct ConversationTests {
    private func route(_ service: ChatService, provider: String = "claude-code", model: String = "sonnet") -> Conversation.Route {
        Conversation.Route(provider: provider, model: model, author: "Claude Code · \(model)", service: service, instructions: "Be brief")
    }

    /// Waits for the reply to settle.
    private func settle(_ conversation: Conversation) async {
        for _ in 0..<200 where conversation.busy { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("Sending adds the question and a reply that fills in as it streams")
    func send() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .reasoning("Adding"), .text("It's "), .text("4."), .usage(Usage(input: 5, output: 3))]
        let conversation = Conversation()
        conversation.send("What's 2+2?", via: route(service))
        #expect(conversation.busy)
        #expect(conversation.phase == .waiting)
        await settle(conversation)
        #expect(conversation.messages.map(\.role) == [.user, .assistant])
        #expect(conversation.messages[1].text == "It's 4.")
        #expect(conversation.messages[1].reasoning == "Adding")
        #expect(conversation.messages[1].author == "Claude Code · sonnet")
        #expect(conversation.phase == .idle)
        #expect(conversation.usage == Usage(input: 5, output: 3))
        let request = service.requests[0]
        #expect(request.model == "sonnet")
        #expect(request.instructions == "Be brief")
        #expect(request.resume == nil)
        #expect(request.messages.map(\.text) == ["What's 2+2?"])
    }

    @Test("The title is the first question, on one line and not too long")
    func title() {
        let conversation = Conversation()
        #expect(conversation.title == "New chat")
        conversation.send(
            "  How do\nplanes stay up when they are very heavy and full of people and luggage?  ", via: route(ScriptedService()))
        #expect(conversation.title == "How do planes stay up when they are very heavy and full of…")
    }

    @Test("Blank messages aren't sent")
    func blank() {
        let conversation = Conversation()
        conversation.send("   \n", via: route(ScriptedService()))
        #expect(conversation.messages.isEmpty)
    }

    @Test("The next message carries on the provider's session, with the whole history")
    func resumes() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        service.events = [.text("Sure")]
        conversation.send("Again", via: route(service))
        await settle(conversation)
        #expect(service.requests[1].resume == "s-1")
        #expect(service.requests[1].messages.map(\.text) == ["Hello", "Hi", "Again"])
    }

    @Test("Another provider starts without the first one's session")
    func switching() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        conversation.send("Again", via: route(service, provider: "opencode"))
        await settle(conversation)
        #expect(service.requests[1].resume == nil)
    }

    @Test("A failure is kept for the chat to show, with what came before it")
    func failure() async {
        let service = ScriptedService()
        service.events = [.text("Part")]
        service.failure = AIError.failed("Overloaded")
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        #expect(conversation.phase == .failed("Overloaded"))
        #expect(conversation.messages.last?.text == "Part")
    }

    @Test("Retrying asks again in place of the failed reply, from a fresh session")
    func retry() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        service.events = []
        service.failure = AIError.failed("Session not found")
        conversation.send("Again", via: route(service))
        await settle(conversation)
        service.failure = nil
        service.events = [.text("Back")]
        conversation.retry(via: route(service))
        await settle(conversation)
        #expect(conversation.messages.map(\.text) == ["Hello", "Hi", "Again", "Back"])
        #expect(conversation.phase == .idle)
        // The session that failed isn't tried again.
        #expect(service.requests[2].resume == nil)
        #expect(service.requests[2].messages.map(\.text) == ["Hello", "Hi", "Again"])
    }

    @Test("Stopping keeps what arrived, marks it, and ends the provider's reply")
    func stop() async throws {
        let service = ScriptedService()
        service.events = [.text("Half")]
        service.hold = true
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        for _ in 0..<100 where conversation.messages.last?.text.isEmpty != false { try await Task.sleep(for: .milliseconds(5)) }
        conversation.stop()
        #expect(!conversation.busy)
        #expect(conversation.phase == .idle)
        #expect(conversation.messages.last?.text == "Half")
        #expect(conversation.messages.last?.interrupted == true)
        for _ in 0..<100 where !service.stopped { try await Task.sleep(for: .milliseconds(5)) }
        #expect(service.stopped)
    }

    @Test("Sending while a reply is coming stops that reply first")
    func sendWhileBusy() async throws {
        let service = ScriptedService()
        service.hold = true
        let conversation = Conversation()
        conversation.send("One", via: route(service))
        service.hold = false
        service.events = [.text("Two it is")]
        conversation.send("Two", via: route(service))
        await settle(conversation)
        #expect(conversation.messages.map(\.text) == ["One", "", "Two", "Two it is"])
    }

    @Test("Activity shows while the reply is coming, and is gone once it's done")
    func activity() async {
        let service = ScriptedService()
        service.events = [.activity(Activity(id: "t", title: "WebSearch")), .activity(Activity(id: "t", title: "WebSearch", done: true))]
        service.hold = true
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        for _ in 0..<100 where conversation.activities.first?.done != true { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(conversation.activities == [Activity(id: "t", title: "WebSearch", done: true)])
        conversation.stop()
        #expect(conversation.activities.isEmpty)
    }

    @Test("A turn whose route can't be found keeps the question and says why, for a retry later")
    func routeFails() async {
        let conversation = Conversation()
        conversation.send("Hello", routing: { throw AIError.needsKey("OpenAI") })
        #expect(conversation.messages.map(\.text) == ["Hello", ""])
        #expect(conversation.phase == .waiting)
        await settle(conversation)
        #expect(conversation.messages.map(\.text) == ["Hello"])
        #expect(conversation.phase == .failed("OpenAI needs an API key — add one in Settings › AI"))
        let service = ScriptedService()
        service.events = [.text("Hi")]
        conversation.retry(via: route(service))
        await settle(conversation)
        #expect(conversation.messages.map(\.text) == ["Hello", "Hi"])
        #expect(conversation.messages.last?.author == "Claude Code · sonnet")
    }

    @Test("A provider coming back after another answered starts afresh, so it hears the turns it missed")
    func comingBack() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("One")]
        let conversation = Conversation()
        conversation.send("First", via: route(service))
        await settle(conversation)
        service.events = [.text("Two")]
        conversation.send("Second", via: route(service, provider: "openai"))
        await settle(conversation)
        conversation.send("Third", via: route(service))
        await settle(conversation)
        #expect(service.requests[2].resume == nil)
        #expect(service.requests[2].messages.map(\.text) == ["First", "One", "Second", "Two", "Third"])
    }

    @Test("A stopped reply's session isn't carried on, since it holds a turn the chat asks again")
    func stoppedSession() async throws {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Half")]
        service.hold = true
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        for _ in 0..<100 where conversation.messages.last?.text.isEmpty != false { try await Task.sleep(for: .milliseconds(5)) }
        conversation.stop()
        service.hold = false
        service.events = [.text("Whole")]
        conversation.retry(via: route(service))
        await settle(conversation)
        #expect(service.requests[1].resume == nil)
    }

    @Test("A search reply keeps the pages it found and what it did, once each")
    func searchRecords() async {
        let service = ScriptedService()
        let page = Source(url: URL(string: "https://swift.org/blog")!, title: "Blog")
        service.events = [
            .activity(Activity(id: "s1", title: "Searching “swift”", kind: .search)), .source(page),
            .source(Source(url: URL(string: "https://www.swift.org/blog/")!, title: "Again")),
            .activity(Activity(id: "s1", title: "Searching “swift”", done: true, kind: .search)),
            .text("It's 6.4 [swift.org](https://swift.org/blog)"),
        ]
        let conversation = Conversation()
        var route = route(service)
        route.search = true
        conversation.send("Latest Swift?", via: route)
        await settle(conversation)
        let reply = conversation.messages[1]
        #expect(reply.sources == [page])
        #expect(reply.steps == [Activity(id: "s1", title: "Searching “swift”", done: true, kind: .search)])
        #expect(service.requests[0].search)
    }

    @Test("Turning search on or off starts the provider afresh, so it gets the new instructions")
    func searchChangesSession() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        var searching = route(service)
        searching.search = true
        conversation.send("Look it up", via: searching)
        await settle(conversation)
        #expect(service.requests[1].resume == nil)
        #expect(service.requests[1].search)
    }

    @Test("Text arriving in many small pieces is shown in a few updates, the first at once, and all of it by the end")
    func coalesced() async {
        let service = ScriptedService()
        service.events = (0..<300).map { .text("w\($0) ") }
        let conversation = Conversation()
        let count = ChangeCount(conversation)
        conversation.send("Hi", via: route(service))
        await settle(conversation)
        #expect(conversation.messages.last?.text.hasPrefix("w0 w1 ") == true)
        #expect(conversation.messages.last?.text.hasSuffix("w299 ") == true)
        #expect(count.changes < 30)
    }

    @Test("A chat carrying a shared page tells the model about it, after the standing instructions")
    func sharedPage() async {
        let service = ScriptedService()
        service.events = [.text("Hi")]
        let conversation = Conversation()
        conversation.attach(PageContext(url: URL(string: "https://example.com/a")!, title: "An article"))
        conversation.send("What is this?", via: route(service))
        await settle(conversation)
        let instructions = service.requests[0].instructions ?? ""
        #expect(instructions.hasPrefix("Be brief"))
        #expect(instructions.contains("An article"))
        #expect(instructions.contains("https://example.com/a"))
    }

    @Test("A chat with no page is asked exactly as before")
    func noPage() async {
        let service = ScriptedService()
        service.events = [.text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        #expect(service.requests[0].instructions == "Be brief")
    }

    @Test("Detaching the page stops sharing it, and the chat carries on")
    func detachPage() async {
        let service = ScriptedService()
        service.events = [.text("Hi")]
        let conversation = Conversation()
        conversation.attach(PageContext(url: URL(string: "https://example.com/a")!, title: "An article"))
        conversation.detachPage()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        #expect(service.requests[0].instructions == "Be brief")
    }

    @Test("A page attached in place of another replaces what the model is shown")
    func reattach() async {
        let service = ScriptedService()
        service.events = [.text("Hi")]
        let conversation = Conversation()
        conversation.attach(PageContext(url: URL(string: "https://example.com/a")!, title: "First"))
        conversation.detachPage()
        conversation.attach(PageContext(url: URL(string: "https://example.com/b")!, title: "Second"))
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        let instructions = service.requests[0].instructions ?? ""
        #expect(instructions.contains("Second"))
        #expect(!instructions.contains("First"))
    }

    @Test("Sharing a page with a provider that already heard the chat starts it afresh")
    func pageChangesSession() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        conversation.attach(PageContext(url: URL(string: "https://example.com/a")!, title: "An article"))
        service.events = [.text("About that page")]
        conversation.send("And now?", via: route(service))
        await settle(conversation)
        #expect(service.requests[1].resume == nil)
        #expect(service.requests[1].instructions?.contains("An article") == true)
    }

    @Test("The same page kept across turns carries the provider's session on")
    func samePageResumes() async {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Hi")]
        let conversation = Conversation()
        conversation.attach(PageContext(url: URL(string: "https://example.com/a")!, title: "An article"))
        conversation.send("Hello", via: route(service))
        await settle(conversation)
        service.events = [.text("Sure")]
        conversation.send("Again", via: route(service))
        await settle(conversation)
        #expect(service.requests[1].resume == "s-1")
    }
}

/// Counts how often a conversation's messages change, as a view watching them would see.
@MainActor
final class ChangeCount {
    private(set) var changes = 0
    private let conversation: Conversation

    init(_ conversation: Conversation) {
        self.conversation = conversation
        watch()
    }

    private func watch() {
        withObservationTracking {
            _ = conversation.messages
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.changes += 1
                self?.watch()
            }
        }
    }
}
