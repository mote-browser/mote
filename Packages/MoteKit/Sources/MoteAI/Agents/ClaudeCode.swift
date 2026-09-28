import Foundation

/// Claude Code's `claude -p`, with stream-json both ways: the prompt goes in
/// as a user line, and the answer comes back as Anthropic's own stream
/// events wrapped in lines of JSON.
///
/// Mote keeps it a chat: no tools but its own web search and page reading
/// when asked to search, no MCP servers, no hooks or slash commands, and
/// Mote's instructions in place of the coding agent's. Each
/// turn is a process of its own that resumes the session the first opened, so
/// Claude keeps the history and its prompt cache.
public struct ClaudeCodeAgent: AgentWire {
    public init() {}

    public func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command {
        let tools = request.search ? "WebSearch,WebFetch" : ""
        var arguments = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
            "--tools", tools, "--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#,
            "--settings", #"{"disableAllHooks":true}"#, "--disable-slash-commands", "--no-chrome",
        ]
        // Allowed up front: in print mode a tool that needs asking is refused.
        if request.search { arguments += ["--allowedTools", tools] }
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
    /// Tools under way, by id, as last shown.
    private var tools: [String: Activity] = [:]
    /// Some answer has been given; the next text block is a new paragraph.
    private var wrote = false
    private var blockStarted = false

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
        case "assistant":
            return described(json["message"]?["content"]?.array ?? [])
        case "user":
            return finishedTools(json["message"]?["content"]?.array ?? [], result: json["tool_use_result"])
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
            case "text_delta":
                guard let text = delta?["text"]?.string, !text.isEmpty else { return [] }
                return paragraph() + [.text(text)]
            case "thinking_delta": return delta?["thinking"]?.string.flatMap { $0.isEmpty ? nil : [.reasoning($0)] } ?? []
            default: return []
            }
        case "content_block_start":
            let block = event["content_block"]
            if block?["type"]?.string == "text" { blockStarted = true }
            guard ["tool_use", "server_tool_use"].contains(block?["type"]?.string ?? ""), let id = block?["id"]?.string else { return [] }
            let activity = Self.activity(id: id, name: block?["name"]?.string ?? "Tool", input: nil)
            tools[id] = activity
            return [.activity(activity)]
        default:
            return []
        }
    }

    /// A break before the first words of a text block that follows others,
    /// so words on either side of a search don't run together.
    private mutating func paragraph() -> [ChatEvent] {
        defer {
            wrote = true
            blockStarted = false
        }
        return wrote && blockStarted ? [.text("\n\n")] : []
    }

    /// The whole tool call arrives once its input is complete: a search now
    /// has its query, a page read its address.
    private mutating func described(_ content: [JSON]) -> [ChatEvent] {
        content.compactMap { block in
            guard block["type"]?.string == "tool_use", let id = block["id"]?.string else { return nil }
            let activity = Self.activity(id: id, name: block["name"]?.string ?? "Tool", input: block["input"])
            guard tools[id] != activity else { return nil }
            tools[id] = activity
            return .activity(activity)
        }
    }

    /// Tools that finished; web tools also give the pages they found or read.
    private mutating func finishedTools(_ content: [JSON], result: JSON?) -> [ChatEvent] {
        content.flatMap { block -> [ChatEvent] in
            guard block["type"]?.string == "tool_result", let id = block["tool_use_id"]?.string, var activity = tools[id] else { return [] }
            activity.done = true
            tools[id] = activity
            return Self.sources(in: result, for: activity) + [.activity(activity)]
        }
    }

    private static func activity(id: String, name: String, input: JSON?) -> Activity {
        switch name {
        case "WebSearch": .search(id, input?["query"]?.string)
        case "WebFetch": .read(id, input?["url"]?.string)
        default: Activity(id: id, title: name)
        }
    }

    /// `tool_use_result` holds a search's results as `{title, url}` lists, and
    /// a page read's address.
    private static func sources(in result: JSON?, for activity: Activity) -> [ChatEvent] {
        guard let result else { return [] }
        switch activity.kind {
        case .search:
            return result["results"]?.array.flatMap { $0["content"]?.array ?? [] }.compactMap { item in
                guard let address = item["url"]?.string, let url = URL(string: address) else { return nil }
                return .source(Source(url: url, title: item["title"]?.string ?? ""))
            } ?? []
        case .read:
            guard let address = result["url"]?.string, let url = URL(string: address) else { return [] }
            return [.source(Source(url: url, title: ""))]
        case .tool:
            return []
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
