import Foundation

/// What someone chose for a provider in Settings. Keys aren't here: they
/// live in the keychain (see `Secrets`).
public struct ProviderSetup: Codable, Equatable, Sendable {
    /// The model to use; nil for the provider's default.
    public var model: String?
    /// Another address for the provider, such as a server on another port.
    public var address: String?
    /// Where the agent's program is, when not where it was found.
    public var program: String?

    public init(model: String? = nil, address: String? = nil, program: String? = nil) {
        self.model = model
        self.address = address
        self.program = program
    }
}

/// Turns a provider and its setup into something to chat with, and lists
/// its models. Everything it reaches the world through can be replaced, so
/// tests run without a network or real programs.
public struct Connector: Sendable {
    public var runner: CommandRunning
    public var transport: HTTPTransport
    /// The folder agents work in.
    public var workspace: URL
    /// The programs found on the Mac (see `ToolLocator`).
    public var tools: ToolLocator.Found

    public init(
        runner: CommandRunning = ProcessRunner(), transport: HTTPTransport = URLSessionTransport(), workspace: URL,
        tools: ToolLocator.Found
    ) {
        self.runner = runner
        self.transport = transport
        self.workspace = workspace
        self.tools = tools
    }

    /// The model a request will name.
    public func model(for provider: Provider, setup: ProviderSetup) -> String {
        let chosen = setup.model?.trimmingCharacters(in: .whitespaces) ?? ""
        return chosen.isEmpty ? provider.defaultModel : chosen
    }

    /// The address used for an HTTP provider.
    public func base(for provider: Provider, setup: ProviderSetup) -> URL? {
        guard let base = provider.base else { return nil }
        guard provider.movable, let typed = setup.address?.trimmingCharacters(in: .whitespaces), !typed.isEmpty,
            let url = URL(string: typed.hasSuffix("/") ? String(typed.dropLast()) : typed), url.scheme?.hasPrefix("http") == true
        else { return base }
        return url
    }

    /// The agent's program: the one chosen in Settings, or the one found.
    public func program(for agent: Provider.Agent, setup: ProviderSetup) -> URL? {
        if let path = setup.program?.trimmingCharacters(in: .whitespaces), path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return tools.tools[agent.program]
    }

    /// Whether a server answers at the provider's address, asked briefly:
    /// for servers on the Mac, which may simply not be running.
    public func reachable(_ provider: Provider, setup: ProviderSetup) async -> Bool {
        guard let base = base(for: provider, setup: setup) else { return false }
        var request = URLRequest(url: base.appending(path: "models"))
        request.timeoutInterval = 1.5
        return (try? await transport.data(for: request)) != nil
    }

    /// Something to chat with, or why there can't be.
    public func service(for provider: Provider, setup: ProviderSetup, key: String?) throws -> any ChatService {
        let key = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider.needsKey, key?.isEmpty != false { throw AIError.needsKey(provider.name) }
        switch provider.connection {
        case .openAI:
            guard let base = base(for: provider, setup: setup) else { throw AIError.unreachable(provider.name) }
            return OpenAIChatService(base: base, key: key, headers: provider.headers, transport: transport)
        case .anthropic:
            guard let base = base(for: provider, setup: setup) else { throw AIError.unreachable(provider.name) }
            return AnthropicService(base: base, key: key ?? "", transport: transport)
        case .agent(let agent):
            guard let program = program(for: agent, setup: setup) else { throw AIError.notInstalled(provider.name) }
            let environment = tools.environment(for: program)
            switch agent {
            case .claudeCode:
                return AgentService(
                    wire: ClaudeCodeAgent(), executable: program, workspace: workspace, runner: runner, environment: environment)
            case .codex:
                return AgentService(wire: CodexAgent(), executable: program, workspace: workspace, runner: runner, environment: environment)
            case .openCode:
                return AgentService(
                    wire: OpenCodeAgent(), executable: program, workspace: workspace, runner: runner, environment: environment)
            case .geminiCLI:
                return AgentService(
                    wire: GeminiCLIAgent(), executable: program, workspace: workspace, runner: runner, environment: environment)
            }
        case .apple:
            return try AppleIntelligence.service()
        }
    }

    /// The models the provider offers, asked of the provider where it can say.
    public func models(for provider: Provider, setup: ProviderSetup, key: String?) async throws -> [Model] {
        switch provider.connection {
        case .openAI:
            guard let service = try service(for: provider, setup: setup, key: key) as? OpenAIChatService else { return provider.suggested }
            return try await service.models()
        case .anthropic:
            guard let service = try service(for: provider, setup: setup, key: key) as? AnthropicService else { return provider.suggested }
            return try await service.models()
        case .agent(.claudeCode):
            guard let program = program(for: .claudeCode, setup: setup) else { throw AIError.notInstalled(provider.name) }
            var command = ClaudeCodeModels.command(executable: program, workspace: workspace)
            command.environment = tools.environment(for: program)
            command.unset = AgentSession.marks
            try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            for try await line in runner.lines(of: command) {
                if let models = ClaudeCodeModels.models(in: line) { return models }
            }
            return provider.suggested
        case .agent(.openCode):
            guard let program = program(for: .openCode, setup: setup) else { throw AIError.notInstalled(provider.name) }
            var command = Command(executable: program, arguments: ["models"], directory: workspace)
            command.environment = tools.environment(for: program)
            command.unset = AgentSession.marks
            var models: [Model] = []
            for try await line in runner.lines(of: command) {
                let id = line.trimmingCharacters(in: .whitespaces)
                // provider/model, one to a line.
                if id.contains("/"), !id.contains(" ") { models.append(Model(id: id)) }
            }
            return models
        case .agent, .apple:
            return provider.suggested
        }
    }
}
