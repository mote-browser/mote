import AppKit
import MoteAI
import MoteCore

// Bench commands on the assistant: what the chat in front holds, asking in
// it, and choosing who answers.

extension Bench {
    var assistantCommands: [String: Command] {
        ["chat": Self.chat]
    }

    /// `chat show` the chat in front; `chat ask TEXT` asks as the new tab's Ask does in
    /// the address field, and `chat follow TEXT` asks again in the chat in
    /// front (test runs); `chat wait [SECONDS]` until its reply is
    /// done; `chat use PROVIDER [MODEL] [ADDRESS]` who answers (test runs); `chat
    /// providers` how each stands.
    private static func chat(_ call: BenchCall) {
        let browser = call.browser
        let request = call.request
        switch request.string("action") ?? "show" {
        case "show":
            call.answer(describe(browser))
        case "ask":
            guard call.testRun("it would ask in your browser") else { return }
            guard let text = request.string("text"), !text.isEmpty else { return call.fail("chat ask needs some text") }
            if browser.active?.isStart != true { browser.newTab() }
            browser.field.typed = text
            browser.ask()
            call.answer(describe(browser))
        case "follow":
            guard call.testRun("it would ask in your browser") else { return }
            guard let text = request.string("text"), !text.isEmpty, let chat = browser.active?.chat else {
                return call.fail("chat follow needs a chat in front and some text")
            }
            Assistant.shared.ask(text, in: chat)
            call.answer(describe(browser))
        case "wait":
            let deadline = Date().addingTimeInterval(request.double("seconds") ?? 30)
            @MainActor func poll() {
                let busy = browser.active?.chat?.busy == true
                guard busy, Date() < deadline else {
                    var out = describe(browser)
                    out["timeout"] = busy
                    return call.answer(out)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() }
            }
            poll()
        case "use":
            guard call.testRun("it would change your settings") else { return }
            guard let id = request.string("provider"), let provider = Provider.named(id) else {
                return call.fail("chat use needs one of: \(Provider.all.map(\.id).joined(separator: ", "))")
            }
            Assistant.shared.providerID = provider.id
            if let model = request.string("model") { Assistant.shared.change(provider) { $0.model = model.isEmpty ? nil : model } }
            if let address = request.string("address") {
                Assistant.shared.change(provider) { $0.address = address }
                Assistant.shared.forgetModels(of: provider)
            }
            call.answer(["provider": provider.id, "model": Assistant.shared.model(for: provider)])
        case "search":
            guard call.testRun("it would change your settings") else { return }
            Assistant.shared.chosenMode = request.flag("on") ? .search : .chat
            call.answer(["chosen": Assistant.shared.chosenMode.rawValue, "mode": Assistant.shared.mode.rawValue])
        case "mode":
            guard call.testRun("it would change your settings") else { return }
            guard let mode = request.string("mode").flatMap(Assistant.Mode.init(rawValue:)) else {
                return call.fail("chat mode needs chat, search or research")
            }
            Assistant.shared.chosenMode = mode
            call.answer(["chosen": mode.rawValue, "mode": Assistant.shared.mode.rawValue])
        case "lead":
            guard call.testRun("it would change your settings") else { return }
            // search, or ask: what Return does in the new tab's composer.
            guard let named = request.string("mode"), ["search", "ask"].contains(named) else {
                return call.fail("chat lead needs search or ask")
            }
            browser.field.asksAssistant = named == "ask"
            call.answer(["leads": browser.field.asksAssistant, "mode": Assistant.shared.mode.rawValue])
        case "demo":
            guard call.testRun("it would open a chat in your browser") else { return }
            let service = DemoReply(sources: request.int("sources") ?? 400, delay: request.double("delay") ?? 0)
            if browser.active?.isStart != true { browser.newTab() }
            let chat = Conversation()
            chat.send(
                "Demo: a long researched reply",
                via: Conversation.Route(provider: "demo", model: "", author: "Mote · demo", service: service, search: true))
            browser.active?.chat = chat
            browser.editing = false
            browser.field.clear()
            call.answer(describe(browser))
        case "providers":
            Task {
                let assistant = Assistant.shared
                let found = await assistant.lookAround()
                call.answer([
                    "chosen": assistant.providerID, "path": found.path ?? "",
                    "providers": Provider.all.map { provider in
                        [
                            "id": provider.id, "status": "\(assistant.status(of: provider))", "model": assistant.model(for: provider),
                            "program": assistant.program(of: provider)?.path ?? "",
                        ]
                    },
                ])
            }
        default:
            call.fail(
                "chat does show, ask TEXT, follow TEXT, wait [SECONDS], use PROVIDER [MODEL] [ADDRESS], mode chat|search|research, search on|off or providers"
            )
        }
    }

    private static func describe(_ browser: Browser) -> [String: Any] {
        guard let tab = browser.active, let chat = tab.chat else { return ["chat": false] }
        let phase: String =
            switch chat.phase {
            case .idle: "idle"
            case .waiting: "waiting"
            case .answering: "answering"
            case .failed(let reason): "failed: \(reason)"
            }
        return [
            "chat": true, "tab": BenchWire.short(tab.id), "title": chat.title, "label": tab.label, "phase": phase,
            "activities": chat.activities.map(\.title),
            "messages": chat.messages.map { message in
                [
                    "role": message.role.rawValue, "text": message.text, "author": message.author ?? "",
                    "reasoning": message.reasoning.count, "interrupted": message.interrupted,
                    "sources": message.sources.map { ["url": $0.url.absoluteString, "title": $0.title] },
                    "steps": message.steps.map { ["title": $0.title, "kind": $0.kind.rawValue, "done": $0.done] },
                ]
            },
        ]
    }
}

/// A long researched reply made up on the spot, for measuring the chat:
/// research steps, many sources, and a report with headings, lists, a table
/// and code, streamed in small pieces `delay` milliseconds apart.
private struct DemoReply: ChatService {
    let sources: Int
    let delay: Double

    func reply(to request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        let (stream, continuation) = AsyncThrowingStream<ChatEvent, Error>.makeStream()
        let task = Task {
            for part in 1...8 {
                continuation.yield(.activity(Activity(id: "part-\(part)", title: "Demo part \(part): what matters here", kind: .task)))
                for search in 1...6 {
                    continuation.yield(
                        .activity(Activity.search("part-\(part)-s\(search)", "query \(search) for part \(part)", done: true)))
                }
                continuation.yield(
                    .activity(Activity(id: "part-\(part)", title: "Demo part \(part): what matters here", done: true, kind: .task)))
            }
            for index in 0..<sources {
                continuation.yield(
                    .source(
                        Source(
                            url: URL(string: "https://site\(index % 40).example/page/\(index)")!, title: "Page \(index) about the subject"))
                )
            }
            for piece in Self.report().split(separator: " ", omittingEmptySubsequences: false) {
                if Task.isCancelled { return }
                continuation.yield(.text(piece + " "))
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    static func report() -> String {
        var text = "# A long demo report\n\nThis summary answers the question directly [site1](https://site1.example/page/1).\n\n"
        for section in 1...12 {
            text += "## Section \(section)\n\n"
            text +=
                "A paragraph with **bold**, `code`, and a claim worth citing [site\(section)](https://site\(section).example/page/\(section)). "
            text += String(repeating: "More words that make the paragraph long enough to wrap over several lines. ", count: 6) + "\n\n"
            text += "- First point [site2](https://site2.example/page/2)\n- Second point\n- Third point with `inline code`\n\n"
            if section % 3 == 0 {
                text += "| Option | Speed | Cost |\n|---|--:|--:|\n| One | 10 | 5 |\n| Two | 20 | 7 |\n| Three | 30 | 9 |\n\n"
            }
            if section % 4 == 0 { text += "```swift\nlet value = compute(section: \(section))\nprint(value)\n```\n\n" }
        }
        return text
    }
}
