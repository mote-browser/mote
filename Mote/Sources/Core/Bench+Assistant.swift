import AppKit
import MoteAI
import MoteCore

// Bench commands on the assistant: what the chat in front holds, asking in
// it, and choosing who answers.

extension Bench {
    var assistantCommands: [String: Command] {
        ["chat": Self.chat]
    }

    /// `chat show` the chat in front; `chat ask TEXT` asks as ⌘Return does in
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
            Assistant.shared.searching = request.flag("on")
            call.answer(["searching": Assistant.shared.searching, "searches": Assistant.shared.searches])
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
            call.fail("chat does show, ask TEXT, follow TEXT, wait [SECONDS], use PROVIDER [MODEL] [ADDRESS], search on|off or providers")
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
