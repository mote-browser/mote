import AppKit
import MoteCore
import WebKit

// The bench: a local socket Tools/bench drives the browser through. Off
// unless turned on in Settings › General. It listens on a Unix socket in the
// app's folder, readable only by its owner, and checks the other end's user
// too. One JSON line in, one out, one request per connection (BenchWire).
// Bench tabs are marked, never picked on their own, and kept out of the
// session and history. The commands are in Bench+….

@MainActor
final class Bench {
    static let shared = Bench()

    weak var browser: Browser?
    private var listener: Int32 = -1
    private var accepting: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]
    private var awake: NSObjectProtocol?
    private(set) var running = false

    /// In the storage folder, so each test world has its own.
    static var socket: URL { Storage.file("bench.sock") }

    // MARK: - Consent

    /// Proof the person turned the bench on. The setting sits in user
    /// defaults, which any local process can write, so turning it on also
    /// leaves an item in the data protection keychain that only Mote-signed
    /// builds can read; without it the setting goes back off at launch. Test
    /// runs go by the setting alone.
    @MainActor
    enum Consent {
        private static var query: [String: Any] {
            [
                kSecClass as String: kSecClassGenericPassword, kSecUseDataProtectionKeychain as String: true,
                kSecAttrService as String: "io.github.mote-browser.mote.bench",
                kSecAttrAccount as String: Storage.world.map { "consent (\($0))" } ?? "consent",
            ]
        }

        /// Also true for a build that can't keep one (no keychain entitlement).
        static var given: Bool {
            var asked = query
            asked[kSecReturnAttributes as String] = true
            let status = SecItemCopyMatching(asked as CFDictionary, nil)
            return status == errSecSuccess || status == errSecMissingEntitlement
        }

        static func grant() {
            var item = query
            item[kSecValueData as String] = Data("on".utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(item as CFDictionary, nil)
            if ![errSecSuccess, errSecDuplicateItem, errSecMissingEntitlement].contains(status) {
                NSLog("Bench: the switch left no mark (%d)", status)
            }
        }

        static func revoke() { SecItemDelete(query as CFDictionary) }
    }

    // MARK: - Listening

    func start(for browser: Browser) {
        guard !running else { return }
        self.browser = browser
        // No App Nap for test runs in the background.
        if Storage.testing, !Storage.measuring, awake == nil {
            awake = ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Bench")
        }
        guard let fd = Self.listen(at: Self.socket.path) else { return }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        accepting = source
        listener = fd
        running = true
    }

    /// A Unix socket at `path`, readable and writable by its owner only.
    private static func listen(at path: String) -> Int32? {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let room = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < room else {
            close(fd)
            return nil
        }
        withUnsafeMutablePointer(to: &address.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: room) { _ = strlcpy($0, path, room) }
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 8) == 0 else {
            close(fd)
            unlink(path)
            return nil
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        return fd
    }

    /// Closes the socket, and any bench tabs left open.
    func stop() {
        guard running else { return }
        accepting?.cancel()
        accepting = nil
        close(listener)
        listener = -1
        unlink(Self.socket.path)
        clients.values.forEach { $0.drop() }
        clients = [:]
        running = false
        browser.map { browser in browser.tabs.filter(\.bench).forEach(browser.close) }
    }

    private func accept() {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        // Only this user, file mode or not.
        var uid = uid_t(0), gid = gid_t(0)
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { return _ = close(fd) }
        clients[fd] = Client(fd: fd) { [weak self] request, answer in
            self?.handle(request, answer)
        } gone: { [weak self] fd in
            self?.clients[fd] = nil
        }
    }

    /// One connection: a line in, its answer out, then closed.
    private final class Client {
        private let fd: Int32
        private let source: DispatchSourceRead
        private let handle: (BenchRequest, @escaping ([String: Any]) -> Void) -> Void
        private let gone: (Int32) -> Void
        private var bytes = Data()
        private var answered = false

        init(fd: Int32, handle: @escaping (BenchRequest, @escaping ([String: Any]) -> Void) -> Void, gone: @escaping (Int32) -> Void) {
            self.fd = fd
            self.handle = handle
            self.gone = gone
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.read() }
            source.resume()
        }

        private func read() {
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = Darwin.read(fd, &chunk, chunk.count)
            guard count > 0 else {
                if count == 0 || errno != EAGAIN { drop() }
                return
            }
            bytes.append(contentsOf: chunk[0..<count])
            switch BenchWire.read(bytes) {
            case .more:
                return
            case .refused(let why):
                source.cancel()
                say(["error": why])
            case .request(let request):
                source.cancel()
                handle(request) { [weak self] in self?.say($0) }
            }
        }

        private func say(_ answer: [String: Any]) {
            guard !answered else { return }
            answered = true
            BenchWire.line(answer).withUnsafeBytes { raw in
                var sent = 0
                while sent < raw.count {
                    let n = write(fd, raw.baseAddress! + sent, raw.count - sent)
                    if n > 0 {
                        sent += n
                    } else if errno == EAGAIN {
                        usleep(2000)
                    } else {
                        break
                    }
                }
            }
            drop()
        }

        func drop() {
            if !source.isCancelled { source.cancel() }
            close(fd)
            gone(fd)
        }
    }

    // MARK: - Commands

    typealias Command = @MainActor (BenchCall) -> Void

    /// Every command, by its verb.
    private lazy var commands: [String: Command] = {
        var all: [String: Command] = [:]
        for family in [pageCommands, inputCommands, chromeCommands, pictureCommands, extensionCommands] {
            all.merge(family) { first, _ in first }
        }
        return all
    }()

    /// Answers once: a page that never answers gets a timeout instead.
    private func handle(_ request: BenchRequest, _ reply: @escaping ([String: Any]) -> Void) {
        var answered = false
        let answer: ([String: Any]) -> Void = { out in
            guard !answered else { return }
            answered = true
            reply(out)
        }
        let patience = request.patience
        DispatchQueue.main.asyncAfter(deadline: .now() + patience) { answer(["error": "no answer within \(Int(patience)) s"]) }
        guard let browser else { return answer(["error": "no browser"]) }
        guard let command = commands[request.verb] else {
            return answer(["error": "unknown command “\(request.verb)”", "commands": commands.keys.sorted()])
        }
        command(BenchCall(request: request, browser: browser, bench: self, answer: answer))
    }
}

/// One request, with what it needs to answer.
@MainActor
struct BenchCall {
    let request: BenchRequest
    let browser: Browser
    let bench: Bench
    let answer: ([String: Any]) -> Void

    var verb: String { request.verb }

    func fail(_ why: String) { answer(["error": why]) }

    /// False, having said why, outside a test run: some commands would take
    /// over the person's window, keyboard or pages.
    func testRun(_ risk: String? = nil) -> Bool {
        guard !Storage.testing else { return true }
        fail("\(verb) only works on a --test run" + (risk.map { " — \($0)" } ?? ""))
        return false
    }

    /// The tab the request names by the start of its id. Outside test runs
    /// only bench tabs answer to it, so a script can't reach the person's own;
    /// in test runs any tab does, popups a bench page opened included.
    func tab() -> Tab? {
        let ref = request.string("id") ?? ""
        if let tab = browser.tabs.first(where: { (Storage.testing || $0.bench) && BenchWire.names(ref, $0.id) }) { return tab }
        fail("no tab “\(ref)” — see tabs")
        return nil
    }

    func describe(_ tab: Tab) -> [String: Any] {
        [
            "id": BenchWire.short(tab.id), "url": tab.address?.absoluteString ?? "", "title": tab.title, "name": tab.name ?? "",
            "loading": tab.loading, "hollow": tab.hollow, "view": tab.built?.url?.absoluteString ?? "", "bench": tab.bench,
            "active": tab.id == browser.activeID, "asleep": tab.asleep, "shy": tab.shy, "noisy": tab.noisy, "muted": tab.muted,
            "extensions": { if #available(macOS 15.4, *) { tab.carriesExtensions } else { false } }(),
        ]
    }

    /// Traffic lights as [left, centre from the top], in window points.
    static func lights(of window: NSWindow) -> [[Int]] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { kind in
            guard let button = window.standardWindowButton(kind) else { return nil }
            let frame = button.convert(button.bounds, to: nil)
            return [Int(frame.minX.rounded()), Int((window.frame.height - frame.midY).rounded())]
        }
    }

    /// A rect in window points from the top left, as [x, y, width, height].
    static func topLeft(_ rect: CGRect, in height: CGFloat) -> [Int] {
        [Int(rect.minX), Int(height - rect.maxY), Int(rect.width), Int(rect.height)]
    }
}
