import XCTest

@testable import Alveary

extension ClaudeAdapterTests {
    func testDecodeSystemStatusContextCompactionStart() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "system",
            "subtype": "status",
            "session_id": "session-123",
            "status": "compacting",
            "compact_metadata": [
                "trigger": "auto"
            ]
        ]

        XCTAssertEqual(
            adapter.decode(json),
            [
                .contextCompactionStarted(
                    id: "claude-context-compaction-session-123-1",
                    trigger: "auto"
                )
            ]
        )
    }

    func testDecodeSystemCompactBoundaryReusesCompactionStartId() {
        let adapter = ClaudeAdapter()
        let start: [String: Any] = [
            "type": "system",
            "subtype": "status",
            "session_id": "session-123",
            "status": "compacting"
        ]
        let completed: [String: Any] = [
            "type": "system",
            "subtype": "compact_boundary",
            "session_id": "session-123",
            "compact_result": "success",
            "compactMetadata": [
                "summary": "Reduced context"
            ]
        ]

        XCTAssertEqual(
            adapter.decode(start),
            [.contextCompactionStarted(id: "claude-context-compaction-session-123-1", trigger: nil)]
        )
        XCTAssertEqual(
            adapter.decode(completed),
            [.contextCompactionCompleted(id: "claude-context-compaction-session-123-1", summary: "Reduced context")]
        )
    }

    func testDecodeSystemContextCompactionFailure() {
        let adapter = ClaudeAdapter()
        let json: [String: Any] = [
            "type": "system",
            "subtype": "status",
            "session_id": "session-123",
            "compact_result": "failed",
            "compact_error": "Compact hook failed"
        ]

        XCTAssertEqual(
            adapter.decode(json),
            [
                .contextCompactionFailed(
                    id: "claude-context-compaction-session-123-1",
                    error: "Compact hook failed"
                )
            ]
        )
    }
}
