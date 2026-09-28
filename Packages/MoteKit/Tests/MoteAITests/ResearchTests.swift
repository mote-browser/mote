import Foundation
import Testing

@testable import MoteAI

/// Answers each request by what it asks for, as a provider would: the plan,
/// a researcher's notes, the gap check, the report. Remembers every request
/// and how many ran at once.
final class RoleService: ChatService, @unchecked Sendable {
    typealias Answer = @Sendable (ChatRequest) throws -> [ChatEvent]

    private let lock = NSLock()
    private let answer: Answer
    private var running = 0
    private(set) var requests: [ChatRequest] = []
    private(set) var busiest = 0

    init(_ answer: @escaping Answer) { self.answer = answer }

    func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        lock.withLock {
            requests.append(request)
            running += 1
            busiest = max(busiest, running)
        }
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        let answer = answer
        Task {
            // Long enough for researchers to overlap.
            try? await Task.sleep(for: .milliseconds(20))
            do {
                for event in try answer(request) { continuation.yield(event) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
            self.lock.withLock { self.running -= 1 }
        }
        return stream
    }

    /// What this service answers to `request`, for another service to reuse.
    func answerFor(_ request: ChatRequest) throws -> [ChatEvent] { try answer(request) }

    func asked(_ role: Research.Role) -> [ChatRequest] {
        lock.withLock { requests.filter { Research.role(of: $0) == role } }
    }
}

@Suite("Research")
struct ResearchTests {
    let question = ChatRequest(model: "m", messages: [Message(role: .user, text: "Is Swift good for servers?")], instructions: "Be Mote")

    /// A provider that plans `parts`, finds a page per part, has no gaps
    /// unless given some, and writes "Report".
    private func provider(parts: [String], gaps: [String] = [], failing: Set<String> = []) -> RoleService {
        RoleService { request in
            switch Research.role(of: request) {
            case .plan:
                let list = parts.map { "\"\($0)\"" }.joined(separator: ",")
                return [.text(#"{"title":"Swift on servers","questions":["# + list + "]}")]
            case .research:
                guard let part = parts.first(where: { request.prompt.contains($0) }) ?? gaps.first(where: { request.prompt.contains($0) })
                else { return [] }
                if failing.contains(part) { throw AIError.failed("\(part) broke") }
                let url = URL(string: "https://\(part.lowercased().replacingOccurrences(of: " ", with: "-")).example/page")!
                return [
                    .activity(Activity.search("s", part)), .source(Source(url: url, title: part)),
                    .activity(Activity.search("s", part, done: true)), .text("- Found \(part) [\(part)](\(url.absoluteString))"),
                ]
            case .review:
                let list = gaps.map { "\"\($0)\"" }.joined(separator: ",")
                return [.text(#"{"questions":["# + list + "]}")]
            case .write:
                return [.text("Report")]
            case nil:
                return []
            }
        }
    }

    /// All the text the events carry.
    static func text(of events: [ChatEvent]) -> String {
        events.compactMap { event in if case .text(let text) = event { text } else { nil } }.joined()
    }

    private func events(_ research: Research) async throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for try await event in research.reply(to: question) { events.append(event) }
        return events
    }

    @Test("Plans, researches every part in parallel with search, then writes from the notes")
    func flow() async throws {
        let service = provider(parts: ["Performance", "Frameworks", "Adoption"])
        let research = Research(service: service, budget: Research.Budget(questions: 5, waves: 2, parallel: 3))
        let events = try await events(research)

        #expect(Self.text(of: events) == "Report")
        let tasks = events.compactMap { event -> Activity? in
            if case .activity(let activity) = event, activity.kind == .task { activity } else { nil }
        }
        #expect(Set(tasks.filter(\.done).map(\.title)) == ["Performance", "Frameworks", "Adoption"])
        let sources = events.filter { event in if case .source = event { true } else { false } }
        #expect(sources.count == 3)
        // Searches from each researcher keep ids of their own.
        let searchIDs = Set(
            events.compactMap { event -> String? in
                if case .activity(let activity) = event, activity.kind == .search { activity.id } else { nil }
            })
        #expect(searchIDs.count == 3)

        let planning = service.asked(.plan).map { $0.search }
        let researchers = service.asked(.research)
        let searching = researchers.allSatisfy { $0.search }
        let knowQuestion = researchers.allSatisfy { $0.prompt.contains("Is Swift good for servers?") }
        #expect(planning == [false])
        #expect(searching)
        #expect(researchers.count == 3)
        #expect(knowQuestion)
        let writer = try #require(service.asked(.write).first)
        #expect(!writer.search)
        #expect(writer.prompt.contains("Found Performance") && writer.prompt.contains("Found Adoption"))
        #expect(writer.instructions == "Be Mote")
        // Only researchers are told how to search.
        #expect(researchers.allSatisfy { $0.instructions == "Be Mote\n\n" + Instructions.search })
        #expect(service.asked(.plan).first?.instructions == "Be Mote")
        #expect(service.busiest > 1)
    }

    @Test("No more researchers run at once than the budget allows")
    func parallelLimit() async throws {
        let service = provider(parts: ["A1", "B2", "C3", "D4", "E5"])
        _ = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 1, parallel: 2)))
        #expect(service.asked(.research).count == 5)
        #expect(service.busiest <= 2)
    }

    @Test("A plan longer than the budget is cut to it")
    func questionLimit() async throws {
        let service = provider(parts: ["A1", "B2", "C3", "D4", "E5", "F6"])
        _ = try await events(Research(service: service, budget: Research.Budget(questions: 4, waves: 1, parallel: 3)))
        #expect(service.asked(.research).count == 4)
    }

    @Test("Gaps found in the notes get a second wave, and only as many waves as the budget")
    func followUps() async throws {
        let service = provider(parts: ["Performance"], gaps: ["Hosting costs"])
        let events = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 2, parallel: 3)))
        #expect(service.asked(.research).count == 2)
        #expect(service.asked(.review).count == 1)
        #expect(service.asked(.write).first?.prompt.contains("Found Hosting costs") == true)
        let followed = events.contains { event in
            if case .activity(let activity) = event { activity.kind == .task && activity.title == "Hosting costs" } else { false }
        }
        #expect(followed)
    }

    @Test("A researcher that fails is noted, and the rest carry on")
    func oneFails() async throws {
        let service = provider(parts: ["Performance", "Frameworks"], failing: ["Frameworks"])
        let events = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 1, parallel: 3)))
        #expect(Self.text(of: events) == "Report")
        let writer = try #require(service.asked(.write).first)
        #expect(writer.prompt.contains("Found Performance"))
        #expect(writer.prompt.contains("Frameworks broke"))
    }

    @Test("When every researcher fails, so does the research")
    func allFail() async {
        let service = provider(parts: ["Performance"], failing: ["Performance"])
        await #expect(throws: AIError.failed("Performance broke")) {
            _ = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 1, parallel: 3)))
        }
    }

    @Test("A plan that isn't JSON is read as a list; no plan at all researches the question itself")
    func loosePlans() {
        #expect(
            Research.questions(in: "Here:\n1. First part\n2) Second part\n- Third part") == ["First part", "Second part", "Third part"])
        #expect(Research.questions(in: #"```json\n{"questions": ["A", "B"]}\n```"#) == ["A", "B"])
        #expect(Research.questions(in: "I can't help") == [])
    }

    @Test("A request says what part of the research it is")
    func roles() {
        for role in [Research.Role.plan, .research, .review, .write] {
            #expect(
                Research.role(of: ChatRequest(model: "", messages: [Message(role: .user, text: Research.opening(role) + " …")])) == role)
        }
        #expect(Research.role(of: question) == nil)
    }

    @Test("The whole plan shows as soon as it's made, before any part starts")
    func planShown() async throws {
        let service = provider(parts: ["A1", "B2", "C3", "D4"])
        let events = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 1, parallel: 1)))
        let firstSearch = try #require(
            events.firstIndex { event in
                if case .activity(let activity) = event { activity.kind == .search } else { false }
            })
        let announced = events[..<firstSearch].compactMap { event -> String? in
            if case .activity(let activity) = event, activity.kind == .task, !activity.done { activity.title } else { nil }
        }
        #expect(Set(announced) == ["A1", "B2", "C3", "D4"])
    }

    @Test("Follow-ups are fewer than the plan's parts")
    func followUpLimit() async throws {
        let service = provider(parts: ["A1"], gaps: ["G1", "G2", "G3", "G4", "G5"])
        _ = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 2, parallel: 3, followUps: 2)))
        #expect(service.asked(.research).count == 3)
    }

    @Test("A gap review that fails still leaves a report written from the notes")
    func reviewFails() async throws {
        let base = provider(parts: ["Performance"])
        let service = RoleService { request in
            if Research.role(of: request) == .review { throw AIError.failed("Overloaded") }
            return try base.answerFor(request)
        }
        let events = try await events(Research(service: service, budget: Research.Budget(questions: 5, waves: 2, parallel: 3)))
        #expect(Self.text(of: events) == "Report")
    }

    @Test("A follow-up question carries earlier replies shortened, not whole")
    func followUpContext() {
        let long = String(repeating: "word ", count: 2_000)
        let request = ChatRequest(
            model: "",
            messages: [Message(role: .user, text: "First"), Message(role: .assistant, text: long), Message(role: .user, text: "And then?")])
        let question = Research.question(in: request)
        #expect(question.contains("And then?"))
        #expect(question.count < 2_500)
    }
}
