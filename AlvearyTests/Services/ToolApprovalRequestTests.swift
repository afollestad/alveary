import XCTest

@testable import Alveary

final class ToolApprovalRequestTests: XCTestCase {
    func testApprovalPromptTitleUsesToolSpecificSingularCopy() {
        XCTAssertEqual(title(for: ["Bash"]), "Approve Bash command?")
        XCTAssertEqual(title(for: ["Write"]), "Approve writing to a file?")
        XCTAssertEqual(title(for: ["Edit"]), "Approve editing a file?")
        XCTAssertEqual(title(for: ["MultiEdit"]), "Approve editing a file?")
        XCTAssertEqual(title(for: ["NotebookEdit"]), "Approve editing a notebook?")
        XCTAssertEqual(title(for: ["Read"]), "Approve reading a file?")
        XCTAssertEqual(title(for: ["LS"]), "Approve listing a directory?")
        XCTAssertEqual(title(for: ["NotebookRead"]), "Approve reading a notebook?")
        XCTAssertEqual(title(for: ["Grep"]), "Approve searching a path?")
        XCTAssertEqual(title(for: ["Glob"]), "Approve searching a path?")
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
        XCTAssertEqual(title(for: ["Read", "Read"]), "Approve reading files?")
        XCTAssertEqual(title(for: ["LS", "LS"]), "Approve listing directories?")
        XCTAssertEqual(title(for: ["NotebookRead", "NotebookRead"]), "Approve reading notebooks?")
        XCTAssertEqual(title(for: ["Grep", "Grep"]), "Approve searching paths?")
        XCTAssertEqual(title(for: ["Glob", "Glob"]), "Approve searching paths?")
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
        XCTAssertEqual(
            request(toolName: "Read", toolInput: #"{"file_path":"Sources/Auth.swift"}"#).conciseSummary,
            "Sources/Auth.swift"
        )
        XCTAssertEqual(
            request(toolName: "LS", toolInput: #"{"path":"Sources"}"#).conciseSummary,
            "Sources"
        )
        XCTAssertEqual(
            request(toolName: "NotebookRead", toolInput: #"{"notebook_path":"Analysis.ipynb"}"#).conciseSummary,
            "Analysis.ipynb"
        )
    }

    func testConciseSummaryUsesSearchPatternAndOptionalPathForNativeSearchApprovals() {
        XCTAssertEqual(
            request(toolName: "Grep", toolInput: #"{"pattern":"APIKey","path":"../other"}"#).conciseSummary,
            "APIKey in ../other"
        )
        XCTAssertEqual(
            request(toolName: "Grep", toolInput: #"{"pattern":"APIKey","glob":"../**/*.swift"}"#).conciseSummary,
            "APIKey"
        )
        XCTAssertEqual(
            request(toolName: "Glob", toolInput: #"{"pattern":"../**/*.swift","path":"../other"}"#).conciseSummary,
            "../**/*.swift in ../other"
        )
    }

    func testTranscriptApprovalSummaryHidesRedundantExitPlanModeSummary() {
        XCTAssertEqual(
            request(toolName: "Bash", toolInput: #"{"command":"date"}"#).transcriptApprovalSummary,
            "date"
        )
        XCTAssertEqual(
            request(toolName: "Write", toolInput: #"{"file_path":"Sources/Auth.swift"}"#).transcriptApprovalSummary,
            "Sources/Auth.swift"
        )
        XCTAssertNil(request(toolName: "ExitPlanMode").transcriptApprovalSummary)
        XCTAssertEqual(request(toolName: "ExitPlanMode").conciseSummary, "Present the plan and leave plan mode")
    }

    func testRTKWrappedBashCommandUsesWrappedCommandForSummaryAndSessionApproval() {
        let approval = request(
            toolName: "Bash",
            toolInput: #"{"command":"rtk git log --oneline -5"}"#
        )

        XCTAssertEqual(approval.conciseSummary, "git log --oneline -5")
        XCTAssertEqual(approval.supportedSessionApprovalScopes, [.exact, .group])
        XCTAssertEqual(
            approval.sessionApprovalGrant(
                conversationId: "conversation-1",
                providerId: "claude",
                scope: .exact
            ),
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-1",
                matchKind: .bashExact,
                matchValue: "git log --oneline -5"
            )
        )
        XCTAssertEqual(
            approval.sessionApprovalGrant(
                conversationId: "conversation-1",
                providerId: "claude",
                scope: .group
            ),
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: "conversation-1",
                sessionId: "session-1",
                matchKind: .bashCommandGroup,
                matchValue: "git log"
            )
        )
    }

    func testNativeReadOnlySessionScopesOnlyOfferExactPathGrantsForPathExactTools() {
        let read = request(toolName: "Read", toolInput: #"{"file_path":"/tmp/project/README.md"}"#)
        let list = request(toolName: "LS", toolInput: #"{"path":"/tmp/project/Sources"}"#)
        let notebookRead = request(toolName: "NotebookRead", toolInput: #"{"notebook_path":"/tmp/project/Analysis.ipynb"}"#)
        let grep = request(toolName: "Grep", toolInput: #"{"pattern":"token","path":"/tmp/project"}"#)
        let glob = request(toolName: "Glob", toolInput: #"{"pattern":"/tmp/project/**/*.swift"}"#)

        XCTAssertEqual(read.supportedSessionApprovalScopes, [.exact])
        XCTAssertEqual(list.supportedSessionApprovalScopes, [.exact])
        XCTAssertEqual(notebookRead.supportedSessionApprovalScopes, [.exact])
        XCTAssertEqual(grep.supportedSessionApprovalScopes, [])
        XCTAssertEqual(glob.supportedSessionApprovalScopes, [])
        XCTAssertEqual(read.sessionApprovalMatch(for: .exact)?.kind, .filePathExact)
        XCTAssertEqual(read.sessionApprovalMatch(for: .exact)?.value, "/tmp/project/README.md")
        XCTAssertEqual(list.sessionApprovalMatch(for: .exact)?.value, "/tmp/project/Sources")
        XCTAssertEqual(notebookRead.sessionApprovalMatch(for: .exact)?.value, "/tmp/project/Analysis.ipynb")
        XCTAssertNil(grep.sessionApprovalMatch(for: .exact))
        XCTAssertNil(glob.sessionApprovalMatch(for: .exact))
    }

    func testQuotedRTKCommandIsNotTreatedAsWrapperPrefix() {
        let approval = request(
            toolName: "Bash",
            toolInput: #"{"command":"\"rtk\" git log --oneline -5"}"#
        )

        XCTAssertEqual(approval.conciseSummary, #""rtk" git log --oneline -5"#)
        XCTAssertEqual(
            approval.sessionApprovalGrant(
                conversationId: "conversation-1",
                providerId: "claude",
                scope: .group
            )?.matchValue,
            "rtk git"
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
