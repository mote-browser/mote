import Foundation

/// A value kept as JSON in the profile folder. Writes happen off the main
/// thread, atomically and in order; a file that no longer reads is set aside
/// rather than overwritten.
struct JSONFile<Value: Codable & Sendable>: Sendable {
    let url: URL
    private var writer: DispatchQueue { fileWriter }

    init(_ name: String) {
        url = Storage.file(name)
    }

    /// The saved value; nil when there is none or it couldn't be read.
    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            Storage.quarantine(url)
            return nil
        }
        return value
    }

    func save(_ value: Value) {
        let url = url
        writer.async { Self.write(value, to: url) }
    }

    /// Saves before returning, after any saves still queued: for quitting,
    /// when queued work may never run.
    func saveNow(_ value: Value) {
        let url = url
        writer.sync { Self.write(value, to: url) }
    }

    /// Removes the file.
    func delete() {
        let url = url
        writer.async { try? FileManager.default.removeItem(at: url) }
    }

    /// On the writer's queue, off the main actor.
    private nonisolated static func write(_ value: Value, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

/// One queue for every file, so saves to a file land in the order they were made.
private let fileWriter = DispatchQueue(label: "io.github.mote-browser.files", qos: .utility)
