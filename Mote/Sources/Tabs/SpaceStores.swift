import MoteCore
import WebKit

/// Where spaces are kept, and their website data. History, bookmarks,
/// passwords, settings and extensions belong to all spaces alike.
@MainActor
enum Spaces {
    private static let file = JSONFile<[Space]>("spaces.json")

    static func read() -> [Space] { SpaceList(saved: file.load() ?? []).spaces }
    static func write(_ spaces: [Space]) { file.save(spaces) }

    /// The space new tabs are made in.
    static var current = Space.firstID
    /// Spaces using the first space's store (see `Space.sharesSignIns`).
    static var sharing: Set<UUID> = []
    /// One store per space: WebKit only shares processes between views using
    /// the same store object.
    private static var stores: [UUID: WKWebsiteDataStore] = [:]

    static func store(for id: UUID) -> WKWebsiteDataStore {
        if id == Space.firstID || sharing.contains(id) { return Storage.websites }
        if let store = stores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = store
        return store
    }

    private static let erasingKey = "spaces.erasing"

    /// Erases a deleted space's store. Its data goes at once (and again a
    /// moment later, for what closing tabs wrote), but WebKit won't remove the
    /// store while anything still holds it, so it's noted and retried, at
    /// launch too.
    static func erase(_ id: UUID) {
        guard id != Space.firstID else { return }
        let store = store(for: id)
        let everything = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        stores[id] = nil
        Storage.settings.set(Set(erasing + [id.uuidString]).sorted(), forKey: erasingKey)
        Task {
            try? await Task.sleep(for: .seconds(2))
            await store.removeData(ofTypes: everything, modifiedSince: .distantPast)
        }
        for delay in [0.0, 3, 15] {
            Task {
                try? await Task.sleep(for: .seconds(delay))
                sweep()
            }
        }
    }

    private static var erasing: [String] { Storage.settings.stringArray(forKey: erasingKey) ?? [] }

    /// Tries again to remove the stores of deleted spaces.
    static func sweep() {
        for text in erasing {
            guard let id = UUID(uuidString: text) else { continue }
            Task {
                do {
                    try await WKWebsiteDataStore.remove(forIdentifier: id)
                } catch {
                    // Gone already counts as removed; otherwise, next time.
                    guard !(await WKWebsiteDataStore.allDataStoreIdentifiers).contains(id) else { return }
                }
                Storage.settings.set(erasing.filter { $0 != text }, forKey: erasingKey)
            }
        }
    }
}

/// A space's tabs while another space is showing.
struct Parked {
    var tabs: [Tab]
    var active: Tab.ID?
}
