import Foundation
import Testing

@testable import MoteAI

@Suite("ToolLocator")
struct ToolLocatorTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    private func locator(
        shell output: [String], failure: Error? = nil, executables: Set<String> = [], folders: [String: [String]] = [:]
    )
        -> (ToolLocator, FakeRunner)
    {
        let runner = FakeRunner()
        runner.output = output
        runner.failure = failure
        let locator = ToolLocator(
            runner: runner, home: home, shell: "/bin/zsh", isExecutable: { executables.contains($0) },
            contents: { folders[$0] ?? [] })
        return (locator, runner)
    }

    @Test("The login shell's answers win, noise from its startup files aside")
    func fromShell() async {
        let (locator, runner) = locator(
            shell: [
                "Welcome back!", "mote-tool:claude:/Users/someone/.local/bin/claude", "mote-tool:codex:",
                "mote-tool:PATH:/opt/homebrew/bin:/usr/bin",
            ], executables: ["/Users/someone/.local/bin/claude", "/opt/homebrew/bin/codex"])
        let found = await locator.find(["claude", "codex"])
        // codex is in Homebrew's folder though the shell didn't know it.
        #expect(
            found.tools == [
                "claude": URL(fileURLWithPath: "/Users/someone/.local/bin/claude"),
                "codex": URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            ])
        #expect(found.path == "/opt/homebrew/bin:/usr/bin")
        let command = try! #require(runner.ran.first)
        #expect(command.executable.path == "/bin/zsh")
        #expect(command.arguments.first == "-ilc")
        #expect(command.directory == home)
    }

    @Test("What the shell can't find is looked for where installers put things")
    func fallbacks() async {
        let (locator, _) = locator(
            shell: ["mote-tool:claude:"], executables: ["/opt/homebrew/bin/claude", "/Users/someone/.bun/bin/gemini"])
        let found = await locator.find(["claude", "gemini", "codex"])
        #expect(found.tools["claude"]?.path == "/opt/homebrew/bin/claude")
        #expect(found.tools["gemini"]?.path == "/Users/someone/.bun/bin/gemini")
        #expect(found.tools["codex"] == nil)
    }

    @Test("A shell that fails still leaves the usual places, nvm's newest node first")
    func nvm() async {
        let nvm = "/Users/someone/.nvm/versions/node"
        let (locator, _) = locator(
            shell: [], failure: AIError.failed("broken rc"),
            executables: ["\(nvm)/v18.2.0/bin/codex", "\(nvm)/v22.11.0/bin/codex"],
            folders: [nvm: ["v18.2.0", "v9.0.0", "v22.11.0"]])
        let found = await locator.find(["codex"])
        #expect(found.tools["codex"]?.path == "\(nvm)/v22.11.0/bin/codex")
        #expect(found.path == nil)
    }

    @Test("A path the shell gives that isn't absolute is ignored")
    func relative() async {
        let (locator, _) = locator(shell: ["mote-tool:claude:claude: aliased to foo"])
        #expect(await locator.find(["claude"]).tools.isEmpty)
    }

    @Test("A tool's environment puts its own folder and the shell's PATH first")
    func environment() {
        let found = ToolLocator.Found(tools: [:], path: "/Users/someone/.nvm/versions/node/v22/bin:/usr/bin")
        let environment = found.environment(for: URL(fileURLWithPath: "/Users/someone/.local/bin/claude"))
        let path = environment["PATH"] ?? ""
        #expect(path.hasPrefix("/Users/someone/.local/bin:/Users/someone/.nvm/versions/node/v22/bin:/usr/bin"))
        #expect(path.contains("/opt/homebrew/bin"))
        #expect(environment["NO_COLOR"] == "1")
    }
}
