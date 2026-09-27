import AppKit
import Combine
import MoteCore

/// The recent downloads list, kept in downloads.json. Downloading itself is
/// Browser+Navigation's.
@MainActor
final class Downloads: ObservableObject {
    @Published private var list = DownloadList()
    private let file = JSONFile<[DownloadRecord]>("downloads.json")

    var kept: [DownloadRecord] { list.records }

    init() {
        list = DownloadList(file.load() ?? [])
    }

    func add(_ record: DownloadRecord) { change { $0.add(record) } }
    func forget(_ record: DownloadRecord) { change { $0.remove(record.id) } }
    /// Empties the list; the files stay.
    func forgetAll() { change { $0.removeAll() } }

    func reveal(_ record: DownloadRecord) { NSWorkspace.shared.activateFileViewerSelecting([record.url]) }
    func open(_ record: DownloadRecord) { NSWorkspace.shared.open(record.url) }

    private func change(_ edit: (inout DownloadList) -> Void) {
        edit(&list)
        file.save(list.records)
    }
}

extension DownloadRecord {
    var stillThere: Bool { FileManager.default.fileExists(atPath: path) }
}
