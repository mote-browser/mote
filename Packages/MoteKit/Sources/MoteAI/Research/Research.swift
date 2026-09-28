import Foundation

/// Deep research on any provider that can search: Mote plans the question
/// into parts, has several researchers search them at once, looks for gaps
/// and sends another wave for them, then has a writer turn the notes into a
/// report that cites its sources.
///
/// It is a `ChatService` wrapped around the provider's own, so the chat
/// shows its progress and report like any reply. The breadth comes from
/// Mote running many searching replies in parallel rather than from asking
/// one reply to search a lot; each researcher keeps a small context of its
/// own and hands back compact notes.
public struct Research: ChatService {
    /// How far a research goes.
    public struct Budget: Sendable {
        /// Most parts in the plan.
        public var questions: Int
        /// Rounds of researching: the plan's, then follow-ups for its gaps.
        public var waves: Int
        /// Researchers running at once.
        public var parallel: Int
        /// Most parts in a wave of follow-ups.
        public var followUps: Int

        public init(questions: Int, waves: Int, parallel: Int, followUps: Int = 3) {
            self.questions = questions
            self.waves = waves
            self.parallel = parallel
            self.followUps = followUps
        }

        public static let standard = Budget(questions: 5, waves: 2, parallel: 3, followUps: 3)
    }

    /// What a request to the provider is for; each opens its prompt its own way.
    public enum Role: String, CaseIterable, Sendable {
        case plan, research, review, write
    }

    let service: any ChatService
    let budget: Budget

    public init(service: any ChatService, budget: Budget = .standard) {
        self.service = service
        self.budget = budget
    }

    public func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        let task = Task {
            do {
                try await run(request) { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    // MARK: - The run

    /// Notes from one researcher, or why there are none.
    struct Notes: Sendable {
        var part: String
        var result: Result<String, Error>
    }

    private func run(_ request: ChatRequest, emit: @escaping @Sendable (ChatEvent) -> Void) async throws {
        let question = Self.question(in: request)

        emit(.activity(Activity(id: "plan", title: "Planning the research", kind: .phase)))
        let plan = try await text(.plan, Self.planPrompt(question, most: budget.questions), for: request)
        var parts = Array(Self.questions(in: plan).prefix(budget.questions))
        if parts.isEmpty { parts = [request.prompt] }
        emit(.activity(Activity(id: "plan", title: "Planning the research", done: true, kind: .phase)))

        var notes: [Notes] = []
        var asked: Set<String> = []
        for wave in 1...max(1, budget.waves) {
            let fresh = parts.filter { asked.insert($0.lowercased()).inserted }
            guard !fresh.isEmpty else { break }
            // The wave's parts show at once, waiting their turn.
            for (index, part) in fresh.enumerated() {
                emit(.activity(Activity(id: "part-\(notes.count + index + 1)", title: part, kind: .task)))
            }
            notes += await investigate(fresh, from: notes.count, question: question, for: request, emit: emit)
            try Task.checkCancellation()
            guard wave < budget.waves, notes.contains(where: { (try? $0.result.get()) != nil }) else { break }
            emit(.activity(Activity(id: "review-\(wave)", title: "Looking for gaps", kind: .phase)))
            defer { emit(.activity(Activity(id: "review-\(wave)", title: "Looking for gaps", done: true, kind: .phase))) }
            // The review only adds to what's found; failing, it leaves the notes as they are.
            guard let review = try? await text(.review, Self.reviewPrompt(question, notes: notes, most: budget.followUps), for: request)
            else { break }
            try Task.checkCancellation()
            parts = Array(Self.questions(in: review).prefix(budget.followUps))
        }
        guard notes.contains(where: { (try? $0.result.get()) != nil }) else {
            if let failure = notes.lazy.compactMap({ notes -> Error? in
                if case .failure(let error) = notes.result { error } else { nil }
            }).first {
                throw failure
            }
            throw AIError.failed("The research found nothing to go on")
        }

        try Task.checkCancellation()
        emit(.activity(Activity(id: "write", title: "Writing the report", kind: .phase)))
        let writing = ChatRequest(
            model: request.model, messages: [Message(role: .user, text: Self.writePrompt(question, notes: notes))],
            instructions: request.instructions)
        for try await event in service.reply(to: writing) {
            switch event {
            case .text, .reasoning, .usage: emit(event)
            case .session, .activity, .source: break
            }
        }
        emit(.activity(Activity(id: "write", title: "Writing the report", done: true, kind: .phase)))
    }

    /// Researches `parts` at once, no more than the budget's at a time,
    /// numbering them on from `first`.
    private func investigate(
        _ parts: [String], from first: Int, question: String, for request: ChatRequest, emit: @escaping @Sendable (ChatEvent) -> Void
    ) async -> [Notes] {
        await withTaskGroup(of: (Int, Notes).self) { group in
            var next = 0
            var results: [Int: Notes] = [:]
            func start() {
                guard next < parts.count else { return }
                let (index, part) = (next, parts[next])
                next += 1
                group.addTask {
                    (index, await research(part, number: first + index + 1, question: question, for: request, emit: emit))
                }
            }
            for _ in 0..<max(1, budget.parallel) { start() }
            while let (index, notes) = await group.next() {
                results[index] = notes
                start()
            }
            return parts.indices.compactMap { results[$0] }
        }
    }

    /// One researcher: a searching reply about one part, its searches and
    /// sources passed on as they come, its text kept as notes.
    private func research(
        _ part: String, number: Int, question: String, for request: ChatRequest, emit: @escaping @Sendable (ChatEvent) -> Void
    ) async -> Notes {
        let id = "part-\(number)"
        emit(.activity(Activity(id: id, title: part, kind: .task)))
        defer { emit(.activity(Activity(id: id, title: part, done: true, kind: .task))) }
        // Only researchers search, so only they are told how.
        let instructions = [request.instructions, Instructions.search].compactMap { $0 }.joined(separator: "\n\n")
        let asking = ChatRequest(
            model: request.model, messages: [Message(role: .user, text: Self.researchPrompt(question, part: part))],
            instructions: instructions, search: true)
        var text = ""
        do {
            for try await event in service.reply(to: asking) {
                switch event {
                case .text(let more): text += more
                case .source: emit(event)
                case .activity(var activity):
                    activity.id = "\(id)-\(activity.id)"
                    emit(.activity(activity))
                case .session, .reasoning, .usage: break
                }
            }
            return Notes(part: part, result: .success(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        } catch {
            return Notes(part: part, result: .failure(error))
        }
    }

    /// The whole text of a reply that doesn't search.
    private func text(_ role: Role, _ prompt: String, for request: ChatRequest) async throws -> String {
        let asking = ChatRequest(model: request.model, messages: [Message(role: .user, text: prompt)], instructions: request.instructions)
        var text = ""
        for try await event in service.reply(to: asking) {
            if case .text(let more) = event { text += more }
        }
        return text
    }

    // MARK: - Reading replies

    /// The question, with what was said before it when it follows on:
    /// earlier replies shortened, since this goes into every prompt of the
    /// research and an earlier report can run to thousands of words.
    static func question(in request: ChatRequest) -> String {
        guard request.messages.count > 1 else { return request.prompt }
        let shortened = request.messages.enumerated().map { index, message in
            var message = message
            if index < request.messages.count - 1, message.text.count > Self.recalled {
                message.text = String(message.text.prefix(Self.recalled)) + "…"
            }
            return message
        }
        return Transcript.prompt(for: shortened)
    }

    /// How much of each earlier message a follow-up research carries.
    static let recalled = 600

    /// The questions in a plan or review: its JSON `questions`, or failing
    /// that the items of a list.
    public static func questions(in reply: String) -> [String] {
        if let open = reply.firstIndex(of: "{"), let close = reply.lastIndex(of: "}"), open < close,
            let json = JSON(parsing: reply[open...close]), let listed = json["questions"]?.array
        {
            return listed.compactMap(\.string).map(clean).filter { !$0.isEmpty }
        }
        let item = /^\s*(?:\d+[.)]|[-*•])\s+(.+)$/.anchorsMatchLineEndings()
        return reply.matches(of: item).map { clean(String($0.output.1)) }.filter { !$0.isEmpty }
    }

    private static func clean(_ question: String) -> String {
        question.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"*`"))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Which part of a research a request is, from how its prompt opens.
    public static func role(of request: ChatRequest) -> Role? {
        Role.allCases.first { request.prompt.hasPrefix(opening($0)) }
    }

    // MARK: - Prompts

    public static func opening(_ role: Role) -> String {
        switch role {
        case .plan: "Plan the research for this question."
        case .research: "Research this part of a larger question."
        case .review: "Review the research notes below."
        case .write: "Write the research report."
        }
    }

    static func planPrompt(_ question: String, most: Int) -> String {
        """
        \(opening(.plan))

        The question: \(question)

        Break it into 3 to \(most) sub-questions that together answer it fully: specific, independent of each other, \
        and covering the angles it needs (key facts, recent developments, numbers, how it works, different \
        viewpoints or criticism). A simple question needs fewer. Write them in the language of the question.

        Reply with JSON only: {"title": "a short title", "questions": ["…"]}
        """
    }

    static func researchPrompt(_ question: String, part: String) -> String {
        """
        \(opening(.research))

        The question: \(question)
        Your part: \(part)

        Search from several angles (at least three searches, in parallel when you can) and read the most useful \
        pages in full. Prefer primary and official sources, note the date of anything that changes, and note where \
        sources disagree.

        Report what you found as a list of concise facts, at most 250 words, each ending with a Markdown link to the \
        page it came from, with the site's name as the link text. Only facts from pages you read; if you found \
        little, say so. No introduction or conclusion.
        """
    }

    static func reviewPrompt(_ question: String, notes: [Notes], most: Int) -> String {
        """
        \(opening(.review))

        The question: \(question)

        \(written(notes))

        Which important parts of the question are still unanswered, rest on a single source, or conflict without \
        being resolved? Suggest up to \(most) follow-up questions that would close those gaps, or none if the notes \
        already answer the question well.

        Reply with JSON only: {"questions": ["…"]}
        """
    }

    static func writePrompt(_ question: String, notes: [Notes]) -> String {
        """
        \(opening(.write))

        The question: \(question)

        \(written(notes))

        Write a thorough, well organised answer from these notes only, in the language of the question:
        - A title as a # heading, then a summary of two to four sentences that answers the question directly.
        - Then sections under ## headings for the main points, with tables where they compare things.
        - Say where sources disagree or evidence is thin, in a short section on what's uncertain if needed.
        - Cite every factual sentence with the Markdown links from the notes, keeping the site's name as the link \
        text. Never make up a link, and don't add a list of sources at the end.
        - Aim for 500 to 1,200 words, as the question needs.
        """
    }

    /// The notes so far, part by part.
    static func written(_ notes: [Notes]) -> String {
        "Research notes, by part:\n\n"
            + notes.map { notes in
                switch notes.result {
                case .success(let text): "## \(notes.part)\n\(text.isEmpty ? "(nothing found)" : text)"
                case .failure(let error):
                    "## \(notes.part)\n(Couldn't research this: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription))"
                }
            }.joined(separator: "\n\n")
    }
}
