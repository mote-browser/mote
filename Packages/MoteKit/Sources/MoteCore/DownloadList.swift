import Foundation

/// A finished download, as the Downloads panel lists it. Stored in
/// downloads.json; the field names are that file's format.
public struct DownloadRecord: Codable, Identifiable, Equatable, Sendable {
    public var name: String
    /// The site it came from.
    public var from: String
    public var path: String
    public var date: Date

    public init(name: String, from: String, path: String, date: Date) {
        self.name = name
        self.from = from
        self.path = path
        self.date = date
    }

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
}

/// The recent downloads, newest first: one entry per file, the last 50.
public struct DownloadList: Equatable, Sendable {
    public static let limit = 50
    public private(set) var records: [DownloadRecord]

    public init(_ records: [DownloadRecord] = []) {
        self.records = Array(records.prefix(Self.limit))
    }

    /// A file downloaded again moves to the top instead of showing twice.
    public mutating func add(_ record: DownloadRecord) {
        records.removeAll { $0.path == record.path }
        records.insert(record, at: 0)
        records = Array(records.prefix(Self.limit))
    }

    public mutating func remove(_ id: DownloadRecord.ID) {
        records.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        records = []
    }
}
