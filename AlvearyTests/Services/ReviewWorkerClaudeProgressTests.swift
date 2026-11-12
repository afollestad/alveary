import Foundation
import Testing

@testable import Alveary

struct ReviewWorkerClaudeProgressTests {
    @Test
    func `summary reports progress without content or uncategorized errors`() throws {
        let progress = try #require(ReviewWorkerClaudeProgress(stdout: stream([
            #"{"type":"system","subtype":"init","cwd":"/packet"}"#,
            assistant(id: "m1", blocks: [#"{"type":"thinking","thinking":"SECRET"}"#], stopReason: "refusal"),
            assistant(id: "m1", blocks: [#"{"type":"tool_use","name":"Read"}"#], stopReason: "refusal"),
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"SECRET"}]}}"#,
            #"{"type":"system","subtype":"api_retry","attempt":1,"max_retries":10,"error":"Request had SECRET text"}"#,
            assistant(
                id: "m2", blocks: [#"{"type":"tool_use","name":"Grep"}"#, #"{"type":"tool_use","name":"Grep"}"#],
                usage: #"{"input_tokens":50,"cache_creation_input_tokens":500,"cache_read_input_tokens":2000}"#
            ),
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":[{"type":"text","text":"SECRET"}]}]}}"#,
            #"{"type":"assistant","message":{"id":"m3","content":[{"type":"tool_use""#
        ]), wasTruncated: false))

        #expect(progress.summary == """
        It had taken 2 turns and made 3 tool calls, and its last answered request carried 2K tokens of context, \
        with 6 bytes of tool output read since. \
        The model's safeguards stopped 1 of its responses. It had retried failed API requests 1 time (last: attempt 1 of 10).
        """)
    }

    @Test
    func `a capture cut off at the limit says so and does not claim how the worker stopped`() throws {
        let progress = try #require(ReviewWorkerClaudeProgress(
            stdout: stream([#"{"type":"system","subtype":"api_retry","attempt":3,"error":"rate_limit","error_status":429}"#]),
            wasTruncated: true
        ))

        #expect(progress.summary == """
        Its output passed the capture limit, so this covers only its start. It had taken 0 turns and made 0 tool calls. \
        It had retried failed API requests 1 time (last: attempt 3, rate_limit, HTTP 429).
        """)
    }

    @Test(arguments: ["", "not json\n", "\n\n"])
    func `a capture without events has no summary`(stdout: String) {
        #expect(ReviewWorkerClaudeProgress(stdout: Data(stdout.utf8), wasTruncated: false) == nil)
    }

    private func stream(_ lines: [String]) -> Data {
        Data(lines.joined(separator: "\n").utf8)
    }

    private func assistant(id: String, blocks: [String], usage: String = #"{"input_tokens":100}"#, stopReason: String? = nil) -> String {
        let stop = stopReason.map { #","stop_reason":"\#($0)""# } ?? ""
        return #"{"type":"assistant","message":{"id":"\#(id)","content":[\#(blocks.joined(separator: ","))],"usage":\#(usage)\#(stop)}}"#
    }
}
