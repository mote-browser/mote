import Foundation

/// Google's Gemini CLI, `gemini --output-format stream-json`: the prompt on
/// stdin, the answer as streamed message lines.
public struct GeminiCLIAgent: AgentWire {
    public init() {}

    public func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command {
        var arguments = ["--output-format", "stream-json"]
        if !request.model.isEmpty { arguments += ["--model", request.model] }
        let prompt: String
        if let session = request.resume {
            arguments += ["--resume", session]
            prompt = request.prompt
        } else {
            let transcript = Transcript.prompt(for: request.messages)
            prompt = request.instructions.map { "\($0)\n\n---\n\n\(transcript)" } ?? transcript
        }
        // Without a terminal it reads the prompt from stdin; `-p ""` makes it headless.
        return Command(executable: executable, arguments: arguments + ["-p", ""], directory: workspace, input: prompt)
    }

    public func decoder() -> GeminiCLIDecoder { GeminiCLIDecoder() }
}

public struct GeminiCLIDecoder: LineDecoder {
    private var tools: [String: Activity] = [:]

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let json = JSON(parsing: line), let type = json["type"]?.string else { return [] }
        switch type {
        case "init":
            return json["session_id"]?.string.map { [.session($0)] } ?? []
        case "message":
            guard json["role"]?.string == "assistant", let text = json["content"]?.string, !text.isEmpty else { return [] }
            return [.text(text)]
        case "tool_use":
            guard let id = json["tool_id"]?.string else { return [] }
            let activity = Self.activity(id: id, name: json["tool_name"]?.string ?? "Tool", parameters: json["parameters"])
            tools[id] = activity
            return [.activity(activity)]
        case "tool_result":
            guard let id = json["tool_id"]?.string else { return [] }
            var activity = tools[id] ?? Activity(id: id, title: "Tool")
            activity.done = true
            let found = activity.kind == .search ? Self.sources(in: json["output"]?.string ?? "") : []
            return found + [.activity(activity)]
        case "error":
            guard json["severity"]?.string != "warning" else { return [] }
            throw AIError.failed(json["message"]?.string ?? "Gemini stopped with an error")
        case "result":
            if json["status"]?.string == "error" {
                throw AIError.failed(json["error"]?["message"]?.string ?? "Gemini stopped with an error")
            }
            guard let stats = json["stats"], let input = stats["input_tokens"]?.int else { return [] }
            return [.usage(Usage(input: input, output: stats["output_tokens"]?.int ?? 0))]
        default:
            return []
        }
    }

    private static func activity(id: String, name: String, parameters: JSON?) -> Activity {
        switch name {
        case "google_web_search":
            return .search(id, parameters?["query"]?.string)
        case "web_fetch":
            // Its prompt names the pages to read.
            let prompt = parameters?["prompt"]?.string
            let url = parameters?["url"]?.string ?? prompt?.firstMatch(of: /https?:\/\/[^\s)"']+/).map { String($0.output) }
            return .read(id, url)
        default:
            return Activity(id: id, title: name)
        }
    }

    /// The search's own list of what it cited: `[1] Title (url)` lines.
    static func sources(in output: String) -> [ChatEvent] {
        let line = /^\[\d+\]\s+(.+?)\s+\((https?:\/\/(?:[^\s()]|\([^\s()]*\))+)\)\s*$/.anchorsMatchLineEndings()
        return output.matches(of: line).compactMap { match in
            URL(string: String(match.output.2)).map { .source(Source(url: $0, title: String(match.output.1))) }
        }
    }
}
