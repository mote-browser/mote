import Foundation
import Observation

/// A chat as it is kept on disk: its messages, and the sessions providers
/// opened for it, so a chat brought back carries on where it was.
public struct SavedChat: Codable, Equatable, Sendable {
    /// A provider's session, and how much of the chat it has heard.
    public struct Session: Codable, Equatable, Sendable {
        public var id: String
        public var heard: Int
        public var search: Bool

        public init(id: String, heard: Int, search: Bool) {
            self.id = id
            self.heard = heard
            self.search = search
        }
    }

    public var id: UUID
    public var messages: [Message]
    public var sessions: [String: Session]
    public var created: Date
    public var updated: Date

    public init(id: UUID, messages: [Message], sessions: [String: Session] = [:], created: Date, updated: Date) {
        self.id = id
        self.messages = messages
        self.sessions = sessions
        self.created = created
        self.updated = updated
    }

    public var title: String { Self.title(of: messages) }

    /// The first question, on one line and cut short.
    public static func title(of messages: [Message]) -> String {
        guard let first = messages.first(where: { $0.role == .user }) else { return "New chat" }
        let line = first.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return line.count > 60 ? String(line.prefix(59)).trimmingCharacters(in: .whitespaces) + "…" : line
    }
}

/// Every chat kept: one JSON file per chat, and a small index of them all so
/// the list shows without reading any chat. Writes go off the main thread,
/// atomically and in order; a lost index is rebuilt from the chats.
@MainActor
@Observable
public final class ChatArchive {
    /// A chat as the list shows it.
    public struct Entry: Codable, Equatable, Identifiable, Sendable {
        public var id: UUID
        public var title: String
        public var updated: Date
        /// Everything asked in the chat, folded for searching.
        var asked: String
    }

    /// Newest first.
    public private(set) var entries: [Entry] = []

    private let folder: URL
    /// Chats deleted this run: one still open in a tab isn't kept again as
    /// it changes.
    @ObservationIgnored private var gone: Set<UUID> = []
    @ObservationIgnored private let writer = DispatchQueue(label: "io.github.mote-browser.chats", qos: .utility)
    private var index: URL { folder.appendingPathComponent("index.json") }

    public init(folder: URL) {
        self.folder = folder
        if let data = try? Data(contentsOf: index), let listed = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = listed
        } else {
            entries = Self.rebuild(in: folder)
        }
        entries.sort { $0.updated > $1.updated }
    }

    /// Keeps `chat`, or its newer version. A chat with no question is not kept.
    public func save(_ chat: SavedChat) {
        guard chat.messages.contains(where: { $0.role == .user }), !gone.contains(chat.id) else { return }
        entries.removeAll { $0.id == chat.id }
        let entry = Self.entry(for: chat)
        entries.insert(entry, at: entries.firstIndex { $0.updated <= entry.updated } ?? entries.endIndex)
        let (file, index, listed) = (file(chat.id), index, entries)
        writer.async {
            Self.write(chat, to: file)
            Self.write(listed, to: index)
        }
    }

    /// The whole chat; nil when it is gone or can't be read.
    public func load(_ id: UUID) -> SavedChat? {
        guard let data = try? Data(contentsOf: file(id)) else { return nil }
        return try? JSONDecoder().decode(SavedChat.self, from: data)
    }

    /// Keeps a deleted chat again, undoing the deletion.
    public func restore(_ chat: SavedChat) {
        gone.remove(chat.id)
        save(chat)
    }

    public func delete(_ id: UUID) {
        gone.insert(id)
        entries.removeAll { $0.id == id }
        let (file, index, listed) = (file(id), index, entries)
        writer.async {
            try? FileManager.default.removeItem(at: file)
            Self.write(listed, to: index)
        }
    }

    public func deleteAll() {
        gone.formUnion(entries.map(\.id))
        entries = []
        let folder = folder
        writer.async { try? FileManager.default.removeItem(at: folder) }
    }

    /// The chats whose title or questions hold every word of `text`.
    public func entries(matching text: String) -> [Entry] {
        let words = Self.fold(text).split(separator: " ")
        guard !words.isEmpty else { return entries }
        return entries.filter { entry in words.allSatisfy { entry.asked.contains($0) } }
    }

    /// Waits for the writes so far, as before quitting.
    public func flush() { writer.sync {} }

    /// Chats over a stretch of time, as the list of all chats heads them.
    public struct Period: Equatable, Sendable {
        public let name: String
        public let entries: [Entry]
    }

    /// `entries`, newest first, in today, yesterday, the last week, the last
    /// month, then one period per month. Empty periods are left out.
    public nonisolated static func periods(of entries: [Entry], now: Date = Date(), calendar: Calendar = .current) -> [Period] {
        let today = calendar.startOfDay(for: now)
        let day: (Int) -> Date = { calendar.date(byAdding: .day, value: -$0, to: today) ?? today }
        let month = DateFormatter()
        month.calendar = calendar
        month.timeZone = calendar.timeZone
        month.locale = Locale(identifier: "en_US")
        var names: [String] = []
        var groups: [String: [Entry]] = [:]
        for entry in entries.sorted(by: { $0.updated > $1.updated }) {
            let name: String
            if entry.updated >= today {
                name = "Today"
            } else if entry.updated >= day(1) {
                name = "Yesterday"
            } else if entry.updated >= day(7) {
                name = "Previous 7 Days"
            } else if entry.updated >= day(30) {
                name = "Previous 30 Days"
            } else {
                let sameYear = calendar.component(.year, from: entry.updated) == calendar.component(.year, from: now)
                month.dateFormat = sameYear ? "MMMM" : "MMMM yyyy"
                name = month.string(from: entry.updated)
            }
            if groups[name] == nil { names.append(name) }
            groups[name, default: []].append(entry)
        }
        return names.map { Period(name: $0, entries: groups[$0] ?? []) }
    }

    // MARK: -

    private func file(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    private static func entry(for chat: SavedChat) -> Entry {
        let asked = chat.messages.filter { $0.role == .user }.map(\.text).joined(separator: " ")
        return Entry(id: chat.id, title: chat.title, updated: chat.updated, asked: fold(String(asked.prefix(2_000))))
    }

    /// Lowercase, without accents, on one line.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func rebuild(in folder: URL) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" && $0.lastPathComponent != "index.json" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), let chat = try? JSONDecoder().decode(SavedChat.self, from: data) else {
                return nil
            }
            return entry(for: chat)
        }
    }

    private nonisolated static func write(_ value: some Encodable, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
