import Foundation

/// Sends HTTP requests, for the providers that live behind a URL. A protocol
/// so tests can answer in place of the network.
public protocol HTTPTransport: Sendable {
    /// The response's body a line at a time, once the status says it
    /// succeeded; otherwise fails with the provider's message.
    func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error>
    /// The whole body of a successful response.
    func data(for request: URLRequest) async throws -> Data
}

/// `URLSession`, without a cache or cookies.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    public func lines(for request: URLRequest) async throws -> AsyncThrowingStream<String, Error> {
        let (bytes, response) = try await HTTPFailure.reaching(request) { try await session.bytes(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 64 * 1024 { break }
            }
            throw HTTPFailure.error(status: status, body: body)
        }
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        let task = Task {
            do {
                // `lines` drops empty lines, which suits the streams read here:
                // every event is one `data:` line.
                for try await line in bytes.lines { continuation.yield(line) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    public func data(for request: URLRequest) async throws -> Data {
        let (data, response) = try await HTTPFailure.reaching(request) { try await session.data(for: request) }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw HTTPFailure.error(status: status, body: data) }
        return data
    }
}

/// Turning failed requests into errors worth showing.
enum HTTPFailure {
    /// Runs `send`, naming the host when nothing answers there.
    static func reaching<Result>(_ request: URLRequest, _ send: () async throws -> Result) async throws -> Result {
        do {
            return try await send()
        } catch let error as URLError
            where [.cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .timedOut].contains(error.code)
        {
            throw AIError.unreachable(request.url?.host() ?? "the provider")
        }
    }

    /// The provider's own words from an error body, when it has any.
    static func error(status: Int, body: Data) -> AIError {
        let text = String(decoding: body, as: UTF8.self)
        guard let json = JSON(parsing: text) else {
            let plain = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return .http(status: status, message: plain.count < 200 && !plain.hasPrefix("<") ? plain : "")
        }
        let error = json["error"]
        let message = error?["message"]?.string ?? error?.string ?? json["message"]?.string ?? json["detail"]?.string ?? ""
        return .http(status: status, message: message)
    }
}

/// Server-sent events, as every streaming API here uses them.
enum ServerSentEvents {
    /// The data of a `data:` line; nil for the event names, ids and
    /// comments around it.
    static func data(in line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let data = line.dropFirst(5)
        return String(data.first == " " ? data.dropFirst() : data)
    }
}
