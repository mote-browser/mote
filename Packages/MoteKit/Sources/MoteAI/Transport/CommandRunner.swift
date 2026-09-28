import Foundation

/// A program to run: what, with which arguments, where, and what to feed it.
public struct Command: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    /// Added to the app's own environment, replacing what they name.
    public var environment: [String: String]
    /// Left out of the environment the app passes on.
    public var unset: Set<String> = []
    public var directory: URL?
    /// Written to the program's input, which is then closed.
    public var input: String?

    public init(
        executable: URL, arguments: [String], environment: [String: String] = [:], directory: URL? = nil, input: String? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.directory = directory
        self.input = input
    }
}

/// Runs programs and hands back their output a line at a time.
public protocol CommandRunning: Sendable {
    /// The lines the program writes, as it writes them. The stream fails if
    /// the program can't start or stops with an error; stopping early ends
    /// the program.
    func lines(of command: Command) -> AsyncThrowingStream<String, Error>
}

/// Runs programs with `Process`.
public struct ProcessRunner: CommandRunning {
    public init() {}

    public func lines(of command: Command) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let run = Run(command: command, continuation: continuation)
        continuation.onTermination = { _ in run.stop() }
        run.start()
        return stream
    }
}

/// One program's run: splits its output into lines, keeps the end of what
/// it says on stderr, and finishes the stream once the program has exited
/// and its output is all read, whichever comes last.
private final class Run: @unchecked Sendable {
    private let command: Command
    private let continuation: AsyncThrowingStream<String, Error>.Continuation
    private let process = Process()
    private let lock = NSLock()

    private var pending = Data()
    private var complaint = Data()
    private var outputEnded = false
    private var errorsEnded = false
    private var exited = false
    private var finished = false

    /// Enough of stderr to explain a failure.
    private static let complaintLimit = 16 * 1024

    init(command: Command, continuation: AsyncThrowingStream<String, Error>.Continuation) {
        self.command = command
        self.continuation = continuation
    }

    func start() {
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.environment = ProcessInfo.processInfo.environment.filter { !command.unset.contains($0.key) }
            .merging(command.environment) { $1 }
        if let directory = command.directory { process.currentDirectoryURL = directory }
        process.standardOutput = output
        process.standardError = errors

        let input: Pipe?
        if command.input != nil {
            input = Pipe()
            // A program that exits before reading everything mustn't take the app down with SIGPIPE.
            _ = fcntl(input!.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            process.standardInput = input
        } else {
            input = nil
            process.standardInput = FileHandle.nullDevice
        }

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.endOutput()
            } else {
                self?.take(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.endErrors()
            } else {
                self?.complain(data)
            }
        }
        process.terminationHandler = { [weak self] _ in self?.exit() }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            finish(throwing: AIError.notInstalled(command.executable.lastPathComponent))
            return
        }
        if let input, let text = command.input {
            let handle = input.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                try? handle.write(contentsOf: Data(text.utf8))
                try? handle.close()
            }
        }
    }

    /// The reader of the stream went away: the program goes too, asked
    /// politely first, then made to if it doesn't (some ignore SIGTERM).
    func stop() {
        lock.lock()
        let running = !exited && process.isRunning
        finished = true
        lock.unlock()
        guard running else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.grace) { [process] in
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    /// How long a program has to end after SIGTERM.
    private static let grace: TimeInterval = 1.5

    private func take(_ data: Data) {
        lock.lock()
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            lines.append(Self.text(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        let open = !finished
        lock.unlock()
        if open { for line in lines { continuation.yield(line) } }
    }

    private func complain(_ data: Data) {
        lock.lock()
        complaint.append(data)
        if complaint.count > Self.complaintLimit { complaint = complaint.suffix(Self.complaintLimit) }
        lock.unlock()
    }

    private func endOutput() {
        lock.lock()
        outputEnded = true
        let rest = pending
        pending = Data()
        let open = !finished
        lock.unlock()
        if open, !rest.isEmpty { continuation.yield(Self.text(rest[...])) }
        settle()
    }

    private func endErrors() {
        lock.lock()
        errorsEnded = true
        lock.unlock()
        settle()
    }

    private func exit() {
        lock.lock()
        exited = true
        lock.unlock()
        settle()
    }

    /// Finishes once the program has exited and all it wrote is read.
    private func settle() {
        lock.lock()
        let done = outputEnded && errorsEnded && exited
        lock.unlock()
        guard done else { return }
        guard process.terminationReason == .exit, process.terminationStatus != 0 else {
            finish(throwing: nil)
            return
        }
        lock.lock()
        let said = Self.text(complaint[...]).trimmingCharacters(in: .whitespacesAndNewlines)
        lock.unlock()
        let name = command.executable.lastPathComponent
        finish(throwing: AIError.failed(said.isEmpty ? "\(name) stopped with status \(process.terminationStatus)" : Self.lastWords(said)))
    }

    private func finish(throwing error: Error?) {
        lock.lock()
        let already = finished
        finished = true
        lock.unlock()
        guard !already else { return }
        continuation.finish(throwing: error)
    }

    private static func text(_ bytes: Data.SubSequence) -> String {
        var line = String(decoding: bytes, as: UTF8.self)
        if line.hasSuffix("\r") { line.removeLast() }
        return line
    }

    /// The end of a long complaint, which is where programs say what went wrong,
    /// without the colour codes terminals would draw.
    static func lastWords(_ text: String) -> String {
        let plain = text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: true).suffix(6)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
