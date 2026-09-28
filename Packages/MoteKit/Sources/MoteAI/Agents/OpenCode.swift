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
        return Command(executable: executable, arguments: arguments, directory: workspace, input: prompt)
    }

    public func decoder() -> OpenCodeDecoder { OpenCodeDecoder() }
}

public struct OpenCodeDecoder: LineDecoder {
    private var session: String?
    private var wrote = false

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
            if let text = part?["text"]?.string, !text.isEmpty {
                // Each part arrives whole; parts after the first are new paragraphs.
                events.append(.text(wrote ? "\n\n" + text : text))
                wrote = true
            }
        case "reasoning":
            if let text = part?["text"]?.string, !text.isEmpty { events.append(.reasoning(text)) }
        case "tool_use":
            if let id = part?["id"]?.string {
                let status = part?["state"]?["status"]?.string
                let done = status == "completed" || status == "error"
                events.append(.activity(Activity(id: id, title: part?["tool"]?.string ?? "Tool", done: done)))
            }
        case "step_finish":
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
}
