import Foundation

/// Why a reply didn't come, worded for the person reading the chat.
public enum AIError: Error, Equatable, Sendable, LocalizedError {
    /// The provider or the program answered with an error of its own.
    case failed(String)
    /// A program to run isn't on this Mac.
    case notInstalled(String)
    /// The provider needs an API key and has none.
    case needsKey(String)
    /// No model is chosen, and the provider has no default.
    case needsModel(String)
    /// An HTTP error, with the provider's own message when it gave one.
    case http(status: Int, message: String)
    /// Nothing answered at the address.
    case unreachable(String)
    /// The answer wasn't in the shape expected.
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message): message
        case .notInstalled(let name): "\(name) isn't installed on this Mac"
        case .needsKey(let name): "\(name) needs an API key — add one in Settings › AI"
        case .needsModel(let name): "Choose a model for \(name) in Settings › AI"
        case .http(let status, let message): message.isEmpty ? AIError.describe(status: status) : message
        case .unreachable(let place): "Couldn't reach \(place)"
        case .malformed(let what): "The reply didn't make sense (\(what))"
        }
    }

    /// Words for an HTTP status that came without a message.
    static func describe(status: Int) -> String {
        switch status {
        case 401, 403: "The API key was refused"
        case 404: "The model or address wasn't found"
        case 429: "Too many requests — try again in a moment"
        case 500...599: "The provider is having trouble (\(status))"
        default: "The request failed (\(status))"
        }
    }
}
