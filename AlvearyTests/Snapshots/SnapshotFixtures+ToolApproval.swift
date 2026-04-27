import XCTest

@testable import Alveary

extension SnapshotTests {
    var sampleBashApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-bash",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test --filter ClaudeAdapterTests\"}"
        )
    }

    var sampleBashBatchApprovals: [ToolApprovalRequest] {
        [
            ToolApprovalRequest(
                sessionId: "session-snapshot",
                toolUseId: "tool-pwd",
                toolName: "Bash",
                toolInput: "{\"command\":\"pwd\"}"
            ),
            ToolApprovalRequest(
                sessionId: "session-snapshot",
                toolUseId: "tool-date",
                toolName: "Bash",
                toolInput: "{\"command\":\"date\"}"
            )
        ]
    }

    var sampleWriteApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-write",
            toolName: "Write",
            toolInput: #"{"file_path":"\#(NSHomeDirectory())/Development/alveary/test_parallel.txt","content":"test"}"#
        )
    }

    var sampleWriteBatchApprovals: [ToolApprovalRequest] {
        let homeDirectory = NSHomeDirectory()
        return [
            ToolApprovalRequest(
                sessionId: "session-snapshot",
                toolUseId: "tool-write-one",
                toolName: "Write",
                toolInput: #"{"file_path":"\#(homeDirectory)/Development/alveary/first.md","content":"One"}"#
            ),
            ToolApprovalRequest(
                sessionId: "session-snapshot",
                toolUseId: "tool-write-two",
                toolName: "Write",
                toolInput: #"{"file_path":"\#(homeDirectory)/Development/alveary/second.md","content":"Two"}"#
            )
        ]
    }

    var sampleEditApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-edit",
            toolName: "Edit",
            toolInput: #"{"file_path":"\#(NSHomeDirectory())/Development/alveary/Alveary/Services/Agent/Claude/ClaudeAdapter.swift"}"#
        )
    }

    var sampleExitPlanModeApproval: ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-snapshot",
            toolUseId: "tool-exit-plan",
            toolName: "ExitPlanMode",
            toolInput: exitPlanModeToolInput(plan: """
            # Implementation Plan

            Render the plan markdown directly above the approval prompt before leaving plan mode.

            - Parse the `plan` field from `ExitPlanMode` tool input.
            - Reuse the assistant markdown bubble so formatting, links, and code blocks stay consistent.
            - Keep the approval card focused on the decision controls.
            """)
        )
    }

    private func exitPlanModeToolInput(plan: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: ["plan": plan], options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
