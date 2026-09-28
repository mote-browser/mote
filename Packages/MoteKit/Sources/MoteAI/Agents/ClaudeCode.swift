import Foundation

/// Claude Code's `claude -p`, with stream-json both ways: the prompt goes in
/// as a user line, and the answer comes back as Anthropic's own stream
/// events wrapped in lines of JSON.
///
/// Mote keeps it a chat: no tools, no MCP servers, no hooks or slash
/// commands, and Mote's instructions in place of the coding agent's. Each
/// turn is a process of its own that resumes the session the first opened, so
/// Claude keeps the history and its prompt cache.
public struct ClaudeCodeAgent: AgentWire {
    public init() {}

    public func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command {
        var arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--tools", "", "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--settings", #"{"disableAllHooks":true}"#, "--disable-slash-commands", "--no-chrome",
        ]
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        if let instructions = request.instructions, !instructions.isEmpty { arguments += ["--system-prompt", instructions] }
        if let session = request.resume { arguments += ["--resume", session] }
        let prompt = request.resume == nil ? Transcript.prompt(for: request.messages) : request.prompt
        let line = JSON.encode(["type": "user", "message": ["role": "user", "content": prompt]])
        return Command(executable: executable, arguments: arguments, directory: workspace, input: line + "\n")
    }

    public func decoder() -> ClaudeCodeDecoder { ClaudeCodeDecoder() }
}

public struct ClaudeCodeDecoder: LineDecoder {
    private var session: String?
    private var tools: [String: String] = [:]

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let json = JSON(parsing: line), let type = json["type"]?.string else { return [] }
        // Subagents stream too; only the main thread is the reply.
        if let parent = json["parent_tool_use_id"], parent != .null { return [] }
        switch type {
        case "system":
            guard json["subtype"]?.string == "init", let id = json["session_id"]?.string else { return [] }
            return started(id)
        case "stream_event":
            return streamed(json["event"])
        case "user":
            return finishedTools(json["message"]?["content"]?.array ?? [])
        case "result":
            return try result(json)
        default:
            return []
        }
    }

    private mutating func started(_ id: String) -> [ChatEvent] {
        guard session == nil else { return [] }
        session = id
        return [.session(id)]
    }

    private mutating func streamed(_ event: JSON?) -> [ChatEvent] {
        guard let event else { return [] }
        switch event["type"]?.string {
        case "content_block_delta":
            let delta = event["delta"]
            switch delta?["type"]?.string {
            case "text_delta": return delta?["text"]?.string.flatMap { $0.isEmpty ? nil : [.text($0)] } ?? []
            case "thinking_delta": return delta?["thinking"]?.string.flatMap { $0.isEmpty ? nil : [.reasoning($0)] } ?? []
            default: return []
            }
        case "content_block_start":
            let block = event["content_block"]
            guard ["tool_use", "server_tool_use"].contains(block?["type"]?.string ?? ""), let id = block?["id"]?.string else { return [] }
            let name = block?["name"]?.string ?? "Tool"
            tools[id] = name
            return [.activity(Activity(id: id, title: name))]
        default:
            return []
        }
    }

    private mutating func finishedTools(_ content: [JSON]) -> [ChatEvent] {
        content.compactMap { block in
            guard block["type"]?.string == "tool_result", let id = block["tool_use_id"]?.string, let name = tools[id] else { return nil }
            return .activity(Activity(id: id, title: name, done: true))
        }
    }

    private mutating func result(_ json: JSON) throws -> [ChatEvent] {
        let failed = json["is_error"]?.bool == true || json["subtype"]?.string?.hasPrefix("error") == true
        if failed {
            let said = json["result"]?.string ?? json["errors"]?.array.compactMap(\.string).joined(separator: "\n") ?? ""
            throw AIError.failed(said.isEmpty ? "Claude Code stopped (\(json["subtype"]?.string ?? "error"))" : said)
        }
        var events: [ChatEvent] = []
        if let id = json["session_id"]?.string { events += started(id) }
        if let usage = json["usage"] {
            let input = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage[$0]?.int }.reduce(
                0, +)
            events.append(.usage(Usage(input: input, output: usage["output_tokens"]?.int ?? 0, cost: json["total_cost_usd"]?.double)))
        }
        return events
    }
}

/// Lists the models Claude Code offers, by asking it to start up and say
/// what it has, without sending a prompt.
public enum ClaudeCodeModels {
    public static func command(executable: URL, workspace: URL) -> Command {
        let ask = JSON.encode(["type": "control_request", "request_id": "mote-models", "request": ["subtype": "initialize"]])
        return Command(
            executable: executable,
            arguments: [
                "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#, "--settings", #"{"disableAllHooks":true}"#,
            ],
            directory: workspace, input: ask + "\n")
    }

    /// The models in the answer to `command`, if this line is it.
    public static func models(in line: String) -> [Model]? {
        guard let json = JSON(parsing: line), json["type"]?.string == "control_response",
            let listed = json["response"]?["response"]?["models"]?.array
        else { return nil }
        return listed.compactMap { entry in
            guard let id = entry["value"]?.string, id != "default" else { return nil }
            let name = entry["displayName"]?.string ?? id
            // "Opus 5.5 · Best for…" names the model in its description's first part.
            let detail = entry["description"]?.string?.components(separatedBy: " · ").last
            return Model(id: id, name: name, detail: detail)
        }
    }
}
