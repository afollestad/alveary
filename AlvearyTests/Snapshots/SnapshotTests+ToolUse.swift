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
}
