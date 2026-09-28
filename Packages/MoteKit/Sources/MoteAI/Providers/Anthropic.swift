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

    public init() {}

    public mutating func read(_ line: String) throws -> [ChatEvent] {
        guard let data = ServerSentEvents.data(in: line), let json = JSON(parsing: data) else { return [] }
        switch json["type"]?.string {
        case "message_start":
            let usage = json["message"]?["usage"]
            input = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].compactMap { usage?[$0]?.int }.reduce(0, +)
            return []
        case "content_block_delta":
            let delta = json["delta"]
            switch delta?["type"]?.string {
            case "text_delta": return delta?["text"]?.string.map { [.text($0)] } ?? []
            case "thinking_delta": return delta?["thinking"]?.string.map { [.reasoning($0)] } ?? []
            default: return []
            }
        case "message_delta":
            guard let output = json["usage"]?["output_tokens"]?.int else { return [] }
            return [.usage(Usage(input: input, output: output))]
        case "error":
            throw AIError.failed(json["error"]?["message"]?.string ?? "Anthropic reported an error")
        default:
            return []
        }
    }
}
