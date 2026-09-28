import Foundation
import Testing

@testable import MoteAI

@Suite("CommandRunner")
struct CommandRunnerTests {
    private let runner = ProcessRunner()

    private func shell(_ script: String, input: String? = nil, environment: [String: String] = [:]) -> Command {
        Command(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script], environment: environment, input: input)
    }

    private func collect(_ command: Command) async throws -> [String] {
        var lines: [String] = []
        for try await line in runner.lines(of: command) { lines.append(line) }
        return lines
    }

    @Test("Output arrives line by line, a last line without a newline included")
    func lines() async throws {
        #expect(try await collect(shell("printf 'one\\ntwo\\n\\nthree'")) == ["one", "two", "", "three"])
    }

    @Test("What is given as input reaches the command, which then sees the end of it")
    func input() async throws {
        #expect(try await collect(shell("cat; echo done", input: "hello\n")) == ["hello", "done"])
    }

    @Test("The command runs with the environment and folder asked for")
    func environmentAndFolder() async throws {
        var command = shell("echo \"$MOTE_TEST\"; pwd -P", environment: ["MOTE_TEST": "set"])
        command.directory = URL(fileURLWithPath: "/private/tmp")
        #expect(try await collect(command) == ["set", "/private/tmp"])
    }

    @Test("Inherited variables asked to be left out don't reach the command")
    func unset() async throws {
        setenv("MOTE_TEST_INHERITED", "yes", 1)
        defer { unsetenv("MOTE_TEST_INHERITED") }
        var command = shell("echo \"[${MOTE_TEST_INHERITED:-}]\"")
        #expect(try await collect(command) == ["[yes]"])
        command.unset = ["MOTE_TEST_INHERITED"]
        #expect(try await collect(command) == ["[]"])
    }

    @Test("A program that ignores the polite signal is still ended when stopped")
    func stubborn() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "mote-runner-\(UUID().uuidString)")
        let command = shell("trap '' TERM; echo started; sleep 4; touch '\(marker.path)'")
        for try await line in runner.lines(of: command) {
            #expect(line == "started")
            break
        }
        try await Task.sleep(for: .milliseconds(4500))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("A command that fails ends the stream with what it said on stderr")
    func failure() async throws {
        await #expect(throws: AIError.failed("it broke")) {
            _ = try await collect(shell("echo partial; echo 'it broke' >&2; exit 3"))
        }
    }

    @Test("A failure with nothing on stderr says how it exited")
    func silentFailure() async throws {
        await #expect(throws: AIError.failed("sh stopped with status 7")) {
            _ = try await collect(shell("exit 7"))
        }
    }

    @Test("A program that isn't there fails to start")
    func missing() async throws {
        let command = Command(executable: URL(fileURLWithPath: "/nonexistent/tool"), arguments: [])
        await #expect(throws: AIError.self) { _ = try await collect(command) }
    }

    @Test("Stopping early ends the process")
    func cancel() async throws {
        let marker = FileManager.default.temporaryDirectory.appending(path: "mote-runner-\(UUID().uuidString)")
        let command = shell("echo started; sleep 5; touch '\(marker.path)'")
        for try await line in runner.lines(of: command) {
            #expect(line == "started")
            break
        }
        try await Task.sleep(for: .milliseconds(5500))
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test("Long output doesn't stall the command")
    func volume() async throws {
        let lines = try await collect(shell("i=0; while [ $i -lt 5000 ]; do echo \"line $i\"; i=$((i+1)); done"))
        #expect(lines.count == 5000)
        #expect(lines.last == "line 4999")
    }
}
