import Foundation

/// OpenAI's Codex CLI, `codex exec --json`: one line per event of the turn,
/// with whole items rather than streamed words. Runs read-only.
public struct CodexAgent: AgentWire {
    public init() {}

    public func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command {
        var arguments = ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only"]
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        let prompt: String
        if let session = request.resume {
            arguments += ["resume", session]
            prompt = request.prompt
        } else {
            let transcript = Transcript.prompt(for: request.messages)
            prompt = request.instructions.map { "\($0)\n\n---\n\n\(transcript)" } ?? transcript
        }
        // "-" reads the prompt from stdin, which keeps it out of the process list.
        return Command(executable: executable, arguments: arguments + ["-"], directory: workspace, input: prompt)
    }

    public func decoder() -> CodexDecoder { CodexDecoder() }
}

public struct CodexDecoder: LineDecoder {
    private var wrote = false

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let json = JSON(parsing: line), let type = json["type"]?.string else { return [] }
        switch type {
        case "thread.started":
            return json["thread_id"]?.string.map { [.session($0)] } ?? []
        case "item.started", "item.completed":
            return item(json["item"], done: type == "item.completed")
        case "turn.completed":
            let usage = json["usage"]
            return [.usage(Usage(input: usage?["input_tokens"]?.int ?? 0, output: usage?["output_tokens"]?.int ?? 0))]
        case "turn.failed":
            throw AIError.failed(json["error"]?["message"]?.string ?? "Codex couldn't finish the turn")
        case "error":
            throw AIError.failed(json["message"]?.string ?? "Codex stopped with an error")
        default:
            return []
        }
    }

    private mutating func item(_ item: JSON?, done: Bool) -> [ChatEvent] {
        guard let item, let kind = item["type"]?.string else { return [] }
        switch kind {
        case "agent_message":
            guard done, let text = item["text"]?.string, !text.isEmpty else { return [] }
            defer { wrote = true }
            return [.text(wrote ? "\n\n" + text : text)]
        case "reasoning":
            guard done, let text = item["text"]?.string, !text.isEmpty else { return [] }
            return [.reasoning(text)]
        case "command_execution", "web_search", "mcp_tool_call", "file_change":
            guard let id = item["id"]?.string else { return [] }
            let title =
                item["command"]?.string ?? item["query"]?.string ?? item["tool"]?.string ?? kind.replacingOccurrences(of: "_", with: " ")
            return [.activity(Activity(id: id, title: title, done: done))]
        default:
            return []
        }
    }
}
