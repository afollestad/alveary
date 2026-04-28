import XCTest

@testable import Alveary

final class ToolApprovalRequestTests: XCTestCase {
    func testApprovalPromptTitleUsesToolSpecificSingularCopy() {
        XCTAssertEqual(title(for: ["Bash"]), "Approve Bash command?")
        XCTAssertEqual(title(for: ["Write"]), "Approve writing to a file?")
        XCTAssertEqual(title(for: ["Edit"]), "Approve editing a file?")
        XCTAssertEqual(title(for: ["MultiEdit"]), "Approve editing a file?")
        XCTAssertEqual(title(for: ["NotebookEdit"]), "Approve editing a notebook?")
        XCTAssertEqual(title(for: ["EnterPlanMode"]), "Approve entering plan mode?")
        XCTAssertEqual(title(for: ["ExitPlanMode"]), "Ready to leave plan mode?")
        XCTAssertEqual(title(for: ["mcp__filesystem__write_file"]), "Approve MCP tool use?")
        XCTAssertEqual(title(for: ["CustomTool"]), "Approve CustomTool tool use?")
    }

    func testApprovalPromptTitleUsesToolSpecificPluralCopy() {
        XCTAssertEqual(title(for: ["Bash", "Bash"]), "Approve Bash commands?")
        XCTAssertEqual(title(for: ["Write", "Write"]), "Approve writing to files?")
        XCTAssertEqual(title(for: ["Edit", "Edit"]), "Approve editing files?")
        XCTAssertEqual(title(for: ["MultiEdit", "MultiEdit"]), "Approve editing files?")
        XCTAssertEqual(title(for: ["NotebookEdit", "NotebookEdit"]), "Approve editing notebooks?")
        XCTAssertEqual(title(for: ["mcp__filesystem__write_file", "mcp__filesystem__write_file"]), "Approve MCP tool uses?")
        XCTAssertEqual(title(for: ["CustomTool", "CustomTool"]), "Approve CustomTool tool uses?")
    }

    func testApprovalPromptTitleFallsBackForMixedBatches() {
        XCTAssertEqual(title(for: ["Bash", "Write"]), "Approve tool uses?")
    }

    func testConciseSummaryUsesHomeAbbreviatedCanonicalPathForFileApprovals() {
        let homePath = NSHomeDirectory() + "/Development/alveary/test_parallel.txt"

        XCTAssertEqual(
            request(toolName: "Write", toolInput: #"{"file_path":"\#(homePath)","content":"test"}"#).conciseSummary,
            "~/Development/alveary/test_parallel.txt"
        )
        XCTAssertEqual(
            request(toolName: "Edit", toolInput: #"{"file_path":"Sources/Auth.swift"}"#).conciseSummary,
            "Sources/Auth.swift"
        )
        XCTAssertEqual(
            request(toolName: "MultiEdit", toolInput: #"{"path":"\#(homePath)"}"#).conciseSummary,
            "~/Development/alveary/test_parallel.txt"
        )
        XCTAssertEqual(
            request(toolName: "NotebookEdit", toolInput: #"{"notebook_path":"\#(homePath)"}"#).conciseSummary,
            "~/Development/alveary/test_parallel.txt"
        )
        XCTAssertEqual(
            request(toolName: "Write", toolInput: #"{"file_path":"/tmp/test_parallel.txt","content":"test"}"#).conciseSummary,
            "/tmp/test_parallel.txt"
        )
    }

    func testNotificationMessageUsesAskUserQuestionSummaryFallback() {
        XCTAssertEqual(
            request(
                toolName: "AskUserQuestion",
                toolInput: #"{"questions":[{"question":"  Pick a target  ","options":[]}]}"#
            ).notificationMessage,
            "Your agent has a question: Pick a target"
        )
        XCTAssertEqual(
            request(
                toolName: "AskUserQuestion",
                toolInput: #"{"questions":[{"question":"  ","options":[]}]}"#
            ).notificationMessage,
            "Your agent has a question: Review the pending question"
        )
    }

    func testPlanMarkdownExtractsExitPlanModePlan() {
        XCTAssertEqual(
            request(
                toolName: "ExitPlanMode",
                toolInput: ##"{"plan":"# Plan\n\n- Render markdown before approval."}"##
            ).planMarkdown,
            "# Plan\n\n- Render markdown before approval."
        )
    }

    func testPlanMarkdownTrimsWhitespace() {
        XCTAssertEqual(
            request(
                toolName: "ExitPlanMode",
                toolInput: #"{"plan":"\n\n  Review this plan.  \n"}"#
            ).planMarkdown,
            "Review this plan."
        )
    }

    func testPlanMarkdownIgnoresNonExitPlanModeTool() {
        XCTAssertNil(
            request(
                toolName: "Bash",
                toolInput: #"{"plan":"Not a plan-mode approval."}"#
            ).planMarkdown
        )
    }

    func testPlanMarkdownIgnoresInvalidInput() {
        XCTAssertNil(request(toolName: "ExitPlanMode", toolInput: #"{"plan":""}"#).planMarkdown)
        XCTAssertNil(request(toolName: "ExitPlanMode", toolInput: #"{"command":"date"}"#).planMarkdown)
        XCTAssertNil(request(toolName: "ExitPlanMode", toolInput: "not json").planMarkdown)
    }

    func testPlanMarkdownUsesFallbackWithoutChangingToolInput() {
        let approval = request(toolName: "ExitPlanMode", toolInput: "{}")
            .withPlanMarkdownFallback("# Plan\n\n- Use the assistant message.")

        XCTAssertEqual(approval.planMarkdown, "# Plan\n\n- Use the assistant message.")
        XCTAssertEqual(approval.toolInput, "{}")
    }

    func testPlanMarkdownUsesFallbackWhenExplicitPlanIsEmpty() {
        let approval = request(toolName: "ExitPlanMode", toolInput: #"{"plan":"  "}"#)
            .withPlanMarkdownFallback("Fallback plan")

        XCTAssertEqual(approval.planMarkdown, "Fallback plan")
    }

    private func title(for toolNames: [String]) -> String {
        let approvals = toolNames.enumerated().map { offset, toolName in
            request(toolName: toolName, toolUseId: "tool-\(offset)")
        }
        return ToolApprovalRequest.approvalPromptTitle(for: approvals)
    }

    private func request(
        toolName: String,
        toolUseId: String = "tool-1",
        toolInput: String = "{}"
    ) -> ToolApprovalRequest {
        ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: toolUseId,
            toolName: toolName,
            toolInput: toolInput
        )
    }
}
