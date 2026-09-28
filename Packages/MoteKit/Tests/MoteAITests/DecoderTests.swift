import Foundation
import Testing

@testable import MoteAI

/// Reads every line through a fresh decoder.
private func decode<Decoder: LineDecoder>(_ decoder: Decoder, _ lines: [String]) throws -> [ChatEvent] {
    var decoder = decoder
    return try lines.flatMap { try decoder.read($0) }
}

@Suite("Claude Code lines")
struct ClaudeCodeDecoderTests {
    // Shortened from a real `claude -p --output-format stream-json` turn.
    let turn = [
        #"{"type":"system","subtype":"hook_started","hook_id":"x","session_id":"s-1"}"#,
        #"{"type":"system","subtype":"init","cwd":"/tmp","session_id":"s-1","tools":[],"model":"claude-haiku-4-5-20251001"}"#,
        #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Short answer."}},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EocD"}},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hey"}},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"stream_event","event":{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":", what's up?"}},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hey, what's up?"}]},"session_id":"s-1","parent_tool_use_id":null}"#,
        #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning"}}"#,
        #"{"type":"result","subtype":"success","is_error":false,"result":"Hey, what's up?","session_id":"s-1","total_cost_usd":0.015162,"usage":{"input_tokens":10,"cache_creation_input_tokens":7461,"cache_read_input_tokens":2,"output_tokens":46}}"#,
    ]

    @Test("A turn gives its session, thinking, text and usage, and nothing twice")
    func turnEvents() throws {
        let events = try decode(ClaudeCodeDecoder(), turn)
        #expect(
            events == [
                .session("s-1"), .reasoning("Short answer."), .text("Hey"), .text(", what's up?"),
                .usage(Usage(input: 7473, output: 46, cost: 0.015162)),
            ])
    }

    @Test("An error result fails the reply with its message")
    func errorResult() {
        let line = #"{"type":"result","subtype":"success","is_error":true,"result":"Invalid API key · Please run /login"}"#
        #expect(throws: AIError.failed("Invalid API key · Please run /login")) { try decode(ClaudeCodeDecoder(), [line]) }
    }

    @Test("An error subtype without a message still fails the reply")
    func errorSubtype() {
        let line = #"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["Session not found"]}"#
        #expect(throws: AIError.failed("Session not found")) { try decode(ClaudeCodeDecoder(), [line]) }
    }

    @Test("Tool use shows as activity that finishes with its result")
    func tools() throws {
        let lines = [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t1","name":"Read","input":{}}},"parent_tool_use_id":null}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"..."}]},"parent_tool_use_id":null}"#,
        ]
        #expect(
            try decode(ClaudeCodeDecoder(), lines) == [
                .activity(Activity(id: "t1", title: "Read")), .activity(Activity(id: "t1", title: "Read", done: true)),
            ])
    }

    @Test("A subagent's own stream stays out of the reply")
    func subagents() throws {
        let line =
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"inner"}},"parent_tool_use_id":"t1"}"#
        #expect(try decode(ClaudeCodeDecoder(), [line]).isEmpty)
    }

    @Test("A web search shows its query, then gives the pages it found as sources")
    func webSearch() throws {
        let lines = [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"t1","name":"WebSearch","input":{}}},"parent_tool_use_id":null}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"WebSearch","input":{"query":"latest swift"}}]},"parent_tool_use_id":null}"#,
            #"{"type":"user","message":{"content":[{"tool_use_id":"t1","type":"tool_result","content":"Web search results..."}]},"parent_tool_use_id":null,"tool_use_result":{"query":"latest swift","results":[{"tool_use_id":"srv","content":[{"title":"Swift 6.4 Released | Swift.org","url":"https://www.swift.org/blog/swift-6.4-released/"},{"title":"Swift (programming language)","url":"https://en.wikipedia.org/wiki/Swift_(programming_language)"}]},"Summary text"]}}"#,
        ]
        #expect(
            try decode(ClaudeCodeDecoder(), lines) == [
                .activity(Activity.search("t1", nil)), .activity(Activity.search("t1", "latest swift")),
                .source(
                    Source(url: URL(string: "https://www.swift.org/blog/swift-6.4-released/")!, title: "Swift 6.4 Released | Swift.org")),
                .source(
                    Source(
                        url: URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!,
                        title: "Swift (programming language)")),
                .activity(Activity.search("t1", "latest swift", done: true)),
            ])
    }

    @Test("A page read shows its site and counts as a source")
    func webFetch() throws {
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t2","name":"WebFetch","input":{"url":"https://www.swift.org/blog/","prompt":"newest post"}}]},"parent_tool_use_id":null}"#,
            ##"{"type":"user","message":{"content":[{"tool_use_id":"t2","type":"tool_result","content":"# Newest"}]},"parent_tool_use_id":null,"tool_use_result":{"bytes":123618,"code":200,"codeText":"OK","result":"# Newest","durationMs":2895,"url":"https://www.swift.org/blog/"}}"##,
        ]
        #expect(
            try decode(ClaudeCodeDecoder(), lines) == [
                .activity(Activity.read("t2", "https://www.swift.org/blog/")),
                .source(Source(url: URL(string: "https://www.swift.org/blog/")!, title: "")),
                .activity(Activity.read("t2", "https://www.swift.org/blog/", done: true)),
            ])
    }

    @Test("Lines that aren't JSON are ignored")
    func noise() throws {
        #expect(try decode(ClaudeCodeDecoder(), ["", "Warning: something", "{"]).isEmpty)
    }
}

@Suite("opencode lines")
struct OpenCodeDecoderTests {
    @Test("Text, reasoning and the session come from the parts")
    func turn() throws {
        let lines = [
            #"{"type":"step_start","timestamp":1,"sessionID":"ses_1","part":{"type":"step-start"}}"#,
            #"{"type":"reasoning","timestamp":2,"sessionID":"ses_1","part":{"type":"reasoning","text":"Thinking it over"}}"#,
            #"{"type":"text","timestamp":3,"sessionID":"ses_1","part":{"type":"text","text":"Hi there, friend!"}}"#,
            #"{"type":"text","timestamp":4,"sessionID":"ses_1","part":{"type":"text","text":"More."}}"#,
            #"{"type":"step_finish","timestamp":5,"sessionID":"ses_1","part":{"type":"step-finish","cost":0.002,"tokens":{"input":12,"output":5}}}"#,
        ]
        #expect(
            try decode(OpenCodeDecoder(), lines) == [
                .session("ses_1"), .reasoning("Thinking it over"), .text("Hi there, friend!"), .text("\n\nMore."),
                .usage(Usage(input: 12, output: 5, cost: 0.002)),
            ])
    }

    @Test("An error line fails the reply with its message")
    func error() {
        let line = #"{"type":"error","sessionID":"ses_2","error":{"type":"provider.no-route","message":"Model unavailable: nope/nothing"}}"#
        #expect(throws: AIError.failed("Model unavailable: nope/nothing")) { try decode(OpenCodeDecoder(), [line]) }
    }

    @Test("Tools show as activity")
    func tools() throws {
        let lines = [
            #"{"type":"tool_use","sessionID":"s","part":{"id":"p1","type":"tool","tool":"read","state":{"status":"running"}}}"#,
            #"{"type":"tool_use","sessionID":"s","part":{"id":"p1","type":"tool","tool":"read","state":{"status":"completed"}}}"#,
        ]
        #expect(
            try decode(OpenCodeDecoder(), lines) == [
                .session("s"), .activity(Activity(id: "p1", title: "read")),
                .activity(Activity(id: "p1", title: "read", done: true)),
            ])
    }
}

extension OpenCodeDecoderTests {
    @Test("Words said on the way to a tool are thinking; the last step's are the answer")
    func narration() throws {
        let lines = [
            #"{"type":"step_start","sessionID":"s","part":{"type":"step-start"}}"#,
            #"{"type":"text","sessionID":"s","part":{"type":"text","text":"I'll search for it."}}"#,
            ###"{"type":"tool_use","sessionID":"s","part":{"id":"c1","type":"tool","tool":"websearch","state":{"status":"completed","input":{"query":"latest xcode"},"output":"## [Xcode - Wikipedia](https://en.wikipedia.org/wiki/Xcode)\n\nXcode is a suite...\n\n## [Xcode 27 - Apple Developer](https://developer.apple.com/xcode/)\n\nText"}}}"###,
            #"{"type":"step_finish","sessionID":"s","part":{"type":"step-finish","reason":"tool-calls","tokens":{"input":10,"output":2}}}"#,
            #"{"type":"step_start","sessionID":"s","part":{"type":"step-start"}}"#,
            #"{"type":"tool_use","sessionID":"s","part":{"id":"c2","type":"tool","tool":"webfetch","state":{"status":"completed","input":{"url":"https://developer.apple.com/support/xcode/","format":"text"},"output":"..."}}}"#,
            #"{"type":"step_finish","sessionID":"s","part":{"type":"step-finish","reason":"tool-calls","tokens":{"input":20,"output":3}}}"#,
            #"{"type":"text","sessionID":"s","part":{"type":"text","text":"Xcode 27 [Apple](https://developer.apple.com/support/xcode/)."}}"#,
        ]
        var decoder = OpenCodeDecoder()
        let events = try lines.flatMap { try decoder.read($0) } + (try decoder.finish())
        #expect(
            events == [
                .session("s"), .reasoning("I'll search for it."),
                .source(Source(url: URL(string: "https://en.wikipedia.org/wiki/Xcode")!, title: "Xcode - Wikipedia")),
                .source(Source(url: URL(string: "https://developer.apple.com/xcode/")!, title: "Xcode 27 - Apple Developer")),
                .activity(Activity.search("c1", "latest xcode", done: true)),
                .usage(Usage(input: 10, output: 2)),
                .source(Source(url: URL(string: "https://developer.apple.com/support/xcode/")!, title: "")),
                .activity(Activity.read("c2", "https://developer.apple.com/support/xcode/", done: true)),
                .usage(Usage(input: 20, output: 3)),
                .text("Xcode 27 [Apple](https://developer.apple.com/support/xcode/)."),
            ])
    }
}

extension CodexDecoderTests {
    @Test("A web search shows its query and passes on any results")
    func webSearch() throws {
        let lines = [
            #"{"type":"item.started","item":{"id":"ws","type":"web_search","query":"swift 6.4"}}"#,
            #"{"type":"item.completed","item":{"id":"ws","type":"web_search","query":"swift 6.4","results":[{"title":"Swift 6.4","url":"https://swift.org/blog/swift-6.4"}]}}"#,
        ]
        #expect(
            try decode(CodexDecoder(), lines) == [
                .activity(Activity.search("ws", "swift 6.4")),
                .source(Source(url: URL(string: "https://swift.org/blog/swift-6.4")!, title: "Swift 6.4")),
                .activity(Activity.search("ws", "swift 6.4", done: true)),
            ])
    }
}

extension GeminiCLIDecoderTests {
    @Test("Google searches and page reads show what they're about")
    func webTools() throws {
        let lines = [
            #"{"type":"tool_use","tool_name":"google_web_search","tool_id":"g1","parameters":{"query":"swift 6.4"}}"#,
            #"{"type":"tool_result","tool_id":"g1","status":"success","output":"Swift 6.4 was released [1].\n\nSources:\n[1] Swift 6.4 Released (https://www.swift.org/blog/swift-6.4-released/)"}"#,
            #"{"type":"tool_use","tool_name":"web_fetch","tool_id":"g2","parameters":{"prompt":"Summarize https://swift.org/blog"}}"#,
        ]
        #expect(
            try decode(GeminiCLIDecoder(), lines) == [
                .activity(Activity.search("g1", "swift 6.4")),
                .source(Source(url: URL(string: "https://www.swift.org/blog/swift-6.4-released/")!, title: "Swift 6.4 Released")),
                .activity(Activity.search("g1", "swift 6.4", done: true)),
                .activity(Activity.read("g2", "https://swift.org/blog")),
            ])
    }
}

@Suite("Codex lines")
struct CodexDecoderTests {
    @Test("A turn gives its thread, reasoning, messages and usage")
    func turn() throws {
        let lines = [
            #"{"type":"thread.started","thread_id":"th-9"}"#,
            #"{"type":"turn.started"}"#,
            #"{"type":"item.completed","item":{"id":"item_0","type":"reasoning","text":"**Planning**"}}"#,
            #"{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"ls","status":"in_progress"}}"#,
            #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"ls","status":"completed"}}"#,
            #"{"type":"item.completed","item":{"id":"item_2","type":"agent_message","text":"Done."}}"#,
            #"{"type":"item.completed","item":{"id":"item_3","type":"agent_message","text":"Also this."}}"#,
            #"{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":7}}"#,
        ]
        #expect(
            try decode(CodexDecoder(), lines) == [
                .session("th-9"), .reasoning("**Planning**"), .activity(Activity(id: "item_1", title: "ls")),
                .activity(Activity(id: "item_1", title: "ls", done: true)), .text("Done."), .text("\n\nAlso this."),
                .usage(Usage(input: 100, output: 7)),
            ])
    }

    @Test("A failed turn fails the reply")
    func failed() {
        let line = #"{"type":"turn.failed","error":{"message":"stream disconnected"}}"#
        #expect(throws: AIError.failed("stream disconnected")) { try decode(CodexDecoder(), [line]) }
    }

    @Test("An error line fails the reply")
    func error() {
        #expect(throws: AIError.failed("bad model")) { try decode(CodexDecoder(), [#"{"type":"error","message":"bad model"}"#]) }
    }
}

@Suite("Gemini CLI lines")
struct GeminiCLIDecoderTests {
    @Test("A turn gives its session and the streamed message")
    func turn() throws {
        let lines = [
            #"{"type":"init","timestamp":"t","session_id":"g-1","model":"gemini-2.5-pro"}"#,
            #"{"type":"message","timestamp":"t","role":"user","content":"hi"}"#,
            #"{"type":"message","timestamp":"t","role":"assistant","content":"Hel","delta":true}"#,
            #"{"type":"message","timestamp":"t","role":"assistant","content":"lo","delta":true}"#,
            #"{"type":"tool_use","timestamp":"t","tool_name":"google_web_search","tool_id":"x1","parameters":{}}"#,
            #"{"type":"tool_result","timestamp":"t","tool_id":"x1","status":"success"}"#,
            #"{"type":"result","timestamp":"t","status":"success","stats":{"input_tokens":3,"output_tokens":2}}"#,
        ]
        #expect(
            try decode(GeminiCLIDecoder(), lines) == [
                .session("g-1"), .text("Hel"), .text("lo"), .activity(Activity.search("x1", nil)),
                .activity(Activity.search("x1", nil, done: true)), .usage(Usage(input: 3, output: 2)),
            ])
    }

    @Test("Errors fail the reply; warnings don't")
    func errors() throws {
        #expect(try decode(GeminiCLIDecoder(), [#"{"type":"error","severity":"warning","message":"slow"}"#]).isEmpty)
        #expect(throws: AIError.failed("quota")) {
            try decode(GeminiCLIDecoder(), [#"{"type":"result","status":"error","error":{"type":"x","message":"quota"}}"#])
        }
    }
}

@Suite("OpenAI-style streams")
struct OpenAIDecoderTests {
    @Test("Content and reasoning deltas come through; [DONE] and comments don't")
    func deltas() throws {
        let lines = [
            ": OPENROUTER PROCESSING",
            #"data: {"id":"c","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}"#,
            #"data: {"id":"c","choices":[{"index":0,"delta":{"reasoning_content":"Hmm"},"finish_reason":null}]}"#,
            #"data: {"id":"c","choices":[{"index":0,"delta":{"reasoning":" ok"},"finish_reason":null}]}"#,
            #"data: {"id":"c","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"data:{"id":"c","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":"stop"}]}"#,
            #"data: {"id":"c","choices":[],"usage":{"prompt_tokens":9,"completion_tokens":2}}"#,
            "data: [DONE]",
        ]
        #expect(
            try decode(OpenAIChatDecoder(), lines) == [
                .reasoning("Hmm"), .reasoning(" ok"), .text("Hello"), .text(" world"), .usage(Usage(input: 9, output: 2)),
            ])
    }

    @Test("An error in the stream fails the reply")
    func streamError() {
        #expect(throws: AIError.failed("Rate limit reached")) {
            try decode(OpenAIChatDecoder(), [#"data: {"error":{"message":"Rate limit reached","code":429}}"#])
        }
    }
}

@Suite("Anthropic streams")
struct AnthropicDecoderTests {
    @Test("Text and thinking deltas come through, with usage from start and end")
    func deltas() throws {
        let lines = [
            "event: message_start",
            #"data: {"type":"message_start","message":{"id":"m","usage":{"input_tokens":25,"output_tokens":1}}}"#,
            "event: content_block_delta",
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Let me"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hi"}}"#,
            #"data: {"type":"ping"}"#,
            #"data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":15}}"#,
            #"data: {"type":"message_stop"}"#,
        ]
        #expect(try decode(AnthropicDecoder(), lines) == [.reasoning("Let me"), .text("Hi"), .usage(Usage(input: 25, output: 15))])
    }

    @Test("An error event fails the reply")
    func error() {
        #expect(throws: AIError.failed("Overloaded")) {
            try decode(AnthropicDecoder(), [#"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#])
        }
    }
}

extension AnthropicDecoderTests {
    @Test("A server search shows its query, lists its results, and cited text ends with links to its sources")
    func webSearch() throws {
        let lines = [
            #"data: {"type":"content_block_start","index":1,"content_block":{"type":"server_tool_use","id":"srv1","name":"web_search","input":{}}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"query\": \"swi"}}"#,
            #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"ft 6.4\"}"}}"#,
            #"data: {"type":"content_block_stop","index":1}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"web_search_tool_result","tool_use_id":"srv1","content":[{"type":"web_search_result","title":"Swift 6.4 Released","url":"https://www.swift.org/blog/swift-6.4-released/","encrypted_content":"x","page_age":"Sep 15, 2026"}]}}"#,
            #"data: {"type":"content_block_stop","index":2}"#,
            #"data: {"type":"content_block_start","index":3,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":3,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","cited_text":"Swift 6.4 is now available","url":"https://www.swift.org/blog/swift-6.4-released/","title":"Swift 6.4 Released","encrypted_index":"y"}}}"#,
            #"data: {"type":"content_block_delta","index":3,"delta":{"type":"text_delta","text":"Swift 6.4 is out."}}"#,
            #"data: {"type":"content_block_stop","index":3}"#,
        ]
        let page = Source(url: URL(string: "https://www.swift.org/blog/swift-6.4-released/")!, title: "Swift 6.4 Released")
        #expect(
            try decode(AnthropicDecoder(), lines) == [
                .activity(Activity.search("srv1", nil)), .activity(Activity.search("srv1", "swift 6.4")), .source(page),
                .activity(Activity.search("srv1", "swift 6.4", done: true)), .text("Swift 6.4 is out."),
                .text(" [swift.org](https://www.swift.org/blog/swift-6.4-released/)"),
            ])
    }
}

@Suite("Responses API streams")
struct ResponsesDecoderTests {
    @Test("Text, reasoning summaries, searches, citations and usage come through")
    func turn() throws {
        let lines = [
            #"event: response.output_item.added"#,
            #"data: {"type":"response.output_item.added","output_index":0,"item":{"type":"web_search_call","id":"ws_1","status":"in_progress"}}"#,
            #"data: {"type":"response.output_item.done","output_index":0,"item":{"type":"web_search_call","id":"ws_1","status":"completed","action":{"type":"search","query":"swift 6.4","sources":[{"type":"url","url":"https://swift.org/blog"}]}}}"#,
            #"data: {"type":"response.reasoning_summary_text.delta","delta":"Looking"}"#,
            #"data: {"type":"response.output_text.delta","delta":"Swift 6.4 "}"#,
            #"data: {"type":"response.output_text.annotation.added","annotation":{"type":"url_citation","url":"https://www.swift.org/blog/swift-6.4-released/?utm_source=openai","title":"Swift 6.4 Released","start_index":0,"end_index":9}}"#,
            #"data: {"type":"response.output_text.delta","delta":"is out."}"#,
            #"data: {"type":"response.completed","response":{"usage":{"input_tokens":30,"output_tokens":9}}}"#,
        ]
        #expect(
            try decode(ResponsesDecoder(), lines) == [
                .activity(Activity.search("ws_1", nil)),
                .source(Source(url: URL(string: "https://swift.org/blog")!, title: "")),
                .activity(Activity.search("ws_1", "swift 6.4", done: true)),
                .reasoning("Looking"), .text("Swift 6.4 "),
                .source(
                    Source(
                        url: URL(string: "https://www.swift.org/blog/swift-6.4-released/?utm_source=openai")!, title: "Swift 6.4 Released")),
                .text("is out."), .usage(Usage(input: 30, output: 9)),
            ])
    }

    @Test("A failed response fails the reply with its message")
    func failed() {
        #expect(throws: AIError.failed("Rate limit")) {
            try decode(ResponsesDecoder(), [#"data: {"type":"response.failed","response":{"error":{"message":"Rate limit"}}}"#])
        }
        #expect(throws: AIError.failed("Bad input")) {
            try decode(ResponsesDecoder(), [#"data: {"type":"error","message":"Bad input"}"#])
        }
    }
}

extension OpenAIDecoderTests {
    @Test("Citations a gateway adds to the stream become sources")
    func annotations() throws {
        let line =
            #"data: {"choices":[{"delta":{"content":"Hi","annotations":[{"type":"url_citation","url_citation":{"url":"https://a.com/x","title":"A"}}]}}]}"#
        #expect(
            try decode(OpenAIChatDecoder(), [line]) == [.text("Hi"), .source(Source(url: URL(string: "https://a.com/x")!, title: "A"))])
    }
}

extension ClaudeCodeDecoderTests {
    @Test("Text blocks on either side of a tool are separate paragraphs")
    func blocks() throws {
        let lines = [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Let me look."}},"parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}},"parent_tool_use_id":null}"#,
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"It's 6.4."}},"parent_tool_use_id":null}"#,
        ]
        #expect(try decode(ClaudeCodeDecoder(), lines) == [.text("Let me look."), .text("\n\n"), .text("It's 6.4.")])
    }
}

extension AnthropicDecoderTests {
    @Test("Text blocks after the first start a new paragraph")
    func blocks() throws {
        let lines = [
            #"data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"One."}}"#,
            #"data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Two."}}"#,
        ]
        #expect(try decode(AnthropicDecoder(), lines) == [.text("One."), .text("\n\n"), .text("Two.")])
    }
}

extension OpenCodeDecoderTests {
    @Test("An answer held back is still shown when the run then fails")
    func heldOnFailure() async throws {
        let lines = [
            #"{"type":"text","sessionID":"s","part":{"type":"text","text":"Partial answer"}}"#,
            #"{"type":"error","sessionID":"s","error":{"message":"Boom"}}"#,
        ]
        let stream = AsyncThrowingStream<ChatEvent, Error>.decoding(
            {
                AsyncStream { continuation in
                    for line in lines { continuation.yield(line) }
                    continuation.finish()
                }
            }, with: OpenCodeDecoder())
        var events: [ChatEvent] = []
        await #expect(throws: AIError.failed("Boom")) {
            for try await event in stream { events.append(event) }
        }
        #expect(events == [.session("s"), .text("Partial answer")])
    }
}
