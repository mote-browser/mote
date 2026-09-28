import Foundation
import Testing

@testable import MoteAI

/// Answers every request with the same lines, and remembers what it was asked.
final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    var lines: [String] = []
    var body = Data()
    var failure: Error?
    private(set) var asked: [URLRequest] = []

    /// Answers for successive requests, in turn; `lines` once they run out.
    var turns: [[String]] = []

    func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        asked.append(request)
        if let failure { throw failure }
        let lines = turns.isEmpty ? lines : turns.removeFirst()
        return AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }
    }

    func data(for request: URLRequest) async throws -> Data {
        asked.append(request)
        if let failure { throw failure }
        return body
    }
}

/// Plays back lines for any command, and remembers the command.
final class FakeRunner: CommandRunning, @unchecked Sendable {
    var output: [String] = []
    var failure: Error?
    private(set) var ran: [Command] = []

    func lines(of command: Command) -> AsyncThrowingStream<String, Error> {
        ran.append(command)
        let (output, failure) = (output, failure)
        return AsyncThrowingStream { continuation in
            for line in output { continuation.yield(line) }
            continuation.finish(throwing: failure)
        }
    }
}

func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
    var events: [ChatEvent] = []
    for try await event in stream { events.append(event) }
    return events
}

private func body(_ request: URLRequest?) -> JSON? {
    request?.httpBody.flatMap { JSON(parsing: String(decoding: $0, as: UTF8.self)) }
}

private let conversation = [
    Message(role: .user, text: "Hi"), Message(role: .assistant, text: "Hello!"), Message(role: .user, text: "What's 2+2?"),
]

@Suite("Transcript")
struct TranscriptTests {
    @Test("A first message goes as it is")
    func first() {
        #expect(Transcript.prompt(for: [Message(role: .user, text: "Hi")]) == "Hi")
    }

    @Test("Later messages carry what was said before them")
    func later() {
        let prompt = Transcript.prompt(for: conversation)
        #expect(prompt.contains("User: Hi\n\nAssistant: Hello!"))
        #expect(prompt.hasSuffix("What's 2+2?"))
    }

    @Test("An empty reply left by a failure isn't written out")
    func skipsEmpty() {
        let messages = [Message(role: .user, text: "Hi"), Message(role: .assistant, text: ""), Message(role: .user, text: "Again")]
        #expect(!Transcript.prompt(for: messages).contains("Assistant:"))
    }
}

@Suite("Agent commands")
struct AgentCommandTests {
    let claude = URL(fileURLWithPath: "/bin/claude")
    let workspace = URL(fileURLWithPath: "/tmp/mote-ai")

    @Test("Claude Code starts a lean chat: no tools, no MCP, no hooks, Mote's instructions")
    func claudeFresh() throws {
        let request = ChatRequest(model: "sonnet", messages: [Message(role: .user, text: "Hi")], instructions: "Be brief")
        let command = ClaudeCodeAgent().command(for: request, executable: claude, workspace: workspace)
        #expect(command.directory == workspace)
        #expect(command.arguments.starts(with: ["-p", "--input-format", "stream-json", "--output-format", "stream-json"]))
        #expect(pair("--tools", in: command) == "")
        #expect(pair("--model", in: command) == "sonnet")
        #expect(pair("--system-prompt", in: command) == "Be brief")
        #expect(pair("--settings", in: command) == #"{"disableAllHooks":true}"#)
        #expect(!command.arguments.contains("--resume"))
        let line = try #require(JSON(parsing: command.input ?? ""))
        #expect(line["type"]?.string == "user")
        #expect(line["message"]?["content"]?.string == "Hi")
        #expect(command.input?.hasSuffix("\n") == true)
    }

    @Test("Claude Code searching gets its web tools, allowed without asking, and nothing else")
    func claudeSearches() {
        let request = ChatRequest(model: "", messages: [Message(role: .user, text: "Hi")], search: true)
        let command = ClaudeCodeAgent().command(for: request, executable: claude, workspace: workspace)
        #expect(pair("--tools", in: command) == "WebSearch,WebFetch")
        #expect(pair("--allowedTools", in: command) == "WebSearch,WebFetch")
        let chatting = ClaudeCodeAgent().command(
            for: ChatRequest(model: "", messages: [Message(role: .user, text: "Hi")]), executable: claude, workspace: workspace)
        #expect(!chatting.arguments.contains("--allowedTools"))
    }

    @Test("Claude Code resumes its session with only the new message")
    func claudeResumes() throws {
        let request = ChatRequest(model: "", messages: conversation, resume: "s-1")
        let command = ClaudeCodeAgent().command(for: request, executable: claude, workspace: workspace)
        #expect(pair("--resume", in: command) == "s-1")
        #expect(!command.arguments.contains("--model"))
        #expect(JSON(parsing: command.input ?? "")?["message"]?["content"]?.string == "What's 2+2?")
    }

    @Test("Claude Code without its session gets the conversation written out")
    func claudeCatchesUp() {
        let command = ClaudeCodeAgent().command(
            for: ChatRequest(model: "", messages: conversation), executable: claude, workspace: workspace)
        let prompt = JSON(parsing: command.input ?? "")?["message"]?["content"]?.string ?? ""
        #expect(prompt.contains("Assistant: Hello!"))
    }

    @Test("opencode takes the prompt on stdin, and its session to carry on")
    func opencode() {
        let fresh = OpenCodeAgent().command(
            for: ChatRequest(model: "opencode/big-pickle", messages: [Message(role: .user, text: "Hi")], instructions: "Be brief"),
            executable: claude, workspace: workspace)
        #expect(fresh.arguments.starts(with: ["run", "--format", "json"]))
        // Read-only: opencode's plan agent neither writes nor runs commands.
        #expect(pair("--agent", in: fresh) == "plan")
        #expect(pair("--model", in: fresh) == "opencode/big-pickle")
        #expect(fresh.input == "Be brief\n\n---\n\nHi")
        let later = OpenCodeAgent().command(
            for: ChatRequest(model: "", messages: conversation, resume: "ses_1"), executable: claude, workspace: workspace)
        #expect(pair("--session", in: later) == "ses_1")
        #expect(later.input == "What's 2+2?")
    }

    @Test("Searching turns on each agent's own web search")
    func agentsSearch() {
        let request = ChatRequest(model: "", messages: [Message(role: .user, text: "Hi")], search: true)
        let codex = CodexAgent().command(for: request, executable: claude, workspace: workspace)
        #expect(pair("-c", in: codex) == #"web_search="live""#)
        let opencode = OpenCodeAgent().command(for: request, executable: claude, workspace: workspace)
        #expect(opencode.environment["OPENCODE_ENABLE_EXA"] == "1")
        let quiet = ChatRequest(model: "", messages: [Message(role: .user, text: "Hi")])
        #expect(!CodexAgent().command(for: quiet, executable: claude, workspace: workspace).arguments.contains("-c"))
        #expect(OpenCodeAgent().command(for: quiet, executable: claude, workspace: workspace).environment["OPENCODE_ENABLE_EXA"] == nil)
    }

    @Test("Codex runs read-only outside a repository, resuming by thread")
    func codex() {
        let command = CodexAgent().command(
            for: ChatRequest(model: "gpt-5", messages: conversation, resume: "th-1"), executable: claude, workspace: workspace)
        #expect(command.arguments.starts(with: ["exec", "--json", "--skip-git-repo-check", "--sandbox", "read-only"]))
        #expect(Array(command.arguments.suffix(3)) == ["resume", "th-1", "-"])
        #expect(command.input == "What's 2+2?")
    }

    @Test("Gemini CLI streams JSON and resumes by session")
    func gemini() {
        let command = GeminiCLIAgent().command(
            for: ChatRequest(model: "", messages: conversation, resume: "g-1"), executable: claude, workspace: workspace)
        #expect(pair("--output-format", in: command) == "stream-json")
        #expect(pair("--resume", in: command) == "g-1")
        #expect(command.input == "What's 2+2?")
    }

    @Test("An agent service runs its command with the environment it was given, and decodes the output")
    func service() async throws {
        let runner = FakeRunner()
        runner.output = [
            #"{"type":"system","subtype":"init","session_id":"s-9"}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"4"}},"parent_tool_use_id":null}"#,
        ]
        let service = AgentService(
            wire: ClaudeCodeAgent(), executable: claude, workspace: FileManager.default.temporaryDirectory.appending(path: "mote-ai-test"),
            runner: runner, environment: ["PATH": "/opt/homebrew/bin"])
        let events = try await collect(service.reply(to: ChatRequest(model: "", messages: conversation)))
        #expect(events == [.session("s-9"), .text("4")])
        #expect(runner.ran.first?.environment["PATH"] == "/opt/homebrew/bin")
    }

    @Test("Agents don't inherit the marks of an agent session Mote was started from")
    func sessionMarks() async throws {
        let runner = FakeRunner()
        let service = AgentService(wire: ClaudeCodeAgent(), executable: claude, workspace: workspace, runner: runner)
        _ = try await collect(service.reply(to: ChatRequest(model: "", messages: conversation)))
        let unset = try #require(runner.ran.first?.unset)
        #expect(unset.contains("CLAUDECODE") && unset.contains("CLAUDE_CODE_SESSION_ID") && unset.contains("CLAUDE_CODE_MESSAGING_SOCKET"))
        #expect(!unset.contains("CLAUDE_CODE_USE_BEDROCK"))
    }

    @Test("An agent that fails fails the reply")
    func serviceFailure() async {
        let runner = FakeRunner()
        runner.failure = AIError.failed("Not logged in")
        let service = AgentService(wire: CodexAgent(), executable: claude, workspace: workspace, runner: runner)
        await #expect(throws: AIError.failed("Not logged in")) {
            try await collect(service.reply(to: ChatRequest(model: "", messages: conversation)))
        }
    }

    private func pair(_ flag: String, in command: Command) -> String? {
        guard let index = command.arguments.firstIndex(of: flag), command.arguments.indices.contains(index + 1) else { return nil }
        return command.arguments[index + 1]
    }
}

@Suite("HTTP providers")
struct HTTPProviderTests {
    let base = URL(string: "https://api.example.com/v1")!

    @Test("Chat Completions gets the system prompt first, the history, and streaming on")
    func openAIRequest() throws {
        let service = OpenAIChatService(base: base, key: "sk-1", headers: ["X-Title": "Mote"], transport: FakeHTTP())
        let request = service.request(for: ChatRequest(model: "gpt-5", messages: conversation, instructions: "Be brief"))
        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        #expect(request.value(forHTTPHeaderField: "X-Title") == "Mote")
        let json = try #require(body(request))
        #expect(json["model"]?.string == "gpt-5")
        #expect(json["stream"]?.bool == true)
        let messages = json["messages"]?.array ?? []
        #expect(messages.map { $0["role"]?.string } == ["system", "user", "assistant", "user"])
        #expect(messages.last?["content"]?.string == "What's 2+2?")
    }

    @Test("A local server without a key gets no Authorization header")
    func noKey() {
        let service = OpenAIChatService(base: URL(string: "http://localhost:11434/v1")!, key: nil, transport: FakeHTTP())
        #expect(
            service.request(for: ChatRequest(model: "llama3", messages: conversation)).value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Chat Completions streams through its decoder")
    func openAIStream() async throws {
        let http = FakeHTTP()
        http.lines = [#"data: {"choices":[{"delta":{"content":"4"}}]}"#, "data: [DONE]"]
        let events = try await collect(
            OpenAIChatService(base: base, key: "k", transport: http).reply(to: ChatRequest(model: "m", messages: conversation)))
        #expect(events == [.text("4")])
        #expect(http.asked.count == 1)
    }

    @Test("The model list is read from data, sorted by name")
    func openAIModels() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"object":"list","data":[{"id":"gpt-5"},{"id":"gpt-4.1"},{"id":"gpt-10"}]}"#.utf8)
        let models = try await OpenAIChatService(base: base, key: "k", transport: http).models()
        #expect(models.map(\.id) == ["gpt-4.1", "gpt-5", "gpt-10"])
        #expect(http.asked.first?.url?.absoluteString == "https://api.example.com/v1/models")
    }

    @Test("Models that can't chat (embeddings, speech, images, moderation) are left out")
    func chatModelsOnly() async throws {
        let http = FakeHTTP()
        http.body = Data(
            #"{"data":[{"id":"gpt-5"},{"id":"text-embedding-3-large"},{"id":"tts-1"},{"id":"whisper-1"},{"id":"dall-e-3"},{"id":"omni-moderation-latest"},{"id":"gpt-image-1"},{"id":"gpt-4o-transcribe"},{"id":"nomic-embed-text"}]}"#
                .utf8)
        let models = try await OpenAIChatService(base: base, key: "k", transport: http).models()
        #expect(models.map(\.id) == ["gpt-5"])
    }

    @Test("Anthropic gets its headers, the system prompt apart, and a token cap")
    func anthropicRequest() throws {
        let service = AnthropicService(base: URL(string: "https://api.anthropic.com")!, key: "sk-ant", transport: FakeHTTP())
        let request = service.request(for: ChatRequest(model: "claude-sonnet-5", messages: conversation, instructions: "Be brief"))
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let json = try #require(body(request))
        #expect(json["system"]?.string == "Be brief")
        #expect(json["max_tokens"]?.int == AnthropicService.replyLimit)
        #expect(json["messages"]?.array.map { $0["role"]?.string } == ["user", "assistant", "user"])
    }

    @Test("Anthropic searching gets its web search tool")
    func anthropicSearch() throws {
        let service = AnthropicService(base: URL(string: "https://api.anthropic.com")!, key: "k", transport: FakeHTTP())
        let request = service.request(for: ChatRequest(model: "m", messages: conversation, search: true))
        let tool = try #require(body(request)?["tools"]?[0])
        #expect(tool["type"]?.string == "web_search_20250305")
        #expect(tool["name"]?.string == "web_search")
        #expect(body(service.request(for: ChatRequest(model: "m", messages: conversation)))?["tools"] == nil)
    }

    @Test("The Responses API gets the history as input, the system prompt apart, and web search")
    func responsesRequest() throws {
        let service = ResponsesService(base: base, key: "sk-1", transport: FakeHTTP())
        let request = service.request(for: ChatRequest(model: "gpt-5", messages: conversation, instructions: "Be brief", search: true))
        #expect(request.url?.absoluteString == "https://api.example.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
        let json = try #require(body(request))
        #expect(json["instructions"]?.string == "Be brief")
        #expect(json["stream"]?.bool == true)
        #expect(json["input"]?.array.map { $0["role"]?.string } == ["user", "assistant", "user"])
        #expect(json["tools"]?[0]?["type"]?.string == "web_search")
        // Every page searched, not only those cited.
        #expect(json["include"]?[0]?.string == "web_search_call.action.sources")
    }

    @Test("A gateway's web plugin is asked for with :online")
    func online() throws {
        let service = OpenAIChatService(base: base, key: "k", online: true, transport: FakeHTTP())
        let json = try #require(body(service.request(for: ChatRequest(model: "openai/gpt-5", messages: conversation, search: true))))
        #expect(json["model"]?.string == "openai/gpt-5:online")
        let plain = try #require(body(service.request(for: ChatRequest(model: "openai/gpt-5", messages: conversation))))
        #expect(plain["model"]?.string == "openai/gpt-5")
    }

    @Test("Anthropic's model list keeps display names")
    func anthropicModels() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"data":[{"id":"claude-sonnet-5","display_name":"Claude Sonnet 5"}]}"#.utf8)
        let models = try await AnthropicService(base: URL(string: "https://api.anthropic.com")!, key: "k", transport: http).models()
        #expect(models == [Model(id: "claude-sonnet-5", name: "Claude Sonnet 5")])
    }

    @Test("Error bodies give the provider's own message")
    func errors() {
        #expect(
            HTTPFailure.error(status: 401, body: Data(#"{"error":{"message":"Incorrect API key"}}"#.utf8))
                == .http(status: 401, message: "Incorrect API key"))
        #expect(
            HTTPFailure.error(status: 404, body: Data(#"{"error":"model 'x' not found"}"#.utf8))
                == .http(status: 404, message: "model 'x' not found"))
        #expect(HTTPFailure.error(status: 502, body: Data("<html>Bad gateway</html>".utf8)) == .http(status: 502, message: ""))
        #expect(AIError.http(status: 429, message: "").errorDescription == "Too many requests — try again in a moment")
    }
}

@Suite("Anthropic pauses")
struct AnthropicPauseTests {
    /// A turn whose server search loop paused after a search, and one that finishes it.
    let paused = [
        #"data: {"type":"message_start","message":{"usage":{"input_tokens":10}}}"#,
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srv1","name":"web_search","input":{}}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"swift\"}"}}"#,
        #"data: {"type":"content_block_stop","index":0}"#,
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srv1","content":[{"type":"web_search_result","title":"Swift","url":"https://swift.org","encrypted_content":"ENC","page_age":null}]}}"#,
        #"data: {"type":"content_block_stop","index":1}"#,
        #"data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://swift.org","title":"Swift","cited_text":"Swift 6.4","encrypted_index":"IDX"}}}"#,
        #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Swift 6.4 is out."}}"#,
        #"data: {"type":"content_block_stop","index":2}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"pause_turn"},"usage":{"output_tokens":20}}"#,
        #"data: {"type":"message_stop"}"#,
    ]
    let resumed = [
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":" More."}}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":3}}"#,
    ]
    let question = ChatRequest(model: "m", messages: [Message(role: .user, text: "Swift?")], search: true)

    @Test("The decoder keeps the reply's blocks as the API sent them, and says when it paused")
    func blocks() throws {
        var decoder = AnthropicDecoder()
        for line in paused { _ = try decoder.read(line) }
        #expect(decoder.paused)
        let blocks = decoder.blocks
        #expect(blocks.map { $0["type"]?.string } == ["server_tool_use", "web_search_tool_result", "text"])
        #expect(blocks[0]["input"]?["query"]?.string == "swift")
        #expect(blocks[1]["content"]?[0]?["encrypted_content"]?.string == "ENC")
        #expect(blocks[2]["text"]?.string == "Swift 6.4 is out.")
        #expect(blocks[2]["citations"]?[0]?["encrypted_index"]?.string == "IDX")
    }

    @Test("A paused turn is sent again with what it said so far, and carries on in the same reply")
    func resumes() async throws {
        let http = FakeHTTP()
        http.turns = [paused, resumed]
        let events = try await collect(
            AnthropicService(base: URL(string: "https://api.anthropic.com")!, key: "k", transport: http).reply(to: question))
        let text = events.compactMap { event in if case .text(let text) = event { text } else { nil } }.joined()
        #expect(text == "Swift 6.4 is out. [swift.org](https://swift.org) More.")
        #expect(http.asked.count == 2)
        let second = try #require(http.asked[1].httpBody.flatMap { JSON(parsing: String(decoding: $0, as: UTF8.self)) })
        let messages = second["messages"]?.array ?? []
        #expect(messages.map { $0["role"]?.string } == ["user", "assistant"])
        #expect(messages[1]["content"]?[1]?["content"]?[0]?["encrypted_content"]?.string == "ENC")
        #expect(messages[1]["content"]?[0]?["input"]?["query"]?.string == "swift")
    }

    @Test("A turn that keeps pausing is carried on only so many times")
    func limit() async throws {
        let http = FakeHTTP()
        http.lines = paused
        _ = try await collect(
            AnthropicService(base: URL(string: "https://api.anthropic.com")!, key: "k", transport: http).reply(to: question))
        #expect(http.asked.count == AnthropicService.continuations + 1)
    }
}
