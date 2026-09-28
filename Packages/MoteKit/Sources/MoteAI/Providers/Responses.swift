import Foundation

/// OpenAI's Responses API, which xAI speaks too: used for searching, since
/// its web search tool isn't offered through Chat Completions.
public struct ResponsesService: ChatService {
    /// Up to the version, such as `https://api.openai.com/v1`.
    let base: URL
    let key: String?
    let transport: HTTPTransport

    public init(base: URL, key: String?, transport: HTTPTransport = URLSessionTransport()) {
        self.base = base
        self.key = key
        self.transport = transport
    }

    public func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let http = self.request(for: request)
        let transport = transport
        return .decoding({ try await transport.lines(for: http) }, with: ResponsesDecoder())
    }

    func request(for chat: ChatRequest) -> URLRequest {
        var body: [String: Any] = [
            "model": chat.model, "stream": true,
            "input": chat.messages.filter { !$0.text.isEmpty }.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        if let instructions = chat.instructions, !instructions.isEmpty { body["instructions"] = instructions }
        if chat.search {
            body["tools"] = [["type": "web_search"]]
            // Every page searched, not only those cited.
            body["include"] = ["web_search_call.action.sources"]
        }
        var request = URLRequest(url: base.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = Data(JSON.encode(body).utf8)
        return request
    }
}

public struct ResponsesDecoder: LineDecoder {
    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let data = ServerSentEvents.data(in: line), let json = JSON(parsing: data) else { return [] }
        switch json["type"]?.string {
        case "response.output_text.delta":
            return json["delta"]?.string.map { [.text($0)] } ?? []
        case "response.reasoning_summary_text.delta":
            return json["delta"]?.string.map { [.reasoning($0)] } ?? []
        case "response.output_item.added":
            guard let item = json["item"], item["type"]?.string == "web_search_call", let id = item["id"]?.string else { return [] }
            return [.activity(.search(id, item["action"]?["query"]?.string))]
        case "response.output_item.done":
            guard let item = json["item"], item["type"]?.string == "web_search_call", let id = item["id"]?.string else { return [] }
            let action = item["action"]
            let found: [ChatEvent] =
                action?["sources"]?.array.compactMap { source in
                    guard let address = source["url"]?.string, let url = URL(string: address) else { return nil }
                    return .source(Source(url: url, title: source["title"]?.string ?? ""))
                } ?? []
            return found + [.activity(.search(id, action?["query"]?.string, done: true))]
        case "response.output_text.annotation.added":
            let annotation = json["annotation"]
            guard annotation?["type"]?.string == "url_citation", let address = annotation?["url"]?.string, let url = URL(string: address)
            else { return [] }
            return [.source(Source(url: url, title: annotation?["title"]?.string ?? ""))]
        case "response.completed":
            guard let usage = json["response"]?["usage"], let input = usage["input_tokens"]?.int else { return [] }
            return [.usage(Usage(input: input, output: usage["output_tokens"]?.int ?? 0))]
        case "response.failed", "response.incomplete":
            let error = json["response"]?["error"]
            throw AIError.failed(
                error?["message"]?.string ?? json["response"]?["incomplete_details"]?["reason"]?.string ?? "The reply failed")
        case "error":
            throw AIError.failed(json["message"]?.string ?? json["error"]?["message"]?.string ?? "The provider reported an error")
        default:
            return []
        }
    }
}
