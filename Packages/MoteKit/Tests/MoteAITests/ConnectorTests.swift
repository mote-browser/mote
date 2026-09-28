import Foundation
import Testing

@testable import MoteAI

@Suite("Connector")
struct ConnectorTests {
    let claude = URL(fileURLWithPath: "/Users/someone/.local/bin/claude")

    private func connector(runner: FakeRunner = FakeRunner(), http: FakeHTTP = FakeHTTP()) -> Connector {
        Connector(
            runner: runner, transport: http, workspace: FileManager.default.temporaryDirectory.appending(path: "mote-ai-tests"),
            tools: ToolLocator.Found(tools: ["claude": claude], path: "/usr/bin"))
    }

    private func provider(_ id: String) throws -> Provider { try #require(Provider.named(id)) }

    @Test("Every provider has its own id")
    func uniqueIDs() {
        #expect(Set(Provider.all.map(\.id)).count == Provider.all.count)
    }

    @Test("A cloud provider without a key says it needs one")
    func needsKey() throws {
        #expect(throws: AIError.needsKey("OpenAI")) { try connector().service(for: provider("openai"), setup: ProviderSetup(), key: nil) }
        #expect(throws: AIError.needsKey("OpenAI")) { try connector().service(for: provider("openai"), setup: ProviderSetup(), key: "  ") }
        #expect(try connector().service(for: provider("openai"), setup: ProviderSetup(), key: "sk-1") is OpenAIChatService)
        #expect(try connector().service(for: provider("anthropic"), setup: ProviderSetup(), key: "sk-ant") is AnthropicService)
    }

    @Test("Local servers need no key")
    func localServer() throws {
        #expect(try connector().service(for: provider("ollama"), setup: ProviderSetup(), key: nil) is OpenAIChatService)
    }

    @Test("An agent that isn't installed says so; one that is runs where it was found")
    func agents() async throws {
        #expect(throws: AIError.notInstalled("Codex")) { try connector().service(for: provider("codex"), setup: ProviderSetup(), key: nil) }
        let runner = FakeRunner()
        let service = try connector(runner: runner).service(for: provider("claude-code"), setup: ProviderSetup(), key: nil)
        _ = try await collect(service.reply(to: ChatRequest(model: "sonnet", messages: [Message(role: .user, text: "Hi")])))
        let command = try #require(runner.ran.first)
        #expect(command.executable == claude)
        #expect(command.environment["PATH"]?.hasPrefix("/Users/someone/.local/bin:/usr/bin") == true)
    }

    @Test("A program chosen in Settings wins over the one found")
    func programOverride() {
        let setup = ProviderSetup(program: "/opt/tools/codex")
        #expect(connector().program(for: .codex, setup: setup)?.path == "/opt/tools/codex")
        #expect(connector().program(for: .claudeCode, setup: ProviderSetup(program: "relative")) == claude)
    }

    @Test("A movable provider takes the address typed for it; others keep theirs")
    func addresses() throws {
        let ollama = try provider("ollama")
        #expect(
            connector().base(for: ollama, setup: ProviderSetup(address: "http://studio.local:11434/v1/"))?.absoluteString
                == "http://studio.local:11434/v1")
        #expect(connector().base(for: ollama, setup: ProviderSetup(address: "not a url"))?.absoluteString == "http://localhost:11434/v1")
        #expect(
            connector().base(for: try provider("openai"), setup: ProviderSetup(address: "http://evil.example"))?.host() == "api.openai.com")
    }

    @Test("The model is the chosen one, or the provider's default")
    func models() throws {
        let anthropic = try provider("anthropic")
        #expect(connector().model(for: anthropic, setup: ProviderSetup()) == "claude-sonnet-5")
        #expect(connector().model(for: anthropic, setup: ProviderSetup(model: " claude-opus-5 ")) == "claude-opus-5")
    }

    @Test("Claude Code lists its models when asked to start up")
    func claudeModels() async throws {
        let runner = FakeRunner()
        runner.output = [
            #"{"type":"system","subtype":"init"}"#,
            #"{"type":"control_response","response":{"subtype":"success","request_id":"mote-models","response":{"models":[{"value":"default","displayName":"Default (recommended)"},{"value":"opus","displayName":"Opus 5.5","description":"Most capable for ambitious work"},{"value":"haiku","displayName":"Haiku 4.5","description":"Fastest for quick answers"}]}}}"#,
        ]
        let models = try await connector(runner: runner).models(for: provider("claude-code"), setup: ProviderSetup(), key: nil)
        #expect(
            models == [
                Model(id: "opus", name: "Opus 5.5", detail: "Most capable for ambitious work"),
                Model(id: "haiku", name: "Haiku 4.5", detail: "Fastest for quick answers"),
            ])
        #expect(runner.ran.first?.unset.contains("CLAUDECODE") == true)
        let input = try #require(runner.ran.first?.input)
        #expect(JSON(parsing: input)?["request"]?["subtype"]?.string == "initialize")
    }

    @Test("opencode lists provider/model lines, and nothing else")
    func openCodeModels() async throws {
        let runner = FakeRunner()
        runner.output = ["deepseek/deepseek-flash", "opencode/big-pickle", "", "Some notice here"]
        let connector = Connector(
            runner: runner, transport: FakeHTTP(), workspace: FileManager.default.temporaryDirectory,
            tools: ToolLocator.Found(tools: ["opencode": URL(fileURLWithPath: "/opt/homebrew/bin/opencode")], path: nil))
        let models = try await connector.models(for: provider("opencode"), setup: ProviderSetup(), key: nil)
        #expect(models.map(\.id) == ["deepseek/deepseek-flash", "opencode/big-pickle"])
        #expect(runner.ran.first?.arguments == ["models"])
    }

    @Test("A cloud provider's models come from its API")
    func cloudModels() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"data":[{"id":"grok-4"}]}"#.utf8)
        let models = try await connector(http: http).models(for: provider("xai"), setup: ProviderSetup(), key: "xai-1")
        #expect(models.map(\.id) == ["grok-4"])
        #expect(http.asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer xai-1")
    }

    @Test("A local server answers or doesn't; the question is quick and asks for nothing much")
    func reachable() async throws {
        let http = FakeHTTP()
        http.body = Data(#"{"data":[]}"#.utf8)
        let ollama = try provider("ollama")
        #expect(await connector(http: http).reachable(ollama, setup: ProviderSetup()))
        let request = try #require(http.asked.first)
        #expect(request.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(request.timeoutInterval <= 2)
        http.failure = AIError.unreachable("localhost")
        #expect(await !connector(http: http).reachable(ollama, setup: ProviderSetup()))
    }

    @Test("Providers that can search say so; searching with OpenAI or xAI goes through the Responses API")
    func searching() throws {
        #expect(
            Set(Provider.all.filter(\.searches).map(\.id)) == [
                "claude-code", "codex", "opencode", "gemini-cli", "anthropic", "openai", "xai", "openrouter",
            ])
        #expect(try connector().service(for: provider("openai"), setup: ProviderSetup(), key: "k", search: true) is ResponsesService)
        #expect(try connector().service(for: provider("xai"), setup: ProviderSetup(), key: "k", search: true) is ResponsesService)
        #expect(try connector().service(for: provider("openai"), setup: ProviderSetup(), key: "k") is OpenAIChatService)
    }
}
