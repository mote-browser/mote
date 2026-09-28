import Foundation

/// A place replies can come from, described as data: what it's called, how
/// it's reached and what it needs. Adding a provider that speaks an API Mote
/// already knows is adding an entry to `Provider.all`.
public struct Provider: Identifiable, Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        /// An agent installed on the Mac, signed in with its own account.
        case agent
        /// A model on the Mac itself, or a server running one here.
        case local
        /// An API on the internet, with a key.
        case cloud
    }

    public enum Connection: Hashable, Sendable {
        /// OpenAI's Chat Completions, from this base (up to the version).
        case openAI(URL)
        case anthropic(URL)
        case agent(Agent)
        /// Apple's on-device model.
        case apple
    }

    /// How a provider searches the web, with its own search.
    public enum Search: Sendable {
        /// Its own tools, in the same requests (agents, Anthropic).
        case own
        /// Through the Responses API (OpenAI, xAI).
        case responses
        /// The model's `:online` variant (OpenRouter).
        case online
    }

    public enum Agent: String, CaseIterable, Sendable {
        case claudeCode, codex, openCode, geminiCLI

        /// The program's name on the command line.
        public var program: String {
            switch self {
            case .claudeCode: "claude"
            case .codex: "codex"
            case .openCode: "opencode"
            case .geminiCLI: "gemini"
            }
        }

        /// How to install it, for when it isn't.
        public var install: String {
            switch self {
            case .claudeCode: "curl -fsSL https://claude.ai/install.sh | bash"
            case .codex: "npm install -g @openai/codex"
            case .openCode: "brew install sst/tap/opencode"
            case .geminiCLI: "npm install -g @google/gemini-cli"
            }
        }
    }

    public let id: String
    public let name: String
    public let kind: Kind
    public let connection: Connection
    /// A line on what it is.
    public let summary: String
    public let needsKey: Bool
    /// Where to get a key.
    public let keyPage: URL?
    /// Used until another is picked; empty lets the provider choose.
    public let defaultModel: String
    /// Offered before the provider's own list is fetched, or when it has none.
    public let suggested: [Model]
    /// The address can be changed, as for a server on another port.
    public let movable: Bool
    /// Sent with every request.
    public let headers: [String: String]
    /// How it searches the web; nil when it can't.
    public let search: Search?

    public var searches: Bool { search != nil }

    init(
        id: String, name: String, kind: Kind, connection: Connection, summary: String, needsKey: Bool = false, keyPage: String? = nil,
        defaultModel: String = "", suggested: [Model] = [], movable: Bool = false, headers: [String: String] = [:], search: Search? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.connection = connection
        self.summary = summary
        self.needsKey = needsKey
        self.keyPage = keyPage.flatMap(URL.init(string:))
        self.defaultModel = defaultModel
        self.suggested = suggested
        self.movable = movable
        self.headers = headers
        self.search = search
    }

    public static func == (a: Provider, b: Provider) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }

    public var agent: Agent? {
        if case .agent(let agent) = connection { return agent }
        return nil
    }

    /// The base address, for providers reached over HTTP.
    public var base: URL? {
        switch connection {
        case .openAI(let url), .anthropic(let url): url
        case .agent, .apple: nil
        }
    }

    public static func named(_ id: String) -> Provider? { all.first { $0.id == id } }
}

extension Provider {
    public static let all: [Provider] = agents + local + cloud

    static let agents: [Provider] = [
        Provider(
            id: "claude-code", name: "Claude Code", kind: .agent, connection: .agent(.claudeCode),
            summary: "Anthropic's agent, with your Claude plan",
            suggested: [
                Model(id: "sonnet", name: "Sonnet"), Model(id: "opus", name: "Opus"), Model(id: "haiku", name: "Haiku"),
            ], search: .own),
        Provider(
            id: "codex", name: "Codex", kind: .agent, connection: .agent(.codex), summary: "OpenAI's agent, with your ChatGPT plan",
            search: .own),
        Provider(
            id: "opencode", name: "opencode", kind: .agent, connection: .agent(.openCode),
            summary: "The open agent, with the models it's set up for", search: .own),
        Provider(
            id: "gemini-cli", name: "Gemini CLI", kind: .agent, connection: .agent(.geminiCLI),
            summary: "Google's agent, with your Google account",
            suggested: [
                Model(id: "gemini-2.5-pro", name: "Gemini 2.5 Pro"), Model(id: "gemini-2.5-flash", name: "Gemini 2.5 Flash"),
            ], search: .own),
    ]

    static let local: [Provider] = [
        Provider(
            id: "apple", name: "Apple Intelligence", kind: .local, connection: .apple, summary: "The Mac's own model. Nothing leaves it",
            suggested: [Model(id: "system", name: "On-device model")]),
        Provider(
            id: "ollama", name: "Ollama", kind: .local, connection: .openAI(URL(string: "http://localhost:11434/v1")!),
            summary: "Open models run by Ollama on this Mac", movable: true),
        Provider(
            id: "lmstudio", name: "LM Studio", kind: .local, connection: .openAI(URL(string: "http://localhost:1234/v1")!),
            summary: "Models served by LM Studio on this Mac", movable: true),
    ]

    static let cloud: [Provider] = [
        Provider(
            id: "anthropic", name: "Anthropic", kind: .cloud, connection: .anthropic(URL(string: "https://api.anthropic.com")!),
            summary: "Claude, through Anthropic's API", needsKey: true, keyPage: "https://console.anthropic.com/settings/keys",
            defaultModel: "claude-sonnet-5", search: .own),
        Provider(
            id: "openai", name: "OpenAI", kind: .cloud, connection: .openAI(URL(string: "https://api.openai.com/v1")!),
            summary: "GPT models, through OpenAI's API", needsKey: true, keyPage: "https://platform.openai.com/api-keys",
            defaultModel: "gpt-5", search: .responses),
        Provider(
            id: "gemini", name: "Google Gemini", kind: .cloud,
            connection: .openAI(URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!),
            summary: "Gemini, through Google AI Studio", needsKey: true, keyPage: "https://aistudio.google.com/apikey",
            defaultModel: "gemini-2.5-flash"),
        Provider(
            id: "openrouter", name: "OpenRouter", kind: .cloud, connection: .openAI(URL(string: "https://openrouter.ai/api/v1")!),
            summary: "Hundreds of models behind one key", needsKey: true, keyPage: "https://openrouter.ai/keys",
            defaultModel: "openrouter/auto",
            headers: ["HTTP-Referer": "https://motebrowser.com", "X-Title": "Mote"], search: .online),
        Provider(
            id: "groq", name: "Groq", kind: .cloud, connection: .openAI(URL(string: "https://api.groq.com/openai/v1")!),
            summary: "Open models, answered very fast", needsKey: true, keyPage: "https://console.groq.com/keys",
            defaultModel: "llama-3.3-70b-versatile"),
        Provider(
            id: "mistral", name: "Mistral", kind: .cloud, connection: .openAI(URL(string: "https://api.mistral.ai/v1")!),
            summary: "Mistral's models, from Europe", needsKey: true, keyPage: "https://console.mistral.ai/api-keys",
            defaultModel: "mistral-large-latest"),
        Provider(
            id: "deepseek", name: "DeepSeek", kind: .cloud, connection: .openAI(URL(string: "https://api.deepseek.com/v1")!),
            summary: "DeepSeek's chat and reasoning models", needsKey: true, keyPage: "https://platform.deepseek.com/api_keys",
            defaultModel: "deepseek-chat"),
        Provider(
            id: "xai", name: "xAI", kind: .cloud, connection: .openAI(URL(string: "https://api.x.ai/v1")!),
            summary: "Grok, through xAI's API",
            needsKey: true, keyPage: "https://console.x.ai", defaultModel: "grok-4", search: .responses),
        Provider(
            id: "custom", name: "Other (OpenAI-compatible)", kind: .cloud, connection: .openAI(URL(string: "http://localhost:8080/v1")!),
            summary: "Any server that speaks OpenAI's API: vLLM, llama.cpp, LiteLLM…", movable: true),
    ]
}
