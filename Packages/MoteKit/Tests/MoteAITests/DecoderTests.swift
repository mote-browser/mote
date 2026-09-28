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
            #"{"type":"stream_event","event":{"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"t1","name":"WebSearch","input":{}}},"parent_tool_use_id":null}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"..."}]},"parent_tool_use_id":null}"#,
        ]
        #expect(
            try decode(ClaudeCodeDecoder(), lines) == [
                .activity(Activity(id: "t1", title: "WebSearch")), .activity(Activity(id: "t1", title: "WebSearch", done: true)),
            ])
    }

    @Test("A subagent's own stream stays out of the reply")
    func subagents() throws {
        let line =
            #"{"type":"stream_event","event":{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"inner"}},"parent_tool_use_id":"t1"}"#
        #expect(try decode(ClaudeCodeDecoder(), [line]).isEmpty)
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
            #"{"type":"tool_use","sessionID":"s","part":{"id":"p1","type":"tool","tool":"webfetch","state":{"status":"running"}}}"#,
            #"{"type":"tool_use","sessionID":"s","part":{"id":"p1","type":"tool","tool":"webfetch","state":{"status":"completed"}}}"#,
        ]
        #expect(
            try decode(OpenCodeDecoder(), lines) == [
                .session("s"), .activity(Activity(id: "p1", title: "webfetch")),
                .activity(Activity(id: "p1", title: "webfetch", done: true)),
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
                .session("g-1"), .text("Hel"), .text("lo"), .activity(Activity(id: "x1", title: "google_web_search")),
                .activity(Activity(id: "x1", title: "google_web_search", done: true)), .usage(Usage(input: 3, output: 2)),
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
