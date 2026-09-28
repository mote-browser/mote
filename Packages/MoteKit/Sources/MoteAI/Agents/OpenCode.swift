import Foundation

/// opencode's `opencode run --format json`: the prompt on stdin, and a line
/// per finished part (text, reasoning, tool) on stdout.
///
/// It runs as opencode's own plan agent, which may read but not write or
/// run commands. Its configuration is otherwise left as it is: its free
/// models refuse requests from a changed one, so Mote's instructions go at
/// the head of the first prompt instead of a system prompt.
public struct OpenCodeAgent: AgentWire {
    public init() {}

    public func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command {
        var arguments = ["run", "--format", "json", "--thinking", "--agent", "plan"]
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        let prompt: String
        if let session = request.resume {
            arguments += ["--session", session]
            prompt = request.prompt
        } else {
            let transcript = Transcript.prompt(for: request.messages)
            prompt = request.instructions.map { "\($0)\n\n---\n\n\(transcript)" } ?? transcript
        }
        // opencode's own web search, which it only offers when asked.
        let environment = request.search ? ["OPENCODE_ENABLE_EXA": "1"] : [:]
        return Command(executable: executable, arguments: arguments, environment: environment, directory: workspace, input: prompt)
    }

    public func decoder() -> OpenCodeDecoder { OpenCodeDecoder() }
}

public struct OpenCodeDecoder: LineDecoder {
    private var session: String?
    private var wrote = false
    /// Text of the step under way. Whether it is the answer or words on the
    /// way to a tool only shows once the step goes on to use one, or ends.
    private var pending: [String] = []

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let json = JSON(parsing: line), let type = json["type"]?.string else { return [] }
        var events: [ChatEvent] = []
        if session == nil, let id = json["sessionID"]?.string {
            session = id
            events.append(.session(id))
        }
        let part = json["part"]
        switch type {
        case "text":
            if let text = part?["text"]?.string, !text.isEmpty { pending.append(text) }
        case "reasoning":
            if let text = part?["text"]?.string, !text.isEmpty { events.append(.reasoning(text)) }
        case "tool_use":
            events += narration()
            if let part { events += Self.tool(part) }
        case "step_finish":
            events += part?["reason"]?.string == "tool-calls" ? narration() : answer()
            if let tokens = part?["tokens"] {
                events.append(
                    .usage(Usage(input: tokens["input"]?.int ?? 0, output: tokens["output"]?.int ?? 0, cost: part?["cost"]?.double)))
            }
        case "error":
            let error = json["error"]
            let message = error?["message"]?.string ?? error?["data"]?["message"]?.string ?? error?["type"]?.string
            throw AIError.failed(message ?? "opencode stopped with an error")
        default:
            break
        }
        return events
    }

    public mutating func finish() throws -> [ChatEvent] { answer() }

    /// The step's text so far was said on the way to a tool.
    private mutating func narration() -> [ChatEvent] {
        defer { pending = [] }
        return pending.map { .reasoning($0) }
    }

    /// The step's text is the answer; parts after the first are new paragraphs.
    private mutating func answer() -> [ChatEvent] {
        defer { pending = [] }
        var events: [ChatEvent] = []
        for text in pending {
            events.append(.text(wrote ? "\n\n" + text : text))
            wrote = true
        }
        return events
    }

    private static func tool(_ part: JSON) -> [ChatEvent] {
        guard let id = part["id"]?.string else { return [] }
        let state = part["state"]
        let status = state?["status"]?.string
        let done = status == "completed" || status == "error"
        let input = state?["input"]
        switch part["tool"]?.string {
        case "websearch":
            let found = status == "completed" ? sources(in: state?["output"]?.string ?? "") : []
            return found + [.activity(.search(id, input?["query"]?.string, done: done))]
        case "webfetch":
            let url = input?["url"]?.string
            let page = url.flatMap(URL.init(string:)).map { ChatEvent.source(Source(url: $0, title: "")) }
            return (status == "completed" ? page.map { [$0] } ?? [] : []) + [.activity(.read(id, url, done: done))]
        default:
            return [.activity(Activity(id: id, title: part["tool"]?.string ?? "Tool", done: done))]
        }
    }

    /// A search's results, written as `## [Title](url)` headings.
    static func sources(in output: String) -> [ChatEvent] {
        let heading = /^##\s+\[(.+?)\]\((https?:\/\/(?:[^\s()]|\([^\s()]*\))+)\)/.anchorsMatchLineEndings()
        return output.matches(of: heading).compactMap { match in
            URL(string: String(match.output.2)).map { .source(Source(url: $0, title: String(match.output.1))) }
        }
    }
}
