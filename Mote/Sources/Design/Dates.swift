import Foundation

/// How dates read in lists.
enum When {
    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let dayAndMonth: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter
    }()

    /// "2 hr. ago".
    static func said(_ date: Date) -> String { relative.localizedString(for: date, relativeTo: Date()) }

    /// The time of day, for rows already under a day heading.
    static func clock(_ date: Date) -> String { time.string(from: date) }

    /// "Today", "Yesterday", or the day and month.
    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return dayAndMonth.string(from: date)
    }
}
