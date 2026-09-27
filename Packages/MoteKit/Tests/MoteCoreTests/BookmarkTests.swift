import Foundation
import Testing

@testable import MoteCore

@Suite("Bookmarks")
struct BookmarkTests {
    private let a = Bookmark.site("A", URL(string: "https://a.com")!)
    private let b = Bookmark.site("", URL(string: "https://b.com/x")!)
    private let inner = Bookmark.folder("Inner", [Bookmark.site("C", URL(string: "https://c.com")!)])

    private let work: Bookmark
    private let tree: BookmarkTree

    init() {
        work = .folder("Work", [b, inner])
        tree = BookmarkTree([a, work])
    }

    @Test("Untitled sites take their address as title")
    func titles() {
        #expect(b.title == Address.displayString(for: URL(string: "https://b.com/x")!))
    }

    @Test("Counting and listing go into folders")
    func reading() {
        #expect(BookmarkTree.count(tree.roots) == 3)
        #expect(BookmarkTree.urls(tree.roots).map(\.host) == ["a.com", "b.com", "c.com"])
        #expect(BookmarkTree.folders(tree.roots).map { "\($0.node.title)\($0.depth)" } == ["Work0", "Inner1"])
        #expect(tree.contains(URL(string: "https://c.com")!))
    }

    @Test("A page already bookmarked isn't added again")
    func adding() {
        var tree = tree
        let done1 = tree.add(URL(string: "https://c.com")!, title: "C again")
        #expect(!done1)
        let done2 = tree.add(URL(string: "https://d.com")!, title: "D")
        #expect(done2)
        #expect(tree.roots.last?.title == "D")
    }

    @Test("Removing reaches into folders")
    func removing() {
        var tree = tree
        tree.remove(inner.children![0].id)
        #expect(BookmarkTree.count(tree.roots) == 2)
    }

    @Test("Moving puts a node at the end of a folder, or of the top")
    func moving() {
        var tree = tree
        let done3 = tree.move(a.id, into: inner.id)
        #expect(done3)
        #expect(tree.roots.count == 1)
        #expect(tree.roots[0].children![1].children!.last?.id == a.id)
        let done4 = tree.move(a.id, into: nil)
        #expect(done4)
        #expect(tree.roots.last?.id == a.id)
    }

    @Test("A folder never goes into itself or its own folders, and nothing goes into a site")
    func badMoves() {
        var tree = tree
        let before = tree
        let done5 = tree.move(work.id, into: work.id)
        #expect(!done5)
        let done6 = tree.move(work.id, into: inner.id)
        #expect(!done6)
        let done7 = tree.move(inner.id, into: a.id)
        #expect(!done7)
        #expect(tree == before)
    }

    @Test("Inserting into a missing parent lands at the top")
    func inserting() {
        var tree = tree
        let d = Bookmark.site("D", URL(string: "https://d.com")!)
        tree.insert(d, into: inner.id)
        #expect(tree.roots[1].children![1].children!.last == d)
        let e = Bookmark.site("E", URL(string: "https://e.com")!)
        tree.insert(e, into: UUID())
        #expect(tree.roots.last == e)
    }

    @Test("Updates change titles, and addresses only of sites")
    func updating() {
        var tree = tree
        let done8 = tree.update(work.id, title: "Job", url: "https://x.com")
        #expect(done8)
        #expect(tree.roots[1].title == "Job")
        #expect(tree.roots[1].url == nil)
        let done9 = tree.update(UUID(), title: "No", url: nil)
        #expect(!done9)
    }

    @Test("An import becomes the top when there's nothing, and replaces its own folder after")
    func imports() {
        var tree = BookmarkTree()
        tree.adopt([a], from: "Chrome")
        #expect(tree.roots == [a])
        tree.adopt([b], from: "Chrome")
        tree.adopt([inner], from: "Chrome")
        #expect(tree.roots.map(\.title) == ["A", "Chrome"])
        #expect(tree.roots[1].children == [inner])
    }

    @Test("The saved file's format stays the same")
    func format() throws {
        let json =
            #"[{"id":"00000000-0000-0000-0000-000000000001","title":"F","children":[{"id":"00000000-0000-0000-0000-000000000002","title":"S","url":"https://s.com"}]}]"#
        let read = try JSONDecoder().decode([Bookmark].self, from: Data(json.utf8))
        #expect(read[0].isFolder)
        #expect(read[0].children?[0].host == "s.com")
    }
}

@Suite("Downloads")
struct DownloadListTests {
    private func record(_ path: String, _ day: Double = 0) -> DownloadRecord {
        DownloadRecord(name: path, from: "site", path: path, date: Date(timeIntervalSince1970: day))
    }

    @Test("The newest goes on top, and a file downloaded again moves up instead of showing twice")
    func adding() {
        var list = DownloadList()
        list.add(record("/a"))
        list.add(record("/b"))
        list.add(record("/a", 1))
        #expect(list.records.map(\.path) == ["/a", "/b"])
        #expect(list.records[0].date == Date(timeIntervalSince1970: 1))
    }

    @Test("Only the last fifty are kept")
    func limit() {
        var list = DownloadList()
        for n in 0..<60 { list.add(record("/\(n)")) }
        #expect(list.records.count == 50)
        #expect(list.records.first?.path == "/59")
        #expect(DownloadList((0..<70).map { record("/\($0)") }).records.count == 50)
    }

    @Test("Forgetting one or all")
    func forgetting() {
        var list = DownloadList([record("/a"), record("/b")])
        list.remove("/a")
        #expect(list.records.map(\.path) == ["/b"])
        list.removeAll()
        #expect(list.records.isEmpty)
    }
}

@Suite("Days")
struct DaysTests {
    @Test("Newest day first, newest first within a day")
    func grouping() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let hour = 3600.0
        let times = [1 * hour, 30 * hour, 2 * hour, 26 * hour].map { Date(timeIntervalSince1970: $0) }
        let days = Days.group(times, by: { $0 }, calendar: calendar)
        #expect(days.map(\.items.count) == [2, 2])
        #expect(days[0].items == [times[1], times[3]])
        #expect(days[1].items == [times[2], times[0]])
        #expect(days[0].day == Date(timeIntervalSince1970: 24 * hour))
    }
}
