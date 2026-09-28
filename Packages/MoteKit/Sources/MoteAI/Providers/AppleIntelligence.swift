import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model, on Macs with Apple Intelligence turned on
/// (macOS 26 and later). Nothing leaves the Mac.
public enum AppleIntelligence {
    /// Why the model can't be used here, or nil when it can.
    public static var unavailable: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return "This Mac can't run Apple Intelligence"
            case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in System Settings"
            case .unavailable(.modelNotReady): return "The model is still downloading"
            case .unavailable: return "Apple Intelligence isn't available"
            }
        }
        #endif
        return "Needs macOS 26 or later"
    }

    static func service() throws -> any ChatService {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), unavailable == nil { return OnDeviceService() }
        #endif
        throw AIError.failed(unavailable ?? "Apple Intelligence isn't available")
    }
}

#if canImport(FoundationModels)
/// A fresh session per reply, given the conversation so far: the model's
/// context is small and its sessions live only in memory anyway.
@available(macOS 26.0, *)
struct OnDeviceService: ChatService {
    func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        let task = Task {
            do {
                let session = LanguageModelSession(instructions: request.instructions ?? "")
                var said = ""
                // Each snapshot is the whole reply so far; pass on what's new.
                for try await snapshot in session.streamResponse(to: Transcript.prompt(for: request.messages)) {
                    let whole = snapshot.content
                    if whole.hasPrefix(said) {
                        let more = String(whole.dropFirst(said.count))
                        if !more.isEmpty { continuation.yield(.text(more)) }
                    }
                    said = whole
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: AIError.failed(error.localizedDescription))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
#endif
