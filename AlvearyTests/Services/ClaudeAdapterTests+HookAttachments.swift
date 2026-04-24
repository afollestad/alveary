import XCTest

@testable import Alveary

extension ClaudeAdapterTests {
    func testDecodeHookDeferredToolAttachmentEmitsDeferredToolApproval() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "attachment",
            "sessionId": "session-123",
            "attachment": [
                "type": "hook_deferred_tool",
                "toolUseID": "tool-1",
                "toolName": "Bash",
                "toolInput": [
                    "command": "pwd",
                    "description": "Print working directory"
                ]
            ]
        ]

        XCTAssertEqual(
            adapter.decode(json),
            [
                .toolApprovalRequested(
                    ToolApprovalRequest(
                        sessionId: "session-123",
                        toolUseId: "tool-1",
                        toolName: "Bash",
                        toolInput: "{\"command\":\"pwd\",\"description\":\"Print working directory\"}"
                    )
                ),
                .tokens(
                    input: 0,
                    output: 0,
                    cacheRead: 0,
                    isError: false,
                    stopReason: "tool_deferred",
                    durationMs: 0,
                    costUsd: 0,
                    permissionDenials: []
                )
            ]
        )
    }

    func testDecodeIgnoresEventsAfterHookDeferredToolAttachment() {
        let adapter = ClaudeAdapter()
        let approvalJSON: [String: Any] = [
            "type": "attachment",
            "sessionId": "session-123",
            "attachment": [
                "type": "hook_deferred_tool",
                "toolUseID": "tool-1",
                "toolName": "Bash",
                "toolInput": [
                    "command": "whoami"
                ]
            ]
        ]
        let trailingJSON: [String: Any] = [
            "type": "assistant",
            "message": [
                "content": [[
                    "type": "text",
                    "text": "The tool call failed internally."
                ]]
            ]
        ]

        XCTAssertFalse(adapter.decode(approvalJSON).isEmpty)
        XCTAssertEqual(adapter.decode(trailingJSON), [])
    }

    func testDecodeHookErrorAttachmentEmitsError() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "attachment",
            "sessionId": "session-123",
            "attachment": [
                "type": "hook_non_blocking_error",
                "hookName": "PreToolUse:Bash",
                "toolUseID": "tool-1",
                "stderr": "Failed with non-blocking status code: boom"
            ]
        ]

        XCTAssertEqual(
            adapter.decode(json),
            [
                .toolApprovalFailed(
                    ToolApprovalFailure(
                        sessionId: "session-123",
                        toolUseId: "tool-1",
                        toolName: "Bash",
                        message: "Claude hook failed (PreToolUse:Bash): Failed with non-blocking status code: boom"
                    )
                )
            ]
        )
    }
}
