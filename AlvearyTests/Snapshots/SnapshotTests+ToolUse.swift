import XCTest

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
            size: CGSize(width: 760, height: 220),
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

    func testToolApprovalBash() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .pending,
                onApprove: {},
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_bash"
        )
    }

    func testToolApprovalEdit() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleEditApproval,
                status: .pending,
                onApprove: {},
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
                onDeny: {}
            ),
            size: CGSize(width: 340, height: 140),
            named: "tool_approval_compact"
        )
    }

    func testToolApprovalApproving() {
        assertMacSnapshot(
            ToolApprovalBlock(
                approval: sampleBashApproval,
                status: .approving,
                onApprove: {},
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
                onDeny: {}
            ),
            size: CGSize(width: 760, height: 120),
            named: "tool_approval_denying"
        )
    }
}
