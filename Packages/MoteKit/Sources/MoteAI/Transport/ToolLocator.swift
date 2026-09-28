import Foundation

/// Finds programs installed for the command line, such as `claude`.
///
/// An app opened from the Dock gets a bare PATH, so it asks the person's
/// login shell, which has read their startup files (Homebrew, nvm, mise…).
/// Whatever that doesn't find is looked for where installers usually put
/// things.
public struct ToolLocator: Sendable {
    public struct Found: Equatable, Sendable {
        public var tools: [String: URL]
        /// The login shell's PATH, when it answered.
        public var path: String?

        public init(tools: [String: URL], path: String?) {
            self.tools = tools
            self.path = path
        }

        /// What a found tool needs in its environment: its own folder and the
        /// shell's PATH, so scripts that start with `#!/usr/bin/env node` find node.
        public func environment(for tool: URL) -> [String: String] {
            let folders =
                [tool.deletingLastPathComponent().path] + (path.map { [$0] } ?? []) + [
                    "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                ]
            var seen = Set<String>()
            let joined = folders.flatMap { $0.split(separator: ":").map(String.init) }.filter { seen.insert($0).inserted }
            return ["PATH": joined.joined(separator: ":"), "NO_COLOR": "1"]
        }
    }

    let runner: CommandRunning
    let home: URL
    let shell: String
    let isExecutable: @Sendable (String) -> Bool
    /// The names in a folder.
    let contents: @Sendable (String) -> [String]

    /// How long the shell has to answer; a slow startup file shouldn't hold things up.
    static let patience: Duration = .seconds(6)

    public init(
        runner: CommandRunning = ProcessRunner(), home: URL = FileManager.default.homeDirectoryForCurrentUser,
        shell: String = ToolLocator.loginShell,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        contents: @escaping @Sendable (String) -> [String] = { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] }
    ) {
        self.runner = runner
        self.home = home
        self.shell = shell
        self.isExecutable = isExecutable
        self.contents = contents
    }

    /// The person's login shell, from the user database.
    public static var loginShell: String {
        guard let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell else { return "/bin/zsh" }
        let path = String(cString: shell)
        return path.isEmpty ? "/bin/zsh" : path
    }

    public func find(_ names: [String]) async -> Found {
        let answer = await askShell(names)
        var tools: [String: URL] = [:]
        for name in names {
            if let path = answer.tools[name], path.hasPrefix("/"), isExecutable(path) {
                tools[name] = URL(fileURLWithPath: path)
            } else if let path = usualPlaces(for: name).first(where: isExecutable) {
                tools[name] = URL(fileURLWithPath: path)
            }
        }
        return Found(tools: tools, path: answer.path)
    }

    // MARK: - The shell

    private func askShell(_ names: [String]) async -> (tools: [String: String], path: String?) {
        let fish = shell.hasSuffix("/fish")
        let script =
            fish
            ? "for t in \(names.joined(separator: " ")); printf 'mote-tool:%s:%s\\n' $t (command -v -- $t); end; printf 'mote-tool:PATH:%s\\n' (string join : $PATH)"
            : "for t in \(names.joined(separator: " ")); do printf 'mote-tool:%s:%s\\n' \"$t\" \"$(command -v -- \"$t\")\"; done; printf 'mote-tool:PATH:%s\\n' \"$PATH\""
        let command = Command(
            executable: URL(fileURLWithPath: shell), arguments: ["-ilc", script], environment: ["MOTE": "1"], directory: home)
        let lines = await collect(runner.lines(of: command))
        var tools: [String: String] = [:]
        var path: String?
        // Startup files can print anything; only the marked lines count.
        for line in lines where line.hasPrefix("mote-tool:") {
            let fields = line.dropFirst("mote-tool:".count).split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let (name, value) = (String(fields[0]), String(fields[1]))
            if name == "PATH" { path = value.isEmpty ? nil : value } else if !value.isEmpty { tools[name] = value }
        }
        return (tools, path)
    }

    /// The lines, or none if the shell fails or takes too long.
    private func collect(_ stream: AsyncThrowingStream<String, Error>) async -> [String] {
        await withTaskGroup(of: [String]?.self) { group in
            group.addTask {
                var lines: [String] = []
                do {
                    for try await line in stream { lines.append(line) }
                } catch {
                    return lines
                }
                return lines
            }
            group.addTask {
                try? await Task.sleep(for: ToolLocator.patience)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? []
        }
    }

    // MARK: - The usual places

    private func usualPlaces(for name: String) -> [String] {
        let home = home.path
        var folders = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/.volta/bin",
            "\(home)/.bun/bin", "\(home)/.cargo/bin", "\(home)/.local/share/mise/shims", "\(home)/.asdf/shims",
            "\(home)/.opencode/bin", "\(home)/Library/pnpm",
        ]
        folders += newestFirst(in: "\(home)/.nvm/versions/node").map { "\(home)/.nvm/versions/node/\($0)/bin" }
        var places = folders.map { "\($0)/\(name)" }
        if name == "claude" { places.append("\(home)/.claude/local/claude") }
        return places
    }

    /// Version folders such as v22.11.0, newest first.
    private func newestFirst(in folder: String) -> [String] {
        let numbers = { (name: String) in name.drop { !$0.isNumber }.split(separator: ".").map { Int($0) ?? 0 } }
        return contents(folder).sorted { numbers($1).lexicographicallyPrecedes(numbers($0)) }
    }
}
