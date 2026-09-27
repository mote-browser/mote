import Combine
import Foundation
import MoteCore

/// Where you've been, for the address field and the History panel. The
/// ranking is `HistoryIndex`'s; this keeps it in history.json, written a
/// moment after the last change.
@MainActor
final class History: ObservableObject {
    typealias Entry = HistoryIndex.Entry

    private var index = HistoryIndex() {
        didSet {
            latest = nil
            objectWillChange.send()
        }
    }
    /// The menu bar is remade on every change to the window, each keystroke
    /// included, so the recent list is kept until history changes.
    private var latest: [Entry]?
    private var saving: Task<Void, Never>?
    private let file = JSONFile<[HistoryIndex.Visit]>("history.json")

    init() {
        if let visits = file.load() { index = HistoryIndex(visits: visits) }
    }

    // MARK: - Writing

    func record(_ url: URL, title: String) {
        index.record(url, title: title)
        scheduleSave()
    }

    /// An imported entry, not saved yet: call `scheduleSave()` after the batch.
    func merge(_ url: URL, title: String, count: Int, last: Date) {
        index.merge(url, title: title, count: count, last: last)
    }

    func retitle(_ url: URL, _ title: String) {
        if index.retitle(url, title) { scheduleSave() }
    }

    func remove(_ key: String) {
        index.remove(key)
        scheduleSave()
    }

    func clear() {
        index.removeAll()
        scheduleSave()
    }

    /// Saves a moment and a half after the last change.
    func scheduleSave() {
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self else { return }
            saving = nil
            file.save(index.visitsToSave())
        }
    }

    // MARK: - Reading

    func entries(matching text: String = "") -> [Entry] { index.entries(matching: text) }

    /// The eight most recent places, for the History menu.
    func recent() -> [Entry] {
        if let latest { return latest }
        let found = Array(index.entries().prefix(8))
        latest = found
        return found
    }

    func suggestions(for typed: String, limit: Int = 5) -> [Suggestion] { index.suggestions(for: typed, limit: limit) }

    func completion(for typed: String, among options: [Suggestion]) -> String? {
        HistoryIndex.completion(for: typed, among: options)
    }
}
