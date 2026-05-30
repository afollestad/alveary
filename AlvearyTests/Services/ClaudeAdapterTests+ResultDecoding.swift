import Foundation
import XCTest

@testable import Alveary

extension ClaudeAdapterTests {
    func testDecodeResultEventEmitsDeferredToolApproval() {
        let adapter = ClaudeAdapter()

        XCTAssertEqual(
            adapter.decode(Self.deferredToolResultJSON()),
            [
                .toolApprovalRequested(
                    ToolApprovalRequest(
                        sessionId: "session-123",
                        toolUseId: "tool-1",
                        toolName: "Bash",
                        toolInput: "{\"command\":\"swift test\"}"
                    )
                ),
                .tokens(
                    input: 10,
                    output: 2,
                    cacheRead: 4,
                    cacheCreation: 6,
                    isError: false,
                    stopReason: "tool_deferred",
                    durationMs: 42,
                    costUsd: 0.01,
                    providerModelId: "claude-sonnet-4-6",
                    contextWindowSize: 200_000,
                    permissionDenials: []
                )
            ]
        )
    }

    func testDecodeResultEventMatchesModelUsageWhenOptionalZeroFieldsAreOmitted() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "result",
            "stop_reason": "end_turn",
            "is_error": false,
            "usage": [
                "input_tokens": 10,
                "output_tokens": 2
            ],
            "duration_ms": "42",
            "total_cost_usd": "0.01",
            "modelUsage": [
                ClaudeModelIDs.opus: [
                    "inputTokens": 100,
                    "outputTokens": 20,
                    "cacheReadInputTokens": 10,
                    "cacheCreationInputTokens": 10,
                    "contextWindow": 1_000_000
                ],
                "claude-sonnet-4-6": [
                    "inputTokens": 10,
                    "outputTokens": 2,
                    "cacheReadInputTokens": 0,
                    "cacheCreationInputTokens": 0,
                    "contextWindow": 200_000
                ]
            ]
        ]

        XCTAssertEqual(
            adapter.decode(json),
            [
                .tokens(
                    input: 10,
                    output: 2,
                    cacheRead: 0,
                    cacheCreation: 0,
                    isError: false,
                    stopReason: "end_turn",
                    durationMs: 42,
                    costUsd: 0.01,
                    providerModelId: "claude-sonnet-4-6",
                    contextWindowSize: 200_000,
                    permissionDenials: []
                )
            ]
        )
    }

    private static func deferredToolResultJSON() -> [String: Any] {
        [
            "type": "result",
            "session_id": "session-123",
            "stop_reason": "tool_deferred",
            "is_error": false,
            "usage": [
                "input_tokens": 10,
                "output_tokens": 2,
                "cache_read_input_tokens": 4,
                "cache_creation_input_tokens": 6
            ],
            "duration_ms": 42,
            "total_cost_usd": 0.01,
            "modelUsage": [
                "claude-sonnet-4-6": [
                    "inputTokens": 10,
                    "outputTokens": 2,
                    "cacheReadInputTokens": 4,
                    "cacheCreationInputTokens": 6,
                    "contextWindow": 200_000,
                    "maxOutputTokens": 32_000
                ]
            ],
            "deferred_tool_use": [
                "id": "tool-1",
                "name": "Bash",
                "input": ["command": "swift test"]
            ]
        ]
    }
}
