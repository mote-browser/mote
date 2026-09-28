import Foundation

/// How to talk to one kind of installed agent: the command for a turn, and
/// how to read what it prints.
public protocol AgentWire: Sendable {
    associatedtype Decoder: LineDecoder
    func command(for request: ChatRequest, executable: URL, workspace: URL) -> Command
    func decoder() -> Decoder
}

/// A chat with an agent installed on the Mac (Claude Code, Codex, opencode,
/// Gemini CLI), one process per turn.
public struct AgentService<Wire: AgentWire>: ChatService {
    let wire: Wire
    let executable: URL
    /// Where the agent runs: a folder of Mote's own, so it never works in
    /// someone's project.
    let workspace: URL
    let runner: CommandRunning
    /// Added to the agent's environment (see `ToolLocator.environment`).
    let environment: [String: String]

    public init(wire: Wire, executable: URL, workspace: URL, runner: CommandRunning = ProcessRunner(), environment: [String: String] = [:])
    {
        self.wire = wire
        self.executable = executable
        self.workspace = workspace
        self.runner = runner
        self.environment = environment
    }

    public func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        var command = wire.command(for: request, executable: executable, workspace: workspace)
        command.environment.merge(environment) { mine, _ in mine }
        command.unset.formUnion(AgentSession.marks)
        let (runner, planned) = (runner, command)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return .decoding({ runner.lines(of: planned) }, with: wire.decoder())
    }
}

enum AgentSession {
    /// What an agent sets for the programs it runs. Mote started from a
    /// terminal inside an agent session inherits them, and an agent that sees
    /// them tries to join that session instead of starting its own, and hangs.
    /// Settings such as CLAUDE_CODE_USE_BEDROCK are left alone.
    static let marks: Set<String> = [
        "CLAUDECODE", "CLAUDE_PID", "CLAUDE_EFFORT", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_CHILD_SESSION",
        "CLAUDE_CODE_SESSION_ATTENDED", "CLAUDE_CODE_MESSAGING_SOCKET", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_CODE_EXECPATH",
        "CODEX_SANDBOX", "CODEX_SANDBOX_NETWORK_DISABLED", "OPENCODE", "OPENCODE_SESSION_ID", "GEMINI_CLI",
    ]
}

/// The conversation written out as one prompt, for providers that weren't
/// part of it from the start (a new agent session, a model switched mid-chat).
public enum Transcript {
    public static func prompt(for messages: [Message]) -> String {
        guard let last = messages.last(where: { $0.role == .user }) else { return "" }
        let earlier = messages.prefix { $0.id != last.id }.filter { !$0.text.isEmpty }
        guard !earlier.isEmpty else { return last.text }
        let lines = earlier.map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }
        return """
            This conversation began earlier. What was said so far:

            \(lines.joined(separator: "\n\n"))

            The user's new message, to answer now:

            \(last.text)
            """
    }
}
