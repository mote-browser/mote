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
    private var tools: [String: String] = [:]

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
            let name = json["tool_name"]?.string ?? "Tool"
            tools[id] = name
            return [.activity(Activity(id: id, title: name))]
        case "tool_result":
            guard let id = json["tool_id"]?.string else { return [] }
            return [.activity(Activity(id: id, title: tools[id] ?? "Tool", done: true))]
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
}
