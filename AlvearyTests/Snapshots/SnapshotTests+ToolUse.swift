import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testWorkingBlockSingleErrorToolCollapsed() {
        assertMacSnapshot(
            WorkingBlock(tools: sampleErrorTools),
            size: CGSize(width: 760, height: 190),
            named: "working_block_single_error_collapsed"
        )
    }

    func testWorkingBlockExpandedErrorTool() {
        assertMacSnapshot(
            WorkingBlock(
                tools: sampleErrorTools,
                initiallyExpanded: true
            ),
            size: CGSize(width: 760, height: 260),
            named: "working_block_expanded_error"
        )
    }
}
