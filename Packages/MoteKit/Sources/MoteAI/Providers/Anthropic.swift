import Foundation

/// Anthropic's Messages API.
public struct AnthropicService: ChatService {
    /// `https://api.anthropic.com`, or a gateway that speaks the same API.
    let base: URL
    let key: String
    let transport: HTTPTransport

    static let version = "2023-06-01"
    /// Replies are capped at this many tokens; the API requires a cap.
    static let replyLimit = 16_000
    /// Searches allowed in one reply.
    static let searchLimit = 8
    /// Times a turn paused by Anthropic's server (`pause_turn`) is carried on.
    static let continuations = 5

    public init(base: URL, key: String, transport: HTTPTransport = URLSessionTransport()) {
        self.base = base
        self.key = key
        self.transport = transport
    }

    /// The reply, carried on when Anthropic's server pauses it: its own loop
    /// of searches stops after a number of rounds with `pause_turn`, and
    /// resumes when sent the turn again with everything the reply said so
    /// far, exactly as it came (search results keep their encrypted content).
    public func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        let transport = transport
        let task = Task {
            do {
                var said: [JSON] = []
                for round in 0...Self.continuations {
                    var decoder = AnthropicDecoder()
                    for try await line in try await transport.lines(for: self.request(for: request, saying: said)) {
                        try Task.checkCancellation()
                        for event in try decoder.read(line) { continuation.yield(event) }
                    }
                    guard decoder.paused, round < Self.continuations else { break }
                    said += decoder.blocks
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// The request for `chat`, carrying on from `said`: what a paused reply
    /// has said so far, as the API's own blocks.
    func request(for chat: ChatRequest, saying said: [JSON] = []) -> URLRequest {
        var messages: [Any] = chat.messages.filter { !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "content": $0.text] }
        if !said.isEmpty { messages.append(["role": "assistant", "content": said.map(\.plain)]) }
        var body: [String: Any] = ["model": chat.model, "max_tokens": Self.replyLimit, "stream": true, "messages": messages]
        if let instructions = chat.instructions, !instructions.isEmpty { body["system"] = instructions }
        // Anthropic's own search, run on its servers; the reply cites what it found.
        if chat.search { body["tools"] = [["type": "web_search_20250305", "name": "web_search", "max_uses": Self.searchLimit]] }
        var request = authorized(URLRequest(url: base.appending(path: "v1/messages")))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(JSON.encode(body).utf8)
        return request
    }

    public func models() async throws -> [Model] {
        var url = base.appending(path: "v1/models")
        url.append(queryItems: [URLQueryItem(name: "limit", value: "100")])
        let data = try await transport.data(for: authorized(URLRequest(url: url)))
        guard let json = JSON(parsing: String(decoding: data, as: UTF8.self)) else { throw AIError.malformed("model list") }
        return json["data"]?.array.compactMap { entry in
            entry["id"]?.string.map { Model(id: $0, name: entry["display_name"]?.string) }
        } ?? []
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.version, forHTTPHeaderField: "anthropic-version")
        return request
    }
}

public struct AnthropicDecoder: LineDecoder {
    private var input = 0
    /// The reply's blocks as the API sent them, by index, for carrying on a paused turn.
    private var sent: [Int: JSON] = [:]
    /// Tool input arriving in pieces, by block index.
    private var partial: [Int: String] = [:]
    /// The server paused the turn (`pause_turn`); it goes on when sent again.
    public private(set) var paused = false

    /// The blocks of the reply so far, in order.
    public var blocks: [JSON] { sent.keys.sorted().compactMap { sent[$0] } }
    /// Server searches under way by block index: their id and the query as it streams in.
    private var searches: [Int: (id: String, query: String)] = [:]
    private var finished: [String: Activity] = [:]
    /// Pages the text block under way cites, by block index.
    private var citations: [Int: [Source]] = [:]
    /// Some answer has been given; the next text block is a new paragraph.
    private var wrote = false
    private var blockStarted = false

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let data = ServerSentEvents.data(in: line), let json = JSON(parsing: data) else { return [] }
        let index = json["index"]?.int ?? -1
        switch json["type"]?.string {
        case "message_start":
            let usage = json["message"]?["usage"]
            input = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage?[$0]?.int }.reduce(0, +)
            return []
        case "content_block_start":
            if let block = json["content_block"] { sent[index] = block }
            return started(json["content_block"], at: index)
        case "content_block_delta":
            keep(json["delta"], at: index)
            return delta(json["delta"], at: index)
        case "content_block_stop":
            if let whole = partial.removeValue(forKey: index), let input = JSON(parsing: whole) { sent[index]?.set("input", input) }
            return stopped(at: index)
        case "message_delta":
            if json["delta"]?["stop_reason"]?.string == "pause_turn" { paused = true }
            guard let output = json["usage"]?["output_tokens"]?.int else { return [] }
            return [.usage(Usage(input: input, output: output))]
        case "error":
            throw AIError.failed(json["error"]?["message"]?.string ?? "Anthropic reported an error")
        default:
            return []
        }
    }

    /// Applies a delta to the block as it will be sent back.
    private mutating func keep(_ delta: JSON?, at index: Int) {
        guard let delta, let block = sent[index] else { return }
        switch delta["type"]?.string {
        case "text_delta":
            sent[index]?.set("text", .string((block["text"]?.string ?? "") + (delta["text"]?.string ?? "")))
        case "thinking_delta":
            sent[index]?.set("thinking", .string((block["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? "")))
        case "signature_delta":
            if let signature = delta["signature"] { sent[index]?.set("signature", signature) }
        case "citations_delta":
            if let citation = delta["citation"] { sent[index]?.set("citations", .array((block["citations"]?.array ?? []) + [citation])) }
        case "input_json_delta":
            partial[index, default: ""] += delta["partial_json"]?.string ?? ""
        default:
            break
        }
    }

    private mutating func started(_ block: JSON?, at index: Int) -> [ChatEvent] {
        switch block?["type"]?.string {
        case "text":
            blockStarted = true
            return []
        case "server_tool_use":
            guard let id = block?["id"]?.string, block?["name"]?.string == "web_search" else { return [] }
            searches[index] = (id, "")
            return [.activity(.search(id, nil))]
        case "web_search_tool_result":
            guard let id = block?["tool_use_id"]?.string else { return [] }
            let found: [ChatEvent] =
                block?["content"]?.array.compactMap { result in
                    guard let address = result["url"]?.string, let url = URL(string: address) else { return nil }
                    return .source(Source(url: url, title: result["title"]?.string ?? ""))
                } ?? []
            var activity = finished[id] ?? .search(id, nil)
            activity.done = true
            return found + [.activity(activity)]
        default:
            return []
        }
    }

    private mutating func delta(_ delta: JSON?, at index: Int) -> [ChatEvent] {
        switch delta?["type"]?.string {
        case "text_delta":
            guard let text = delta?["text"]?.string, !text.isEmpty else { return [] }
            let events: [ChatEvent] = wrote && blockStarted ? [.text("\n\n"), .text(text)] : [.text(text)]
            (wrote, blockStarted) = (true, false)
            return events
        case "thinking_delta":
            return delta?["thinking"]?.string.map { [.reasoning($0)] } ?? []
        case "input_json_delta":
            searches[index]?.query += delta?["partial_json"]?.string ?? ""
            return []
        case "citations_delta":
            let citation = delta?["citation"]
            guard let address = citation?["url"]?.string, let url = URL(string: address) else { return [] }
            let source = Source(url: url, title: citation?["title"]?.string ?? "")
            if !(citations[index] ?? []).contains(where: { $0.id == source.id }) { citations[index, default: []].append(source) }
            return []
        default:
            return []
        }
    }

    /// A search's query is whole once its block ends; a cited text block ends
    /// with links to what it cites, the way the chat shows citations.
    private mutating func stopped(at index: Int) -> [ChatEvent] {
        if let search = searches.removeValue(forKey: index) {
            let query = JSON(parsing: search.query)?["query"]?.string
            let activity = Activity.search(search.id, query)
            finished[search.id] = activity
            return query == nil ? [] : [.activity(activity)]
        }
        guard let cited = citations.removeValue(forKey: index), !cited.isEmpty else { return [] }
        return [.text(cited.map { " [\($0.site)](\($0.url.absoluteString))" }.joined())]
    }
}
