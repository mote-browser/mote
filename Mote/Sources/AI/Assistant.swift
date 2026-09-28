import Foundation
import MoteAI
import Observation

/// The assistant every window asks: which provider answers, how each is set
/// up, and what's installed on the Mac. Chats themselves are `Conversation`s,
/// one per chat tab; this only gets them a route to a provider.
///
/// The choices are kept in the settings store, keys in the keychain.
@MainActor
@Observable
final class Assistant {
    static let shared = Assistant()

    /// Whether a provider can answer, as Settings shows it.
    enum Status: Equatable {
        case ready
        case looking
        case missing(String)
        case needsKey
        case unavailable(String)
    }

    /// The provider that answers.
    var providerID: String {
        didSet { Storage.settings.set(providerID, forKey: Keys.provider) }
    }

    private(set) var setups: [String: ProviderSetup]
    /// What was found on the Mac; nil until the first look.
    private(set) var found: ToolLocator.Found?
    private(set) var looking = false
    /// Models listed by each provider, once asked.
    private(set) var models: [String: [Model]] = [:]
    private(set) var listing: Set<String> = []
    /// Why a provider's list couldn't be had.
    private(set) var listFailures: [String: String] = [:]
    /// Servers on the Mac that didn't answer when last asked.
    private(set) var offline: Set<String> = []
    /// Bumped when a key changes, so views asking `hasKey` look again.
    private(set) var keysChanged = 0

    @ObservationIgnored let secrets: Secrets
    @ObservationIgnored private var search: Task<ToolLocator.Found, Never>?
    /// Model lists being fetched, so a second asker waits for the first.
    @ObservationIgnored private var lists: [String: Task<[Model], Never>] = [:]
    @ObservationIgnored private var serversChecked: Date?

    /// Where the agents work: a folder of Mote's own, never a project.
    static var workspace: URL { Storage.folder.appending(path: "Assistant", directoryHint: .isDirectory) }

    private enum Keys {
        static let provider = "ai.provider"
        static let setups = "ai.setups"
    }

    init(secrets: Secrets? = nil) {
        // A service of its own per test world, so test runs never read or
        // change the real keys.
        let service = "io.github.mote-browser.mote.ai" + (Storage.world.map { ".\($0)" } ?? "")
        self.secrets = secrets ?? KeychainSecrets(service: service, label: Storage.world.map { "Mote AI (\($0))" } ?? "Mote AI")
        let stored = Storage.settings.string(forKey: Keys.provider).flatMap(Provider.named)
        providerID = stored?.id ?? "claude-code"
        setups =
            Storage.settings.data(forKey: Keys.setups).flatMap { try? JSONDecoder().decode([String: ProviderSetup].self, from: $0) } ?? [:]
    }

    var provider: Provider { Provider.named(providerID) ?? Provider.all[0] }

    func setup(for provider: Provider) -> ProviderSetup { setups[provider.id] ?? ProviderSetup() }

    func change(_ provider: Provider, _ edit: (inout ProviderSetup) -> Void) {
        var setup = setup(for: provider)
        edit(&setup)
        setups[provider.id] = setup
        if let data = try? JSONEncoder().encode(setups) { Storage.settings.set(data, forKey: Keys.setups) }
    }

    // MARK: - Keys

    func hasKey(for provider: Provider) -> Bool {
        _ = keysChanged
        return secrets.key(for: provider.id) != nil
    }

    @discardableResult
    func setKey(_ key: String, for provider: Provider) -> Bool {
        let saved = secrets.setKey(key, for: provider.id)
        keysChanged += 1
        models[provider.id] = nil
        listFailures[provider.id] = nil
        return saved
    }

    // MARK: - What's installed

    /// Looks for the agents' programs, once unless asked again. Callers
    /// arriving while a look is under way wait for it, and find `found` set.
    @discardableResult
    func lookAround(again: Bool = false) async -> ToolLocator.Found {
        if !again, let found { return found }
        if let search { return await search.value }
        looking = true
        let names = Provider.Agent.allCases.map(\.program)
        let task = Task { @MainActor [weak self] in
            let result = await Task.detached { await ToolLocator().find(names) }.value
            self?.found = result
            self?.search = nil
            self?.looking = false
            return result
        }
        search = task
        async let servers: Void = checkServers()
        let result = await task.value
        await servers
        return result
    }

    /// Asks each server on the Mac (Ollama, LM Studio) whether it's running.
    func checkServers() async {
        serversChecked = Date()
        let servers = Provider.all.filter { $0.kind == .local && $0.base != nil }
        for provider in servers {
            let answers = await connector.reachable(provider, setup: setup(for: provider))
            if answers { offline.remove(provider.id) } else { offline.insert(provider.id) }
        }
    }

    private var connector: Connector {
        Connector(workspace: Self.workspace, tools: found ?? ToolLocator.Found(tools: [:], path: nil))
    }

    func status(of provider: Provider) -> Status {
        switch provider.connection {
        case .agent(let agent):
            guard found != nil else { return .looking }
            return connector.program(for: agent, setup: setup(for: provider)) == nil ? .missing(agent.install) : .ready
        case .apple:
            return AppleIntelligence.unavailable.map(Status.unavailable) ?? .ready
        case .openAI, .anthropic:
            if offline.contains(provider.id) {
                return .unavailable("Not running at \(connector.base(for: provider, setup: setup(for: provider))?.host() ?? "its address")")
            }
            return provider.needsKey && !hasKey(for: provider) ? .needsKey : .ready
        }
    }

    /// Where the program was found, for Settings.
    func program(of provider: Provider) -> URL? {
        provider.agent.flatMap { connector.program(for: $0, setup: setup(for: provider)) }
    }

    func model(for provider: Provider) -> String { connector.model(for: provider, setup: setup(for: provider)) }

    /// The name of the model in use, as its provider lists it.
    func modelName(for provider: Provider) -> String {
        let id = model(for: provider)
        guard !id.isEmpty else { return provider.kind == .agent ? "Default model" : "No model" }
        return (models[provider.id] ?? provider.suggested).first { $0.id == id }?.name ?? id
    }

    // MARK: - Models

    /// Asks the provider for its models, keeping the answer. A failure is
    /// kept too, so nothing is started again until `forgetModels`.
    @discardableResult
    func listModels(of provider: Provider) async -> [Model] {
        if let known = models[provider.id] { return known }
        if listFailures[provider.id] != nil { return provider.suggested }
        if let running = lists[provider.id] { return await running.value }
        listing.insert(provider.id)
        let task = Task { @MainActor [self] in
            defer {
                listing.remove(provider.id)
                lists[provider.id] = nil
            }
            if provider.agent != nil { await lookAround() }
            do {
                let listed = try await connector.models(for: provider, setup: setup(for: provider), key: secrets.key(for: provider.id))
                models[provider.id] = listed
                return listed
            } catch {
                listFailures[provider.id] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                return provider.suggested
            }
        }
        lists[provider.id] = task
        return await task.value
    }

    /// Gets ready to ask: finds the programs, sees which servers run, and
    /// lists the chosen provider's models. Called when asking looks likely
    /// (the pointer on the model chip, ⌘ held over the composer), so nothing
    /// is started for someone who never asks.
    func prepare() {
        Task {
            await lookAround()
            if serversChecked.map({ Date().timeIntervalSince($0) > 15 }) ?? true { await checkServers() }
            await listModels(of: provider)
        }
    }

    func forgetModels(of provider: Provider) {
        models[provider.id] = nil
        listFailures[provider.id] = nil
    }

    // MARK: - Asking

    /// A route to the chosen provider, or why there isn't one. A provider with
    /// no model chosen and no default gets the first it lists.
    func route(to provider: Provider? = nil) async throws -> Conversation.Route {
        let provider = provider ?? self.provider
        if provider.agent != nil { await lookAround() }
        // Whatever failed before (a server not yet started) is tried again.
        if listFailures[provider.id] != nil { forgetModels(of: provider) }
        var model = model(for: provider)
        if model.isEmpty, provider.kind != .agent {
            guard let first = await listModels(of: provider).first else {
                throw listFailures[provider.id].map(AIError.failed) ?? AIError.needsModel(provider.name)
            }
            change(provider) { $0.model = first.id }
            model = first.id
        }
        let service = try connector.service(for: provider, setup: setup(for: provider), key: secrets.key(for: provider.id))
        let author = model.isEmpty ? provider.name : "\(provider.name) · \(modelName(for: provider))"
        return Conversation.Route(provider: provider.id, model: model, author: author, service: service, instructions: Self.instructions())
    }

    /// Sends `text` in `conversation` to the chosen provider.
    func ask(_ text: String, in conversation: Conversation) {
        conversation.send(text, routing: { [self] in try await route() })
    }

    /// Asks again for the last reply, through whatever provider is chosen now.
    func retry(in conversation: Conversation) {
        conversation.retry(routing: { [self] in try await route() })
    }

    /// Mote's standing instructions to every provider.
    static func instructions(now: Date = Date()) -> String {
        let day = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        return """
            You are the assistant built into Mote, a web browser for the Mac. Answer the person's questions directly and \
            helpfully, in the language they write in. Keep answers as short as the question allows; use Markdown \
            (headings, lists, tables, fenced code with a language) where it makes the answer easier to read. When you \
            mention a website, give its full https:// address as a Markdown link. Today is \(day).
            """
    }
}
