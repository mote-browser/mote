import Foundation
import Testing

@testable import MoteAI

@MainActor
@Suite("Chat archive")
struct ChatArchiveTests {
    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("chats-\(UUID().uuidString)", isDirectory: true)
    }

    private func chat(_ question: String, answer: String = "Answer", at time: TimeInterval = 1_000) -> SavedChat {
        SavedChat(
            id: UUID(),
            messages: [Message(role: .user, text: question), Message(role: .assistant, text: answer, author: "Claude Code · sonnet")],
            created: Date(timeIntervalSince1970: time), updated: Date(timeIntervalSince1970: time))
    }

    private func settle(_ conversation: Conversation) async {
        for _ in 0..<200 where conversation.busy { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("A saved chat is listed, newest first, and reads back whole after a relaunch")
    func saveAndLoad() {
        let place = folder()
        let archive = ChatArchive(folder: place)
        let old = chat("Old question", at: 1_000)
        let new = chat("New question", at: 2_000)
        archive.save(old)
        archive.save(new)
        #expect(archive.entries.map(\.title) == ["New question", "Old question"])
        archive.flush()

        let reopened = ChatArchive(folder: place)
        #expect(reopened.entries.map(\.id) == [new.id, old.id])
        #expect(reopened.load(old.id) == old)
    }

    @Test("Saving a chat again moves it to the top instead of listing it twice")
    func resave() {
        let archive = ChatArchive(folder: folder())
        var first = chat("First", at: 1_000)
        archive.save(first)
        archive.save(chat("Second", at: 2_000))
        first.messages.append(Message(role: .user, text: "More"))
        first.updated = Date(timeIntervalSince1970: 3_000)
        archive.save(first)
        #expect(archive.entries.map(\.title) == ["First", "Second"])
    }

    @Test("A chat without a question isn't kept")
    func empty() {
        let archive = ChatArchive(folder: folder())
        archive.save(SavedChat(id: UUID(), messages: [], created: Date(), updated: Date()))
        #expect(archive.entries.isEmpty)
    }

    @Test("Deleting removes a chat from the list and from disk; clearing removes them all")
    func delete() {
        let place = folder()
        let archive = ChatArchive(folder: place)
        let one = chat("One")
        let two = chat("Two", at: 2_000)
        archive.save(one)
        archive.save(two)
        archive.delete(one.id)
        #expect(archive.entries.map(\.id) == [two.id])
        archive.flush()
        #expect(ChatArchive(folder: place).load(one.id) == nil)
        #expect(ChatArchive(folder: place).entries.map(\.id) == [two.id])

        archive.deleteAll()
        archive.flush()
        #expect(archive.entries.isEmpty)
        #expect(ChatArchive(folder: place).entries.isEmpty)
    }

    @Test("A deleted chat still open somewhere isn't kept again, unless the deletion is undone")
    func undo() {
        let archive = ChatArchive(folder: folder())
        var open = chat("Open elsewhere")
        archive.save(open)
        archive.delete(open.id)
        open.messages.append(Message(role: .user, text: "Later"))
        archive.save(open)
        #expect(archive.entries.isEmpty)
        archive.restore(open)
        #expect(archive.entries.map(\.id) == [open.id])
    }

    @Test("Finds chats by their title or by anything asked in them, ignoring case and accents")
    func search() {
        let archive = ChatArchive(folder: folder())
        var long = chat("Swift on servers")
        long.messages += [Message(role: .user, text: "And what about Vapor's café?"), Message(role: .assistant, text: "Kubernetes")]
        archive.save(long)
        archive.save(chat("Pasta recipes", at: 2_000))
        #expect(archive.entries(matching: "swift").map(\.title) == ["Swift on servers"])
        #expect(archive.entries(matching: "VAPOR cafe").map(\.title) == ["Swift on servers"])
        #expect(archive.entries(matching: "").count == 2)
        #expect(archive.entries(matching: "nothing like it").isEmpty)
    }

    @Test("A lost index is rebuilt from the chats themselves")
    func rebuild() throws {
        let place = folder()
        let archive = ChatArchive(folder: place)
        let kept = chat("Kept", at: 1_000)
        archive.save(kept)
        archive.flush()
        try "not json".write(to: place.appendingPathComponent("index.json"), atomically: true, encoding: .utf8)
        #expect(ChatArchive(folder: place).entries.map(\.id) == [kept.id])
    }

    @Test("A conversation is saved as it goes, and one brought back carries on where it was")
    func conversation() async {
        let archive = ChatArchive(folder: folder())
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Four")]
        let conversation = Conversation()
        conversation.changed = { archive.save($0.saved) }
        conversation.send("What's 2+2?", via: Conversation.Route(provider: "claude-code", model: "", author: "Claude", service: service))
        await settle(conversation)
        archive.flush()
        let saved = try! #require(archive.load(conversation.id))
        #expect(saved.messages.map(\.text) == ["What's 2+2?", "Four"])

        let back = Conversation(saved: saved)
        #expect(back.id == conversation.id)
        #expect(back.messages == conversation.messages)
        #expect(back.title == "What's 2+2?")
        back.send("And 3+3?", via: Conversation.Route(provider: "claude-code", model: "", author: "Claude", service: service))
        await settle(back)
        // The provider's session came back too, so it only needs the new question.
        #expect(service.requests.last?.resume == "s-1")
    }

    @Test("A chat saved while a reply was coming comes back with that reply stopped")
    func midReply() {
        let service = ScriptedService()
        service.events = [.session("s-1"), .text("Half")]
        service.hold = true
        let conversation = Conversation()
        conversation.send("Tell me", via: Conversation.Route(provider: "p", model: "", author: "A", service: service))
        let saved = conversation.saved
        #expect(saved.messages.last?.role == .assistant)
        #expect(saved.messages.last?.interrupted == true)
        conversation.stop()
    }
}

@Suite("Chat archive periods")
struct ChatPeriodTests {
    /// Monday 28 September 2026, 15:00 in UTC.
    let now = Date(timeIntervalSince1970: 1_790_607_600)
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ title: String, hoursAgo: Double) -> ChatArchive.Entry {
        ChatArchive.Entry(id: UUID(), title: title, updated: now.addingTimeInterval(-hoursAgo * 3_600), asked: "")
    }

    @Test("Chats fall in today, yesterday, the week, the month, then one period per month, newest first")
    func periods() {
        let entries = [
            entry("This morning", hoursAgo: 5), entry("Last night", hoursAgo: 20), entry("Friday", hoursAgo: 72),
            entry("Two weeks ago", hoursAgo: 24 * 14), entry("July", hoursAgo: 24 * 70), entry("Also July", hoursAgo: 24 * 75),
            entry("Last year", hoursAgo: 24 * 400),
        ]
        let periods = ChatArchive.periods(of: entries, now: now, calendar: calendar)
        #expect(periods.map(\.name) == ["Today", "Yesterday", "Previous 7 Days", "Previous 30 Days", "July", "August 2025"])
        #expect(periods.map { $0.entries.map(\.title) }[4] == ["July", "Also July"])
    }

    @Test("Periods with no chats aren't shown")
    func empty() {
        let periods = ChatArchive.periods(of: [entry("Old", hoursAgo: 24 * 10)], now: now, calendar: calendar)
        #expect(periods.map(\.name) == ["Previous 30 Days"])
    }
}
