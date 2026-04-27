import XCTest
import SwiftUI

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testToolGroupMultipleCollapsed() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupTools),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_multiple_collapsed"
        )
    }

    func testToolGroupSingleEntry() {
        assertMacSnapshot(
            ToolGroupBlock(tools: [sampleGroupTools[0]]),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_single_entry"
        )
    }

    func testToolGroupAggregateInProgress() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupToolsInProgress),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_aggregate_in_progress"
        )
    }

    func testToolGroupAggregateError() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupToolsWithError),
            size: CGSize(width: 760, height: 80),
            named: "tool_group_aggregate_error"
        )
    }

    func testToolGroupExpandedIndentsChildren() {
        assertMacSnapshot(
            ToolGroupBlock(tools: sampleGroupTools, initiallyExpanded: true),
            size: CGSize(width: 760, height: 240),
            named: "tool_group_expanded_indents_children"
        )
    }

    func testStandaloneBashErrorCollapsed() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneBashErrorTool),
            size: CGSize(width: 760, height: 80),
            named: "standalone_bash_error_collapsed"
        )
    }

    func testStandaloneEditRow() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneEditTool),
            size: CGSize(width: 760, height: 80),
            named: "standalone_edit_row"
        )
    }

    func testStandaloneBashErrorExpanded() {
        assertMacSnapshot(
            StandaloneToolRow(tool: sampleStandaloneBashErrorTool, initiallyExpanded: true),
            size: CGSize(width: 760, height: 240),
            named: "standalone_bash_error_expanded"
        )
    }

    func testStandaloneMarkdownReadExpandedRendersMarkdown() {
        let description = """
        Apply a signature watermark to portfolio photos in images/portfolio/. Use when the user asks to sign, watermark, \
        or add a signature to portfolio images, or to re-apply or adjust the watermark opacity/font/position.
        """
        let tool = ToolEntry(
            id: "read-markdown",
            name: "Read",
            summary: "Read `SKILL.md`",
            input: "{\"file_path\":\"/tmp/alveary/SKILL.md\"}",
            output: """
            1\t---
            2\tname: watermark-portfolio-images
            3\tdescription: \(description)
            4\t---
            5\t# Watermark Portfolio Images
            6\t
            7\tRun `python3 watermark.py`.
            8\t
            9\t- Keep originals
            10\t- Skip signed files
            11\t
            12\t## Parameters
            13\t
            14\t| Setting | Value |
            15\t|---|---|
            16\t| Font | Gingerink (`GingerinkPersonalUse-rvJd7.ttf`) |
            17\t| Position | Bottom-right: `padding_x = max(12, int(width * 0.02))` |
            """,
            stderr: nil,
            isComplete: true,
            isInterrupted: false,
            isImage: false,
            noOutputExpected: false,
            isError: false
        )

        assertMacSnapshot(
            StandaloneToolRow(tool: tool, initiallyExpanded: true),
            size: CGSize(width: 760, height: 420),
            named: "standalone_markdown_read_expanded"
        )
    }

    func testStandaloneExpandedThenCollapsedSpacing() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 6) {
                StandaloneToolRow(tool: sampleStandaloneBashPwdTool, initiallyExpanded: true)
                StandaloneToolRow(tool: sampleStandaloneBashDateTool)
            },
            size: CGSize(width: 520, height: 160),
            named: "standalone_expanded_then_collapsed_spacing"
        )
    }

    func testToolApprovalBash() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_bash"
        )
    }

    func testToolApprovalBatchBash() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashBatchApprovals[0],
                approvals: sampleBashBatchApprovals,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 150),
            named: "tool_approval_batch_bash"
        )
    }

    func testToolApprovalWrite() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleWriteApproval,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_write"
        )
    }

    func testToolApprovalBatchWrite() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleWriteBatchApprovals[0],
                approvals: sampleWriteBatchApprovals,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 150),
            named: "tool_approval_batch_write"
        )
    }

    func testToolApprovalEdit() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleEditApproval,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_edit"
        )
    }

    func testToolApprovalCompact() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .pending,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 340, height: 140),
            named: "tool_approval_compact"
        )
    }

    func testToolApprovalExitPlanMode() {
        assertMacSnapshot(
            VStack(alignment: .leading, spacing: 6) {
                if let planMarkdown = sampleExitPlanModeApproval.planMarkdown {
                    AssistantBubble(markdown: planMarkdown)
                }

                ToolApprovalBlock(
                    approval: sampleExitPlanModeApproval,
                    status: .pending,
                    onApprove: {},
                    onApproveForSession: { _ in },
                    onDeny: {}
                )
            },
            size: CGSize(width: 760, height: 300),
            named: "tool_approval_exit_plan_mode"
        )
    }

    func testToolApprovalBlockedByPrompt() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .pending,
                isBlocked: true,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_blocked_by_prompt"
        )
    }

    func testToolApprovalApproving() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .approving,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_approving"
        )
    }

    func testToolApprovalDenying() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .denying,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_denying"
        )
    }

    func testToolApprovalApprovedGroup() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .approvedForSessionGroup,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_approved_group"
        )
    }

    func testToolApprovalApprovedForSession() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleEditApproval,
                status: .approvedForSessionExact,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_approved_for_session"
        )
    }

    func testToolApprovalSuperseded() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .superseded,
                onApprove: {},
                onApproveForSession: { _ in },
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_superseded"
        )
    }
}
