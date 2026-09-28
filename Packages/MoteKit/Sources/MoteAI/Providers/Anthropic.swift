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

    public init(base: URL, key: String, transport: HTTPTransport = URLSessionTransport()) {
        self.base = base
        self.key = key
        self.transport = transport
    }

    public func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let http = self.request(for: request)
        let transport = transport
        return .decoding({ try await transport.lines(for: http) }, with: AnthropicDecoder())
    }

    func request(for chat: ChatRequest) -> URLRequest {
        var body: [String: Any] = [
            "model": chat.model, "max_tokens": Self.replyLimit, "stream": true,
            "messages": chat.messages.filter { !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
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
            return started(json["content_block"], at: index)
        case "content_block_delta":
            return delta(json["delta"], at: index)
        case "content_block_stop":
            return stopped(at: index)
        case "message_delta":
            guard let output = json["usage"]?["output_tokens"]?.int else { return [] }
            return [.usage(Usage(input: input, output: output))]
        case "error":
            throw AIError.failed(json["error"]?["message"]?.string ?? "Anthropic reported an error")
        default:
            return []
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
