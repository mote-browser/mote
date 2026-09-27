import Foundation

/// Things grouped by the day they happened on, for lists with day headings.
public enum Days {
    public struct Group<Item>: Sendable where Item: Sendable {
        /// The day's start.
        public let day: Date
        public let items: [Item]
    }

    /// Newest day first, and newest first within each day.
    public static func group<Item: Sendable>(_ items: [Item], by date: (Item) -> Date, calendar: Calendar = .current) -> [Group<Item>] {
        Dictionary(grouping: items) { calendar.startOfDay(for: date($0)) }
            .sorted { $0.key > $1.key }
            .map { Group(day: $0.key, items: $0.value.sorted { date($0) > date($1) }) }
    }
}
