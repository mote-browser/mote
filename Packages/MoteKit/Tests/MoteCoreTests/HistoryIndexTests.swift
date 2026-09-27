import Foundation
import Testing

@testable import MoteCore

@Suite("HistoryIndex")
struct HistoryIndexTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test("Keys drop scheme and www but keep the query")
    func keys() {
        #expect(HistoryIndex.key(for: url("https://www.Example.com/Path")) == "example.com/path")
        #expect(HistoryIndex.key(for: url("https://youtube.com/watch?v=AbC")) == "youtube.com/watch?v=AbC")
    }

    @Test("Only web pages are recorded")
    func recordsOnlyWebPages() {
        var index = HistoryIndex()
        index.record(url("file:///tmp/page.html"), title: "File", at: now)
        index.record(url("about:blank"), title: "Blank", at: now)
        #expect(index.isEmpty)
    }

    @Test("A deep page also counts as a visit to its site")
    func deepPageCountsForSite() {
        var index = HistoryIndex()
        index.record(url("https://github.com/apple/swift"), title: "Swift", at: now)
        #expect(index.visitsByKey["github.com"]?.count == 1)
        #expect(index.visitsByKey["github.com/apple/swift"]?.title == "Swift")
    }

    @Test("Untitled site roots don't appear as entries")
    func entriesHideUntitledRoots() {
        var index = HistoryIndex()
        index.record(url("https://github.com/apple/swift"), title: "Swift", at: now)
        #expect(index.entries().map(\.key) == ["github.com/apple/swift"])
    }

    @Test("Entries match address or title, newest first")
    func entriesMatching() {
        var index = HistoryIndex()
        index.record(url("https://a.example/one"), title: "Recipes", at: now.addingTimeInterval(-60))
        index.record(url("https://b.example/two"), title: "Cooking", at: now)
        #expect(index.entries(matching: "example").map(\.key) == ["b.example/two", "a.example/one"])
        #expect(index.entries(matching: "RECIPES").map(\.key) == ["a.example/one"])
    }

    @Test("Visited sites outrank built-in ones, and prefixes outrank substrings")
    func suggestionRanking() {
        var index = HistoryIndex()
        index.record(url("https://gitlab.com/"), title: "GitLab", at: now)
        let suggestions = index.suggestions(for: "git", now: now)
        #expect(suggestions.first?.key == "gitlab.com")
        #expect(suggestions.first?.kind == .visited)
        #expect(suggestions.contains { $0.key == "github.com" && $0.kind == .known })
    }

    @Test("The label after the first dot matches")
    func matchesAfterFirstDot() {
        var index = HistoryIndex()
        index.record(url("https://mail.google.com/"), title: "Gmail", at: now)
        #expect(index.suggestions(for: "google", now: now).map(\.key).contains("mail.google.com"))
    }

    @Test("Frequent recent visits rank above old ones")
    func frecency() {
        var index = HistoryIndex()
        for _ in 0..<5 { index.record(url("https://news.example/"), title: "News", at: now) }
        index.record(url("https://notes.example/"), title: "Notes", at: now.addingTimeInterval(-90 * 86_400))
        #expect(index.suggestions(for: "n", now: now).first?.key == "news.example")
    }

    @Test("Typed schemes and www are ignored")
    func normalizesTyped() {
        #expect(HistoryIndex.normalized("  HTTPS://www.Example.com ") == "example.com")
    }

    @Test("Inline completion extends what was typed")
    func completion() {
        let options = [Suggestion(key: "github.com", title: "", url: url("https://github.com"), kind: .known)]
        #expect(HistoryIndex.completion(for: "gi", among: options) == "thub.com")
        #expect(HistoryIndex.completion(for: "g", among: options) == nil)
        #expect(HistoryIndex.completion(for: "github.com", among: options) == nil)
    }

    @Test("Importing adds visit counts")
    func merge() {
        var index = HistoryIndex()
        index.record(url("https://example.com/a"), title: "", at: now)
        index.merge(url("https://example.com/a"), title: "Imported", count: 10, last: now.addingTimeInterval(-10))
        let visit = index.visitsByKey["example.com/a"]
        #expect(visit?.count == 11)
        #expect(visit?.title == "Imported")
        #expect(visit?.last == now)
    }

    @Test("Restoring merges visits whose keys now collide")
    func restoreMergesDuplicates() {
        let visits = [
            HistoryIndex.Visit(url: "https://www.example.com/", key: "old-key-1", title: "A", count: 2, last: now),
            HistoryIndex.Visit(url: "https://example.com/", key: "old-key-2", title: "B", count: 3, last: now.addingTimeInterval(-1)),
        ]
        let index = HistoryIndex(visits: visits)
        #expect(index.visitsByKey.count == 1)
        #expect(index.visitsByKey["example.com"]?.count == 5)
        #expect(index.visitsByKey["example.com"]?.title == "A")
    }

    @Test("Saving keeps the most valuable entries")
    func capacity() {
        var index = HistoryIndex()
        for number in 0..<(HistoryIndex.capacity + 10) {
            index.record(url("https://site\(number).example/"), title: "", at: now)
        }
        #expect(index.visitsToSave(now: now).count == HistoryIndex.capacity)
    }
}
